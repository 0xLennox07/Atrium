import 'package:core_models/core_models.dart';

/// The header names [AuthInterceptor] sets for an instance itself.
///
/// A user-configured header of the same name never reaches the wire: the
/// interceptor runs per request, after the profile's headers are installed as
/// client defaults, so it overwrites them. That matters for reverse-proxy
/// auth, where the whole point of the header is to be seen by something in
/// front of the service. `Authorization` is the one that collides in
/// practice, because five kinds spend it on their own credentials.
///
/// Kept beside the interceptor so the two cannot drift; a test asserts this
/// agrees with what the interceptor actually sends for every kind.
Set<String> serviceAuthHeaderNames(ServiceKind kind, InstanceAuth auth) {
  switch (auth) {
    case InstanceAuthApiKey():
      switch (kind) {
        case ServiceKind.speedtestTracker || ServiceKind.tracearr:
          return const <String>{'Authorization', 'Accept'};
        case ServiceKind.sabnzbd || ServiceKind.tautulli:
          // Query parameter, not a header, so nothing collides.
          return const <String>{};
        case _:
          return const <String>{'X-Api-Key'};
      }
    case InstanceAuthPlex():
      return const <String>{'X-Plex-Token', 'Accept'};
    case InstanceAuthUserPass(
          :final String username,
          :final String password,
        )
        when kind == ServiceKind.nzbget ||
            kind == ServiceKind.transmission ||
            kind == ServiceKind.rtorrent:
      // Transmission's auth is optional and rTorrent has none of its own, so
      // with no credentials entered the interceptor sends no header at all.
      return username.isEmpty && password.isEmpty
          ? const <String>{}
          : const <String>{'Authorization'};
    case InstanceAuthUserPass() || InstanceAuthCookie():
      // Token and cookie flows are handled by the service's own session
      // manager rather than by a static header.
      return const <String>{};
  }
}

/// Whether [kind] refuses a request carrying an `Authorization` header it did
/// not issue itself.
///
/// qBittorrent parses the header rather than ignoring it and answers 401
/// instead of falling back to its session cookie, so a proxy credential sent
/// this way locks the user out of a service that is otherwise reachable.
/// Verified against qBittorrent 5.x: the same request answers 403 without the
/// header and 401 with it. `Proxy-Authorization` is not affected.
bool rejectsForeignAuthorization(ServiceKind kind) =>
    kind == ServiceKind.qbittorrent;

/// The header to reach for when the credential is meant for a reverse proxy.
///
/// `Proxy-Authorization` is what RFC 7235 reserves for an intermediary, and
/// it is the only name that survives every service in the stack: nothing
/// overwrites it and nothing rejects it.
///
/// Whether the proxy reads it is a separate question, and not every one does.
/// Verified: Authelia accepts it on an authz endpoint carrying the
/// `HeaderProxyAuthorization` strategy, while nginx's `auth_basic`, which is
/// what an nginx Proxy Manager access list runs on, only ever reads
/// `Authorization`. Hence "where your proxy accepts it" in the warning rather
/// than a flat recommendation.
const String proxyAuthHeaderName = 'Proxy-Authorization';

/// Why [headerName] will not do what the user expects for [instances], or
/// null when it is fine.
///
/// Two ways a header can be configured and still not work: a service spends
/// that name on its own sign-in and overwrites it before the request leaves,
/// or the service refuses one it did not issue. Both are worth saying at the
/// moment the header is typed rather than leaving someone to wonder why a
/// proxy keeps rejecting them.
String? headerConflictWarning(String headerName, List<Instance> instances) {
  final String name = headerName.trim();
  if (name.isEmpty) {
    return null;
  }
  final String lower = name.toLowerCase();

  final List<String> overwritten = <String>[
    for (final Instance i in instances)
      if (serviceAuthHeaderNames(i.kind, i.auth)
          .any((String h) => h.toLowerCase() == lower))
        i.name,
  ];
  final List<String> refused = <String>[
    if (lower == 'authorization')
      for (final Instance i in instances)
        if (rejectsForeignAuthorization(i.kind)) i.name,
  ];

  if (overwritten.isEmpty && refused.isEmpty) {
    return null;
  }
  final StringBuffer buffer = StringBuffer();
  if (overwritten.isNotEmpty) {
    final bool one = overwritten.length == 1;
    buffer.write('${overwritten.join(', ')} ${one ? 'uses' : 'use'} this '
        'header for ${one ? 'its' : 'their'} own sign-in, so your value is '
        'replaced before the request is sent. ');
  }
  if (refused.isNotEmpty) {
    buffer.write('${refused.join(', ')} '
        '${refused.length == 1 ? 'refuses' : 'refuse'} a header of this name '
        'that it did not issue, and will answer 401. ');
  }
  buffer.write('Use $proxyAuthHeaderName instead where your proxy accepts '
      'it, such as Authelia. nginx basic auth only reads this header.');
  return buffer.toString();
}
