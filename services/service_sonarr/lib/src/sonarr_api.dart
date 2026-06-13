import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';

import 'models/sonarr_add_models.dart';
import 'models/sonarr_blocklist.dart';
import 'models/sonarr_calendar.dart';
import 'models/sonarr_episode.dart';
import 'models/sonarr_history.dart';
import 'models/sonarr_queue.dart';
import 'models/sonarr_release.dart';
import 'models/sonarr_series.dart';
import 'models/sonarr_settings_models.dart';
import 'models/sonarr_system.dart';
import 'models/sonarr_wanted.dart';

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

  Future<List<SonarrEpisode>> getEpisodes(int seriesId) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/episode',
        queryParameters: <String, dynamic>{'seriesId': seriesId},
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrEpisode.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateEpisode(SonarrEpisode episode) async {
    try {
      await _dio.put<dynamic>(
        '$_base/episode/${episode.id}',
        data: episode.toJson(),
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> searchEpisode(int episodeId) async {
    try {
      await _dio.post<dynamic>(
        '$_base/command',
        data: <String, dynamic>{
          'name': 'EpisodeSearch',
          'episodeIds': <int>[episodeId],
        },
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrRelease>> getReleases(int episodeId) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/release',
        queryParameters: <String, dynamic>{'episodeId': episodeId},
        options: Options(
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 120),
        ),
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrRelease(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrRelease>> getSeasonReleases(int seriesId, int seasonNumber) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/release',
        queryParameters: <String, dynamic>{
          'seriesId': seriesId,
          'seasonNumber': seasonNumber,
        },
        options: Options(
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 120),
        ),
      );
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrRelease(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> grabRelease(SonarrRelease release) async {
    try {
      await _dio.post<dynamic>(
        '$_base/release',
        data: release.raw,
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
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

  Future<List<Map<String, dynamic>>> getQualityProfilesRaw() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/qualityprofile');
      return (resp.data as List<dynamic>).map((dynamic e) => e as Map<String, dynamic>).toList();
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

  Future<SonarrHistoryPage> getHistory({
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/history',
        queryParameters: <String, dynamic>{
          'page': page,
          'pageSize': pageSize,
          'sortKey': 'date',
          'sortDirection': 'descending',
        },
      );
      return SonarrHistoryPage.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<SonarrBlocklistPage> getBlocklist({
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/blocklist',
        queryParameters: <String, dynamic>{
          'page': page,
          'pageSize': pageSize,
          'sortKey': 'date',
          'sortDirection': 'descending',
        },
      );
      return SonarrBlocklistPage.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> deleteBlocklist(int id) async {
    try {
      await _dio.delete<dynamic>('$_base/blocklist/$id');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<SonarrWantedPage> getWantedMissing({
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/wanted/missing',
        queryParameters: <String, dynamic>{
          'page': page,
          'pageSize': pageSize,
          'includeSeries': true,
        },
      );
      return SonarrWantedPage.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<SonarrWantedPage> getWantedCutoff({
    int page = 1,
    int pageSize = 50,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/wanted/cutoff',
        queryParameters: <String, dynamic>{
          'page': page,
          'pageSize': pageSize,
          'includeSeries': true,
        },
      );
      return SonarrWantedPage.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> triggerMissingSearch() async {
    try {
      await _dio.post<dynamic>(
        '$_base/command',
        data: <String, dynamic>{
          'name': 'MissingEpisodeSearch',
        },
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> triggerCutoffUnmetSearch() async {
    try {
      await _dio.post<dynamic>(
        '$_base/command',
        data: <String, dynamic>{
          'name': 'CutoffUnmetEpisodeSearch',
        },
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<SonarrSystemStatus> getSystemStatus() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/system/status');
      return SonarrSystemStatus.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrDiskSpace>> getDiskSpace() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/diskspace');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrDiskSpace.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrSystemTask>> getSystemTasks() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/system/task');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrSystemTask.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> runSystemTask(String taskName) async {
    try {
      await _dio.post<dynamic>(
        '$_base/command',
        data: <String, dynamic>{
          'name': taskName,
        },
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrHealth>> getHealth() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/health');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrHealth.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrBackup>> getBackups() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/system/backup');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrBackup.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> deleteBackup(int id) async {
    try {
      await _dio.delete<dynamic>('$_base/system/backup/$id');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrTag>> getTags() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/tag');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrTag.fromJson(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> createTag(String label) async {
    try {
      await _dio.post<dynamic>('$_base/tag', data: <String, dynamic>{'label': label});
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> deleteTag(int id) async {
    try {
      await _dio.delete<dynamic>('$_base/tag/$id');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrIndexer>> getIndexers() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/indexer');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrIndexer(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateIndexerRaw(Map<String, dynamic> indexerJson) async {
    try {
      await _dio.put<dynamic>('$_base/indexer/${indexerJson['id']}', data: indexerJson);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> testIndexerRaw(Map<String, dynamic> indexerJson) async {
    try {
      await _dio.post<dynamic>('$_base/indexer/test', data: indexerJson);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> deleteIndexer(int id) async {
    try {
      await _dio.delete<dynamic>('$_base/indexer/$id');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrDownloadClient>> getDownloadClients() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/downloadclient');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrDownloadClient(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateDownloadClientRaw(Map<String, dynamic> clientJson) async {
    try {
      await _dio.put<dynamic>('$_base/downloadclient/${clientJson['id']}', data: clientJson);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> testDownloadClientRaw(Map<String, dynamic> clientJson) async {
    try {
      await _dio.post<dynamic>('$_base/downloadclient/test', data: clientJson);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> deleteDownloadClient(int id) async {
    try {
      await _dio.delete<dynamic>('$_base/downloadclient/$id');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrNotification>> getNotifications() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/notification');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrNotification(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateNotificationRaw(Map<String, dynamic> notificationJson) async {
    try {
      await _dio.put<dynamic>('$_base/notification/${notificationJson['id']}', data: notificationJson);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> testNotificationRaw(Map<String, dynamic> notificationJson) async {
    try {
      await _dio.post<dynamic>('$_base/notification/test', data: notificationJson);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> deleteNotification(int id) async {
    try {
      await _dio.delete<dynamic>('$_base/notification/$id');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrImportList>> getImportLists() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/importlist');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrImportList(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateImportListRaw(Map<String, dynamic> listJson) async {
    try {
      await _dio.put<dynamic>('$_base/importlist/${listJson['id']}', data: listJson);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> testImportListRaw(Map<String, dynamic> listJson) async {
    try {
      await _dio.post<dynamic>('$_base/importlist/test', data: listJson);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> deleteImportList(int id) async {
    try {
      await _dio.delete<dynamic>('$_base/importlist/$id');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<SonarrHostConfig> getHostConfig() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/config/host');
      return SonarrHostConfig(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateHostConfigRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.put<dynamic>('$_base/config/host/${raw['id']}', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<SonarrNamingConfig> getNamingConfig() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/config/naming');
      return SonarrNamingConfig(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateNamingConfigRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.put<dynamic>('$_base/config/naming/${raw['id']}', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<SonarrMediaManagementConfig> getMediaManagementConfig() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/config/mediamanagement');
      return SonarrMediaManagementConfig(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateMediaManagementConfigRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.put<dynamic>('$_base/config/mediamanagement/${raw['id']}', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<SonarrUiConfig> getUiConfig() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/config/ui');
      return SonarrUiConfig(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateUiConfigRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.put<dynamic>('$_base/config/ui/${raw['id']}', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrMetadataProvider>> getMetadataProviders() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/metadata');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrMetadataProvider(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateMetadataProviderRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.put<dynamic>('$_base/metadata/${raw['id']}', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> testMetadataProviderRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.post<dynamic>('$_base/metadata/test', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrDelayProfile>> getDelayProfiles() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/delayprofile');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrDelayProfile(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateDelayProfileRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.put<dynamic>('$_base/delayprofile/${raw['id']}', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrCustomFormat>> getCustomFormats() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/customformat');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrCustomFormat(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> deleteCustomFormat(int id) async {
    try {
      await _dio.delete<dynamic>('$_base/customformat/$id');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<Map<String, dynamic>>> getDownloadClientSchema() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/downloadclient/schema');
      return (resp.data as List<dynamic>).map((dynamic e) => e as Map<String, dynamic>).toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> createDownloadClientRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.post<dynamic>('$_base/downloadclient', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<Map<String, dynamic>>> getIndexerSchema() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/indexer/schema');
      return (resp.data as List<dynamic>).map((dynamic e) => e as Map<String, dynamic>).toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> createIndexerRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.post<dynamic>('$_base/indexer', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<Map<String, dynamic>>> getNotificationSchema() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/notification/schema');
      return (resp.data as List<dynamic>).map((dynamic e) => e as Map<String, dynamic>).toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> createNotificationRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.post<dynamic>('$_base/notification', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<Map<String, dynamic>>> getImportListSchema() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/importlist/schema');
      return (resp.data as List<dynamic>).map((dynamic e) => e as Map<String, dynamic>).toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> createImportListRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.post<dynamic>('$_base/importlist', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrQualityDefinition>> getQualityDefinitions() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/qualitydefinition');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrQualityDefinition(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateQualityDefinitionRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.put<dynamic>('$_base/qualitydefinition/${raw['id']}', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrReleaseProfile>> getReleaseProfiles() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/releaseprofile');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrReleaseProfile(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> createReleaseProfileRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.post<dynamic>('$_base/releaseprofile', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateReleaseProfileRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.put<dynamic>('$_base/releaseprofile/${raw['id']}', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> deleteReleaseProfile(int id) async {
    try {
      await _dio.delete<dynamic>('$_base/releaseprofile/$id');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> deleteEpisodeFile(int id) async {
    try {
      await _dio.delete<dynamic>('$_base/episodefile/$id');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<Map<String, dynamic>>> getRenamePreviews(int seriesId) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/rename',
        queryParameters: <String, dynamic>{'seriesId': seriesId},
      );
      return (resp.data as List<dynamic>).map((dynamic e) => e as Map<String, dynamic>).toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> executeRename(int seriesId, List<int> filesIds) async {
    try {
      await _dio.post<dynamic>(
        '$_base/command',
        data: <String, dynamic>{
          'name': 'RenameFiles',
          'seriesId': seriesId,
          'files': filesIds,
        },
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrImportListExclusion>> getImportListExclusions() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/importlistexclusion');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrImportListExclusion(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> createImportListExclusionRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.post<dynamic>('$_base/importlistexclusion', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> deleteImportListExclusion(int id) async {
    try {
      await _dio.delete<dynamic>('$_base/importlistexclusion/$id');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<SonarrAutoTaggingRule>> getAutoTaggingRules() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/autotagging');
      return (resp.data as List<dynamic>)
          .map((dynamic e) => SonarrAutoTaggingRule(e as Map<String, dynamic>))
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> createAutoTaggingRuleRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.post<dynamic>('$_base/autotagging', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateAutoTaggingRuleRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.put<dynamic>('$_base/autotagging/${raw['id']}', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> deleteAutoTaggingRule(int id) async {
    try {
      await _dio.delete<dynamic>('$_base/autotagging/$id');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<Map<String, dynamic>> getQualityProfileSchema() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/qualityprofile/schema');
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> createQualityProfileRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.post<dynamic>('$_base/qualityprofile', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> updateQualityProfileRaw(Map<String, dynamic> raw) async {
    try {
      await _dio.put<dynamic>('$_base/qualityprofile/${raw['id']}', data: raw);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<void> deleteQualityProfile(int id) async {
    try {
      await _dio.delete<dynamic>('$_base/qualityprofile/$id');
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
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
