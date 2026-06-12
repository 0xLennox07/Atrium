import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';

import 'models/overseerr_request.dart';

/// Thin client over the Overseerr / Jellyseerr API.
///
/// Auth is an `X-Api-Key` header (added by `core_networking`'s
/// [AuthInterceptor]), so this rides the shared `instanceDioProvider` Dio.
class OverseerrApi {
  OverseerrApi(this._dio);

  final Dio _dio;

  static const String _base = 'api/v1';

  Future<List<OverseerrRequest>> getRequests({int take = 30}) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/request',
        queryParameters: <String, dynamic>{
          'take': take,
          'skip': 0,
          'sort': 'added',
        },
      );
      return OverseerrRequestPage.fromJson(resp.data as Map<String, dynamic>)
          .results;
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> approve(int requestId) =>
      _post('$_base/request/$requestId/approve');

  Future<void> decline(int requestId) =>
      _post('$_base/request/$requestId/decline');

  Future<void> _post(String path) async {
    try {
      await _dio.post<dynamic>(path);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }
}
