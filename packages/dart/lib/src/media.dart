import 'dart:async';
import 'dart:typed_data';

import 'errors.dart';
import 'file_source_stub.dart' if (dart.library.io) 'file_source_io.dart';
import 'models.dart';

/// Exact maximum image upload size: 10 MiB.
const int imageMaxBytes = 10 * 1024 * 1024;

/// Exact maximum video upload size: 1,500,000,000 bytes.
const int videoMaxBytes = 1500000000;

const Map<String, String> _imageMimeTypes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'bmp': 'image/bmp',
  'tif': 'image/tiff',
  'tiff': 'image/tiff',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'heif': 'image/heif',
};

const Map<String, String> _videoMimeTypes = {
  'mp4': 'video/mp4',
  'avi': 'video/vnd.avi',
  'mov': 'video/quicktime',
  'mkv': 'video/matroska',
  'wmv': 'video/x-ms-wmv',
  'flv': 'video/x-flv',
  'webm': 'video/webm',
  'ogg': 'video/ogg',
  'ogv': 'video/ogg',
};

/// Documented image extensions, without the leading dot.
final Set<String> imageExtensions = Set.unmodifiable(_imageMimeTypes.keys);

/// Documented video extensions, without the leading dot.
final Set<String> videoExtensions = Set.unmodifiable(_videoMimeTypes.keys);

/// Deterministic multipart MIME type for [filename]. Unknown extensions use
/// `application/octet-stream`; the server still inspects the content.
String mimeForFilename(String filename) {
  final extension = _extension(filename);
  return _imageMimeTypes[extension] ??
      _videoMimeTypes[extension] ??
      'application/octet-stream';
}

String? _extension(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return null;
  return filename.substring(dot + 1).toLowerCase();
}

/// Upload input for `detectImage` and `detectVideo`.
///
/// Every variant except [MediaInput.stream] can be replayed, so automatic
/// retries send the same bytes again.
sealed class MediaInput {
  const MediaInput._(this._filename);

  /// A readable regular file on the local filesystem (mobile, desktop, and
  /// server). The file is streamed, never fully loaded into memory, and is
  /// reopened for each retry. [filename] defaults to the path's basename.
  ///
  /// Not available on Flutter Web; use [MediaInput.bytes] or
  /// [MediaInput.openRead] there.
  const factory MediaInput.file(String path, {String? filename}) = _FileMedia;

  /// In-memory bytes. [filename] is required because it selects the multipart
  /// MIME type; include the real extension.
  const factory MediaInput.bytes(Uint8List bytes, {required String filename}) =
      _BytesMedia;

  /// A source that can be read more than once, such as a Flutter `XFile`:
  ///
  /// ```dart
  /// MediaInput.openRead(
  ///   file.openRead,
  ///   length: await file.length(),
  ///   filename: file.name,
  /// )
  /// ```
  ///
  /// [openRead] is called once per attempt and must return the complete
  /// content of exactly [length] bytes each time.
  const factory MediaInput.openRead(
    Stream<List<int>> Function() openRead, {
    required int length,
    required String filename,
  }) = _ReopenableMedia;

  /// A single-use stream of exactly [length] bytes. Because it cannot be
  /// replayed, the client must be configured with `maxRetries: 0`.
  const factory MediaInput.stream(
    Stream<List<int>> stream, {
    required int length,
    required String filename,
  }) = _StreamMedia;

  final String? _filename;
}

final class _FileMedia extends MediaInput {
  const _FileMedia(this.path, {String? filename}) : super._(filename);
  final String path;
}

final class _BytesMedia extends MediaInput {
  const _BytesMedia(this.bytes, {required String filename}) : super._(filename);
  final Uint8List bytes;
}

final class _ReopenableMedia extends MediaInput {
  const _ReopenableMedia(
    this.openRead, {
    required this.length,
    required String filename,
  }) : super._(filename);
  final Stream<List<int>> Function() openRead;
  final int length;
}

final class _StreamMedia extends MediaInput {
  const _StreamMedia(
    this.stream, {
    required this.length,
    required String filename,
  }) : super._(filename);
  final Stream<List<int>> stream;
  final int length;
}

