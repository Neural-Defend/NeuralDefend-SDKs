# Changelog

All notable changes to this package follow Keep a Changelog and Semantic Versioning.

## [Unreleased]

### Changed

- Replaced platform-dependent `mimetypes.guess_type()` with a deterministic
  extension-to-MIME mapping covering every documented image and video format.
- Added `.heif` as a recognized image extension (was missing from the documented
  HEIC/HEIF family).
- Require `filename=` for byte inputs and nameless streams so multipart metadata is
  deterministic.
- Use current canonical AVI and Matroska media types.
- Reject non-Neural Defend API origins unless `allow_custom_base_url=True` is explicitly
  set; redirects remain disabled so credentials and media cannot be forwarded.
- Keep path uploads bound to one validated file handle across retries, require a literal
  boolean custom-origin opt-in, and reject response scores outside `0.1` through `10.0`.

## [1.0.0] - 2026-07-26

### Added

- Initial typed `NeuroVerifyClient` facade for image and video analysis.
- Streaming `httpx` multipart transport with bounded retries and rewind support.
- Immutable result models, tolerant raw JSON parsing, and documented error hierarchy.
- JSON-serializable normalized result output with explicit, separate raw diagnostics.
- Local upload and video-parameter validation.

Contract: NeuroVerify OpenAPI 1.0.0 from source commit
`494fc8c88585e0920efe54b41f3f8d355025c475`.

[Unreleased]: https://github.com/Neural-Defend/NeuralDefend-SDKs/compare/python-v1.0.0...HEAD
[1.0.0]: https://github.com/Neural-Defend/NeuralDefend-SDKs/releases/tag/python-v1.0.0
