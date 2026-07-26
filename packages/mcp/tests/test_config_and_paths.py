from __future__ import annotations

import os
import subprocess
from pathlib import Path

import httpx
import pytest

import neuraldefend_mcp.path_security as path_security
from neuraldefend_mcp.config import ConfigurationError, load_config
from neuraldefend_mcp.path_security import (
    LocalFileError,
    PathConfigurationError,
    _contains_windows_device_or_ads,
    _is_contained,
    open_validated_media,
    prepare_allowed_roots,
)


def test_required_environment(tmp_path: Path) -> None:
    with pytest.raises(ConfigurationError, match="API_KEY"):
        load_config({})
    with pytest.raises(ConfigurationError, match="ALLOWED_DIRS"):
        load_config({"NEURALDEFEND_API_KEY": "secret"})
    with pytest.raises(ConfigurationError, match="empty entry"):
        load_config(
            {
                "NEURALDEFEND_API_KEY": "secret",
                "NEURALDEFEND_MCP_ALLOWED_DIRS": f"{tmp_path}{os.pathsep}",
            }
        )


def test_allowed_dirs_use_platform_separator_and_deduplicate(tmp_path: Path) -> None:
    first = tmp_path / "first"
    second = tmp_path / "second"
    first.mkdir()
    second.mkdir()
    config = load_config(
        {
            "NEURALDEFEND_API_KEY": "  secret  ",
            "NEURALDEFEND_MCP_ALLOWED_DIRS": os.pathsep.join((str(first), str(second), str(first))),
            "NEURALDEFEND_MCP_MAX_CONCURRENCY": "3",
        }
    )
    assert config.allowed_roots == (first.resolve(), second.resolve())
    assert config.api_key == "secret"
    assert config.environment == "production"
    assert config.max_concurrency == 3


def test_environment_is_restricted_to_known_origins(tmp_path: Path) -> None:
    base = {
        "NEURALDEFEND_API_KEY": "secret",
        "NEURALDEFEND_MCP_ALLOWED_DIRS": str(tmp_path),
    }
    staging = load_config({**base, "NEURALDEFEND_MCP_ENVIRONMENT": " STAGING "})
    assert staging.environment == "staging"

    with pytest.raises(ConfigurationError, match="ENVIRONMENT"):
        load_config({**base, "NEURALDEFEND_MCP_ENVIRONMENT": "custom"})


@pytest.mark.parametrize("value", ["0", "-1", "33", "1.5", "many"])
def test_concurrency_must_be_safe_positive_integer(tmp_path: Path, value: str) -> None:
    with pytest.raises(ConfigurationError, match="CONCURRENCY"):
        load_config(
            {
                "NEURALDEFEND_API_KEY": "secret",
                "NEURALDEFEND_MCP_ALLOWED_DIRS": str(tmp_path),
                "NEURALDEFEND_MCP_MAX_CONCURRENCY": value,
            }
        )


def test_allowed_root_must_be_absolute_directory_not_file_or_filesystem_root(
    tmp_path: Path,
) -> None:
    file_path = tmp_path / "file"
    file_path.write_bytes(b"x")
    with pytest.raises(PathConfigurationError, match="absolute"):
        prepare_allowed_roots(["relative"])
    with pytest.raises(PathConfigurationError, match="directory"):
        prepare_allowed_roots([str(file_path)])
    with pytest.raises(PathConfigurationError, match="Filesystem roots"):
        prepare_allowed_roots([str(Path(tmp_path.anchor))])


def test_candidate_must_be_absolute_existing_file(tmp_path: Path) -> None:
    roots = prepare_allowed_roots([str(tmp_path)])
    with pytest.raises(LocalFileError) as relative:
        open_validated_media("relative.bin", roots, max_bytes=10)
    assert relative.value.code == "invalid_path"
    with pytest.raises(LocalFileError) as missing:
        open_validated_media(str(tmp_path / "missing.bin"), roots, max_bytes=10)
    assert missing.value.code == "not_found"
    with pytest.raises(LocalFileError) as directory:
        open_validated_media(str(tmp_path), roots, max_bytes=10)
    assert directory.value.code == "not_a_file"


def test_component_aware_containment_rejects_prefix_sibling(tmp_path: Path) -> None:
    allowed = tmp_path / "allowed"
    sibling = tmp_path / "allowed-sibling"
    allowed.mkdir()
    sibling.mkdir()
    media = sibling / "media.bin"
    media.write_bytes(b"x")
    roots = prepare_allowed_roots([str(allowed)])
    with pytest.raises(LocalFileError) as raised:
        open_validated_media(str(media), roots, max_bytes=10)
    assert raised.value.code == "outside_allowed_dirs"


