import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';

import 'models/bazarr_models.dart';

/// Thin client over the Bazarr API.
///
/// Auth is an API-key header (added by `core_networking`'s [AuthInterceptor]),
/// so this rides the shared `instanceDioProvider` Dio.
class BazarrApi {
  BazarrApi(this._dio);

  final Dio _dio;

  Future<BazarrBadges> getBadges() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('api/badges');
      return BazarrBadges.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<BazarrWantedEpisode>> getWantedEpisodes() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'api/episodes/wanted',
        queryParameters: <String, dynamic>{'start': 0, 'length': -1},
      );
      return BazarrWantedEpisodes.fromJson(resp.data as Map<String, dynamic>)
          .data;
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<BazarrWantedMovie>> getWantedMovies() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'api/movies/wanted',
        queryParameters: <String, dynamic>{'start': 0, 'length': -1},
      );
      return BazarrWantedMovies.fromJson(resp.data as Map<String, dynamic>).data;
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }
}
