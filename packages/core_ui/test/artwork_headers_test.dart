import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Artwork headers are resolved from the URL, so the matching is the whole
/// correctness story: too loose and a user's proxy credentials go to TMDB,
/// too strict and posters stay blank behind Authelia.
void main() {
  tearDown(ArtworkHeaders.reset);

  Instance instance(
    String id, {
    String local = 'http://sonarr.example.test',
    String external = '',
    Map<String, String> headers = const <String, String>{},
  }) =>
      Instance(
        id: id,
        name: id,
        kind: ServiceKind.sonarr,
        localUrl: local,
        externalUrl: external,
        urlMode: UrlMode.auto,
        auth: const InstanceAuth.apiKey(apiKey: 'k'),
        customHeaders: headers,
      );

  test('a url under an instance gets that instance headers', () {
    ArtworkHeaders.update(
      instances: <Instance>[
        instance('a', headers: const <String, String>{'Authorization': 'Basic x'}),
      ],
      global: const <String, String>{},
    );

    expect(
      ArtworkHeaders.forUrl('http://sonarr.example.test/api/v3/mediacover/1/poster.jpg'),
      <String, String>{'Authorization': 'Basic x'},
    );
  });

  test('global headers reach every instance, instance keys win', () {
    ArtworkHeaders.update(
      instances: <Instance>[
        instance('a', headers: const <String, String>{'X-Which': 'instance'}),
      ],
      global: const <String, String>{
        'X-Which': 'global',
        'CF-Access-Client-Id': 'id',
      },
    );

    final Map<String, String>? headers =
        ArtworkHeaders.forUrl('http://sonarr.example.test/poster.jpg');

    expect(headers?['X-Which'], 'instance');
    expect(headers?['CF-Access-Client-Id'], 'id');
  });

  test('artwork on a third party gets nothing', () {
    // Add-search results point at TMDB and Fanart.tv. Sending the user's
    // proxy credentials to those would leak them off the network entirely.
    ArtworkHeaders.update(
      instances: <Instance>[
        instance('a', headers: const <String, String>{'Authorization': 'Basic x'}),
      ],
      global: const <String, String>{},
    );

    expect(ArtworkHeaders.forUrl('https://image.tmdb.org/t/p/w500/x.jpg'), isNull);
  });

  test('the longest matching base wins', () {
    // Two services behind one hostname on different sub-paths. Matching the
    // shorter base first would hand over the wrong instance's headers.
    ArtworkHeaders.update(
      instances: <Instance>[
        instance('root',
            local: 'https://home.example.test',
            headers: const <String, String>{'X-Who': 'root'}),
        instance('sub',
            local: 'https://home.example.test/sonarr',
            headers: const <String, String>{'X-Who': 'sub'}),
      ],
      global: const <String, String>{},
    );

    expect(
      ArtworkHeaders.forUrl('https://home.example.test/sonarr/api/v3/mediacover/1/poster.jpg')?['X-Who'],
      'sub',
    );
    expect(
      ArtworkHeaders.forUrl('https://home.example.test/other/poster.jpg')?['X-Who'],
      'root',
    );
  });

  test('a trailing slash or different casing still matches', () {
    ArtworkHeaders.update(
      instances: <Instance>[
        instance('a',
            local: 'http://Sonarr.Example.Test:8989/',
            headers: const <String, String>{'Authorization': 'Basic x'}),
      ],
      global: const <String, String>{},
    );

    expect(
      ArtworkHeaders.forUrl('http://sonarr.example.test:8989/api/v3/mediacover/1/poster.jpg'),
      isNotNull,
    );
  });

  test('the external url matches as well as the local one', () {
    // Which of the two an artwork url was built from depends on where the
    // device is, so both have to resolve.
    ArtworkHeaders.update(
      instances: <Instance>[
        instance('a',
            local: 'http://192.168.0.10:8989',
            external: 'https://sonarr.example.test',
            headers: const <String, String>{'Authorization': 'Basic x'}),
      ],
      global: const <String, String>{},
    );

    expect(ArtworkHeaders.forUrl('http://192.168.0.10:8989/p.jpg'), isNotNull);
    expect(ArtworkHeaders.forUrl('https://sonarr.example.test/p.jpg'), isNotNull);
  });

  test('an instance with no headers configured resolves to null', () {
    // Null rather than an empty map, so the image widgets keep their existing
    // "send nothing" behaviour for everyone not behind a proxy.
    ArtworkHeaders.update(
      instances: <Instance>[instance('a')],
      global: const <String, String>{},
    );

    expect(ArtworkHeaders.forUrl('http://sonarr.example.test/p.jpg'), isNull);
  });

  test('a host that merely starts with an instance host does not match', () {
    // sonarr.example.test.evil.com must not pick up the credentials for
    // sonarr.example.test.
    ArtworkHeaders.update(
      instances: <Instance>[
        instance('a', headers: const <String, String>{'Authorization': 'Basic x'}),
      ],
      global: const <String, String>{},
    );

    expect(
      ArtworkHeaders.forUrl('http://sonarr.example.test.evil.example/p.jpg'),
      isNull,
    );
  });

  test('an empty or null url resolves to null', () {
    ArtworkHeaders.update(
      instances: <Instance>[
        instance('a', headers: const <String, String>{'Authorization': 'Basic x'}),
      ],
      global: const <String, String>{},
    );

    expect(ArtworkHeaders.forUrl(null), isNull);
    expect(ArtworkHeaders.forUrl(''), isNull);
  });
}
