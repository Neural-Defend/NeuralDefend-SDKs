//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of neuraldefend_core;

class UnifiedFaceAuthenticityScore {
  /// Returns a new [UnifiedFaceAuthenticityScore] instance.
  UnifiedFaceAuthenticityScore({
    required this.uniqueTrxId,
    required this.filename,
    required this.contentType,
    required this.status,
    required this.billable,
    required this.statusCode,
    required this.riskScore,
    required this.riskLevel,
    required this.message,
    this.aiThreatSignals = const [],
  });

  /// Unique transaction identifier. Store it for audit trail correlation and dispute resolution.
  String uniqueTrxId;

  /// Name of the uploaded file, as received.
  String filename;

  /// MIME type detected for the uploaded file.
  String contentType;

  /// Outcome of the request. `success` means the file was scored. `rejected` means the file did not pass pre-analysis validation and was not scored. `error` means a server-side failure prevented analysis.
  UnifiedFaceAuthenticityScoreStatusEnum status;

  /// `Y` when the request counts toward billing, `N` otherwise.
  UnifiedFaceAuthenticityScoreBillableEnum billable;

  /// 1 scored successfully (HTTP 200, billable). 2 input validation rejection (HTTP 400, not billable). 5 server-side error (HTTP 500 or 503, not billable). 6 no face detected (HTTP 200, billable). 7 multiple faces detected (HTTP 200, billable).
  UnifiedFaceAuthenticityScoreStatusCodeEnum statusCode;

  /// Authenticity risk from 0.1 to 10.0, where higher means a higher likelihood of spoofing or AI generation. Null when the request was rejected or errored. Prefer `risk_level` for business rules, since band thresholds may be tuned.
  ///
  /// Minimum value: 0.1
  /// Maximum value: 10.0
  double? riskScore;

  /// Risk band derived from `risk_score`: low is 0.1-3.9, medium is 4.0-6.9, high is 7.0-10.0. Null when the request was not scored.
  UnifiedFaceAuthenticityScoreRiskLevelEnum? riskLevel;

  /// Human-readable explanation of the result, safe to surface to end users.
  String message;

  /// Checks applied during analysis. Present only on scored responses.
  List<String> aiThreatSignals;

  @override
  bool operator ==(Object other) => identical(this, other) || other is UnifiedFaceAuthenticityScore &&
    other.uniqueTrxId == uniqueTrxId &&
    other.filename == filename &&
    other.contentType == contentType &&
    other.status == status &&
    other.billable == billable &&
    other.statusCode == statusCode &&
    other.riskScore == riskScore &&
    other.riskLevel == riskLevel &&
    other.message == message &&
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
    (riskScore == null ? 0 : riskScore!.hashCode) +
    (riskLevel == null ? 0 : riskLevel!.hashCode) +
    (message.hashCode) +
    (aiThreatSignals.hashCode);

