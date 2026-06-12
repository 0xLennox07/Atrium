import 'dart:io';

import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'models/emby_auth.dart';
import 'models/emby_item.dart';
import 'models/emby_view.dart';

/// Client for the Emby REST API.
///
/// Emby's API is close to Jellyfin's, with two differences we handle here:
/// the request-identity header is `X-Emby-Authorization` (not `Authorization`)
/// and the session token rides in `X-Emby-Token` on subsequent calls. Auth
/// flow is otherwise the same: POST username/password to
/// `/Users/AuthenticateByName`, capture `AccessToken` + `User.Id`, re-login
/// once on a 401.
class EmbyClient {
  EmbyClient({
    required Dio dio,
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.deviceId,
  }) : _dio = dio;

  final Dio _dio;
  final Uri baseUrl;
  final String username;
  final String password;
  final String deviceId;

  String? _token;
  String? _userId;
  bool _loggedIn = false;

  static EmbyClient create({
    required Uri baseUrl,
    required String username,
    required String password,
    required String deviceId,
    required bool allowSelfSigned,
  }) {
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: baseUrl.toString(),
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    if (allowSelfSigned) {
      final IOHttpClientAdapter adapter =
          dio.httpClientAdapter as IOHttpClientAdapter;
      adapter.createHttpClient = () => HttpClient()
        ..badCertificateCallback =
            (X509Certificate _, String __, int ___) => true;
    }
    return EmbyClient(
      dio: dio,
      baseUrl: baseUrl,
      username: username,
      password: password,
      deviceId: deviceId,
    );
  }

  String _identityHeader() {
    const String client = 'Atrium';
    const String version = '0.1.0';
    return 'MediaBrowser Client="$client", Device="$client", '
        'DeviceId="$deviceId", Version="$version"';
  }

