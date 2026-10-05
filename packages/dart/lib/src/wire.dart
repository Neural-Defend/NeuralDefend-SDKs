import 'errors.dart';
import 'models.dart';

const String imageEnvelope = 'unified_face_authenticity_score';
const String videoEnvelope = 'unified_video_authenticity_score';

/// Replaces every occurrence of [secret] in [value].
String redact(String value, String secret) =>
    secret.isEmpty ? value : value.split(secret).join('[REDACTED]');

/// Deep, redacted, unmodifiable copy of decoded JSON.
Object? freezeJson(Object? value, String secret) => switch (value) {
      String() => redact(value, secret),
      Map() => Map<String, Object?>.unmodifiable({
          for (final entry in value.entries)
            '${entry.key}': freezeJson(entry.value, secret),
        }),
      List() => List<Object?>.unmodifiable(
          value.map((nested) => freezeJson(nested, secret)),
        ),
      _ => value,
    };

Map<String, Object?> freezeEnvelope(Map<String, Object?> value, String secret) =>
    freezeJson(value, secret)! as Map<String, Object?>;

class _Context {
  _Context(this.httpStatus, this.requestId);
  final int httpStatus;
  final String? requestId;

  ProtocolError invalid(String field, [String expectation = 'was missing or invalid']) =>
      ProtocolError(
        'The response field "$field" $expectation.',
        statusCode: httpStatus,
        requestId: requestId,
      );
}

String _requiredString(Map<String, Object?> value, String field, _Context context) {
  final candidate = value[field];
  if (candidate is! String) throw context.invalid(field);
  return candidate;
}

int _requiredInt(Map<String, Object?> value, String field, _Context context) {
  final candidate = value[field];
  if (candidate is int) return candidate;
  if (candidate is double && candidate.isFinite && candidate == candidate.truncateToDouble()) {
    return candidate.toInt();
  }
  throw context.invalid(field, 'must be an integer');
}

double? _nullableScore(Map<String, Object?> value, String field, _Context context) {
  if (!value.containsKey(field)) throw context.invalid(field, 'was missing');
  final candidate = value[field];
  if (candidate == null) return null;
  if (candidate is! num || !candidate.isFinite || candidate < 0.1 || candidate > 10.0) {
    throw context.invalid(field, 'must be from 0.1 through 10.0 or null');
  }
  return candidate.toDouble();
}

String? _nullableString(Map<String, Object?> value, String field, _Context context) {
  if (!value.containsKey(field)) throw context.invalid(field, 'was missing');
  final candidate = value[field];
  if (candidate == null || candidate is String) return candidate as String?;
  throw context.invalid(field, 'must be a string or null');
}

bool _billable(Map<String, Object?> value, _Context context) => switch (value['billable']) {
      'Y' => true,
      'N' => false,
      _ => throw context.invalid('billable', 'must be exactly "Y" or "N"'),
    };

List<String> _signals(Map<String, Object?> value, _Context context) {
  final candidate = value['ai_threat_signals'];
  if (candidate == null) return const [];
  if (candidate is! List || candidate.any((item) => item is! String)) {
    throw context.invalid('ai_threat_signals', 'must be an array of strings');
  }
  return List<String>.unmodifiable(candidate.cast<String>());
}

ResultStatus _status(String wire) => switch (wire) {
      'success' => ResultStatus.success,
      'rejected' => ResultStatus.rejected,
      _ => ResultStatus.unknown,
    };

ServerError _envelopeError(
  String message,
  Map<String, Object?> envelope,
  String secret,
  _Context context,
) =>
    ServerError(
      redact(message, secret),
      statusCode: context.httpStatus,
      requestId: context.requestId,
      raw: freezeEnvelope(envelope, secret),
    );

