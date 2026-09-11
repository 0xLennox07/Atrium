import 'package:atrium/src/dashboard/widgets/recently_added_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_sonarr/service_sonarr.dart';

import 'dashboard_widgets_test.dart' show pumpBody;

/// Artwork has to carry the same auth the API calls do.
///
/// Behind a forward-auth proxy (Authelia, Cloudflare Access) every request
/// needs the configured header or the proxy answers it instead of the service.
/// API calls get theirs from the dio factory, which merges the profile's
/// global headers with the instance's. Artwork never goes through dio: it goes
/// out through CachedNetworkImage on its own client, and unless it is handed
/// `httpHeaders` it sends none.
///
/// This asserts on the widget rather than on a socket deliberately.
/// TestWidgetsFlutterBinding stubs HttpClient to answer 400 without opening a
/// connection, so a network-level test here reports "no header arrived" when
/// in truth no request was ever made. What the app controls, and what this
/// needs to pin down, is whether the headers are passed in at all.
void main() {
  testWidgets('a poster request carries the instance custom headers',
      (WidgetTester tester) async {
    const String base = 'http://sonarr.example.test';
    final Instance sonarr = Instance(
      id: 'sonarr-headers',
      name: 'Sonarr',
      kind: ServiceKind.sonarr,
      localUrl: base,
      externalUrl: '',
      urlMode: UrlMode.auto,
      auth: const InstanceAuth.apiKey(apiKey: 'k'),
      customHeaders: const <String, String>{
        'Authorization': 'Basic dGVzdDp0ZXN0',
      },
    );

    // A real api, so the poster URL is built by the same code as in the app.
    final SonarrApi api = SonarrApi(
      Dio(BaseOptions(baseUrl: '$base/')),
      apiKey: 'k',
    );

    // What app.dart does whenever the active profile changes. Artwork headers
    // are resolved from a lookup rather than a provider, because artwork is
    // requested from places with no ref to read.
    addTearDown(ArtworkHeaders.reset);
    ArtworkHeaders.update(
      instances: <Instance>[sonarr],
      global: const <String, String>{},
    );

    await pumpBody(
      tester,
      <Override>[
        sonarrApiProvider(sonarr).overrideWith((Ref ref) async => api),
        sonarrSeriesProvider(sonarr).overrideWith(
          (Ref ref) async => const <SonarrSeries>[
            SonarrSeries(
              title: 'Header Test',
              year: 2026,
              added: '2026-09-09T00:00:00Z',
              images: <SonarrImage>[
                SonarrImage(
                  coverType: 'poster',
                  url: '/MediaCover/1/poster.jpg',
                ),
              ],
            ),
          ],
        ),
      ],
      DashboardRecentlyAddedWidget(
        sonarrInstances: <Instance>[sonarr],
        radarrInstances: const <Instance>[],
      ),
      pumps: 5,
    );

    final Finder posters = find.byType(CachedNetworkImage);
    expect(
      posters,
      findsOneWidget,
      reason: 'no poster was rendered, so this test proves nothing about its '
          'headers',
    );

    final CachedNetworkImage poster = tester.widget<CachedNetworkImage>(posters);
    expect(
      poster.imageUrl,
      contains('/api/v3/mediacover/'),
      reason: 'the url should resolve to the instance, not a third party',
    );
    expect(
      poster.httpHeaders,
      containsPair('Authorization', 'Basic dGVzdDp0ZXN0'),
      reason: 'without the configured header the proxy answers the poster '
          'request instead of the service, which is why artwork comes up '
          'blank behind Authelia while everything else works',
    );
  });
}