  @override
  String toString() => 'UnifiedFaceAuthenticityScore[uniqueTrxId=$uniqueTrxId, filename=$filename, contentType=$contentType, status=$status, billable=$billable, statusCode=$statusCode, riskScore=$riskScore, riskLevel=$riskLevel, message=$message, aiThreatSignals=$aiThreatSignals]';

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{};
      json[r'unique_trx_id'] = this.uniqueTrxId;
      json[r'filename'] = this.filename;
      json[r'content_type'] = this.contentType;
      json[r'status'] = this.status;
      json[r'billable'] = this.billable;
      json[r'status_code'] = this.statusCode;
    if (this.riskScore != null) {
      json[r'risk_score'] = this.riskScore;
    } else {
      json[r'risk_score'] = null;
    }
    if (this.riskLevel != null) {
      json[r'risk_level'] = this.riskLevel;
    } else {
      json[r'risk_level'] = null;
    }
      json[r'message'] = this.message;
      json[r'ai_threat_signals'] = this.aiThreatSignals;
    return json;
  }

  /// Returns a new [UnifiedFaceAuthenticityScore] instance and imports its values from
  /// [value] if it's a [Map], null otherwise.
  // ignore: prefer_constructors_over_static_methods
  static UnifiedFaceAuthenticityScore? fromJson(dynamic value) {
    if (value is Map) {
      final json = value.cast<String, dynamic>();

      // Ensure that the map contains the required keys.
      // Note 1: the values aren't checked for validity beyond being non-null.
      // Note 2: this code is stripped in release mode!
      assert(() {
        requiredKeys.forEach((key) {
          assert(json.containsKey(key), 'Required key "UnifiedFaceAuthenticityScore[$key]" is missing from JSON.');
          assert(json[key] != null, 'Required key "UnifiedFaceAuthenticityScore[$key]" has a null value in JSON.');
        });
        return true;
      }());

      return UnifiedFaceAuthenticityScore(
        uniqueTrxId: mapValueOfType<String>(json, r'unique_trx_id')!,
        filename: mapValueOfType<String>(json, r'filename')!,
        contentType: mapValueOfType<String>(json, r'content_type')!,
        status: UnifiedFaceAuthenticityScoreStatusEnum.fromJson(json[r'status'])!,
        billable: UnifiedFaceAuthenticityScoreBillableEnum.fromJson(json[r'billable'])!,
        statusCode: UnifiedFaceAuthenticityScoreStatusCodeEnum.fromJson(json[r'status_code'])!,
        riskScore: mapValueOfType<double>(json, r'risk_score'),
        riskLevel: UnifiedFaceAuthenticityScoreRiskLevelEnum.fromJson(json[r'risk_level']),
        message: mapValueOfType<String>(json, r'message')!,
        aiThreatSignals: json[r'ai_threat_signals'] is Iterable
            ? (json[r'ai_threat_signals'] as Iterable).cast<String>().toList(growable: false)
            : const [],
      );
    }
    return null;
  }

  static List<UnifiedFaceAuthenticityScore> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UnifiedFaceAuthenticityScore>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UnifiedFaceAuthenticityScore.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }

  static Map<String, UnifiedFaceAuthenticityScore> mapFromJson(dynamic json) {
    final map = <String, UnifiedFaceAuthenticityScore>{};
    if (json is Map && json.isNotEmpty) {
      json = json.cast<String, dynamic>(); // ignore: parameter_assignments
      for (final entry in json.entries) {
        final value = UnifiedFaceAuthenticityScore.fromJson(entry.value);
        if (value != null) {
          map[entry.key] = value;
        }
      }
    }
    return map;
  }

  // maps a json object with a list of UnifiedFaceAuthenticityScore-objects as value to a dart map
  static Map<String, List<UnifiedFaceAuthenticityScore>> mapListFromJson(dynamic json, {bool growable = false,}) {
    final map = <String, List<UnifiedFaceAuthenticityScore>>{};
    if (json is Map && json.isNotEmpty) {
      // ignore: parameter_assignments
      json = json.cast<String, dynamic>();
      for (final entry in json.entries) {
        map[entry.key] = UnifiedFaceAuthenticityScore.listFromJson(entry.value, growable: growable,);
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
    'risk_score',
    'risk_level',
    'message',
  };
}

/// Outcome of the request. `success` means the file was scored. `rejected` means the file did not pass pre-analysis validation and was not scored. `error` means a server-side failure prevented analysis.
class UnifiedFaceAuthenticityScoreStatusEnum {
  /// Instantiate a new enum with the provided [value].
  const UnifiedFaceAuthenticityScoreStatusEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const success = UnifiedFaceAuthenticityScoreStatusEnum._(r'success');
  static const rejected = UnifiedFaceAuthenticityScoreStatusEnum._(r'rejected');
  static const error = UnifiedFaceAuthenticityScoreStatusEnum._(r'error');

  /// List of all possible values in this [enum][UnifiedFaceAuthenticityScoreStatusEnum].
  static const values = <UnifiedFaceAuthenticityScoreStatusEnum>[
    success,
    rejected,
    error,
  ];

  static UnifiedFaceAuthenticityScoreStatusEnum? fromJson(dynamic value) => UnifiedFaceAuthenticityScoreStatusEnumTypeTransformer().decode(value);

  static List<UnifiedFaceAuthenticityScoreStatusEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UnifiedFaceAuthenticityScoreStatusEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UnifiedFaceAuthenticityScoreStatusEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UnifiedFaceAuthenticityScoreStatusEnum] to String,
/// and [decode] dynamic data back to [UnifiedFaceAuthenticityScoreStatusEnum].
class UnifiedFaceAuthenticityScoreStatusEnumTypeTransformer {
  factory UnifiedFaceAuthenticityScoreStatusEnumTypeTransformer() => _instance ??= const UnifiedFaceAuthenticityScoreStatusEnumTypeTransformer._();

  const UnifiedFaceAuthenticityScoreStatusEnumTypeTransformer._();

  String encode(UnifiedFaceAuthenticityScoreStatusEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a UnifiedFaceAuthenticityScoreStatusEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UnifiedFaceAuthenticityScoreStatusEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'success': return UnifiedFaceAuthenticityScoreStatusEnum.success;
        case r'rejected': return UnifiedFaceAuthenticityScoreStatusEnum.rejected;
        case r'error': return UnifiedFaceAuthenticityScoreStatusEnum.error;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [UnifiedFaceAuthenticityScoreStatusEnumTypeTransformer] instance.
  static UnifiedFaceAuthenticityScoreStatusEnumTypeTransformer? _instance;
}


/// `Y` when the request counts toward billing, `N` otherwise.
class UnifiedFaceAuthenticityScoreBillableEnum {
  /// Instantiate a new enum with the provided [value].
  const UnifiedFaceAuthenticityScoreBillableEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const Y = UnifiedFaceAuthenticityScoreBillableEnum._(r'Y');
  static const N = UnifiedFaceAuthenticityScoreBillableEnum._(r'N');

  /// List of all possible values in this [enum][UnifiedFaceAuthenticityScoreBillableEnum].
  static const values = <UnifiedFaceAuthenticityScoreBillableEnum>[
    Y,
    N,
  ];

  static UnifiedFaceAuthenticityScoreBillableEnum? fromJson(dynamic value) => UnifiedFaceAuthenticityScoreBillableEnumTypeTransformer().decode(value);

  static List<UnifiedFaceAuthenticityScoreBillableEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UnifiedFaceAuthenticityScoreBillableEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UnifiedFaceAuthenticityScoreBillableEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UnifiedFaceAuthenticityScoreBillableEnum] to String,
/// and [decode] dynamic data back to [UnifiedFaceAuthenticityScoreBillableEnum].
class UnifiedFaceAuthenticityScoreBillableEnumTypeTransformer {
  factory UnifiedFaceAuthenticityScoreBillableEnumTypeTransformer() => _instance ??= const UnifiedFaceAuthenticityScoreBillableEnumTypeTransformer._();

  const UnifiedFaceAuthenticityScoreBillableEnumTypeTransformer._();

  String encode(UnifiedFaceAuthenticityScoreBillableEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a UnifiedFaceAuthenticityScoreBillableEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UnifiedFaceAuthenticityScoreBillableEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'Y': return UnifiedFaceAuthenticityScoreBillableEnum.Y;
        case r'N': return UnifiedFaceAuthenticityScoreBillableEnum.N;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [UnifiedFaceAuthenticityScoreBillableEnumTypeTransformer] instance.
  static UnifiedFaceAuthenticityScoreBillableEnumTypeTransformer? _instance;
}


/// 1 scored successfully (HTTP 200, billable). 2 input validation rejection (HTTP 400, not billable). 5 server-side error (HTTP 500 or 503, not billable). 6 no face detected (HTTP 200, billable). 7 multiple faces detected (HTTP 200, billable).
class UnifiedFaceAuthenticityScoreStatusCodeEnum {
  /// Instantiate a new enum with the provided [value].
  const UnifiedFaceAuthenticityScoreStatusCodeEnum._(this.value);

  /// The underlying value of this enum member.
  final int value;

  @override
  String toString() => value.toString();

  int toJson() => value;

  static const number1 = UnifiedFaceAuthenticityScoreStatusCodeEnum._(1);
  static const number2 = UnifiedFaceAuthenticityScoreStatusCodeEnum._(2);
  static const number5 = UnifiedFaceAuthenticityScoreStatusCodeEnum._(5);
  static const number6 = UnifiedFaceAuthenticityScoreStatusCodeEnum._(6);
  static const number7 = UnifiedFaceAuthenticityScoreStatusCodeEnum._(7);

  /// List of all possible values in this [enum][UnifiedFaceAuthenticityScoreStatusCodeEnum].
  static const values = <UnifiedFaceAuthenticityScoreStatusCodeEnum>[
    number1,
    number2,
    number5,
    number6,
    number7,
  ];

  static UnifiedFaceAuthenticityScoreStatusCodeEnum? fromJson(dynamic value) => UnifiedFaceAuthenticityScoreStatusCodeEnumTypeTransformer().decode(value);

  static List<UnifiedFaceAuthenticityScoreStatusCodeEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UnifiedFaceAuthenticityScoreStatusCodeEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UnifiedFaceAuthenticityScoreStatusCodeEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UnifiedFaceAuthenticityScoreStatusCodeEnum] to int,
/// and [decode] dynamic data back to [UnifiedFaceAuthenticityScoreStatusCodeEnum].
class UnifiedFaceAuthenticityScoreStatusCodeEnumTypeTransformer {
  factory UnifiedFaceAuthenticityScoreStatusCodeEnumTypeTransformer() => _instance ??= const UnifiedFaceAuthenticityScoreStatusCodeEnumTypeTransformer._();

  const UnifiedFaceAuthenticityScoreStatusCodeEnumTypeTransformer._();

  int encode(UnifiedFaceAuthenticityScoreStatusCodeEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a UnifiedFaceAuthenticityScoreStatusCodeEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UnifiedFaceAuthenticityScoreStatusCodeEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case 1: return UnifiedFaceAuthenticityScoreStatusCodeEnum.number1;
        case 2: return UnifiedFaceAuthenticityScoreStatusCodeEnum.number2;
        case 5: return UnifiedFaceAuthenticityScoreStatusCodeEnum.number5;
        case 6: return UnifiedFaceAuthenticityScoreStatusCodeEnum.number6;
        case 7: return UnifiedFaceAuthenticityScoreStatusCodeEnum.number7;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [UnifiedFaceAuthenticityScoreStatusCodeEnumTypeTransformer] instance.
  static UnifiedFaceAuthenticityScoreStatusCodeEnumTypeTransformer? _instance;
}


/// Risk band derived from `risk_score`: low is 0.1-3.9, medium is 4.0-6.9, high is 7.0-10.0. Null when the request was not scored.
class UnifiedFaceAuthenticityScoreRiskLevelEnum {
  /// Instantiate a new enum with the provided [value].
  const UnifiedFaceAuthenticityScoreRiskLevelEnum._(this.value);

  /// The underlying value of this enum member.
  final String value;

  @override
  String toString() => value;

  String toJson() => value;

  static const low = UnifiedFaceAuthenticityScoreRiskLevelEnum._(r'low');
  static const medium = UnifiedFaceAuthenticityScoreRiskLevelEnum._(r'medium');
  static const high = UnifiedFaceAuthenticityScoreRiskLevelEnum._(r'high');

  /// List of all possible values in this [enum][UnifiedFaceAuthenticityScoreRiskLevelEnum].
  static const values = <UnifiedFaceAuthenticityScoreRiskLevelEnum>[
    low,
    medium,
    high,
  ];

  static UnifiedFaceAuthenticityScoreRiskLevelEnum? fromJson(dynamic value) => UnifiedFaceAuthenticityScoreRiskLevelEnumTypeTransformer().decode(value);

  static List<UnifiedFaceAuthenticityScoreRiskLevelEnum> listFromJson(dynamic json, {bool growable = false,}) {
    final result = <UnifiedFaceAuthenticityScoreRiskLevelEnum>[];
    if (json is List && json.isNotEmpty) {
      for (final row in json) {
        final value = UnifiedFaceAuthenticityScoreRiskLevelEnum.fromJson(row);
        if (value != null) {
          result.add(value);
        }
      }
    }
    return result.toList(growable: growable);
  }
}

/// Transformation class that can [encode] an instance of [UnifiedFaceAuthenticityScoreRiskLevelEnum] to String,
/// and [decode] dynamic data back to [UnifiedFaceAuthenticityScoreRiskLevelEnum].
class UnifiedFaceAuthenticityScoreRiskLevelEnumTypeTransformer {
  factory UnifiedFaceAuthenticityScoreRiskLevelEnumTypeTransformer() => _instance ??= const UnifiedFaceAuthenticityScoreRiskLevelEnumTypeTransformer._();

  const UnifiedFaceAuthenticityScoreRiskLevelEnumTypeTransformer._();

  String encode(UnifiedFaceAuthenticityScoreRiskLevelEnum data) => data.value;

  /// Decodes a [dynamic value][data] to a UnifiedFaceAuthenticityScoreRiskLevelEnum.
  ///
  /// If [allowNull] is true and the [dynamic value][data] cannot be decoded successfully,
  /// then null is returned. However, if [allowNull] is false and the [dynamic value][data]
  /// cannot be decoded successfully, then an [UnimplementedError] is thrown.
  ///
  /// The [allowNull] is very handy when an API changes and a new enum value is added or removed,
  /// and users are still using an old app with the old code.
  UnifiedFaceAuthenticityScoreRiskLevelEnum? decode(dynamic data, {bool allowNull = true}) {
    if (data != null) {
      switch (data) {
        case r'low': return UnifiedFaceAuthenticityScoreRiskLevelEnum.low;
        case r'medium': return UnifiedFaceAuthenticityScoreRiskLevelEnum.medium;
        case r'high': return UnifiedFaceAuthenticityScoreRiskLevelEnum.high;
        default:
          if (!allowNull) {
            throw ArgumentError('Unknown enum value to decode: $data');
          }
      }
    }
    return null;
  }

  /// Singleton [UnifiedFaceAuthenticityScoreRiskLevelEnumTypeTransformer] instance.
  static UnifiedFaceAuthenticityScoreRiskLevelEnumTypeTransformer? _instance;
}


