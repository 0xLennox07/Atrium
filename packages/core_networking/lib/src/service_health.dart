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
    // *arr family + Seerr: authed REST status endpoints.
    case ServiceKind.sonarr:
    case ServiceKind.radarr:
      return (path: 'api/v3/system/status', mode: _HealthMode.authed);
    case ServiceKind.lidarr:
    case ServiceKind.prowlarr:
      return (path: 'api/v1/system/status', mode: _HealthMode.authed);
    case ServiceKind.bazarr:
      return (path: 'api/system/status', mode: _HealthMode.authed);
    case ServiceKind.seerr:
      return (path: 'api/v1/status', mode: _HealthMode.authed);
    case ServiceKind.tracearr:
      return (path: 'api/v2/public/docs', mode: _HealthMode.authed);
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
    case ServiceKind.beszel:
      return (path: 'api/health', mode: _HealthMode.publicEndpoint);
    case ServiceKind.dashdot:
      return (path: 'info', mode: _HealthMode.publicEndpoint);
    case ServiceKind.speedtestTracker:
      return (path: 'api/v1/results?page[size]=1', mode: _HealthMode.authed);
    case ServiceKind.nzbget:
      // JSON-RPC accepts GET for parameterless methods; Basic auth is
      // attached by the interceptor, so 401 means bad credentials.
      return (path: 'jsonrpc/version', mode: _HealthMode.authed);
    case ServiceKind.transmission:
      // The RPC endpoint answers an unprimed GET with 409 (its CSRF
      // rejection), which is a distinctive Transmission signature - better
      // evidence than the 200 a bare web root would give. A probe cannot do
      // the token handshake, and RPC auth is optional, so any response counts
      // as up.
      return (path: 'transmission/rpc', mode: _HealthMode.reachable);
    case ServiceKind.deluge:
      // Deluge's login is a POST, so a probe cannot authenticate cheaply.
      // `/json` answers GET with 405, which is a better liveness signal than
      // the root path: any web server returns 200 for `/`, but only Deluge's
      // RPC endpoint is there to refuse the method.
      return (path: 'json', mode: _HealthMode.reachable);
    case ServiceKind.rtorrent:
      // XML-RPC only answers POST - a GET makes the proxy in front return 502
      // whether the daemon is alive or dead, which is no signal at all. So this
      // is the one kind the probe POSTs (see [_probeBody]), and a real
      // `methodResponse` is required for ok.
      return (path: '', mode: _HealthMode.authed);
    case ServiceKind.unraid:
      // The only API Unraid exposes is GraphQL on one endpoint, so the probe
      // POSTs the cheapest query there is rather than fetching a status page.
      return (path: 'graphql', mode: _HealthMode.authed);
  }
}

/// The request body to POST for [kind], or null to probe with a plain GET.
///
/// Only rTorrent needs this: it has no GET-able status endpoint, so the probe
/// sends the cheapest XML-RPC call there is.
String? _probeBody(ServiceKind kind) => switch (kind) {
      ServiceKind.rtorrent => '<?xml version="1.0"?><methodCall>'
          '<methodName>system.client_version</methodName>'
          '<params></params></methodCall>',
      // GraphQL has no status route. `__typename` is the smallest legal query
      // and answers on any schema, so it costs the server nothing.
      ServiceKind.unraid => '{"query":"{__typename}"}',
      ServiceKind.beszel => null,
      _ => null,
    };

/// Content type for the probe body.
///
/// rTorrent speaks XML-RPC; GraphQL refuses anything that is not JSON, so the
/// two POST probes cannot share one header.
String _probeContentType(ServiceKind kind) => switch (kind) {
      ServiceKind.unraid => Headers.jsonContentType,
      _ => 'text/xml',
    };

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
      final String? body = _probeBody(instance.kind);
      final Options options = Options(
        validateStatus: (_) => true,
        receiveTimeout: const Duration(seconds: 8),
        contentType:
            body == null ? null : _probeContentType(instance.kind),
        responseType: body == null ? null : ResponseType.plain,
      );
      final Response<dynamic> resp = body == null
          ? await dio.get<dynamic>(cfg.path, options: options)
          : await dio.post<dynamic>(cfg.path, data: body, options: options);
      final int status = resp.statusCode ?? 0;
      return interpretServiceHealthResponse(
        instance.kind,
        status,
        resp.data,
        contentType: resp.headers.value(Headers.contentTypeHeader),
      );
    } on DioException {
      return Health.error;
    } on Object {
      return Health.error;
    } finally {
      dio?.close(force: true);
    }
  }
}

/// Interprets a completed HTTP health response without retaining or exposing
/// its body. Public for focused tests; callers should normally use
/// [HealthProbe].
Health interpretServiceHealthResponse(
  ServiceKind kind,
  int status,
  Object? data, {
  String? contentType,
}) {
  if (status == 0) {
    return Health.error;
  }

  // A page where an API should be.
  //
  // Every health endpoint here answers with JSON, or XML-RPC in rTorrent's
  // case. None answer with a web page. A forward-auth proxy redirects an
  // unauthenticated request to its login portal, the probe follows the
  // redirect as any client would, and the portal returns a perfectly healthy
  // 200 full of markup. Status alone cannot tell that apart from a working
  // server, so a login page was being reported as Online.
  //
  // Read from the content type rather than the body: Authelia's portal opens
  // with a licence comment, so looking for a leading <html would miss it.
  // Restricted to 2xx because several services legitimately answer with a
  // page on an error, Transmission's 409 and rTorrent's 502 among them, and
  // those are already interpreted correctly.
  if (status >= 200 &&
      status < 300 &&
      (contentType?.toLowerCase().contains('text/html') ?? false)) {
    return Health.warning;
  }

  final _HealthMode mode = _config(kind).mode;
  switch (mode) {
    case _HealthMode.authed:
      if (status >= 200 && status < 300) {
        if (kind == ServiceKind.speedtestTracker &&
            !_isSpeedtestResultsEnvelope(data)) {
          // The host answered, but not with the authenticated API contract.
          return Health.warning;
        }
        if (kind == ServiceKind.unraid && !'$data'.contains('__typename')) {
          // GraphQL answers 200 even when it refuses the key, so the status
          // alone would call a bad key healthy. The echoed __typename is the
          // proof the query actually ran.
          return Health.warning;
        }
        if (kind == ServiceKind.rtorrent &&
            !'$data'.contains('methodResponse')) {
          // A 200 from the web UI or a proxy landing page is not the XML-RPC
          // endpoint, so the URL is pointed at the wrong place.
          return Health.warning;
        }
        return Health.ok;
      }
      // 401/403, API-level 4xx, redirects, and 5xx all prove the host answered
      // while indicating credentials, compatibility, or server health needs
      // attention.
      return Health.warning;
    case _HealthMode.publicEndpoint:
      return (status >= 200 && status < 300) ? Health.ok : Health.error;
    case _HealthMode.reachable:
      return Health.ok;
  }
}

bool _isSpeedtestResultsEnvelope(Object? data) =>
    data is Map && data['data'] is List;
