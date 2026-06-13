import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_ui/core_ui.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_bazarr/service_bazarr.dart';
import 'package:service_overseerr/service_overseerr.dart';
import 'package:service_plex/service_plex.dart';
import 'package:service_radarr/service_radarr.dart';
import 'package:service_sabnzbd/service_sabnzbd.dart';
import 'package:service_sonarr/service_sonarr.dart';
import 'package:service_tautulli/service_tautulli.dart';
import 'package:atrium/src/screens/calendar_screen.dart';

/// Deterministic render tests for the service modules added in the final pass.
///
/// Emulator UI-automation of the Add-service dropdown proved flaky, so instead
/// of driving taps we pump each `*Home` widget directly with its leaf data
/// provider overridden to fixed data. This exercises the real widget tree of
/// each new module and asserts it renders the expected content - proving the
/// screens are wired and build, not just that they compile.
Instance _instance(ServiceKind kind) => Instance(
      id: 'test-${kind.name}',
      name: 'Test ${kind.displayName}',
      kind: kind,
      localUrl: 'http://localhost',
      externalUrl: '',
      urlMode: UrlMode.auto,
      auth: const InstanceAuth.apiKey(apiKey: 'k'),
    );

Future<void> _pump(
  WidgetTester tester,
  List<Override> overrides,
  Widget home, {
  int pumps = 1,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AtriumTheme.light(null),
        home: Scaffold(body: home),
      ),
    ),
  );
  // Overridden FutureProviders complete on the next microtask; each pump
  // surfaces one async stage. Screens with nested providers (e.g. Plex:
  // libraries → items grid) need more than one. pumpAndSettle would hang on
  // the loading spinner, so we pump a fixed number of frames instead.
  for (int i = 0; i < pumps; i++) {
    await tester.pump();
  }
}

