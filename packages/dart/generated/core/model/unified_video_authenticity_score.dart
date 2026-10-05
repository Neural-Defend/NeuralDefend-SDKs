//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of neuraldefend_core;

class UnifiedVideoAuthenticityScore {
  /// Returns a new [UnifiedVideoAuthenticityScore] instance.
  UnifiedVideoAuthenticityScore({
    required this.uniqueTrxId,
    required this.filename,
    required this.contentType,
    required this.status,
    required this.billable,
    required this.statusCode,
    required this.videoRiskScore,
    required this.videoRiskLevel,
    required this.videoMessage,
    required this.audioRiskScore,
    required this.audioRiskLevel,
    required this.audioMessage,
    this.aiThreatSignals = const [],
  });

  /// Unique transaction identifier. Store it for audit trail correlation and dispute resolution.
  String uniqueTrxId;

  /// Name of the uploaded file, as received.
  String filename;

  /// MIME type detected for the uploaded file.
  String contentType;

  /// Outcome of the request. `success` means the file was scored. `rejected` means the file did not pass pre-analysis validation and was not scored. `error` means a server-side failure prevented analysis.
  UnifiedVideoAuthenticityScoreStatusEnum status;

  /// `Y` when the request counts toward billing, `N` otherwise.
  UnifiedVideoAuthenticityScoreBillableEnum billable;

  /// 1 scored successfully (HTTP 200, billable). 2 input validation rejection (HTTP 400, not billable). 5 server-side error (HTTP 500 or 503, not billable). 6 no scorable single-face frames (HTTP 200, billable).
  UnifiedVideoAuthenticityScoreStatusCodeEnum statusCode;

  /// Video modality risk from 0.1 to 10.0, where higher means a higher likelihood of AI manipulation. Null when the request was rejected or errored.
  ///
  /// Minimum value: 0.1
  /// Maximum value: 10.0
  double? videoRiskScore;

  /// Video risk band: low is 0.1-3.9, medium is 4.0-6.9, high is 7.0-10.0. Null when the video was not scored.
  UnifiedVideoAuthenticityScoreVideoRiskLevelEnum? videoRiskLevel;

  /// Human-readable explanation for the video modality. Rejection and error copy is carried on this field.
  String videoMessage;

  /// Audio modality risk from 0.1 to 10.0. Null when the video has no audio track, or when audio analysis was skipped or failed.
  ///
  /// Minimum value: 0.1
  /// Maximum value: 10.0
  double? audioRiskScore;

  /// Audio risk band, using the same thresholds as video. Null when the audio was not scored.
  UnifiedVideoAuthenticityScoreAudioRiskLevelEnum? audioRiskLevel;

  /// Human-readable explanation for the audio modality, such as \"No audio track detected\". Null on rejected requests.
  String? audioMessage;

  /// Checks applied during analysis. Present only on scored responses.
  List<String> aiThreatSignals;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UnifiedVideoAuthenticityScore &&
    other.uniqueTrxId == uniqueTrxId &&
    other.filename == filename &&
    other.contentType == contentType &&
    other.status == status &&
    other.billable == billable &&
    other.statusCode == statusCode &&
    other.videoRiskScore == videoRiskScore &&
    other.videoRiskLevel == videoRiskLevel &&
    other.videoMessage == videoMessage &&
    other.audioRiskScore == audioRiskScore &&
    other.audioRiskLevel == audioRiskLevel &&
    other.audioMessage == audioMessage &&
    _deepEquality.equals(other.aiThreatSignals, aiThreatSignals);

  @override
  int get hashCode =>
    // ignore: unnecessary_parenthesis
    (uniqueTrxId.hashCode) +
    (filename.hashCode) +
    (contentType.hashCode) +
    (status.hashCode) +
    (billable.hashCode) +
    (statusCode.hashCode) +
    (videoRiskScore == null ? 0 : videoRiskScore!.hashCode) +
    (videoRiskLevel == null ? 0 : videoRiskLevel!.hashCode) +
    (videoMessage.hashCode) +
    (audioRiskScore == null ? 0 : audioRiskScore!.hashCode) +
    (audioRiskLevel == null ? 0 : audioRiskLevel!.hashCode) +
    (audioMessage == null ? 0 : audioMessage!.hashCode) +
    (aiThreatSignals.hashCode);

