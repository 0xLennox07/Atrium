import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// [serviceAuthHeaderNames] has to keep telling the truth about what
/// [AuthInterceptor] actually sends.
///
/// The Custom Headers screen warns people off names the interceptor is going
/// to overwrite, so if the two drift the warning either cries wolf or, worse,
/// stays quiet while a reverse-proxy credential is silently dropped.
void main() {
  /// Runs a request through the interceptor and reports the headers it set.
  Set<String> headersActuallySet(ServiceKind kind, InstanceAuth auth) {
    final RequestOptions options = RequestOptions(path: '/probe');
    final AuthInterceptor interceptor =
        AuthInterceptor(kind: kind, auth: auth);
    interceptor.onRequest(options, RequestInterceptorHandler());
    return options.headers.keys.toSet();
  }

  const InstanceAuth apiKey = InstanceAuth.apiKey(apiKey: 'k');
  const InstanceAuth plex = InstanceAuth.plexToken(token: 't');
  const InstanceAuth userPass =
      InstanceAuth.userPass(username: 'u', password: 'p');
  const InstanceAuth blankUserPass =
      InstanceAuth.userPass(username: '', password: '');

  test('it matches the interceptor for every kind and auth', () {
    for (final ServiceKind kind in ServiceKind.values) {
      for (final InstanceAuth auth in <InstanceAuth>[
        apiKey,
        plex,
        userPass,
        blankUserPass,
      ]) {
        expect(
          serviceAuthHeaderNames(kind, auth),
          headersActuallySet(kind, auth),
          reason: 'drifted for ${kind.name} with ${auth.runtimeType}',
        );
      }
    }
  });

  test('the five kinds that spend Authorization on themselves are named', () {
    // These are the ones where a user's own Authorization header never
    // reaches the wire, which is the whole reason the warning exists.
    final Set<ServiceKind> owners = <ServiceKind>{
      for (final ServiceKind kind in ServiceKind.values)
        for (final InstanceAuth auth in <InstanceAuth>[apiKey, userPass])
          if (serviceAuthHeaderNames(kind, auth).contains('Authorization'))
            kind,
    };

    expect(owners, <ServiceKind>{
      ServiceKind.speedtestTracker,
      ServiceKind.tracearr,
      ServiceKind.nzbget,
      ServiceKind.transmission,
      ServiceKind.rtorrent,
    });
  });

  test('an unconfigured transmission or rtorrent collides with nothing', () {
    // Their auth is optional, so with nothing entered there is no header to
    // overwrite and no reason to warn.
    expect(
      serviceAuthHeaderNames(ServiceKind.transmission, blankUserPass),
      isEmpty,
    );
    expect(
      serviceAuthHeaderNames(ServiceKind.rtorrent, blankUserPass),
      isEmpty,
    );
  });

  test('the query-key services collide with nothing', () {
    // SABnzbd and Tautulli carry the key in the query string.
    expect(serviceAuthHeaderNames(ServiceKind.sabnzbd, apiKey), isEmpty);
    expect(serviceAuthHeaderNames(ServiceKind.tautulli, apiKey), isEmpty);
  });

  test('qBittorrent is flagged as refusing a foreign Authorization', () {
    expect(rejectsForeignAuthorization(ServiceKind.qbittorrent), isTrue);
    expect(rejectsForeignAuthorization(ServiceKind.sonarr), isFalse);
  });

  group('conflict warning', _warningTests);

  test('the recommended proxy header is one nothing else touches', () {
    // If any service ever starts setting Proxy-Authorization itself, the
    // advice in the Custom Headers screen stops being true.
    for (final ServiceKind kind in ServiceKind.values) {
      for (final InstanceAuth auth in <InstanceAuth>[
        apiKey,
        plex,
        userPass,
      ]) {
        expect(
          serviceAuthHeaderNames(kind, auth),
          isNot(contains(proxyAuthHeaderName)),
          reason: '${kind.name} would overwrite the proxy header',
        );
      }
    }
  });
}

/// The warning the Custom Headers screen shows while a name is being typed.
void _warningTests() {
  Instance inst(String name, ServiceKind kind, InstanceAuth auth) => Instance(
        id: name,
        name: name,
        kind: kind,
        localUrl: 'http://x',
        externalUrl: '',
        urlMode: UrlMode.auto,
        auth: auth,
      );

  const InstanceAuth key = InstanceAuth.apiKey(apiKey: 'k');
  const InstanceAuth up = InstanceAuth.userPass(username: 'u', password: 'p');

  test('Authorization warns about the services that overwrite it', () {
    final String? w = headerConflictWarning('Authorization', <Instance>[
      inst('NZBGet', ServiceKind.nzbget, up),
      inst('Sonarr', ServiceKind.sonarr, key),
    ]);

    expect(w, contains('NZBGet'));
    expect(w, isNot(contains('Sonarr')), reason: 'Sonarr is unaffected');
    expect(w, contains('Proxy-Authorization'));
  });

  test('Authorization warns that qBittorrent refuses it', () {
    final String? w = headerConflictWarning('Authorization', <Instance>[
      inst('qBittorrent', ServiceKind.qbittorrent, key),
    ]);

    expect(w, contains('qBittorrent'));
    expect(w, contains('401'));
  });

  test('the recommended header warns about nothing', () {
    expect(
      headerConflictWarning('Proxy-Authorization', <Instance>[
        inst('qBittorrent', ServiceKind.qbittorrent, key),
        inst('NZBGet', ServiceKind.nzbget, up),
        inst('Sonarr', ServiceKind.sonarr, key),
      ]),
      isNull,
    );
  });

  test('an ordinary header name warns about nothing', () {
    expect(
      headerConflictWarning('CF-Access-Client-Id', <Instance>[
        inst('Sonarr', ServiceKind.sonarr, key),
      ]),
      isNull,
    );
  });

  test('X-Api-Key warns for the services that set it themselves', () {
    // The old placeholder on that field. Configuring it globally would have
    // been overwritten for every *arr in the profile.
    expect(
      headerConflictWarning('X-Api-Key', <Instance>[
        inst('Sonarr', ServiceKind.sonarr, key),
      ]),
      contains('Sonarr'),
    );
  });

  test('the match ignores header case, as HTTP does', () {
    expect(
      headerConflictWarning('authorization', <Instance>[
        inst('qBittorrent', ServiceKind.qbittorrent, key),
      ]),
      isNotNull,
    );
  });

  test('empty and whitespace names warn about nothing', () {
    expect(headerConflictWarning('', <Instance>[]), isNull);
    expect(headerConflictWarning('   ', <Instance>[]), isNull);
  });
}
