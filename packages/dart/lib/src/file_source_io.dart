import 'dart:io';

import 'errors.dart';

/// A regular file that can be opened once per upload attempt.
class FileSource {
  FileSource(this._file, this.length);

  final File _file;
  final int length;

  Stream<List<int>> open() => _file.openRead();
}

Future<FileSource> openFileSource(String path) async {
  if (path.trim().isEmpty) {
    throw ValidationError(
      ValidationErrorCode.fileNotFound,
      'The file path must not be empty.',
    );
  }
  final type = await FileSystemEntity.type(path, followLinks: false);
  if (type == FileSystemEntityType.link) {
    throw ValidationError(
      ValidationErrorCode.unsupportedInput,
      'The file path must not be a symbolic link.',
    );
  }
  if (type == FileSystemEntityType.notFound) {
    throw ValidationError(
      ValidationErrorCode.fileNotFound,
      'The file path does not exist or is not readable.',
    );
  }
  if (type != FileSystemEntityType.file) {
    throw ValidationError(
      ValidationErrorCode.unsupportedInput,
      'The file path must reference a regular file.',
    );
  }
  final file = File(path);
  try {
    final length = await file.length();
    final handle = await file.open();
    await handle.close();
    return FileSource(file, length);
  } on FileSystemException {
    throw ValidationError(
      ValidationErrorCode.fileNotFound,
      'The file path does not exist or is not readable.',
    );
  }
}