  @override
  String toString() => 'UnifiedVideoAuthenticityScore[uniqueTrxId=$uniqueTrxId, filename=$filename, contentType=$contentType, status=$status, billable=$billable, statusCode=$statusCode, videoRiskScore=$videoRiskScore, videoRiskLevel=$videoRiskLevel, videoMessage=$videoMessage, audioRiskScore=$audioRiskScore, audioRiskLevel=$audioRiskLevel, audioMessage=$audioMessage, aiThreatSignals=$aiThreatSignals]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'unique_trx_id'] = this.uniqueTrxId;
      json[r'filename'] = this.filename;
      json[r'content_type'] = this.contentType;
      json[r'status'] = this.status;
      json[r'billable'] = this.billable;
      json[r'status_code'] = this.statusCode;
    if (this.videoRiskScore != null) {
      json[r'video_risk_score'] = this.videoRiskScore;
    } else {
      json[r'video_risk_score'] = null;
    }
    if (this.videoRiskLevel != null) {
      json[r'video_risk_level'] = this.videoRiskLevel;
    } else {
      json[r'video_risk_level'] = null;
    }
      json[r'video_message'] = this.videoMessage;
    if (this.audioRiskScore != null) {
      json[r'audio_risk_score'] = this.audioRiskScore;
    } else {
      json[r'audio_risk_score'] = null;
    }
    if (this.audioRiskLevel != null) {
      json[r'audio_risk_level'] = this.audioRiskLevel;
    } else {
      json[r'audio_risk_level'] = null;
    }
    if (this.audioMessage != null) {
      json[r'audio_message'] = this.audioMessage;
    } else {
      json[r'audio_message'] = null;
    }
      json[r'ai_threat_signals'] = this.aiThreatSignals;
    return json;
  }

  /// Returns a new [UnifiedVideoAuthenticityScore] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static UnifiedVideoAuthenticityScore? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        requiredKeys.forEach((key) {
          assert(json.containsKey(key), 'Required key "UnifiedVideoAuthenticityScore[$key]" is missing from JSON.');
          assert(json[key] != null, 'Required key "UnifiedVideoAuthenticityScore[$key]" has a null value in JSON.');
        });
        return true;
      }());

      return UnifiedVideoAuthenticityScore(
        uniqueTrxId: mapValueOfType<String>(json, r'unique_trx_id')!,
        filename: mapValueOfType<String>(json, r'filename')!,
        contentType: mapValueOfType<String>(json, r'content_type')!,
        status: UnifiedVideoAuthenticityScoreStatusEnum.fromJson(json[r'status'])!,
        billable: UnifiedVideoAuthenticityScoreBillableEnum.fromJson(json[r'billable'])!,
        statusCode: UnifiedVideoAuthenticityScoreStatusCodeEnum.fromJson(json[r'status_code'])!,
        videoRiskScore: mapValueOfType<double>(json, r'video_risk_score'),
        videoRiskLevel: UnifiedVideoAuthenticityScoreVideoRiskLevelEnum.fromJson(json[r'video_risk_level']),
        videoMessage: mapValueOfType<String>(json, r'video_message')!,
        audioRiskScore: mapValueOfType<double>(json, r'audio_risk_score'),
        audioRiskLevel: UnifiedVideoAuthenticityScoreAudioRiskLevelEnum.fromJson(json[r'audio_risk_level']),
        audioMessage: mapValueOfType<String>(json, r'audio_message'),
        aiThreatSignals: json[r'ai_threat_signals'] is Iterable
            ? (json[r'ai_threat_signals'] as Iterable).cast<String>().toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  static List<UnifiedVideoAuthenticityScore> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UnifiedVideoAuthenticityScore>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UnifiedVideoAuthenticityScore.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UnifiedVideoAuthenticityScore> mapFromJson(dynamic json) {
    final map = <String, UnifiedVideoAuthenticityScore>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UnifiedVideoAuthenticityScore.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of UnifiedVideoAuthenticityScore-objects as value to a dart map
  static Map<String, List<UnifiedVideoAuthenticityScore>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UnifiedVideoAuthenticityScore>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UnifiedVideoAuthenticityScore.listFromJson(entry.value, growable: growable,);
      }
    }
    return map;
  }

  /// The list of required keys that must be present in a JSON.
  static const requiredKeys = <String>{
    'unique_trx_id',
    'filename',
    'content_type',
    'status',
    'billable',
    'status_code',
    'video_risk_score',
    'video_risk_level',
    'video_message',
    'audio_risk_score',
    'audio_risk_level',
    'audio_message',
  };
}

