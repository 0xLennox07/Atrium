import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';

import 'models/plex_models.dart';

/// Thin client over the Plex Media Server API.
///
/// Plex uses a static `X-Plex-Token`, attached (with `Accept: application/json`)
/// by `core_networking`'s [AuthInterceptor], so unlike Jellyfin/Emby this can
/// ride the shared `instanceDioProvider` Dio. The token is also needed to
/// build poster URLs, so we pass it in separately.
class PlexApi {
  PlexApi(this._dio, {required this.token});

  final Dio _dio;
  final String token;

  Future<List<PlexLibrary>> getLibraries() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('/library/sections');
      return PlexLibrariesResponse.fromJson(resp.data as Map<String, dynamic>)
              .mediaContainer
              ?.directory ??
          <PlexLibrary>[];
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<PlexMetadata>> getItems(String sectionKey) async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('/library/sections/$sectionKey/all');
      return PlexItemsResponse.fromJson(resp.data as Map<String, dynamic>)
              .mediaContainer
              ?.metadata ??
          <PlexMetadata>[];
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Children of a show (its seasons) or a season (its episodes).
  Future<List<PlexMetadata>> getChildren(String ratingKey) async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('/library/metadata/$ratingKey/children');
      return PlexItemsResponse.fromJson(resp.data as Map<String, dynamic>)
              .mediaContainer
              ?.metadata ??
          <PlexMetadata>[];
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }



  /// Builds an absolute poster URL from a relative [thumb] path. Returns null
  /// when the item has no thumbnail. The Dio base URL is the already-resolved
  /// LAN/WAN address.
  String? imageUrl(String? thumb) {
    if (thumb == null || thumb.isEmpty) {
      return null;
    }
    final String base =
        _dio.options.baseUrl.replaceAll(RegExp(r'/+$'), '');
    return '$base$thumb?X-Plex-Token=$token';
  }
}
