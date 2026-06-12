import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';

import 'models/sonarr_add_models.dart';
import 'models/sonarr_calendar.dart';
import 'models/sonarr_queue.dart';
import 'models/sonarr_series.dart';

/// Thin typed client over the Sonarr v3 REST API.
///
/// Construction takes a [Dio] already configured for the instance (base URL
/// + `X-Api-Key` header), produced by `core_networking`'s DioFactory. Every
/// method maps transport failures to [NetworkException] so the UI layer sees
/// one error type.
///
/// [apiKey] is an optional copy of the instance's API key, used only to
/// build authenticated *image* URLs (Sonarr's `/MediaCover/...` routes
/// don't honor the `X-Api-Key` header - they need it as a query parameter
/// because the bytes are fetched by `cached_network_image`, which bypasses
/// our Dio entirely).
class SonarrApi {
  SonarrApi(this._dio, {this.apiKey});

  final Dio _dio;
  final String? apiKey;

  static const String _base = 'api/v3';

  Future<List<SonarrSeries>> getSeries() async {
    return _list<SonarrSeries>('$_base/series', SonarrSeries.fromJson);
  }

  Future<SonarrSeries> getSeriesById(int id) async {
    return _one<SonarrSeries>('$_base/series/$id', SonarrSeries.fromJson);
  }

  Future<SonarrQueuePage> getQueue({
    int page = 1,
    int pageSize = 50,
    bool includeSeries = true,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/queue',
        queryParameters: <String, dynamic>{
          'page': page,
          'pageSize': pageSize,
          'includeSeries': includeSeries,
        },
      );
      return SonarrQueuePage.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrCalendarEntry>> getCalendar({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/calendar',
        queryParameters: <String, dynamic>{
          'start': start.toUtc().toIso8601String(),
          'end': end.toUtc().toIso8601String(),
          'includeSeries': true,
        },
      );
      return (resp.data as List<dynamic>)
          .map(
            (dynamic e) =>
                SonarrCalendarEntry.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Kicks off a search for all monitored missing episodes of a series.
  Future<void> searchSeries(int seriesId) async {
    try {
      await _dio.post<dynamic>(
        '$_base/command',
        data: <String, dynamic>{
          'name': 'SeriesSearch',
          'seriesId': seriesId,
        },
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Kicks off a search for one season of a series.
  Future<void> searchSeason(int seriesId, int seasonNumber) async {
    try {
      await _dio.post<dynamic>(
        '$_base/command',
        data: <String, dynamic>{
          'name': 'SeasonSearch',
          'seriesId': seriesId,
          'seasonNumber': seasonNumber,
        },
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Updates a series. Sonarr's PUT wants the FULL series object, so the
  /// caller fetches it (fresh), mutates fields (monitored flags, etc.), and
  /// passes the whole JSON map back through here. We deliberately take the
  /// raw map rather than the typed model: our model is a trimmed projection
  /// and round-tripping it would drop fields Sonarr expects back.
  Future<void> updateSeriesRaw(Map<String, dynamic> seriesJson) async {
    try {
      await _dio.put<dynamic>(
        '$_base/series/${seriesJson['id']}',
        data: seriesJson,
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Fetches the FULL series JSON (untrimmed) for read-modify-write flows.
  Future<Map<String, dynamic>> getSeriesRaw(int id) async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('$_base/series/$id');
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Deletes a series, optionally with its files on disk.
  Future<void> deleteSeries(int id, {bool deleteFiles = false}) async {
    try {
      await _dio.delete<dynamic>(
        '$_base/series/$id',
        queryParameters: <String, dynamic>{'deleteFiles': deleteFiles},
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Searches the metadata provider for series matching [term].
  Future<List<SonarrLookupResult>> lookupSeries(String term) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/series/lookup',
        queryParameters: <String, dynamic>{'term': term},
      );
      return (resp.data as List<dynamic>)
          .map(
            (dynamic e) => SonarrLookupResult(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Quality profiles configured on the server.
  Future<List<SonarrQualityProfile>> getQualityProfiles() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('$_base/qualityprofile');
      return (resp.data as List<dynamic>)
          .map(
            (dynamic e) =>
                SonarrQualityProfile.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Root folders configured on the server.
  Future<List<SonarrRootFolder>> getRootFolders() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('$_base/rootfolder');
      return (resp.data as List<dynamic>)
          .map(
            (dynamic e) =>
                SonarrRootFolder.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Adds a series from a lookup result.
  ///
  /// [lookup] is the complete raw object from [lookupSeries] - Sonarr's POST
  /// expects it back whole, decorated with the library options below.
  /// [monitor] follows Sonarr's addOptions.monitor vocabulary ('all',
  /// 'future', 'missing', 'existing', 'firstSeason', 'latestSeason', 'none').
  Future<void> addSeries(
    SonarrLookupResult lookup, {
    required int qualityProfileId,
    required String rootFolderPath,
    bool monitored = true,
    String monitor = 'all',
    bool searchForMissing = true,
    bool seasonFolder = true,
  }) async {
    try {
      final Map<String, dynamic> body =
          Map<String, dynamic>.of(lookup.raw)
            ..['qualityProfileId'] = qualityProfileId
            ..['rootFolderPath'] = rootFolderPath
            ..['monitored'] = monitored
            ..['seasonFolder'] = seasonFolder
            ..['addOptions'] = <String, dynamic>{
              'monitor': monitor,
              'searchForMissingEpisodes': searchForMissing,
            };
      await _dio.post<dynamic>('$_base/series', data: body);
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

  /// Absolute, authenticated URL for a series image, suitable for
  /// `CachedNetworkImage`.
  ///
  /// Sonarr's `images[].url` points at the web-UI route
  /// (`/MediaCover/...`), which is session-authenticated - requesting it
  /// with `?apikey=` just bounces to the login page as `text/html`, which
  /// the platform image decoder then fails on ("unimplemented"). The API
  /// route `/api/v3/mediacover/...` serves the same files and DOES accept
  /// `apikey`, so we rewrite the path onto it.
  ///
  /// Preference order:
  /// 1. The Sonarr-hosted [SonarrImage.url], rewritten through
  ///    `/api/v3/mediacover/...` and resolved against the dio's current
  ///    base URL (so the LAN/WAN choice the resolver picked is honored).
  /// 2. The upstream [SonarrImage.remoteUrl] (TheTVDB / TVMaze / etc.) as a
  ///    fallback if the local copy hasn't been generated yet.
  String? posterUrl(SonarrImage image) {
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

  Future<List<T>> _list<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(path);
      return (resp.data as List<dynamic>)
          .map((dynamic e) => fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<T> _one<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(path);
      return fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }
}