/// Outcome of the request. `success` means the file was scored. `rejected` means the file did not pass pre-analysis validation and was not scored. `error` means a server-side failure prevented analysis.
class UnifiedVideoAuthenticityScoreStatusEnum {
  /// Instantiate a new enum with the provided [value].
  const UnifiedVideoAuthenticityScoreStatusEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const success = UnifiedVideoAuthenticityScoreStatusEnum._(r'success');
  static const rejected = UnifiedVideoAuthenticityScoreStatusEnum._(r'rejected');
  static const error = UnifiedVideoAuthenticityScoreStatusEnum._(r'error');

  /// List of all possible values in this [enum][UnifiedVideoAuthenticityScoreStatusEnum].
  static const values = <UnifiedVideoAuthenticityScoreStatusEnum>[
    success,
    rejected,
    error,
  ];

  static UnifiedVideoAuthenticityScoreStatusEnum? fromJson(dynamic value) => UnifiedVideoAuthenticityScoreStatusEnumTypeTransformer().decode(value);

  static List<UnifiedVideoAuthenticityScoreStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UnifiedVideoAuthenticityScoreStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UnifiedVideoAuthenticityScoreStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UnifiedVideoAuthenticityScoreStatusEnum] to String,
/// and [decode] dynamic data back to [UnifiedVideoAuthenticityScoreStatusEnum].
class UnifiedVideoAuthenticityScoreStatusEnumTypeTransformer {
  factory UnifiedVideoAuthenticityScoreStatusEnumTypeTransformer() => _instance ??= const UnifiedVideoAuthenticityScoreStatusEnumTypeTransformer._();

  const UnifiedVideoAuthenticityScoreStatusEnumTypeTransformer._();

  String encode(UnifiedVideoAuthenticityScoreStatusEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a UnifiedVideoAuthenticityScoreStatusEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UnifiedVideoAuthenticityScoreStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'success': return UnifiedVideoAuthenticityScoreStatusEnum.success;
        case r'rejected': return UnifiedVideoAuthenticityScoreStatusEnum.rejected;
        case r'error': return UnifiedVideoAuthenticityScoreStatusEnum.error;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [UnifiedVideoAuthenticityScoreStatusEnumTypeTransformer] instance.
  static UnifiedVideoAuthenticityScoreStatusEnumTypeTransformer? _instance;
}


/// `Y` when the request counts toward billing, `N` otherwise.
class UnifiedVideoAuthenticityScoreBillableEnum {
  /// Instantiate a new enum with the provided [value].
  const UnifiedVideoAuthenticityScoreBillableEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const Y = UnifiedVideoAuthenticityScoreBillableEnum._(r'Y');
  static const N = UnifiedVideoAuthenticityScoreBillableEnum._(r'N');

  /// List of all possible values in this [enum][UnifiedVideoAuthenticityScoreBillableEnum].
  static const values = <UnifiedVideoAuthenticityScoreBillableEnum>[
    Y,
    N,
  ];

  static UnifiedVideoAuthenticityScoreBillableEnum? fromJson(dynamic value) => UnifiedVideoAuthenticityScoreBillableEnumTypeTransformer().decode(value);

  static List<UnifiedVideoAuthenticityScoreBillableEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UnifiedVideoAuthenticityScoreBillableEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UnifiedVideoAuthenticityScoreBillableEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UnifiedVideoAuthenticityScoreBillableEnum] to String,
/// and [decode] dynamic data back to [UnifiedVideoAuthenticityScoreBillableEnum].
class UnifiedVideoAuthenticityScoreBillableEnumTypeTransformer {
  factory UnifiedVideoAuthenticityScoreBillableEnumTypeTransformer() => _instance ??= const UnifiedVideoAuthenticityScoreBillableEnumTypeTransformer._();

  const UnifiedVideoAuthenticityScoreBillableEnumTypeTransformer._();