/// Kind of detection endpoint.
enum DetectionKind {
  image('/detect/image', imageMaxBytes, '10 MiB'),
  video('/detect/video', videoMaxBytes, '1.5 GB');

  const DetectionKind(this.path, this.maxBytes, this.limitLabel);

  final String path;
  final int maxBytes;
  final String limitLabel;

  Set<String> get extensions =>
      this == DetectionKind.image ? imageExtensions : videoExtensions;
}

/// Validated media ready for one or more upload attempts.
class PreparedMedia {
  PreparedMedia._({
    required this.filename,
    required this.length,
    required this.replayable,
    required Stream<List<int>> Function() open,
  }) : _open = open;

  final String filename;
  final int length;
  final bool replayable;
  final Stream<List<int>> Function() _open;
  bool _opened = false;

  String get contentType => mimeForFilename(filename);

  /// Opens the content for one attempt. The returned stream emits exactly
  /// [length] bytes or fails with a [ValidationError].
  Stream<List<int>> open() {
    if (_opened && !replayable) {
      throw ValidationError(
        ValidationErrorCode.streamNotReplayable,
        'A single-use stream cannot be uploaded more than once.',
      );
    }
    _opened = true;
    return _exactLength(_open(), length);
  }
}

/// Validates [input] for [kind] and returns a replayable upload source.
Future<PreparedMedia> prepareMedia(
  MediaInput input,
  DetectionKind kind,
  void Function(ValidationWarning warning) onWarning,
) async {
  final PreparedMedia prepared;
  switch (input) {
    case _FileMedia(:final path):
      final source = await openFileSource(path);
      prepared = PreparedMedia._(
        filename: _requireFilename(input._filename ?? _basename(path)),
        length: source.length,
        replayable: true,
        open: source.open,
      );
    case _BytesMedia(:final bytes):
      prepared = PreparedMedia._(
        filename: _requireFilename(input._filename),
        length: bytes.length,
        replayable: true,
        open: () => Stream<List<int>>.value(bytes),
      );
    case _ReopenableMedia(:final openRead, :final length):
      prepared = PreparedMedia._(
        filename: _requireFilename(input._filename),
        length: length,
        replayable: true,
        open: openRead,
      );
    case _StreamMedia(:final stream, :final length):
      prepared = PreparedMedia._(
        filename: _requireFilename(input._filename),
        length: length,
        replayable: false,
        open: () => stream,
      );
  }

  if (prepared.length <= 0) {
    throw ValidationError(ValidationErrorCode.emptyFile, 'The upload is empty.');
  }
  if (prepared.length > kind.maxBytes) {
    throw ValidationError(
      ValidationErrorCode.fileTooLarge,
      'The ${kind.name} exceeds the ${kind.limitLabel} limit.',
    );
  }
  final extension = _extension(prepared.filename);
  if (extension == null || !kind.extensions.contains(extension)) {
    onWarning(ValidationWarning(
      code: 'unsupported_extension',
      filename: prepared.filename,
      message: 'The .${extension ?? '(none)'} extension is not documented '
          'for ${kind.name} uploads; the server will inspect the content.',
    ));
  }
  return prepared;
}

String _requireFilename(String? filename) {
  final trimmed = filename?.trim() ?? '';
  if (trimmed.isEmpty) {
    throw ValidationError(
      ValidationErrorCode.filenameRequired,
      'A filename with the real extension is required, for example '
      '"photo.jpg" or "clip.mp4".',
    );
  }
  return _basename(trimmed);
}

String _basename(String path) {
  final separator = path.lastIndexOf(RegExp(r'[/\\]'));
  return separator < 0 ? path : path.substring(separator + 1);
}

Stream<List<int>> _exactLength(Stream<List<int>> source, int length) async* {
  var seen = 0;
  await for (final chunk in source) {
    seen += chunk.length;
    if (seen > length) {
      throw ValidationError(
        ValidationErrorCode.fileTooLarge,
        'The upload produced more than the declared $length bytes.',
      );
    }
    yield chunk;
  }
  if (seen != length) {
    throw ValidationError(
      ValidationErrorCode.unsupportedInput,
      'The upload ended after $seen of the declared $length bytes.',
    );
  }
}
