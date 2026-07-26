"""Filesystem allowlisting and single-open media validation."""

from __future__ import annotations

import os
import stat
import sys
from collections.abc import Iterable
from dataclasses import dataclass
from pathlib import Path, PureWindowsPath
from typing import Any, BinaryIO, cast

IMAGE_MAX_BYTES = 10 * 1024 * 1024
VIDEO_MAX_BYTES = 1_500_000_000

_WINDOWS_RESERVED_NAMES = {
    "CON",
    "PRN",
    "AUX",
    "NUL",
    *(f"COM{index}" for index in range(1, 10)),
    *(f"LPT{index}" for index in range(1, 10)),
}
_REPARSE_POINT = getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400)


class PathConfigurationError(Exception):
    def __init__(self, public_message: str) -> None:
        super().__init__(public_message)
        self.public_message = public_message


class LocalFileError(Exception):
    def __init__(self, code: str, public_message: str) -> None:
        super().__init__(public_message)
        self.code = code
        self.public_message = public_message


class _BoundedReader:
    """Expose only the validated prefix even if another process appends later."""

    def __init__(self, stream: BinaryIO, size: int) -> None:
        self._stream = stream
        self._size = size

    def read(self, size: int = -1) -> bytes:
        remaining = max(0, self._size - self.tell())
        requested = remaining if size < 0 else min(size, remaining)
        return self._stream.read(requested)

    def seek(self, offset: int, whence: int = os.SEEK_SET) -> int:
        if whence == os.SEEK_SET:
            target = offset
        elif whence == os.SEEK_CUR:
            target = self.tell() + offset
        elif whence == os.SEEK_END:
            target = self._size + offset
        else:
            raise ValueError("invalid whence")
        if target < 0:
            raise ValueError("negative seek position")
        return self._stream.seek(min(target, self._size), os.SEEK_SET)

    def tell(self) -> int:
        return self._stream.tell()

    def seekable(self) -> bool:
        return True

    def readable(self) -> bool:
        return True

    @property
    def closed(self) -> bool:
        return self._stream.closed

    @property
    def name(self) -> object:
        return self._stream.name

    def close(self) -> None:
        self._stream.close()


@dataclass
class ValidatedMedia:
    """An already-open regular file; callers must close it."""

    stream: BinaryIO
    size: int
    filename: str

    def close(self) -> None:
        self.stream.close()

    def __enter__(self) -> ValidatedMedia:
        return self

    def __exit__(self, *_args: object) -> None:
        self.close()


def _contains_windows_device_or_ads(raw: str) -> bool:
    normalized = raw.replace("/", "\\")
    lowered = normalized.casefold()
    if lowered.startswith(("\\\\?\\", "\\\\.\\", "\\??\\")):
        return True

    windows_path = PureWindowsPath(raw)
    for part in windows_path.parts:
        if part in {windows_path.anchor, "\\", "/"}:
            continue
        if ":" in part:
            return True
        cleaned = part.rstrip(" .")
        stem = cleaned.split(".", 1)[0].upper()
        if stem in _WINDOWS_RESERVED_NAMES:
            return True
    return False


def _validate_path_text(raw: str, *, configuration: bool) -> None:
    if "\x00" in raw:
        if configuration:
            raise PathConfigurationError("An allowed directory is invalid.")
        raise LocalFileError("invalid_path", "The media path is invalid.")
    if os.name == "nt" and _contains_windows_device_or_ads(raw):
        if configuration:
            raise PathConfigurationError("An allowed directory uses a forbidden Windows path.")
        raise LocalFileError(
            "invalid_path",
            "Windows device and alternate stream paths are forbidden.",
        )


def _is_reparse_or_symlink(path: Path) -> bool:
    metadata = path.lstat()
    return stat.S_ISLNK(metadata.st_mode) or bool(
        getattr(metadata, "st_file_attributes", 0) & _REPARSE_POINT
    )


def _components_without_anchor(path: Path) -> list[Path]:
    components: list[Path] = []
    current = path
    while current != current.parent:
        components.append(current)
        current = current.parent
    components.reverse()
    return components


def _reject_link_components(path: Path, *, configuration: bool) -> None:
    try:
        for component in _components_without_anchor(path):
            if _is_reparse_or_symlink(component):
                if configuration:
                    raise PathConfigurationError(
                        "Allowed directories cannot contain symlinks, junctions, or reparse points."
                    )
                raise LocalFileError(
                    "unsafe_path",
                    "The media path cannot contain symlinks, junctions, or reparse points.",
                )
    except FileNotFoundError as exc:
        if configuration:
            raise PathConfigurationError("Every allowed directory must exist.") from exc
        raise LocalFileError("not_found", "The media file does not exist.") from exc
    except OSError as exc:
        if configuration:
            raise PathConfigurationError(
                "An allowed directory cannot be inspected safely."
            ) from exc
        raise LocalFileError("invalid_path", "The media path cannot be inspected safely.") from exc


def prepare_allowed_roots(entries: Iterable[str]) -> tuple[Path, ...]:
    roots: list[Path] = []
    for entry in entries:
        raw = entry.strip()
        _validate_path_text(raw, configuration=True)
        candidate = Path(raw)
        if not candidate.is_absolute():
            raise PathConfigurationError("Every allowed directory must be an absolute path.")
        _reject_link_components(candidate, configuration=True)
        try:
            resolved = candidate.resolve(strict=True)
        except (OSError, RuntimeError) as exc:
            raise PathConfigurationError("Every allowed directory must resolve safely.") from exc
        if resolved.parent == resolved:
            raise PathConfigurationError("Filesystem roots cannot be allowed directories.")
        if not resolved.is_dir():
            raise PathConfigurationError("Every allowed path must be a directory.")
        if resolved not in roots:
            roots.append(resolved)
    if not roots:
        raise PathConfigurationError("At least one allowed directory is required.")
    return tuple(roots)