  String encode(UnifiedVideoAuthenticityScoreBillableEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a UnifiedVideoAuthenticityScoreBillableEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UnifiedVideoAuthenticityScoreBillableEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'Y': return UnifiedVideoAuthenticityScoreBillableEnum.Y;
        case r'N': return UnifiedVideoAuthenticityScoreBillableEnum.N;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [UnifiedVideoAuthenticityScoreBillableEnumTypeTransformer] instance.
  static UnifiedVideoAuthenticityScoreBillableEnumTypeTransformer? _instance;
}


/// 1 scored successfully (HTTP 200, billable). 2 input validation rejection (HTTP 400, not billable). 5 server-side error (HTTP 500 or 503, not billable). 6 no scorable single-face frames (HTTP 200, billable).
class UnifiedVideoAuthenticityScoreStatusCodeEnum {
  /// Instantiate a new enum with the provided [value].
  const UnifiedVideoAuthenticityScoreStatusCodeEnum._(this.value);

  /// The underlying value of this enum member.
  final int value;

  @override
  String toString() => value.toString();

  int toJson() => value;

  static const number1 = UnifiedVideoAuthenticityScoreStatusCodeEnum._(1);
  static const number2 = UnifiedVideoAuthenticityScoreStatusCodeEnum._(2);
  static const number5 = UnifiedVideoAuthenticityScoreStatusCodeEnum._(5);
  static const number6 = UnifiedVideoAuthenticityScoreStatusCodeEnum._(6);

  /// List of all possible values in this [enum][UnifiedVideoAuthenticityScoreStatusCodeEnum].
  static const values = <UnifiedVideoAuthenticityScoreStatusCodeEnum>[
    number1,
    number2,
    number5,
    number6,
  ];

  static UnifiedVideoAuthenticityScoreStatusCodeEnum? fromJson(dynamic value) => UnifiedVideoAuthenticityScoreStatusCodeEnumTypeTransformer().decode(value);

  static List<UnifiedVideoAuthenticityScoreStatusCodeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UnifiedVideoAuthenticityScoreStatusCodeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UnifiedVideoAuthenticityScoreStatusCodeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UnifiedVideoAuthenticityScoreStatusCodeEnum] to int,
/// and [decode] dynamic data back to [UnifiedVideoAuthenticityScoreStatusCodeEnum].
class UnifiedVideoAuthenticityScoreStatusCodeEnumTypeTransformer {
  factory UnifiedVideoAuthenticityScoreStatusCodeEnumTypeTransformer() => _instance ??= const UnifiedVideoAuthenticityScoreStatusCodeEnumTypeTransformer._();

  const UnifiedVideoAuthenticityScoreStatusCodeEnumTypeTransformer._();

  int encode(UnifiedVideoAuthenticityScoreStatusCodeEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a UnifiedVideoAuthenticityScoreStatusCodeEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UnifiedVideoAuthenticityScoreStatusCodeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case 1: return UnifiedVideoAuthenticityScoreStatusCodeEnum.number1;
        case 2: return UnifiedVideoAuthenticityScoreStatusCodeEnum.number2;
        case 5: return UnifiedVideoAuthenticityScoreStatusCodeEnum.number5;
        case 6: return UnifiedVideoAuthenticityScoreStatusCodeEnum.number6;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [UnifiedVideoAuthenticityScoreStatusCodeEnumTypeTransformer] instance.
  static UnifiedVideoAuthenticityScoreStatusCodeEnumTypeTransformer? _instance;
}


/// Video risk band: low is 0.1-3.9, medium is 4.0-6.9, high is 7.0-10.0. Null when the video was not scored.
class UnifiedVideoAuthenticityScoreVideoRiskLevelEnum {
  /// Instantiate a new enum with the provided [value].
  const UnifiedVideoAuthenticityScoreVideoRiskLevelEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const low = UnifiedVideoAuthenticityScoreVideoRiskLevelEnum._(r'low');
  static const medium = UnifiedVideoAuthenticityScoreVideoRiskLevelEnum._(r'medium');
  static const high = UnifiedVideoAuthenticityScoreVideoRiskLevelEnum._(r'high');

  /// List of all possible values in this [enum][UnifiedVideoAuthenticityScoreVideoRiskLevelEnum].
  static const values = <UnifiedVideoAuthenticityScoreVideoRiskLevelEnum>[
    low,
    medium,
    high,
  ];

  static UnifiedVideoAuthenticityScoreVideoRiskLevelEnum? fromJson(dynamic value) => UnifiedVideoAuthenticityScoreVideoRiskLevelEnumTypeTransformer().decode(value);

