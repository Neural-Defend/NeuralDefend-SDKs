//
// AUTO-GENERATED FILE, DO NOT MODIFY!
//
// @dart=2.18

// ignore_for_file: unused_element, unused_import
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: constant_identifier_names
// ignore_for_file: lines_longer_than_80_chars

part of neuraldefend_core;


class VideoAuthenticityApi {
  VideoAuthenticityApi([ApiClient? apiClient]) : apiClient = apiClient ?? defaultApiClient;

  final ApiClient apiClient;

  /// Score the authenticity of a video and its audio track
  ///
  /// Analyzes a video and returns independent risk scores for the video and audio modalities, each with its own risk band and message.  **Requirements.** MP4, AVI, MOV, MKV, WMV, FLV, WebM, OGG, or OGV. Maximum 1.5 GB. Frames are sampled uniformly, 12 by default. Frames containing several faces are skipped; if no single-face frames remain, the response is a rejection with `status_code: 6` on HTTP 200, and it is billable.  **Reading the result.** Video and audio are scored separately and no combined score is returned. Derive one client-side when you need it, for example max(video_risk_score, audio_risk_score or 0). Silent videos return null audio scores with `audio_message` set to \"No audio track detected\"; this is a success, not an error.  Every request produces a new `unique_trx_id`; requests are not idempotent.
  ///
  /// Note: This method returns the HTTP [Response].
  ///
  /// Parameters:
  ///
  /// * [MultipartFile] file (required):
  ///   Video to analyze.
  ///
  /// * [int] maxFrames:
  ///   Maximum number of frames to sample, from 1 to 100. Defaults to 12.
  ///
  /// * [int] sampleRate:
  ///   Optional frame sampling override. Must be 1 or greater.
  Future<Response> detectVideoWithHttpInfo(MultipartFile file, { int? maxFrames, int? sampleRate, }) async {
    // ignore: prefer_const_declarations
    final path = r'/detect/video';

    // ignore: prefer_final_locals
    Object? postBody;

    final queryParams = <QueryParam>[];
    final headerParams = <String, String>{};
    final formParams = <String, String>{};

    if (maxFrames != null) {
      queryParams.addAll(_queryParams('', 'max_frames', maxFrames));
    }
    if (sampleRate != null) {
      queryParams.addAll(_queryParams('', 'sample_rate', sampleRate));
    }

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

  /// Score the authenticity of a video and its audio track
  ///
  /// Analyzes a video and returns independent risk scores for the video and audio modalities, each with its own risk band and message.  **Requirements.** MP4, AVI, MOV, MKV, WMV, FLV, WebM, OGG, or OGV. Maximum 1.5 GB. Frames are sampled uniformly, 12 by default. Frames containing several faces are skipped; if no single-face frames remain, the response is a rejection with `status_code: 6` on HTTP 200, and it is billable.  **Reading the result.** Video and audio are scored separately and no combined score is returned. Derive one client-side when you need it, for example max(video_risk_score, audio_risk_score or 0). Silent videos return null audio scores with `audio_message` set to \"No audio track detected\"; this is a success, not an error.  Every request produces a new `unique_trx_id`; requests are not idempotent.
  ///
  /// Parameters:
  ///
  /// * [MultipartFile] file (required):
  ///   Video to analyze.
  ///
  /// * [int] maxFrames:
  ///   Maximum number of frames to sample, from 1 to 100. Defaults to 12.
  ///
  /// * [int] sampleRate:
  ///   Optional frame sampling override. Must be 1 or greater.
  Future<DetectVideoResponse?> detectVideo(MultipartFile file, { int? maxFrames, int? sampleRate, }) async {
    final response = await detectVideoWithHttpInfo(file,  maxFrames: maxFrames, sampleRate: sampleRate, );
    if (response.statusCode >= HttpStatus.badRequest) {
      throw ApiException(response.statusCode, await _decodeBodyBytes(response));
    }
    // When a remote server returns no body with a status of 204, we shall not decode it.
    // At the time of writing this, `dart:convert` will throw an "Unexpected end of input"
    // FormatException when trying to decode an empty string.
    if (response.body.isNotEmpty && response.statusCode != HttpStatus.noContent) {
      return await apiClient.deserializeAsync(await _decodeBodyBytes(response), 'DetectVideoResponse',) as DetectVideoResponse;
    
    }
    return null;
  }
}