def _is_contained(candidate: Path, root: Path) -> bool:
    try:
        candidate.relative_to(root)
    except ValueError:
        return False
    return True


def _final_opened_path(descriptor: int) -> Path:
    """Resolve the path attached to an open handle without reopening it."""

    if os.name == "nt":
        import ctypes
        import msvcrt
        from ctypes import wintypes

        loader: Any = getattr(ctypes, "WinDLL")  # noqa: B009
        kernel32: Any = loader("kernel32", use_last_error=True)
        get_final_path: Any = kernel32.GetFinalPathNameByHandleW
        get_final_path.argtypes = [
            wintypes.HANDLE,
            wintypes.LPWSTR,
            wintypes.DWORD,
            wintypes.DWORD,
        ]
        get_final_path.restype = wintypes.DWORD
        buffer = ctypes.create_unicode_buffer(32_768)
        handle = msvcrt.get_osfhandle(descriptor)
        length = int(get_final_path(handle, buffer, len(buffer), 0))
        if length <= 0 or length >= len(buffer):
            raise OSError(ctypes.get_last_error(), "cannot resolve opened file handle")
        raw = buffer.value
        if raw.startswith("\\\\?\\UNC\\"):
            raw = "\\\\" + raw[8:]
        elif raw.startswith("\\\\?\\"):
            raw = raw[4:]
        return Path(raw)

    if sys.platform.startswith("linux"):
        return Path(f"/proc/self/fd/{descriptor}").resolve(strict=True)

    if sys.platform == "darwin":
        import fcntl

        raw = fcntl.fcntl(descriptor, 50, b"\0" * 1024)
        if not isinstance(raw, bytes):
            raise OSError("cannot resolve opened file handle")
        value = raw.split(b"\0", 1)[0].decode(sys.getfilesystemencoding(), errors="strict")
        if not value:
            raise OSError("cannot resolve opened file handle")
        return Path(value)

    raise OSError("opened-file path verification is unsupported on this platform")


def _resolve_allowed_candidate(raw_path: str, allowed_roots: tuple[Path, ...]) -> Path:
    _validate_path_text(raw_path, configuration=False)
    candidate = Path(raw_path)
    if not candidate.is_absolute():
        raise LocalFileError("invalid_path", "The media path must be absolute.")
    _reject_link_components(candidate, configuration=False)
    try:
        resolved = candidate.resolve(strict=True)
    except FileNotFoundError as exc:
        raise LocalFileError("not_found", "The media file does not exist.") from exc
    except (OSError, RuntimeError) as exc:
        raise LocalFileError("invalid_path", "The media path cannot be resolved safely.") from exc

    if not any(_is_contained(resolved, root) for root in allowed_roots):
        raise LocalFileError(
            "outside_allowed_dirs",
            "The media file is outside allowed directories.",
        )
    if resolved.is_dir():
        raise LocalFileError("not_a_file", "The media path must identify a file.")
    return resolved


def open_validated_media(
    raw_path: str,
    allowed_roots: tuple[Path, ...],
    *,
    max_bytes: int,
) -> ValidatedMedia:
    """Open once, then validate and return the exact handle used for upload."""

    resolved = _resolve_allowed_candidate(raw_path, allowed_roots)
    try:
        before = resolved.lstat()
        flags = os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_CLOEXEC", 0)
        flags |= getattr(os, "O_NOFOLLOW", 0)
        descriptor = os.open(resolved, flags)
    except FileNotFoundError as exc:
        raise LocalFileError("not_found", "The media file does not exist.") from exc
    except OSError as exc:
        raise LocalFileError("open_failed", "The media file could not be opened safely.") from exc

    try:
        opened = os.fstat(descriptor)
        if (before.st_dev, before.st_ino) != (opened.st_dev, opened.st_ino):
            raise LocalFileError("changed_file", "The media file changed while it was opened.")
        try:
            opened_path = _final_opened_path(descriptor)
        except (OSError, RuntimeError, UnicodeError) as exc:
            raise LocalFileError(
                "open_failed",
                "The opened media file could not be verified safely.",
            ) from exc
        if not any(_is_contained(opened_path, root) for root in allowed_roots):
            raise LocalFileError(
                "changed_file",
                "The media file changed while it was opened.",
            )
        if bool(getattr(opened, "st_file_attributes", 0) & _REPARSE_POINT):
            raise LocalFileError("unsafe_path", "Reparse-point media files are forbidden.")
        if not stat.S_ISREG(opened.st_mode):
            raise LocalFileError("not_a_file", "The media path must identify a regular file.")
        if opened.st_size == 0:
            raise LocalFileError("empty_file", "The media file is empty.")
        if opened.st_size > max_bytes:
            raise LocalFileError("file_too_large", "The media file exceeds the allowed size.")
        raw_stream = os.fdopen(descriptor, "rb", closefd=True)
        stream = cast(BinaryIO, _BoundedReader(raw_stream, opened.st_size))
        descriptor = -1
        return ValidatedMedia(
            stream=stream,
            size=opened.st_size,
            filename=opened_path.name,
        )
    finally:
        if descriptor >= 0:
            os.close(descriptor)