void main() {
  testWidgets('SabnzbdHome renders queue slots', (WidgetTester tester) async {
    final Instance instance = _instance(ServiceKind.sabnzbd);
    await _pump(
      tester,
      <Override>[
        sabQueueProvider(instance).overrideWith(
          (Ref ref) async => const SabQueue(
            status: 'Downloading',
            speed: '1.2 M',
            slots: <SabSlot>[
              SabSlot(
                nzoId: '1',
                filename: 'Ubuntu.24.04.iso',
                percentage: '45',
                status: 'Downloading',
                timeleft: '0:05:00',
              ),
            ],
          ),
        ),
      ],
      SabnzbdHome(instance: instance),
    );
    expect(find.text('Ubuntu.24.04.iso'), findsOneWidget);
  });

  testWidgets('TautulliHome renders active streams', (WidgetTester tester) async {
    final Instance instance = _instance(ServiceKind.tautulli);
    await _pump(
      tester,
      <Override>[
        tautulliActivityProvider(instance).overrideWith(
          (Ref ref) async => const TautulliActivity(
            streamCount: 1,
            sessions: <TautulliSession>[
              TautulliSession(
                friendlyName: 'Alice',
                fullTitle: 'The Matrix',
                progressPercent: 30,
                state: 'playing',
                player: 'Living Room TV',
              ),
            ],
          ),
        ),
      ],
      TautulliHome(instance: instance),
    );
    expect(find.text('The Matrix'), findsOneWidget);
  });

  testWidgets('OverseerrHome renders requests with approve action',
      (WidgetTester tester) async {
    final Instance instance = _instance(ServiceKind.overseerr);
    await _pump(
      tester,
      <Override>[
        overseerrRequestsProvider(instance).overrideWith(
          (Ref ref) async => const <OverseerrRequest>[
            OverseerrRequest(
              id: 1,
              status: 1,
              type: 'movie',
              requestedBy: OverseerrUser(displayName: 'Bob'),
            ),
          ],
        ),
      ],
      OverseerrHome(instance: instance),
    );
    expect(find.text('Movie request'), findsOneWidget);
    expect(find.text('by Bob'), findsOneWidget);
    // Pending requests expose an approve button.
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('BazarrHome renders wanted-subtitles rows', (WidgetTester tester) async {
    final Instance instance = _instance(ServiceKind.bazarr);
    await _pump(
      tester,
      <Override>[
        bazarrBadgesProvider(instance).overrideWith(
          (Ref ref) async =>
              const BazarrBadges(episodes: 3, movies: 1, providers: 5),
        ),
        bazarrWantedProvider(instance).overrideWith(
          (Ref ref) async => const <BazarrWantedRow>[
            BazarrWantedRow(
              title: 'Breaking Bad',
              subtitle: 'S01E01 · Pilot',
              missing: <BazarrSubtitle>[BazarrSubtitle(name: 'English', code2: 'en')],
              isMovie: false,
            ),
          ],
        ),
      ],
      BazarrHome(instance: instance),
    );
    expect(find.text('Breaking Bad'), findsOneWidget);
  });

  testWidgets('PlexHome renders hub sections', (WidgetTester tester) async {
    final Instance instance = _instance(ServiceKind.plex);
    await _pump(
      tester,
      <Override>[
        // A throwaway PlexApi so the poster card can call imageUrl() without a
        // live connection; the test asserts on the title, not the poster.
        plexApiProvider(instance).overrideWith(
          (Ref ref) async => PlexApi(Dio(), token: 'tok'),
        ),
        plexLibrariesProvider(instance).overrideWith(
          (Ref ref) async => const <PlexLibrary>[
            PlexLibrary(key: '1', title: 'Movies', type: 'movie'),
          ],
        ),
        // The Home tab is the default view, so it renders the on-deck and
        // recently-added rows rather than a library grid.
        plexOnDeckProvider(instance).overrideWith(
          (Ref ref) async => const <PlexMetadata>[
            PlexMetadata(
              ratingKey: '10',
              title: 'Blade Runner',
              year: 1982,
              type: 'movie',
              viewOffset: 600000,
              duration: 6000000,
            ),
          ],
        ),
        plexRecentlyAddedProvider(instance).overrideWith(
          (Ref ref) async => const <PlexMetadata>[],
        ),
      ],
      PlexHome(instance: instance),
      pumps: 4,
    );
    expect(find.text('Continue Watching'), findsOneWidget);
    expect(find.text('Blade Runner'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
  });

  testWidgets('CalendarScreen renders Sonarr and Radarr aggregated entries', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final Instance sonarr = _instance(ServiceKind.sonarr);
    final Instance radarr = _instance(ServiceKind.radarr);
    final DateTime airDate = DateTime.now();

    await _pump(
      tester,
      <Override>[
        activeInstancesProvider.overrideWith(
          (Ref ref) => <Instance>[sonarr, radarr],
        ),
        sonarrApiProvider(sonarr).overrideWith(
          (Ref ref) async => SonarrApi(Dio(), apiKey: 'k'),
        ),
        radarrApiProvider(radarr).overrideWith(
          (Ref ref) async => RadarrApi(Dio(), apiKey: 'k'),
        ),
        sonarrCalendarProvider.overrideWith(
          (Ref ref, (Instance, DateTime) key) async => <SonarrCalendarEntry>[
            SonarrCalendarEntry(
              id: 1,
              seriesId: 10,
              title: 'The Rains of Castamere',
              seasonNumber: 3,
              episodeNumber: 9,
              airDateUtc: airDate,
              hasFile: false,
              monitored: true,
              series: const SonarrSeries(
                id: 10,
                title: 'Game of Thrones',
              ),
            ),
          ],
        ),
        radarrCalendarProvider.overrideWith(
          (Ref ref, (Instance, DateTime) key) async => <RadarrMovie>[
            RadarrMovie(
              id: 1,
              title: 'Inception',
              year: 2010,
              inCinemas: airDate.toIso8601String(),
              monitored: true,
              hasFile: false,
            ),
          ],
        ),
      ],
      const CalendarScreen(),
      pumps: 3,
    );

    expect(find.text('Game of Thrones - S03E09'), findsOneWidget);
    expect(find.text('Inception'), findsOneWidget);
    expect(find.text('Missing'), findsNWidgets(2));
  });
}
