import 'errors.dart';

/// Filesystem paths are unavailable on this platform (for example Flutter
/// Web).
class FileSource {
  FileSource._();

  int get length => 0;

  Stream<List<int>> open() => const Stream.empty();
}

Future<FileSource> openFileSource(String path) async {
  throw ValidationError(
    ValidationErrorCode.unsupportedInput,
    'File paths are not supported on this platform; use MediaInput.bytes or '
    'MediaInput.openRead instead.',
  );
}
