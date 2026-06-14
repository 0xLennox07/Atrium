import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';

import 'models/tautulli_activity.dart';
import 'models/tautulli_json.dart';
import 'models/tautulli_models.dart';

/// Thin client over the Tautulli API.
///
/// Tautulli endpoints are `/api/v2?cmd=<command>` with the `apikey` query param
/// (appended by `core_networking`'s [AuthInterceptor]), so this rides the
/// shared `instanceDioProvider` Dio and just adds `cmd`.
class TautulliApi {
  TautulliApi(this._dio, {this.apiKey});

  final Dio _dio;

  /// Needed to build image-proxy URLs that bypass Dio - `CachedNetworkImage`
  /// fetches directly, so the key has to ride in the URL.
  final String? apiKey;

  /// Builds a Tautulli image-proxy URL for a Plex [thumb] path (poster/art).
  /// Absolute URLs (e.g. plex.tv user avatars) are returned unchanged; an
  /// empty thumb yields null so callers can show a fallback.
  String? imageUrl(
    String? thumb, {
    int width = 300,
    int height = 450,
    String fallback = 'poster',
  }) {
    if (thumb == null || thumb.isEmpty) {
      return null;
    }
    if (thumb.startsWith('http')) {
      return thumb;
    }
    final String base = _dio.options.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final String img = Uri.encodeQueryComponent(thumb);
    return '$base/api/v2?cmd=pms_image_proxy&img=$img'
        '&width=$width&height=$height&fallback=$fallback&apikey=${apiKey ?? ''}';
  }

  /// Runs a command and returns `response.data`.
  ///
  /// Tautulli answers HTTP 200 even for failed commands - the real outcome
  /// is `response.result` with the reason in `response.message`, so both are
  /// checked here for every call.
  Future<dynamic> _cmd(String cmd, [Map<String, dynamic>? params]) async {
    try {
      final Response<dynamic> resp = await _dio.get<dynamic>(
        'api/v2',
        queryParameters: <String, dynamic>{'cmd': cmd, ...?params},
      );
      final Map<String, dynamic> envelope =
          (resp.data as Map<String, dynamic>)['response']
              as Map<String, dynamic>;
      if (tString(envelope['result']) != 'success') {
        final String message = tString(envelope['message']);
        throw NetworkUnknownException(
          message.isEmpty ? 'Tautulli: $cmd failed.' : message,
        );
      }
      return envelope['data'];
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<TautulliActivity> getActivity() async {
    final dynamic data = await _cmd('get_activity');
    if (data is! Map<String, dynamic>) {
      return const TautulliActivity();
    }
    return TautulliActivity.fromJson(data);
  }

  /// Watch history, newest first.
  Future<TautulliHistoryPage> getHistory({int length = 100, int start = 0}) async {
    final dynamic data = await _cmd('get_history', <String, dynamic>{
      'length': length,
      'start': start,
      'order_column': 'date',
      'order_dir': 'desc',
    });
    return TautulliHistoryPage.fromJson(data as Map<String, dynamic>);
  }

  /// Home statistics (top movies/shows/users/platforms...) over
  /// [timeRangeDays].
  Future<List<TautulliHomeStat>> getHomeStats({
    int timeRangeDays = 30,
    int statsCount = 5,
  }) async {
    final dynamic data = await _cmd('get_home_stats', <String, dynamic>{
      'time_range': timeRangeDays,
      'stats_count': statsCount,
    });
    return ((data as List<dynamic>?) ?? <dynamic>[])
        .map((dynamic e) => TautulliHomeStat.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// All users with play counts, most plays first.
  Future<List<TautulliUser>> getUsers() async {
    final dynamic data = await _cmd('get_users_table', <String, dynamic>{
      'length': 200,
      'order_column': 'plays',
      'order_dir': 'desc',
    });
    final List<dynamic> rows =
        ((data as Map<String, dynamic>)['data'] as List<dynamic>?) ??
            <dynamic>[];
    return rows
        .map((dynamic e) => TautulliUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Stops an active stream. Requires Plex Pass on the server side;
  /// without it Tautulli reports the failure in its message, which is
  /// surfaced by [_cmd].
  Future<void> terminateSession(
    TautulliSession session, {
    String message = 'Stream stopped by the server owner.',
  }) async {
    await _cmd('terminate_session', <String, dynamic>{
      if (session.sessionKey.isNotEmpty) 'session_key': session.sessionKey,
      if (session.sessionId.isNotEmpty) 'session_id': session.sessionId,
      'message': message,
    });
  }
}
