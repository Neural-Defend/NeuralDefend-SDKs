/// Official Dart and Flutter client for the Neural Defend NeuroVerify image
/// and video authenticity API.
///
/// ```dart
/// final client = NeuroVerifyClient(apiKey: apiKey);
/// try {
///   final result = await client.detectImage(MediaInput.file('selfie.jpg'));
///   switch (result.status) {
///     case ResultStatus.success:
///       print('${result.riskLevel} (${result.riskScore})');
///     case ResultStatus.rejected:
///       print('Not scored: ${result.message}');
///     case ResultStatus.unknown:
///       print('Upgrade the SDK: ${result.originalStatus}');
///   }
/// } finally {
///   client.close();
/// }
/// ```
///
/// Risk scores and bands are decision-support signals, not proof that media
/// is authentic or manipulated.
library;

export 'src/client.dart'
    show NeuroVerifyClient, UploadProgressCallback, productionUrl, stagingUrl;
export 'src/errors.dart'
    show
        AbortError,
        AuthenticationError,
        HttpError,
        NetworkError,
        NeuroVerifyError,
        ProtocolError,
        RateLimitError,
        ScopeError,
        ServerError,
        TimeoutError,
        ValidationError,
        ValidationErrorCode;
export 'src/media.dart'
    show
        MediaInput,
        imageExtensions,
        imageMaxBytes,
        mimeForFilename,
        videoExtensions,
        videoMaxBytes;
export 'src/models.dart'
    show ImageResult, ResultStatus, RiskLevel, ValidationWarning, VideoResult;
export 'src/version.dart' show sdkVersion;
