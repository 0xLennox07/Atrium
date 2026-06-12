import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'models/qbit_detail.dart';
import 'models/qbit_torrent.dart';
import 'models/qbit_transfer_info.dart';

/// Client for the qBittorrent WebUI API v2.
///
/// Unlike the *arr services (static `X-Api-Key`), qBittorrent uses
/// cookie-based session auth: POST credentials to `/api/v2/auth/login`, which
/// sets an `SID` cookie that must ride along on every subsequent request. We
/// attach a [CookieManager] so Dio persists that cookie, and re-login once on
/// a 403 (expired session).
///
/// qBittorrent also enforces CSRF/Referer checks by default, so we set the
/// `Referer` header to the base URL - that's what browser-equivalent clients
/// do and it satisfies a default WebUI config.
class QbittorrentClient {
  QbittorrentClient({
    required Dio dio,
    required CookieJar cookies,
    required this.username,
    required this.password,
  })  : _dio = dio,
        _cookies = cookies;

  final Dio _dio;
  final CookieJar _cookies;
  final String username;
  final String password;
  bool _loggedIn = false;

  /// Builds a client with a cookie-aware Dio pointed at [baseUrl].
  static QbittorrentClient create({
    required Uri baseUrl,
    required String username,
    required String password,
    required bool allowSelfSigned,
  }) {
    final String baseUrlStr = baseUrl.toString();
    final String normalizedBaseUrl = baseUrlStr.endsWith('/') ? baseUrlStr : '$baseUrlStr/';
    final CookieJar cookies = CookieJar();
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: normalizedBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: <String, dynamic>{'Referer': normalizedBaseUrl},
      ),
    );
    dio.interceptors.add(CookieManager(cookies));
    if (allowSelfSigned) {
      final IOHttpClientAdapter adapter =
          dio.httpClientAdapter as IOHttpClientAdapter;
      adapter.createHttpClient = () => HttpClient()
        ..badCertificateCallback =
            (X509Certificate _, String __, int ___) => true;
    }
    return QbittorrentClient(
      dio: dio,
      cookies: cookies,
      username: username,
      password: password,
    );
  }

  /// Authenticates and stores the session cookie.
  ///
  /// qBittorrent's `/api/v2/auth/login` response shape depends on version:
  ///
  ///   * **qBit ≤ 4.x:** HTTP 200 + body `Ok.` on success, `Fails.` on
  ///     wrong creds, HTTP 403 on banned IP.
  ///   * **qBit ≥ 5.x:** HTTP 204 No Content + `Set-Cookie: QBT_SID_<port>=…`
  ///     on success (the cookie name is port-scoped now). Wrong creds and
  ///     ban behavior are unchanged.
  ///
  /// We accept any status (`validateStatus`) so we can branch on each case
  /// explicitly and surface remediation advice in the error message.
  Future<void> login() async {
    try {
      // Start each login with a clean cookie jar so a stale SID from an
      // earlier failed attempt can't shadow the fresh one we're about to
      // receive.
      await _cookies.deleteAll();
      final Response<String> resp = await _dio.post<String>(
        'api/v2/auth/login',
        data: <String, dynamic>{'username': username, 'password': password},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          validateStatus: (int? s) => s != null,
        ),
      );
      final int status = resp.statusCode ?? 0;
      final String body = (resp.data ?? '').trim();
      if (status == 204 || (status == 200 && body == 'Ok.')) {
        _loggedIn = true;
        return;
      }
      if (status == 403) {
        throw const NetworkAuthException(
          'qBittorrent banned this IP after repeated failed logins. '
          "Wait ~5 minutes and retry, or disable the ban in qBit's "
          'Tools → Options → Web UI → Authentication.',
        );
      }
      if (status == 200 && body == 'Fails.') {
        throw const NetworkAuthException(
          'qBittorrent rejected the credentials. Verify username + password '
          "directly in qBit's web UI. Three wrong attempts trigger a "
          '5-minute IP ban.',
        );
      }
      throw NetworkAuthException(
        'qBittorrent login returned HTTP $status with body: '
        '${body.isEmpty ? '<empty>' : body}',
      );
    } on DioException catch (e) {
      throw NetworkException.fromDio(e);
    }
  }

  Future<List<QbitTorrent>> getTorrents() => _guarded(() async {
        final Response<dynamic> resp =
            await _dio.get<dynamic>('api/v2/torrents/info');
        return (resp.data as List<dynamic>)
            .map((dynamic e) => QbitTorrent.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<QbitTransferInfo> getTransferInfo() => _guarded(() async {
        final Response<dynamic> resp =
            await _dio.get<dynamic>('api/v2/transfer/info');
        return QbitTransferInfo.fromJson(resp.data as Map<String, dynamic>);
      });

  Future<void> pause(String hash) => _torrentCommand(hash, stop: true);

  Future<void> resume(String hash) => _torrentCommand(hash, stop: false);

  Future<void> delete(String hash, {required bool deleteFiles}) =>
      _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/delete',
          data: <String, dynamic>{'hashes': hash, 'deleteFiles': deleteFiles},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Adds one or more torrents from magnet links or http(s) `.torrent` URLs.
  ///
  /// [urlsOrMagnets] may contain multiple entries (qBittorrent accepts them
  /// newline-separated). Optional [category], [savePath], [paused], and
  /// [sequential] map to the matching `/torrents/add` form fields. Returns
  /// nothing - call `getTorrents()` afterwards to refresh.
  Future<void> addUrls(
    List<String> urlsOrMagnets, {
    String? category,
    String? savePath,
    bool paused = false,
    bool sequential = false,
  }) =>
      _guarded(() async {
        final FormData form = FormData.fromMap(<String, dynamic>{
          'urls': urlsOrMagnets.join('\n'),
          if (category != null && category.isNotEmpty) 'category': category,
          if (savePath != null && savePath.isNotEmpty) 'savepath': savePath,
          'paused': paused ? 'true' : 'false',
          'sequentialDownload': sequential ? 'true' : 'false',
        });
        await _dio.post<dynamic>('api/v2/torrents/add', data: form);
      });

  /// Backwards-compatible single-URL add.
  Future<void> addUrl(String urlOrMagnet) => addUrls(<String>[urlOrMagnet]);

  /// Adds a torrent from a raw `.torrent` file's bytes (multipart upload).
  Future<void> addTorrentFile(
    Uint8List bytes, {
    required String filename,
    String? category,
    String? savePath,
    bool paused = false,
    bool sequential = false,
  }) =>
      _guarded(() async {
        final FormData form = FormData.fromMap(<String, dynamic>{
          'torrents': MultipartFile.fromBytes(
            bytes,
            filename: filename,
            contentType: DioMediaType('application', 'x-bittorrent'),
          ),
          if (category != null && category.isNotEmpty) 'category': category,
          if (savePath != null && savePath.isNotEmpty) 'savepath': savePath,
          'paused': paused ? 'true' : 'false',
          'sequentialDownload': sequential ? 'true' : 'false',
        });
        await _dio.post<dynamic>('api/v2/torrents/add', data: form);
      });

  /// Detailed properties of one torrent (`/torrents/properties`).
  Future<QbitTorrentProperties> getProperties(String hash) =>
      _guarded(() async {
        final Response<dynamic> resp = await _dio.get<dynamic>(
          'api/v2/torrents/properties',
          queryParameters: <String, dynamic>{'hash': hash},
        );
        return QbitTorrentProperties.fromJson(
          resp.data as Map<String, dynamic>,
        );
      });

  /// Per-file listing of one torrent (`/torrents/files`).
  Future<List<QbitFile>> getFiles(String hash) => _guarded(() async {
        final Response<dynamic> resp = await _dio.get<dynamic>(
          'api/v2/torrents/files',
          queryParameters: <String, dynamic>{'hash': hash},
        );
        return (resp.data as List<dynamic>)
            .map((dynamic e) => QbitFile.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  /// Tracker list of one torrent (`/torrents/trackers`).
  Future<List<QbitTracker>> getTrackers(String hash) => _guarded(() async {
        final Response<dynamic> resp = await _dio.get<dynamic>(
          'api/v2/torrents/trackers',
          queryParameters: <String, dynamic>{'hash': hash},
        );
        return (resp.data as List<dynamic>)
            .map(
              (dynamic e) => QbitTracker.fromJson(e as Map<String, dynamic>),
            )
            .toList();
      });

  /// Sets download priority for files within a torrent.
  ///
  /// [priority]: 0 = don't download, 1 = normal, 6 = high, 7 = maximal.
  /// [fileIds] are the indices from [getFiles] (`QbitFile.index`).
  Future<void> setFilePriority(
    String hash,
    List<int> fileIds,
    int priority,
  ) =>
      _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/filePrio',
          data: <String, dynamic>{
            'hash': hash,
            'id': fileIds.join('|'),
            'priority': priority,
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// All category names defined on the server (sorted).
  Future<List<String>> getCategories() => _guarded(() async {
        final Response<dynamic> resp =
            await _dio.get<dynamic>('api/v2/torrents/categories');
        final Map<String, dynamic> map =
            (resp.data as Map<String, dynamic>?) ?? <String, dynamic>{};
        final List<String> names = map.keys.toList()..sort();
        return names;
      });

  /// Moves a torrent into [category] (empty string clears it).
  Future<void> setCategory(String hash, String category) => _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/setCategory',
          data: <String, dynamic>{'hashes': hash, 'category': category},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Forces a re-check of a torrent's data.
  Future<void> recheck(String hash) => _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/recheck',
          data: <String, dynamic>{'hashes': hash},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Bumps a torrent's queue priority up or down one slot.
  Future<void> setPriority(String hash, {required bool increase}) =>
      _guarded(() async {
        final String path = increase
            ? 'api/v2/torrents/increasePrio'
            : 'api/v2/torrents/decreasePrio';
        await _dio.post<dynamic>(
          path,
          data: <String, dynamic>{'hashes': hash},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Pauses or resumes every torrent. qBit 5.0 renamed the global endpoints
  /// (pause→stop, resume→start) just like the per-torrent ones, so we try the
  /// new path first and fall back on 404.
  Future<void> setAllPaused({required bool paused}) => _guarded(() async {
        final String primary = paused
            ? 'api/v2/torrents/stop'
            : 'api/v2/torrents/start';
        final String fallback = paused
            ? 'api/v2/torrents/pause'
            : 'api/v2/torrents/resume';
        try {
          await _dio.post<dynamic>(
            primary,
            data: <String, dynamic>{'hashes': 'all'},
            options: Options(contentType: Headers.formUrlEncodedContentType),
          );
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) {
            await _dio.post<dynamic>(
              fallback,
              data: <String, dynamic>{'hashes': 'all'},
              options: Options(contentType: Headers.formUrlEncodedContentType),
            );
          } else {
            rethrow;
          }
        }
      });

  void close() => _dio.close(force: true);

  /// qBittorrent 5.0 renamed pause→stop and resume→start. Try the new path,
  /// fall back to the legacy one on 404 so we work across versions.
  Future<void> _torrentCommand(String hash, {required bool stop}) =>
      _guarded(() async {
        final String primary =
            stop ? 'api/v2/torrents/stop' : 'api/v2/torrents/start';
        final String fallback =
            stop ? 'api/v2/torrents/pause' : 'api/v2/torrents/resume';
        try {
          await _dio.post<dynamic>(
            primary,
            data: <String, dynamic>{'hashes': hash},
            options: Options(contentType: Headers.formUrlEncodedContentType),
          );
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) {
            await _dio.post<dynamic>(
              fallback,
              data: <String, dynamic>{'hashes': hash},
              options: Options(contentType: Headers.formUrlEncodedContentType),
            );
          } else {
            rethrow;
          }
        }
      });

  /// Ensures a session exists, runs [call], and re-logins once on a 403.
  Future<T> _guarded<T>(Future<T> Function() call) async {
    if (!_loggedIn) {
      await login();
    }
    try {
      return await call();
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
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
