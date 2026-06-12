import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';

import 'models/prowlarr_indexer.dart';
import 'models/prowlarr_indexer_stats.dart';
import 'models/prowlarr_release.dart';

/// Thin typed client over the Prowlarr v1 REST API.
///
/// Construction takes a [Dio] already configured for the instance (base URL +
/// `X-Api-Key`). Every method maps transport failures to [NetworkException].
class ProwlarrApi {
  ProwlarrApi(this._dio);

  final Dio _dio;

  static const String _base = 'api/v1';

  Future<List<ProwlarrIndexer>> getIndexers() async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>('$_base/indexer');
      return (resp.data as List<dynamic>)
          .map(
            (dynamic e) => ProwlarrIndexer.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<ProwlarrIndexerStats> getIndexerStats() async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('$_base/indexerstats');
      return ProwlarrIndexerStats.fromJson(resp.data as Map<String, dynamic>);
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Tests a single indexer; throws on failure, returns normally on success.
  ///
  /// The *arr test route wants the full indexer resource as the body
  /// (`POST /indexer/test`); there is no per-id test route - POSTing to
  /// `/indexer/{id}/test` is a 405. The test waits on the live tracker, so
  /// it gets extra receive-timeout headroom.
  Future<void> testIndexer(int id) async {
    final Map<String, dynamic> raw = await getIndexerRaw(id);
    try {
      await _dio.post<dynamic>(
        '$_base/indexer/test',
        data: raw,
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Raw indexer object for read-modify-write updates. The PUT endpoint
  /// expects the complete definition (fields, capabilities, ...), and
  /// [ProwlarrIndexer] is a trimmed projection of it.
  Future<Map<String, dynamic>> getIndexerRaw(int id) async {
    try {
      final Response<dynamic> resp =
          await _dio.get<dynamic>('$_base/indexer/$id');
      return resp.data as Map<String, dynamic>;
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// `forceSave=true` skips Prowlarr's test-on-save: without it, enabling an
  /// indexer whose tracker is unreachable (or slow) rejects the PUT with a
  /// validation error. A user flipping the enable switch should not be
  /// blocked on tracker reachability.
  Future<void> updateIndexerRaw(Map<String, dynamic> indexer) async {
    try {
      await _dio.put<dynamic>(
        '$_base/indexer/${indexer['id']}',
        queryParameters: <String, dynamic>{'forceSave': 'true'},
        data: indexer,
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Enables or disables an indexer via read-modify-write on the raw object.
  Future<void> setIndexerEnabled(int id, {required bool enabled}) async {
    final Map<String, dynamic> raw = await getIndexerRaw(id);
    raw['enable'] = enabled;
    await updateIndexerRaw(raw);
  }

  /// Manual search across indexers. Empty [indexerIds] means all enabled
  /// indexers.
  ///
  /// The request fans out to every indexer and waits for the slow ones, so it
  /// gets far more receive-timeout headroom than the Dio default.
  Future<List<ProwlarrRelease>> search(
    String query, {
    List<int> indexerIds = const <int>[],
    List<int> categories = const <int>[],
    int limit = 150,
  }) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        '$_base/search',
        queryParameters: <String, dynamic>{
          'query': query,
          'type': 'search',
          'limit': limit,
          'offset': 0,
          if (indexerIds.isNotEmpty) 'indexerIds': indexerIds,
          if (categories.isNotEmpty) 'categories': categories,
        },
        options: Options(receiveTimeout: const Duration(seconds: 120)),
      );
      return (resp.data as List<dynamic>)
          .map(
            (dynamic e) => ProwlarrRelease.fromJson(e as Map<String, dynamic>),
          )
          .toList();
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  /// Asks Prowlarr to grab [release] and push it to the download client
  /// configured for its protocol. Only `guid` + `indexerId` are needed -
  /// Prowlarr resolves the release from its cache.
  Future<void> grabRelease(ProwlarrRelease release) async {
    try {
      await _dio.post<dynamic>(
        '$_base/search',
        data: <String, dynamic>{
          'guid': release.guid,
          'indexerId': release.indexerId,
        },
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }
}
