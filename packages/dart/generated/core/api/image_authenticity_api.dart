//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of neuraldefend_core;


class ImageAuthenticityApi {
  ImageAuthenticityApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Score the authenticity of a face image
  ///
  /// Analyzes a single-face image and returns an opaque authenticity risk score with a risk band and a human-readable message.  **Requirements.** JPEG, PNG, BMP, TIFF, WebP, or HEIC. Maximum 10 MB, minimum 224x224 pixels, exactly one face. EXIF rotation is corrected automatically. Images with no face or several faces return `status: \"rejected\"` on HTTP 200 and are billable.  **Reading the result.** Branch on `status` first, then apply business rules to `risk_level` rather than to `risk_score`, since band thresholds may be tuned.  Every request produces a new `unique_trx_id`; requests are not idempotent.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [MultipartFile] file (required):
  ///   Image to analyze.
  Future<Response> detectImageWithHttpInfo(MultipartFile file,) async {
    // ignore: prefer_const_declarations
    final path = r'/detect/image';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    const contentTypes = <String>['multipart/form-data'];

    bool hasFields = false;
    final mp = MultipartRequest('POST', Uri.parse(path));
    if (file != null) {
      hasFields = true;
      mp.fields[r'file'] = file.field;
      mp.files.add(file);
    }
    if (hasFields) {
      postBody = mp;
    }

    return apiClient.invokeAPI(
      path,
      'POST',
      queryParams,
      postBody,
      headerParams,
      formParams,
      contentTypes.isEmpty ? null : contentTypes.first,
    );
  }

  /// Score the authenticity of a face image
  ///
  /// Analyzes a single-face image and returns an opaque authenticity risk score with a risk band and a human-readable message.  **Requirements.** JPEG, PNG, BMP, TIFF, WebP, or HEIC. Maximum 10 MB, minimum 224x224 pixels, exactly one face. EXIF rotation is corrected automatically. Images with no face or several faces return `status: \"rejected\"` on HTTP 200 and are billable.  **Reading the result.** Branch on `status` first, then apply business rules to `risk_level` rather than to `risk_score`, since band thresholds may be tuned.  Every request produces a new `unique_trx_id`; requests are not idempotent.
  ///
  /// Parameters:
  ///
  /// * [MultipartFile] file (required):
  ///   Image to analyze.
  Future<DetectImageResponse?> detectImage(MultipartFile file,) async {
    final response = await detectImageWithHttpInfo(file,);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DetectImageResponse',) as DetectImageResponse;
    
    }
    return null;
  }
}
