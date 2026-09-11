import 'dart:convert';
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
    this.apiKey,
  })  : _dio = dio,
        _cookies = cookies;

  final Dio _dio;
  final CookieJar _cookies;
  final String username;
  final String password;

  /// qBittorrent 5.2+ API key (`qbt_…`). When set it is sent as
  /// `Authorization: Bearer <key>` and the cookie login flow is skipped
  /// entirely (the key is stateless and cannot use the auth endpoints).
  final String? apiKey;

  bool get _usesApiKey => apiKey != null && apiKey!.isNotEmpty;
  bool _loggedIn = false;

  /// Builds a client with a cookie-aware Dio pointed at [baseUrl].
  static QbittorrentClient create({
    required Uri baseUrl,
    required String username,
    required String password,
    required bool allowSelfSigned,
    String? apiKey,
    Map<String, String> customHeaders = const <String, String>{},
  }) {
    final String baseUrlStr = baseUrl.toString();
    final String normalizedBaseUrl =
        baseUrlStr.endsWith('/') ? baseUrlStr : '$baseUrlStr/';
    final CookieJar cookies = CookieJar();
    final Map<String, dynamic> headers = <String, dynamic>{
      'Referer': normalizedBaseUrl,
      if (apiKey != null && apiKey.isNotEmpty)
        'Authorization': 'Bearer $apiKey',
    };
    final Dio dio = Dio(
      BaseOptions(
        baseUrl: normalizedBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: headers,
      ),
    );
    // User-configured headers ride alongside the Referer above (a user
    // Referer key would deliberately override it - instance wins).
    dio.options.headers.addAll(customHeaders);
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
      apiKey: apiKey,
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

  Future<void> pause(List<String> hashes) =>
      _torrentCommand(hashes.join('|'), stop: true);

  Future<void> resume(List<String> hashes) =>
      _torrentCommand(hashes.join('|'), stop: false);

  Future<void> delete(List<String> hashes, {required bool deleteFiles}) =>
      _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/delete',
          data: <String, dynamic>{
            'hashes': hashes.join('|'),
            'deleteFiles': deleteFiles,
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Adds one or more torrents from magnet links or http(s) `.torrent` URLs.
  ///
  /// [urlsOrMagnets] may contain multiple entries (qBittorrent accepts them
  /// newline-separated). Optional [category], [savePath], [paused],
  /// [sequential] and [skipHashCheck] map to the matching `/torrents/add`
  /// form fields. Returns nothing - call `getTorrents()` afterwards to
  /// refresh.
  Future<void> addUrls(
    List<String> urlsOrMagnets, {
    String? category,
    String? savePath,
    bool paused = false,
    bool sequential = false,
    bool skipHashCheck = false,
  }) =>
      _guarded(() async {
        final FormData form = FormData.fromMap(<String, dynamic>{
          'urls': urlsOrMagnets.join('\n'),
          if (category != null && category.isNotEmpty) 'category': category,
          if (savePath != null && savePath.isNotEmpty) 'savepath': savePath,
          'paused': paused ? 'true' : 'false',
          'sequentialDownload': sequential ? 'true' : 'false',
          // Same feature under two names. Every released qBittorrent up to
          // 5.2 reads skip_checking; unreleased master renamed it seedMode.
          // Unknown form fields are ignored, so sending both is correct on
          // either side of that rename.
          'skip_checking': skipHashCheck ? 'true' : 'false',
          'seedMode': skipHashCheck ? 'true' : 'false',
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
    bool skipHashCheck = false,
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
          // Same feature under two names. Every released qBittorrent up to
          // 5.2 reads skip_checking; unreleased master renamed it seedMode.
          // Unknown form fields are ignored, so sending both is correct on
          // either side of that rename.
          'skip_checking': skipHashCheck ? 'true' : 'false',
          'seedMode': skipHashCheck ? 'true' : 'false',
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

  /// Peers list of one torrent (`/sync/torrentPeers`).
  Future<List<QbitPeer>> getPeers(String hash) => _guarded(() async {
        final Response<dynamic> resp = await _dio.get<dynamic>(
          'api/v2/sync/torrentPeers',
          queryParameters: <String, dynamic>{'hash': hash, 'rid': 0},
        );
        final Map<String, dynamic> data = resp.data as Map<String, dynamic>;
        final Map<String, dynamic>? peersMap =
            data['peers'] as Map<String, dynamic>?;
        if (peersMap == null) return <QbitPeer>[];

        final List<QbitPeer> results = <QbitPeer>[];
        for (final MapEntry<String, dynamic> entry in peersMap.entries) {
          final String ipPort = entry.key;
          final Map<String, dynamic> peerData =
              entry.value as Map<String, dynamic>;

          String ip = ipPort;
          int port = 0;
          if (ipPort.contains(':')) {
            final int lastColon = ipPort.lastIndexOf(':');
            ip = ipPort.substring(0, lastColon);
            port = int.tryParse(ipPort.substring(lastColon + 1)) ?? 0;
          }

          peerData['ip'] = ip;
          peerData['port'] = port;
          results.add(QbitPeer.fromJson(peerData));
        }
        return results;
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

  /// Every category on the server, mapped to the save path it defines.
  ///
  /// A category is free to define no path of its own, which comes back as an
  /// empty string and means the server's global default applies. Note the key
  /// is `savePath` here while the same idea is `save_path` in
  /// `app/preferences`; qBittorrent is inconsistent between the two endpoints,
  /// so both spellings are accepted.
  Future<Map<String, String>> getCategories() => _guarded(() async {
        final Response<dynamic> resp =
            await _dio.get<dynamic>('api/v2/torrents/categories');
        final Map<String, dynamic> map =
            (resp.data as Map<String, dynamic>?) ?? <String, dynamic>{};
        final Map<String, String> paths = <String, String>{};
        for (final MapEntry<String, dynamic> e in map.entries) {
          final dynamic v = e.value;
          final Object? raw = v is Map<String, dynamic>
              ? (v['savePath'] ?? v['save_path'])
              : null;
          paths[e.key] = raw?.toString() ?? '';
        }
        return paths;
      });

  /// Moves a torrent into [category] (empty string clears it).
  Future<void> setCategory(List<String> hashes, String category) =>
      _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/setCategory',
          data: <String, dynamic>{
            'hashes': hashes.join('|'),
            'category': category,
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Forces a re-check of a torrent's data.
  Future<void> recheck(List<String> hashes) => _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/recheck',
          data: <String, dynamic>{'hashes': hashes.join('|')},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Moves torrents up in queue (increases priority).
  Future<void> queueUp(List<String> hashes) => _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/increasePrio',
          data: <String, dynamic>{'hashes': hashes.join('|')},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Moves torrents down in queue (decreases priority).
  Future<void> queueDown(List<String> hashes) => _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/decreasePrio',
          data: <String, dynamic>{'hashes': hashes.join('|')},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Moves torrents to top of queue (maximal priority).
  Future<void> queueTop(List<String> hashes) => _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/topPrio',
          data: <String, dynamic>{'hashes': hashes.join('|')},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Moves torrents to bottom of queue (minimal priority).
  Future<void> queueBottom(List<String> hashes) => _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/bottomPrio',
          data: <String, dynamic>{'hashes': hashes.join('|')},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Bumps a torrent's queue priority up or down one slot.
  Future<void> setPriority(String hash, {required bool increase}) =>
      increase ? queueUp(<String>[hash]) : queueDown(<String>[hash]);

  Future<void> reannounce(List<String> hashes) => _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/reannounce',
          data: <String, dynamic>{'hashes': hashes.join('|')},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  Future<void> setForceStart(List<String> hashes, {required bool value}) =>
      _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/setForceStart',
          data: <String, dynamic>{'hashes': hashes.join('|'), 'value': value},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  Future<void> rename(String hash, String name) => _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/rename',
          data: <String, dynamic>{'hash': hash, 'name': name},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  Future<void> setLocation(List<String> hashes, String location) =>
      _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/setLocation',
          data: <String, dynamic>{
            'hashes': hashes.join('|'),
            'location': location,
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  Future<void> addTags(List<String> hashes, String tags) => _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/addTags',
          data: <String, dynamic>{'hashes': hashes.join('|'), 'tags': tags},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  Future<void> removeTags(List<String> hashes, String tags) =>
      _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/removeTags',
          data: <String, dynamic>{'hashes': hashes.join('|'), 'tags': tags},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Creates tags so they exist on the server even before any torrent uses
  /// them. addTags implicitly creates unknown tags too, but calling this first
  /// keeps a freshly-typed tag in the picker list.
  Future<void> createTags(String tags) => _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/torrents/createTags',
          data: <String, dynamic>{'tags': tags},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Every tag defined on the instance (GET /api/v2/torrents/tags returns a
  /// bare JSON array of strings).
  Future<List<String>> getTags() => _guarded(() async {
        final Response<dynamic> resp =
            await _dio.get<dynamic>('api/v2/torrents/tags');
        final dynamic data = resp.data;
        if (data is List) {
          return data.map((dynamic e) => e.toString()).toList();
        }
        return <String>[];
      });

  Future<Uint8List> exportTorrent(String hash) => _guarded(() async {
        final Response<List<int>> resp = await _dio.get<List<int>>(
          'api/v2/torrents/export',
          queryParameters: <String, dynamic>{'hash': hash},
          options: Options(responseType: ResponseType.bytes),
        );
        return Uint8List.fromList(resp.data!);
      });

  /// Pauses or resumes every torrent. qBit 5.0 renamed the global endpoints
  /// (pause→stop, resume→start) just like the per-torrent ones, so we try the
  /// new path first and fall back on 404.
  Future<void> setAllPaused({required bool paused}) => _guarded(() async {
        final String primary =
            paused ? 'api/v2/torrents/stop' : 'api/v2/torrents/start';
        final String fallback =
            paused ? 'api/v2/torrents/pause' : 'api/v2/torrents/resume';
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

  /// Application version string (e.g. `v5.0.0`).
  Future<String> getAppVersion() => _guarded(() async {
        final Response<String> res = await _dio.get<String>(
          'api/v2/app/version',
          options: Options(responseType: ResponseType.plain),
        );
        return res.data?.trim() ?? '';
      });

  /// Web API version string (e.g. `2.11.0`).
  Future<String> getApiVersion() => _guarded(() async {
        final Response<String> res = await _dio.get<String>(
          'api/v2/app/webapiVersion',
          options: Options(responseType: ResponseType.plain),
        );
        return res.data?.trim() ?? '';
      });

  /// Global application preferences and configuration map.
  Future<Map<String, dynamic>> getPreferences() => _guarded(() async {
        final Response<dynamic> res =
            await _dio.get<dynamic>('api/v2/app/preferences');
        if (res.data is Map) {
          return Map<String, dynamic>.from(res.data as Map);
        } else if (res.data is String && (res.data as String).isNotEmpty) {
          try {
            final dynamic decoded = jsonDecode(res.data as String);
            if (decoded is Map) {
              return Map<String, dynamic>.from(decoded);
            }
          } catch (_) {}
        }
        return <String, dynamic>{};
      });

  /// Set application preferences.
  Future<void> setPreferences(Map<String, dynamic> prefs) => _guarded(() async {
        await _dio.post<dynamic>(
          'api/v2/app/setPreferences',
          data: <String, dynamic>{'json': jsonEncode(prefs)},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
      });

  /// Toggles the Alternative Speed Limits mode.
  Future<void> toggleAltSpeedLimits() => _guarded(() async {
        await _dio.post<dynamic>('api/v2/transfer/toggleSpeedLimitsMode');
      });

  /// Returns 1 if alt speed mode is enabled, 0 otherwise.
  Future<int> getSpeedLimitsMode() => _guarded(() async {
        final Response<String> res = await _dio.get<String>(
          'api/v2/transfer/speedLimitsMode',
          options: Options(responseType: ResponseType.plain),
        );
        return int.tryParse(res.data?.trim() ?? '0') ?? 0;
      });

  /// Retrieves list of network interfaces recognized by the qBittorrent host.
  Future<List<Map<String, String>>> getNetworkInterfaces() =>
      _guarded(() async {
        try {
          final Response<dynamic> res =
              await _dio.get<dynamic>('api/v2/app/networkInterfacesList');
          dynamic raw = res.data;
          if (raw is String && raw.isNotEmpty) {
            try {
              raw = jsonDecode(raw);
            } catch (_) {}
          }
          if (raw is List) {
            return raw.map((dynamic item) {
              if (item is Map) {
                final String name = item['name']?.toString() ?? '';
                final String value = item['value']?.toString() ?? name;
                return <String, String>{'name': name, 'value': value};
              } else if (item is String) {
                return <String, String>{'name': item, 'value': item};
              }
              return <String, String>{
                'name': item.toString(),
                'value': item.toString(),
              };
            }).toList();
          }
        } catch (_) {}
        return <Map<String, String>>[];
      });

  /// Retrieves list of IP addresses available for a given network interface
  /// or all available addresses if [iface] is empty or omitted.
  Future<List<String>> getNetworkInterfaceAddresses({String? iface}) =>
      _guarded(() async {
        try {
          final Response<dynamic> res = await _dio.get<dynamic>(
            'api/v2/app/networkInterfaceAddressesList',
            queryParameters: iface != null && iface.isNotEmpty
                ? <String, dynamic>{'iface': iface}
                : null,
          );
          dynamic raw = res.data;
          if (raw is String && raw.isNotEmpty) {
            try {
              raw = jsonDecode(raw);
            } catch (_) {}
          }
          if (raw is List) {
            return raw.map((dynamic e) => e.toString()).toList();
          }
        } catch (_) {}
        return <String>[];
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
    // API-key auth is stateless: no login round-trip, and a 403 means the key
    // itself was rejected (re-login is impossible - keys can't use the auth
    // endpoints), so surface a clear error instead of retrying.
    if (!_usesApiKey && !_loggedIn) {
      await login();
    }
    try {
      return await call();
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        if (_usesApiKey) {
          throw const NetworkAuthException(
            'qBittorrent rejected the API key. Check it in qBittorrent 5.2+ '
            'Web UI settings (sent as Authorization: Bearer), or rotate the '
            'key and re-enter it.',
          );
        }
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
