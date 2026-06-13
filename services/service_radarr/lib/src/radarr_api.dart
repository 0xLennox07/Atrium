import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';

import 'models/radarr_add_models.dart';
import 'models/radarr_movie.dart';
import 'models/radarr_queue.dart';
import 'models/radarr_release.dart';

/// Thin typed client over the Radarr v3 REST API.
///
/// Mirrors [SonarrApi]: construction takes a [Dio] already configured for the
/// instance (base URL + `X-Api-Key`), and every method maps transport
/// failures to [NetworkException] so the UI sees one error type.
///
/// [apiKey] is an optional copy of the instance's API key, used only to build
/// authenticated *image* URLs (Radarr's `/MediaCover/...` routes don't read
/// the `X-Api-Key` header - `cached_network_image` fetches the bytes outside
/// of our Dio so the key has to ride as a query param).
class RadarrApi {
  RadarrApi(this._dio, {this.apiKey});

  final Dio _dio;
  final String? apiKey;

  static const String _base = 'api/v3';

  Future<List<RadarrMovie>> getMovies() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/movie');
      return (resp.data as List<dynamic>)
          .map(
            (dynamic e) => RadarrMovie.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<RadarrMovie> getMovieById(int id) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/movie/$id');
      return RadarrMovie.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<RadarrQueuePage> getQueue({
    int page = 1,
    int pageSize = 50,
    bool includeMovie = true,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/queue',
        queryParameters: <String, dynamic>{
          'page': page,
          'pageSize': pageSize,
          'includeMovie': includeMovie,
        },
      );
      return RadarrQueuePage.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Kicks off a search for a movie.
  Future<void> searchMovie(int movieId) async {
    try {
      await _dio.post<dynamic>(
        '$_base/command',
        data: <String, dynamic>{
          'name': 'MoviesSearch',
          'movieIds': <int>[movieId],
        },
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<RadarrRelease>> getReleases(int movieId) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/release',
        queryParameters: <String, dynamic>{'movieId': movieId},
        options: Options(
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 120),
        ),
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => RadarrRelease(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> grabRelease(RadarrRelease release) async {
    try {
      await _dio.post<dynamic>(
        '$_base/release',
        data: release.raw,
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Updates a movie. Radarr's PUT wants the FULL movie object; see
  /// [SonarrApi.updateSeriesRaw] for why this takes a raw map.
  Future<void> updateMovieRaw(Map<String, dynamic> movieJson) async {
    try {
      await _dio.put<dynamic>(
        '$_base/movie/${movieJson['id']}',
        data: movieJson,
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Fetches the FULL movie JSON (untrimmed) for read-modify-write flows.
  Future<Map<String, dynamic>> getMovieRaw(int id) async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('$_base/movie/$id');
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Deletes a movie, optionally with its files on disk.
  Future<void> deleteMovie(int id, {bool deleteFiles = false}) async {
    try {
      await _dio.delete<dynamic>(
        '$_base/movie/$id',
        queryParameters: <String, dynamic>{'deleteFiles': deleteFiles},
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Searches the metadata provider for movies matching [term].
  Future<List<RadarrLookupResult>> lookupMovies(String term) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/movie/lookup',
        queryParameters: <String, dynamic>{'term': term},
      );
      return (resp.data as List<dynamic>)
          .map(
            (dynamic e) => RadarrLookupResult(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Quality profiles configured on the server.
  Future<List<RadarrQualityProfile>> getQualityProfiles() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('$_base/qualityprofile');
      return (resp.data as List<dynamic>)
          .map(
            (dynamic e) =>
                RadarrQualityProfile.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Root folders configured on the server.
  Future<List<RadarrRootFolder>> getRootFolders() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('$_base/rootfolder');
      return (resp.data as List<dynamic>)
          .map(
            (dynamic e) =>
                RadarrRootFolder.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Adds a movie from a lookup result.
  ///
  /// [lookup] is the complete raw object from [lookupMovies] - Radarr's POST
  /// expects it back whole, decorated with the library options below.
  Future<void> addMovie(
    RadarrLookupResult lookup, {
    required int qualityProfileId,
    required String rootFolderPath,
    bool monitored = true,
    bool searchOnAdd = true,
  }) async {
    try {
      final Map<String, dynamic> body =
          Map<String, dynamic>.of(lookup.raw)
            ..['qualityProfileId'] = qualityProfileId
            ..['rootFolderPath'] = rootFolderPath
            ..['monitored'] = monitored
            ..['addOptions'] = <String, dynamic>{
              'searchForMovie': searchOnAdd,
            };
      await _dio.post<dynamic>('$_base/movie', data: body);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Removes a queue item, optionally blocklisting the release.
  Future<void> deleteQueueItem(
    int id, {
    bool removeFromClient = true,
    bool blocklist = false,
  }) async {
    try {
      await _dio.delete<dynamic>(
        '$_base/queue/$id',
        queryParameters: <String, dynamic>{
          'removeFromClient': removeFromClient,
          'blocklist': blocklist,
        },
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<RadarrMovie>> getCalendar({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/calendar',
        queryParameters: <String, dynamic>{
          'start': start.toUtc().toIso8601String(),
          'end': end.toUtc().toIso8601String(),
        },
      );
      return (resp.data as List<dynamic>)
          .map(
            (dynamic e) => RadarrMovie.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Absolute, authenticated URL for a movie image, suitable for
  /// `CachedNetworkImage`.
  ///
  /// Radarr's `images[].url` points at the session-authenticated web-UI
  /// route (`/MediaCover/...`) which bounces `?apikey=` requests to the
  /// login page as HTML; the API route `/api/v3/mediacover/...` serves the
  /// same files and accepts `apikey`. See [SonarrApi.posterUrl].
  String? posterUrl(RadarrImage image) {
    final String? remote = image.url;
    final String? upstream = image.remoteUrl;
    if (remote != null && remote.isNotEmpty) {
      final Uri base = Uri.parse(_dio.options.baseUrl);
      
      String pathOrUrl = remote;
      if (pathOrUrl.startsWith('/MediaCover/')) {
        pathOrUrl = '$_base/mediacover${pathOrUrl.substring('/MediaCover'.length)}';
      } else if (pathOrUrl.startsWith('MediaCover/')) {
        pathOrUrl = '$_base/mediacover${pathOrUrl.substring('MediaCover'.length)}';
      }

      final Uri abs = pathOrUrl.startsWith('http')
          ? Uri.parse(pathOrUrl)
          : base.resolve(pathOrUrl.startsWith('/') ? pathOrUrl.substring(1) : pathOrUrl);

      if (apiKey == null || apiKey!.isEmpty) {
        return abs.toString();
      }
      return abs.replace(
        queryParameters: <String, String>{
          ...abs.queryParameters,
          'apikey': apiKey!,
        },
      ).toString();
    }
    if (upstream != null && upstream.isNotEmpty) {
      return upstream;
    }
    return null;
  }
}
