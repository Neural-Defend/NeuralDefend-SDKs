import 'dart:io';

/// Whether this runtime is a Flutter app. Flutter apps never read process
/// environment variables for credentials; the key must be passed explicitly.
const bool _isFlutter = bool.fromEnvironment('dart.library.ui');

/// Reads a process environment variable on the Dart VM (servers and CLIs).
String? environmentValue(String name) {
  if (_isFlutter) return null;
  final value = Platform.environment[name];
  return value == null || value.trim().isEmpty ? null : value;
}

/// Whether the runtime allows the SDK to set a `User-Agent` header.
const bool canSetUserAgent = true;

/// Short runtime label used in error messages.
const String platformLabel = _isFlutter ? 'flutter' : 'dart-vm';
