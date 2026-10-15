import 'dart:math' as math;

/// Service-owned risk band. Base decisions on the band rather than on score
/// thresholds, which the service may tune.
enum RiskLevel {
  low,
  medium,
  high;

  /// Returns the band for a wire value, or `null` when the value is absent or
  /// not recognized by this SDK version.
  static RiskLevel? tryParse(String? value) => switch (value) {
        'low' => RiskLevel.low,
        'medium' => RiskLevel.medium,
        'high' => RiskLevel.high,
        _ => null,
      };
}

/// Normalized outcome of a detection request.
enum ResultStatus {
  /// The media was scored and every returned risk band is recognized.
  success,

  /// The API declined to score the media. This is a normal result, not an
  /// exception, and it can be billable.
  rejected,

  /// The API returned an outcome or risk band this SDK version does not
  /// recognize. Do not make policy decisions from it; upgrade the SDK.
  unknown,
}

/// Additional per-call warning that does not prevent the upload.
class ValidationWarning {
  const ValidationWarning({
    required this.code,
    required this.message,
    required this.filename,
  });

  /// Currently always `unsupported_extension`.
  final String code;
  final String message;
  final String filename;

  @override
  String toString() => 'ValidationWarning($code): $message';
}

abstract class _DetectionResult {
  _DetectionResult({
    required this.status,
    required this.originalStatus,
    required this.uniqueTrxId,
    required this.filename,
    required this.contentType,
    required this.statusCode,
    required this.billable,
    required this.aiThreatSignals,
    required this.raw,
  });

  /// Normalized outcome. Always branch on this before reading scores.
  final ResultStatus status;

  /// Exact wire `status` value, useful when [status] is
  /// [ResultStatus.unknown].
  final String originalStatus;

  /// Transaction ID. Every accepted attempt receives a new one; persist it for
  /// audit, billing, and support correlation.
  final String uniqueTrxId;

  final String filename;

  /// Content type detected by the service.
  final String contentType;

  /// Service status code. Unknown values are preserved.
  final int statusCode;

  /// Authoritative billing indicator for this transaction. Rejections can be
  /// billable.
  final bool billable;

  /// Checks reported by the service. The list may evolve; do not build fixed
  /// logic around it.
  final List<String> aiThreatSignals;

  /// Redacted, unmodifiable wire envelope using the API's field names.
  ///
  /// Not a stable contract and excluded from [toJson]. It may contain
  /// filenames, messages, future fields, or other customer data; do not log or
  /// persist it routinely.
  final Map<String, Object?> raw;

  /// `true` only for a recognized, scored result.
  bool get scored => status == ResultStatus.success;

  /// `true` when the API rejected the media without an exception.
  bool get rejected => status == ResultStatus.rejected;

  Map<String, Object?> _baseJson() => {
        'status': status.name,
        'scored': scored,
        'rejected': rejected,
        if (status == ResultStatus.unknown) 'originalStatus': originalStatus,
        'uniqueTrxId': uniqueTrxId,
        'filename': filename,
        'contentType': contentType,
        'statusCode': statusCode,
        'billable': billable,
        'aiThreatSignals': aiThreatSignals,
      };

  /// Stable normalized fields as a JSON-compatible map. Excludes [raw].
  Map<String, Object?> toJson();
}

/// Result of [NeuroVerifyClient.detectImage].
class ImageResult extends _DetectionResult {
  ImageResult({
    required super.status,
    required super.originalStatus,
    required super.uniqueTrxId,
    required super.filename,
    required super.contentType,
    required super.statusCode,
    required super.billable,
    required super.aiThreatSignals,
    required super.raw,
    required this.riskScore,
    required this.riskLevel,
    required this.originalRiskLevel,
    required this.message,
  });

  /// Risk score from 0.1 through 10.0; higher means more observed risk.
  /// `null` when the image was not scored.
  final double? riskScore;

  /// Recognized risk band, or `null` when unscored or unrecognized.
  final RiskLevel? riskLevel;

  /// Exact wire `risk_level` value, preserved for unknown bands.
  final String? originalRiskLevel;

  /// Service message. Suitable for user guidance; do not branch on its text.
  final String message;

  /// `true` when the recognized risk band is [RiskLevel.high].
  bool get highRisk => riskLevel == RiskLevel.high;

  @override
  Map<String, Object?> toJson() => {
        ..._baseJson(),
        if (status == ResultStatus.unknown)
          'originalRiskLevel': originalRiskLevel,
        'riskScore': riskScore,
        'riskLevel': riskLevel?.name,
        'message': message,
        'highRisk': highRisk,
      };

  @override
  String toString() => 'ImageResult(${toJson()})';
}

/// Result of [NeuroVerifyClient.detectVideo]. Video and audio are independent
/// modalities and can carry different risk bands.
class VideoResult extends _DetectionResult {
  VideoResult({
    required super.status,
    required super.originalStatus,
    required super.uniqueTrxId,
    required super.filename,
    required super.contentType,
    required super.statusCode,
    required super.billable,
    required super.aiThreatSignals,
    required super.raw,
    required this.videoRiskScore,
    required this.videoRiskLevel,
    required this.originalVideoRiskLevel,
    required this.videoMessage,
    required this.audioRiskScore,
    required this.audioRiskLevel,
    required this.originalAudioRiskLevel,
    required this.audioMessage,
  });

  final double? videoRiskScore;
  final RiskLevel? videoRiskLevel;
  final String? originalVideoRiskLevel;
  final String videoMessage;

  /// `null` when the video has no audio track or was not scored.
  final double? audioRiskScore;
  final RiskLevel? audioRiskLevel;
  final String? originalAudioRiskLevel;

  /// For example `"No audio track detected"`; `null` on rejections.
  final String? audioMessage;

  /// `true` when an audio risk score was returned.
  bool get hasAudio => audioRiskScore != null;

  /// SDK convenience: the maximum available modality score. The API does not
  /// return a combined score, and this does not replace modality-aware policy.
  double? get overallRiskScore {
    final video = videoRiskScore;
    final audio = audioRiskScore;
    if (video == null) return audio;
    if (audio == null) return video;
    return math.max(video, audio);
  }

  @override
  Map<String, Object?> toJson() => {
        ..._baseJson(),
        if (status == ResultStatus.unknown) ...{
          'originalVideoRiskLevel': originalVideoRiskLevel,
          'originalAudioRiskLevel': originalAudioRiskLevel,
        },
        'hasAudio': hasAudio,
        'videoRiskScore': videoRiskScore,
        'videoRiskLevel': videoRiskLevel?.name,
        'videoMessage': videoMessage,
        'audioRiskScore': audioRiskScore,
        'audioRiskLevel': audioRiskLevel?.name,
        'audioMessage': audioMessage,
        'overallRiskScore': overallRiskScore,
      };

  @override
  String toString() => 'VideoResult(${toJson()})';
}
