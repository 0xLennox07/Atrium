import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';

import 'models/sab_queue.dart';

/// Thin client over the SABnzbd API.
///
/// SABnzbd auth is an `apikey` query param, and `output=json` selects JSON -
/// both are appended by `core_networking`'s [AuthInterceptor], so this rides
/// the shared `instanceDioProvider` Dio and only needs to add `mode=…`.
class SabnzbdApi {
  SabnzbdApi(this._dio);

  final Dio _dio;

  Future<SabQueue> getQueue() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'api',
        queryParameters: <String, dynamic>{'mode': 'queue'},
      );
      return SabQueueResponse.fromJson(resp.data as Map<String, dynamic>)
              .queue ??
          const SabQueue();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Pause the whole queue.
  Future<void> pauseAll() => _simple(<String, dynamic>{'mode': 'pause'});

  /// Resume the whole queue.
  Future<void> resumeAll() => _simple(<String, dynamic>{'mode': 'resume'});

  Future<void> pauseItem(String nzoId) => _simple(<String, dynamic>{
        'mode': 'queue',
        'name': 'pause',
        'value': nzoId,
      });

  Future<void> resumeItem(String nzoId) => _simple(<String, dynamic>{
        'mode': 'queue',
        'name': 'resume',
        'value': nzoId,
      });

  Future<void> deleteItem(String nzoId) => _simple(<String, dynamic>{
        'mode': 'queue',
        'name': 'delete',
        'value': nzoId,
      });

  Future<void> _simple(Map<String, dynamic> params) async {
    try {
      await _dio.get<dynamic>('api', queryParameters: params);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }
}