  Future<void> login() async {
    try {
      _dio.options.headers['X-Emby-Authorization'] = _identityHeader();
      final Response<dynamic> resp = await _dio.post<dynamic>(
        '/Users/AuthenticateByName',
        data: <String, dynamic>{'Username': username, 'Pw': password},
      );
      final EmbyAuthResult result =
          EmbyAuthResult.fromJson(resp.data as Map<String, dynamic>);
      _token = result.accessToken;
      _userId = result.user.id;
      _dio.options.headers['X-Emby-Token'] = _token;
      _loggedIn = true;
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<EmbyView>> getViews() => _guarded(() async {
        final Response<dynamic> resp =
            await _dio.get<dynamic>('/Users/$_userId/Views');
        final Map<String, dynamic> map = resp.data as Map<String, dynamic>;
        final List<dynamic> items =
            (map['Items'] as List<dynamic>?) ?? <dynamic>[];
        return items
            .map((dynamic e) => EmbyView.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<List<EmbyItem>> getItems(String parentId) => _guarded(() async {
        final Response<dynamic> resp = await _dio.get<dynamic>(
          '/Users/$_userId/Items',
          queryParameters: <String, dynamic>{
            'ParentId': parentId,
            'SortBy': 'SortName',
            'SortOrder': 'Ascending',
            'Fields': 'PrimaryImageAspectRatio,ImageTags',
            'ImageTypeLimit': 1,
            'EnableImageTypes': 'Primary',
            'Limit': 200,
          },
        );
        return EmbyItemsResult.fromJson(resp.data as Map<String, dynamic>).items;
      });

  Future<List<EmbyItem>> getResumeItems() => _guarded(() async {
        final Response<dynamic> resp = await _dio.get<dynamic>(
          '/Users/$_userId/Items/Resume',
          queryParameters: <String, dynamic>{
            'Limit': 24,
            'MediaTypes': 'Video',
            'Fields': 'PrimaryImageAspectRatio,Overview,ImageTags',
            'ImageTypeLimit': 1,
            'EnableImageTypes': 'Primary',
          },
        );
        return EmbyItemsResult.fromJson(
          resp.data as Map<String, dynamic>,
        ).items;
      });

  Future<List<EmbyItem>> getNextUp() => _guarded(() async {
        final Response<dynamic> resp = await _dio.get<dynamic>(
          '/Shows/NextUp',
          queryParameters: <String, dynamic>{
            'UserId': _userId,
            'Limit': 24,
            'Fields': 'PrimaryImageAspectRatio,Overview,ImageTags',
            'ImageTypeLimit': 1,
            'EnableImageTypes': 'Primary',
          },
        );
        return EmbyItemsResult.fromJson(
          resp.data as Map<String, dynamic>,
        ).items;
      });

  Future<List<EmbyItem>> searchItems(String query) => _guarded(() async {
        final Response<dynamic> resp = await _dio.get<dynamic>(
          '/Users/$_userId/Items',
          queryParameters: <String, dynamic>{
            'SearchTerm': query,
            'Limit': 50,
            'Recursive': true,
            'IncludeItemTypes': 'Series,Movie,Episode',
            'Fields': 'PrimaryImageAspectRatio,Overview',
            'ImageTypeLimit': 1,
            'EnableImageTypes': 'Primary',
          },
        );
        return EmbyItemsResult.fromJson(
          resp.data as Map<String, dynamic>,
        ).items;
      });

  Future<List<EmbyItem>> getFavorites() => _guarded(() async {
        final Response<dynamic> resp = await _dio.get<dynamic>(
          '/Users/$_userId/Items',
          queryParameters: <String, dynamic>{
            'Filters': 'IsFavorite',
            'Recursive': true,
            'Limit': 24,
            'Fields': 'PrimaryImageAspectRatio,Overview,ImageTags',
            'ImageTypeLimit': 1,
            'EnableImageTypes': 'Primary',
          },
        );
        return EmbyItemsResult.fromJson(
          resp.data as Map<String, dynamic>,
        ).items;
      });

  Future<EmbyUserData> markFavorite(String itemId, bool isFavorite) => _guarded(() async {
        final Response<dynamic> resp = isFavorite 
            ? await _dio.post<dynamic>('/Users/$_userId/FavoriteItems/$itemId')
            : await _dio.delete<dynamic>('/Users/$_userId/FavoriteItems/$itemId');
            
        return EmbyUserData.fromJson(
          resp.data as Map<String, dynamic>,
        );
      });

  Future<List<EmbyItem>> getLatestItems() => _guarded(() async {
        final Response<dynamic> resp = await _dio.get<dynamic>(
          '/Users/$_userId/Items/Latest',
          queryParameters: <String, dynamic>{
            'Limit': 20,
            'Fields': 'PrimaryImageAspectRatio,Overview',
            'ImageTypeLimit': 1,
            'EnableImageTypes': 'Primary',
          },
        );
        final List<dynamic> list = resp.data as List<dynamic>;
        return list
            .map((dynamic e) => EmbyItem.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<EmbyItem> getItemDetails(String itemId) => _guarded(() async {
        final Response<dynamic> resp = await _dio.get<dynamic>(
          '/Users/$_userId/Items/$itemId',
          queryParameters: <String, dynamic>{
            'Fields': 'Overview,People,CommunityRating,OfficialRating,RunTimeTicks',
          },
        );
        return EmbyItem.fromJson(resp.data as Map<String, dynamic>);
      });

  Future<List<EmbyItem>> getSeasons(String seriesId) => _guarded(() async {
        final Response<dynamic> resp = await _dio.get<dynamic>(
          '/Shows/$seriesId/Seasons',
          queryParameters: <String, dynamic>{
            'UserId': _userId,
            'Fields': 'PrimaryImageAspectRatio,Overview',
            'ImageTypeLimit': 1,
            'EnableImageTypes': 'Primary',
          },
        );
        return EmbyItemsResult.fromJson(
          resp.data as Map<String, dynamic>,
        ).items;
      });

  Future<List<EmbyItem>> getEpisodes(String seriesId, String seasonId) =>
      _guarded(() async {
        final Response<dynamic> resp = await _dio.get<dynamic>(
          '/Shows/$seriesId/Episodes',
          queryParameters: <String, dynamic>{
            'SeasonId': seasonId,
            'UserId': _userId,
            'Fields': 'PrimaryImageAspectRatio,Overview,RunTimeTicks,CommunityRating,ImageTags',
            'ImageTypeLimit': 1,
            'EnableImageTypes': 'Primary',
          },
        );
        return EmbyItemsResult.fromJson(
          resp.data as Map<String, dynamic>,
        ).items;
      });

  String get _baseStr => baseUrl.toString().replaceAll(RegExp(r'/+$'), '');



  /// Builds a primary-image (poster) URL for [item], or null if it has none.
  String? imageUrl(EmbyItem item, {int maxHeight = 420}) {
    final String key = _token == null ? '' : '&api_key=$_token';

    // Prefer the Series poster (anime cover) over the episode thumbnail.
    if (item.type == 'Episode' && item.seriesId != null) {
      final String tagParam = item.seriesPrimaryImageTag != null
          ? '&tag=${item.seriesPrimaryImageTag}'
          : '';
      return '$_baseStr/Items/${item.seriesId}/Images/Primary'
          '?quality=90&maxHeight=$maxHeight$tagParam$key';
    }

    if (item.imageTags.containsKey('Primary')) {
      final String tag = item.imageTags['Primary']!;
      return '$_baseStr/Items/${item.id}/Images/Primary'
          '?tag=$tag&quality=90&maxHeight=$maxHeight$key';
    }

    if (item.seriesPrimaryImageTag != null && item.seriesId != null) {
      final String tag = item.seriesPrimaryImageTag!;
      return '$_baseStr/Items/${item.seriesId}/Images/Primary'
          '?tag=$tag&quality=90&maxHeight=$maxHeight$key';
    }

    if (item.parentPrimaryImageTag != null && item.parentId != null) {
      final String tag = item.parentPrimaryImageTag!;
      return '$_baseStr/Items/${item.parentId}/Images/Primary'
          '?tag=$tag&quality=90&maxHeight=$maxHeight$key';
    }

    // Fallback: If no tags were provided in the payload, try fetching the primary image directly.
    return '$_baseStr/Items/${item.id}/Images/Primary'
        '?quality=90&maxHeight=$maxHeight$key';
  }

  void close() => _dio.close(force: true);

  Future<T> _guarded<T>(Future<T> Function() call) async {
    if (!_loggedIn) {
      await login();
    }
    try {
      return await call();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        _loggedIn = false;
        await login();
        try {
          return await call();
        } on DioException catch (e2) {
          throw NetworkException.fromDio(e2);
        }
      }
      throw NetworkException.fromDio(e);
    }
  }
}
