# Changelog

All notable changes to this package follow Keep a Changelog and Semantic Versioning.

## [Unreleased]

## [1.0.3] - 2026-08-22

### Changed

- Relaxed the mypy dev dependency upper bound to `<3` and pinned ruff to `0.16.1`.

## [1.0.2] - 2026-07-27

### Changed

- Expanded PyPI metadata with SEO keywords, Homepage/Repository links, and topic
  classifiers for deepfake and AI-generated media detection.
- Added Neural Defend website API-key onboarding steps and inline code comments across
  guides, examples, and the media-authenticity agent skill.

## [1.0.1] - 2026-07-27

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
- Expanded the published guide with complete onboarding, method documentation, normalized
  response examples, retry and billing guidance, privacy controls, and troubleshooting.

## [1.0.0] - 2026-07-26

### Added

- Initial typed `NeuroVerifyClient` facade for image and video analysis.
- Streaming `httpx` multipart transport with bounded retries and rewind support.
- Immutable result models, tolerant raw JSON parsing, and documented error hierarchy.
- JSON-serializable normalized result output with explicit, separate raw diagnostics.
- Local upload and video-parameter validation.

Contract: NeuroVerify OpenAPI 1.0.0 from source commit
`494fc8c88585e0920efe54b41f3f8d355025c475`.

[Unreleased]: https://github.com/Neural-Defend/NeuralDefend-SDKs/compare/python-v1.0.3...HEAD
[1.0.3]: https://github.com/Neural-Defend/NeuralDefend-SDKs/compare/python-v1.0.2...python-v1.0.3
[1.0.2]: https://github.com/Neural-Defend/NeuralDefend-SDKs/compare/python-v1.0.1...python-v1.0.2
[1.0.1]: https://github.com/Neural-Defend/NeuralDefend-SDKs/compare/python-v1.0.0...python-v1.0.1
[1.0.0]: https://github.com/Neural-Defend/NeuralDefend-SDKs/releases/tag/python-v1.0.0