  static List<UnifiedVideoAuthenticityScoreVideoRiskLevelEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UnifiedVideoAuthenticityScoreVideoRiskLevelEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UnifiedVideoAuthenticityScoreVideoRiskLevelEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UnifiedVideoAuthenticityScoreVideoRiskLevelEnum] to String,
/// and [decode] dynamic data back to [UnifiedVideoAuthenticityScoreVideoRiskLevelEnum].
class UnifiedVideoAuthenticityScoreVideoRiskLevelEnumTypeTransformer {
  factory UnifiedVideoAuthenticityScoreVideoRiskLevelEnumTypeTransformer() => _instance ??= const UnifiedVideoAuthenticityScoreVideoRiskLevelEnumTypeTransformer._();

  const UnifiedVideoAuthenticityScoreVideoRiskLevelEnumTypeTransformer._();

  String encode(UnifiedVideoAuthenticityScoreVideoRiskLevelEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a UnifiedVideoAuthenticityScoreVideoRiskLevelEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UnifiedVideoAuthenticityScoreVideoRiskLevelEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'low': return UnifiedVideoAuthenticityScoreVideoRiskLevelEnum.low;
        case r'medium': return UnifiedVideoAuthenticityScoreVideoRiskLevelEnum.medium;
        case r'high': return UnifiedVideoAuthenticityScoreVideoRiskLevelEnum.high;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [UnifiedVideoAuthenticityScoreVideoRiskLevelEnumTypeTransformer] instance.
  static UnifiedVideoAuthenticityScoreVideoRiskLevelEnumTypeTransformer? _instance;
}


/// Audio risk band, using the same thresholds as video. Null when the audio was not scored.
class UnifiedVideoAuthenticityScoreAudioRiskLevelEnum {
  /// Instantiate a new enum with the provided [value].
  const UnifiedVideoAuthenticityScoreAudioRiskLevelEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const low = UnifiedVideoAuthenticityScoreAudioRiskLevelEnum._(r'low');
  static const medium = UnifiedVideoAuthenticityScoreAudioRiskLevelEnum._(r'medium');
  static const high = UnifiedVideoAuthenticityScoreAudioRiskLevelEnum._(r'high');

  /// List of all possible values in this [enum][UnifiedVideoAuthenticityScoreAudioRiskLevelEnum].
  static const values = <UnifiedVideoAuthenticityScoreAudioRiskLevelEnum>[
    low,
    medium,
    high,
  ];

  static UnifiedVideoAuthenticityScoreAudioRiskLevelEnum? fromJson(dynamic value) => UnifiedVideoAuthenticityScoreAudioRiskLevelEnumTypeTransformer().decode(value);

  static List<UnifiedVideoAuthenticityScoreAudioRiskLevelEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UnifiedVideoAuthenticityScoreAudioRiskLevelEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UnifiedVideoAuthenticityScoreAudioRiskLevelEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UnifiedVideoAuthenticityScoreAudioRiskLevelEnum] to String,
/// and [decode] dynamic data back to [UnifiedVideoAuthenticityScoreAudioRiskLevelEnum].
class UnifiedVideoAuthenticityScoreAudioRiskLevelEnumTypeTransformer {
  factory UnifiedVideoAuthenticityScoreAudioRiskLevelEnumTypeTransformer() => _instance ??= const UnifiedVideoAuthenticityScoreAudioRiskLevelEnumTypeTransformer._();

  const UnifiedVideoAuthenticityScoreAudioRiskLevelEnumTypeTransformer._();

  String encode(UnifiedVideoAuthenticityScoreAudioRiskLevelEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a UnifiedVideoAuthenticityScoreAudioRiskLevelEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UnifiedVideoAuthenticityScoreAudioRiskLevelEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'low': return UnifiedVideoAuthenticityScoreAudioRiskLevelEnum.low;
        case r'medium': return UnifiedVideoAuthenticityScoreAudioRiskLevelEnum.medium;
        case r'high': return UnifiedVideoAuthenticityScoreAudioRiskLevelEnum.high;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [UnifiedVideoAuthenticityScoreAudioRiskLevelEnumTypeTransformer] instance.
  static UnifiedVideoAuthenticityScoreAudioRiskLevelEnumTypeTransformer? _instance;
}


