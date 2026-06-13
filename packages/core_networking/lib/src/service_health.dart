import 'package:core_models/core_models.dart';
import 'package:dio/dio.dart';

import 'dio_factory.dart';

/// How a service's health endpoint should be interpreted.
enum _HealthMode {
  /// Endpoint uses the attached auth (api key / token / query key).
  /// 2xx → ok, 401/403 → warning (reachable but bad creds), else → error.
  authed,

  /// Endpoint is public (no auth needed). 2xx → ok, else → error.
  publicEndpoint,

  /// We can't cheaply authenticate in a lightweight probe (cookie/login
  /// services), so any HTTP response - including 401/403 - proves the host is
  /// up. Only a transport failure is an error.
  reachable,
}

/// Per-[ServiceKind] health endpoint + interpretation mode.
///
/// Keeping this table here (rather than in each service module) lets the
/// dashboard probe every instance uniformly without depending on all 11
/// service packages.
({String path, _HealthMode mode}) _config(ServiceKind kind) {
  switch (kind) {
    // *arr family + Overseerr: authed REST status endpoints.
    case ServiceKind.sonarr:
    case ServiceKind.radarr:
      return (path: 'api/v3/system/status', mode: _HealthMode.authed);
    case ServiceKind.prowlarr:
      return (path: 'api/v1/system/status', mode: _HealthMode.authed);
    case ServiceKind.bazarr:
      return (path: 'api/system/status', mode: _HealthMode.authed);
    case ServiceKind.overseerr:
      return (path: 'api/v1/status', mode: _HealthMode.authed);
    // Query-key services - AuthInterceptor appends the key as a query param.
    case ServiceKind.tautulli:
      return (
        path: 'api/v2?cmd=get_server_friendly_name',
        mode: _HealthMode.authed,
      );
    case ServiceKind.sabnzbd:
      return (path: 'api?mode=version', mode: _HealthMode.authed);
    // Plex: X-Plex-Token is attached; /identity returns server identity.
    case ServiceKind.plex:
      return (path: 'identity', mode: _HealthMode.authed);
    // Media servers expose an unauthenticated public-info endpoint.
    case ServiceKind.jellyfin:
    case ServiceKind.emby:
      return (path: 'System/Info/Public', mode: _HealthMode.publicEndpoint);
    // qBittorrent needs a session cookie we don't mint in a probe; any
    // response means the WebUI is up.
    case ServiceKind.qbittorrent:
      return (path: 'api/v2/app/version', mode: _HealthMode.reachable);
    case ServiceKind.glances:
      return (path: 'api/4/core', mode: _HealthMode.authed);
  }
}

/// Probes the real health of a configured [Instance].
///
/// Unlike a blind `GET /` (which treats a 404 or a login page as "up"), this
/// hits the service's own status endpoint with its real auth and returns a
/// [Health] the dashboard can trust:
///
/// * [Health.ok] - reachable and the credentials work.
/// * [Health.warning] - reachable but the API key / token was rejected
///   (so the user knows to fix it), or the server answered 5xx.
/// * [Health.error] - could not reach the server at all.
class HealthProbe {
  HealthProbe({required DioFactory dioFactory}) : _dioFactory = dioFactory;

  final DioFactory _dioFactory;

  Future<Health> check(Instance instance) async {
    final ({String path, _HealthMode mode}) cfg = _config(instance.kind);
    Dio? dio;
    try {
      dio = await _dioFactory.create(instance);
      final Response<dynamic> resp = await dio.get<dynamic>(
        cfg.path,
        options: Options(
          validateStatus: (_) => true,
          receiveTimeout: const Duration(seconds: 8),
        ),
      );
      final int status = resp.statusCode ?? 0;
      return _interpret(status, cfg.mode);
    } on DioException {
      return Health.error;
    } on Object {
      return Health.error;
    } finally {
      dio?.close(force: true);
    }
  }

  Health _interpret(int status, _HealthMode mode) {
    if (status == 0) {
      return Health.error;
    }
    switch (mode) {
      case _HealthMode.authed:
        if (status >= 200 && status < 300) {
          return Health.ok;
        }
        if (status == 401 || status == 403) {
          return Health.warning;
        }
        // 5xx = reachable but unhealthy; 4xx (e.g. 404 wrong path) = warning.
        return Health.warning;
      case _HealthMode.publicEndpoint:
        return (status >= 200 && status < 300) ? Health.ok : Health.error;
      case _HealthMode.reachable:
        // Any HTTP status proves the host answered.
        return Health.ok;
    }
  }
}