/// Parses an image envelope. Throws [ServerError] for `status: "error"` and
/// [ProtocolError] for contract violations.
ImageResult parseImage(
  Map<String, Object?> envelope, {
  required int httpStatus,
  required String? requestId,
  required String secret,
}) {
  final context = _Context(httpStatus, requestId);
  final originalStatus = _requiredString(envelope, 'status', context);
  final uniqueTrxId = _requiredString(envelope, 'unique_trx_id', context);
  final filename = _requiredString(envelope, 'filename', context);
  final contentType = _requiredString(envelope, 'content_type', context);
  final statusCode = _requiredInt(envelope, 'status_code', context);
  final billable = _billable(envelope, context);
  final signals = _signals(envelope, context);
  final message = _requiredString(envelope, 'message', context);
  final score = _nullableScore(envelope, 'risk_score', context);
  final originalLevel = _nullableString(envelope, 'risk_level', context);
  final level = RiskLevel.tryParse(originalLevel);

  if (originalStatus == 'error') {
    throw _envelopeError(message, envelope, secret, context);
  }
  var status = _status(originalStatus);
  if (status == ResultStatus.success && (score == null || level == null)) {
    status = ResultStatus.unknown;
  }
  return ImageResult(
    status: status,
    originalStatus: originalStatus,
    uniqueTrxId: uniqueTrxId,
    filename: filename,
    contentType: contentType,
    statusCode: statusCode,
    billable: billable,
    aiThreatSignals: signals,
    raw: freezeEnvelope(envelope, secret),
    riskScore: score,
    riskLevel: level,
    originalRiskLevel: originalLevel,
    message: message,
  );
}

/// Parses a video envelope. Throws [ServerError] for `status: "error"` and
/// [ProtocolError] for contract violations.
VideoResult parseVideo(
  Map<String, Object?> envelope, {
  required int httpStatus,
  required String? requestId,
  required String secret,
}) {
  final context = _Context(httpStatus, requestId);
  final originalStatus = _requiredString(envelope, 'status', context);
  final uniqueTrxId = _requiredString(envelope, 'unique_trx_id', context);
  final filename = _requiredString(envelope, 'filename', context);
  final contentType = _requiredString(envelope, 'content_type', context);
  final statusCode = _requiredInt(envelope, 'status_code', context);
  final billable = _billable(envelope, context);
  final signals = _signals(envelope, context);
  final videoMessage = _requiredString(envelope, 'video_message', context);
  final audioMessage = _nullableString(envelope, 'audio_message', context);
  final videoScore = _nullableScore(envelope, 'video_risk_score', context);
  final originalVideoLevel = _nullableString(envelope, 'video_risk_level', context);
  final videoLevel = RiskLevel.tryParse(originalVideoLevel);
  final audioScore = _nullableScore(envelope, 'audio_risk_score', context);
  final originalAudioLevel = _nullableString(envelope, 'audio_risk_level', context);
  final audioLevel = RiskLevel.tryParse(originalAudioLevel);

  if (originalStatus == 'error') {
    throw _envelopeError(videoMessage, envelope, secret, context);
  }
  var status = _status(originalStatus);
  if (status == ResultStatus.success) {
    final videoScored = videoScore != null && videoLevel != null;
    final audioConsistent = (audioScore == null && originalAudioLevel == null) ||
        (audioScore != null && audioLevel != null);
    if (!videoScored || !audioConsistent) status = ResultStatus.unknown;
  }
  return VideoResult(
    status: status,
    originalStatus: originalStatus,
    uniqueTrxId: uniqueTrxId,
    filename: filename,
    contentType: contentType,
    statusCode: statusCode,
    billable: billable,
    aiThreatSignals: signals,
    raw: freezeEnvelope(envelope, secret),
    videoRiskScore: videoScore,
    videoRiskLevel: videoLevel,
    originalVideoRiskLevel: originalVideoLevel,
    videoMessage: videoMessage,
    audioRiskScore: audioScore,
    audioRiskLevel: audioLevel,
    originalAudioRiskLevel: originalAudioLevel,
    audioMessage: audioMessage,
  );
}
