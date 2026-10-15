/// Browsers and Flutter Web expose no process environment.
String? environmentValue(String name) => null;

/// Browsers forbid scripts from setting `User-Agent`.
const bool canSetUserAgent = false;

/// Short runtime label used in error messages.
const String platformLabel = 'web';