def test_empty_and_size_boundaries(tmp_path: Path) -> None:
    roots = prepare_allowed_roots([str(tmp_path)])
    empty = tmp_path / "empty.bin"
    exact = tmp_path / "exact.bin"
    too_large = tmp_path / "too-large.bin"
    empty.write_bytes(b"")
    exact.write_bytes(b"1234")
    too_large.write_bytes(b"12345")

    with pytest.raises(LocalFileError) as empty_error:
        open_validated_media(str(empty), roots, max_bytes=4)
    assert empty_error.value.code == "empty_file"

    with open_validated_media(str(exact), roots, max_bytes=4) as media:
        assert media.size == 4
        assert media.stream.read() == b"1234"

    with pytest.raises(LocalFileError) as size_error:
        open_validated_media(str(too_large), roots, max_bytes=4)
    assert size_error.value.code == "file_too_large"


def test_post_open_handle_path_must_remain_inside_allowlist(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    allowed = tmp_path / "allowed"
    outside = tmp_path / "outside"
    allowed.mkdir()
    outside.mkdir()
    media = allowed / "media.bin"
    media.write_bytes(b"x")
    roots = prepare_allowed_roots([str(allowed)])
    monkeypatch.setattr(
        path_security,
        "_final_opened_path",
        lambda _descriptor: outside / "media.bin",
    )

    with pytest.raises(LocalFileError) as raised:
        open_validated_media(str(media), roots, max_bytes=10)
    assert raised.value.code == "changed_file"


def test_opened_media_does_not_read_bytes_appended_after_validation(tmp_path: Path) -> None:
    media = tmp_path / "media.bin"
    media.write_bytes(b"safe")
    roots = prepare_allowed_roots([str(tmp_path)])

    with open_validated_media(str(media), roots, max_bytes=4) as validated:
        with media.open("ab") as output:
            output.write(b"-appended")
        assert validated.stream.read() == b"safe"
        validated.stream.seek(0, os.SEEK_END)
        assert validated.stream.tell() == 4
        validated.stream.seek(0)
        request = httpx.Request(
            "POST",
            "https://example.test/upload",
            files={"file": ("media.bin", validated.stream)},
        )
        body = request.read()
        assert b"safe-appended" not in body
        assert int(request.headers["content-length"]) == len(body)


def test_symlink_file_and_component_are_rejected(tmp_path: Path) -> None:
    allowed = tmp_path / "allowed"
    target_dir = tmp_path / "target"
    allowed.mkdir()
    target_dir.mkdir()
    target = target_dir / "media.bin"
    target.write_bytes(b"x")
    roots = prepare_allowed_roots([str(allowed)])
    link = allowed / "linked.bin"
    directory_link = allowed / "linked-dir"
    try:
        link.symlink_to(target)
        directory_link.symlink_to(target_dir, target_is_directory=True)
    except OSError:
        pytest.skip("symlink creation is not permitted on this platform")

    with pytest.raises(LocalFileError) as final_link:
        open_validated_media(str(link), roots, max_bytes=10)
    assert final_link.value.code == "unsafe_path"
    with pytest.raises(LocalFileError) as component_link:
        open_validated_media(str(directory_link / "media.bin"), roots, max_bytes=10)
    assert component_link.value.code == "unsafe_path"


@pytest.mark.skipif(os.name != "nt", reason="Windows junction semantics")
def test_windows_junction_component_is_rejected(tmp_path: Path) -> None:
    allowed = tmp_path / "allowed"
    target = tmp_path / "target"
    allowed.mkdir()
    target.mkdir()
    (target / "media.bin").write_bytes(b"x")
    junction = allowed / "junction"
    completed = subprocess.run(
        ["cmd", "/c", "mklink", "/J", str(junction), str(target)],
        capture_output=True,
        text=True,
        check=False,
    )
    if completed.returncode != 0:
        pytest.skip("junction creation is not permitted")
    roots = prepare_allowed_roots([str(allowed)])
    with pytest.raises(LocalFileError) as raised:
        open_validated_media(str(junction / "media.bin"), roots, max_bytes=10)
    assert raised.value.code == "unsafe_path"


@pytest.mark.parametrize(
    "path",
    [
        r"\\?\C:\media\image.jpg",
        r"\\.\PhysicalDrive0",
        r"C:\media\image.jpg:secret",
        r"C:\media\CON.jpg",
        r"C:\media\LPT9",
    ],
)
def test_windows_device_and_ads_forms_are_recognized(path: str) -> None:
    assert _contains_windows_device_or_ads(path)


def test_nul_is_rejected_without_echoing_input(tmp_path: Path) -> None:
    roots = prepare_allowed_roots([str(tmp_path)])
    with pytest.raises(LocalFileError) as raised:
        open_validated_media(f"{tmp_path}\x00secret", roots, max_bytes=10)
    assert "secret" not in str(raised.value)


@pytest.mark.skipif(os.name != "nt", reason="Windows drive and UNC semantics")
def test_windows_cross_drive_and_unc_containment_is_component_aware() -> None:
    assert not _is_contained(Path(r"E:\media\clip.mp4"), Path(r"D:\media"))
    assert _is_contained(
        Path(r"\\server\share\allowed\clip.mp4"),
        Path(r"\\server\share\allowed"),
    )
    assert not _is_contained(
        Path(r"\\server\other\allowed\clip.mp4"),
        Path(r"\\server\share\allowed"),
    )
