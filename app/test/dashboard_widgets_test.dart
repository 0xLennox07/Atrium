import 'package:atrium/src/dashboard/dashboard_board.dart';
import 'package:atrium/src/dashboard/dashboard_widget_card.dart';
import 'package:atrium/src/dashboard/dashboard_widget_kind.dart';
import 'package:atrium/src/dashboard/widgets/downloads_widget.dart';
import 'package:atrium/src/dashboard/widgets/recently_added_widget.dart';
import 'package:atrium/src/dashboard/widgets/requests_widget.dart';
import 'package:atrium/src/dashboard/widgets/server_info_widget.dart';
import 'package:atrium/src/dashboard/widgets/streams_widget.dart';
import 'package:atrium/src/dashboard/widgets/upcoming_widget.dart';
import 'package:atrium/src/screens/calendar_screen.dart';
import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:service_jellyfin/service_jellyfin.dart' as jf;
import 'package:service_glances/service_glances.dart';
import 'package:service_nzbget/service_nzbget.dart';
import 'package:service_qbittorrent/service_qbittorrent.dart';
import 'package:service_radarr/service_radarr.dart';
import 'package:service_seerr/service_seerr.dart';
import 'package:service_sabnzbd/service_sabnzbd.dart';
import 'package:service_sonarr/service_sonarr.dart';
import 'package:service_tautulli/service_tautulli.dart';

/// Render tests for the dashboard widget board: each widget pumped with its
/// leaf providers overridden to fixed data, mirroring
/// new_services_render_test.dart's approach.
Instance makeInstance(ServiceKind kind) => Instance(
      id: 'test-${kind.name}',
      name: 'Test ${kind.displayName}',
      kind: kind,
      localUrl: 'http://localhost',
      externalUrl: '',
      urlMode: UrlMode.auto,
      auth: const InstanceAuth.apiKey(apiKey: 'k'),
    );

Future<void> pumpBody(
  WidgetTester tester,
  List<Override> overrides,
  Widget body, {
  int pumps = 2,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AtriumTheme.light(null),
        home: Scaffold(body: body),
      ),
    ),
  );
  for (int i = 0; i < pumps; i++) {
    await tester.pump();
  }
}

void main() {
  testWidgets('DashboardWidgetCard renders header, trailing and child',
      (WidgetTester tester) async {
    await pumpBody(
      tester,
      const <Override>[],
      Builder(
        builder: (BuildContext context) => DashboardWidgetCard(
          kind: DashboardWidgetKind.downloads,
          accent: Theme.of(context).colorScheme.primary,
          trailing: const Text('9 active'),
          child: const Text('card body'),
        ),
      ),
    );
    expect(find.text('Active downloads'), findsOneWidget);
    expect(find.text('9 active'), findsOneWidget);
    expect(find.text('card body'), findsOneWidget);
    expect(find.byIcon(Icons.download_rounded), findsOneWidget);
  });

  testWidgets(
      'DashboardDownloadsWidget shows combined qBit + SAB + NZBGet items',
      (WidgetTester tester) async {
    final Instance qbit = makeInstance(ServiceKind.qbittorrent);
    final Instance sab = makeInstance(ServiceKind.sabnzbd);
    final Instance nzbget = makeInstance(ServiceKind.nzbget);
    await pumpBody(
      tester,
      <Override>[
        qbitRawTorrentsProvider(qbit).overrideWith(
          (Ref ref) async => const <QbitTorrent>[
            QbitTorrent(
              hash: 'h1',
              name: 'Ubuntu ISO',
              state: 'downloading',
              progress: 0.45,
              dlspeed: 1048576,
            ),
          ],
        ),
        qbitTransferProvider(qbit).overrideWith(
          (Ref ref) async => const QbitTransferInfo(dlSpeed: 1048576),
        ),
        sabQueueProvider(sab).overrideWith(
          (Ref ref) async => const SabQueue(
            status: 'Downloading',
            speed: '2.0 M',
            slots: <SabSlot>[
              SabSlot(
                nzoId: 'n1',
                filename: 'Show.S01E01.mkv',
                percentage: '80',
                status: 'Downloading',
              ),
            ],
          ),
        ),
        nzbgetQueueProvider(nzbget).overrideWith(
          (Ref ref) => Future<List<NzbgetGroup>>.value(<NzbgetGroup>[
            const NzbgetGroup(
              nzbId: 1,
              name: 'Distro.Refresh.nzb',
              status: 'DOWNLOADING',
              fileSizeMb: 100,
              downloadedSizeMb: 50,
            ),
          ]),
        ),
        nzbgetStatusProvider(nzbget).overrideWith(
          (Ref ref) => Future<NzbgetStatus>.value(
            const NzbgetStatus(downloadRate: 1024),
          ),
        ),
      ],
      DashboardDownloadsWidget(
        qbitInstances: <Instance>[qbit],
        sabInstances: <Instance>[sab],
        nzbgetInstances: <Instance>[nzbget],
        delugeInstances: <Instance>[],
        transmissionInstances: <Instance>[],
        rtorrentInstances: <Instance>[],
      ),
    );
    expect(find.text('Ubuntu ISO'), findsOneWidget);
    expect(find.text('Show.S01E01.mkv'), findsOneWidget);
    expect(find.text('Distro.Refresh.nzb'), findsOneWidget);
    expect(find.text('Active downloads'), findsOneWidget);
  });

  test('parseSabSpeed handles K/M/G suffixes and bare bytes', () {
    expect(parseSabSpeed('2.0 M'), 2 * 1024 * 1024);
    expect(parseSabSpeed('512 K'), 512 * 1024);
    expect(parseSabSpeed('100'), 100);
    expect(parseSabSpeed(''), 0);
    expect(parseSabSpeed('junk'), 0);
  });

  testWidgets('DashboardStreamsWidget shows Tautulli and Jellyfin sessions',
      (WidgetTester tester) async {
    final Instance tau = makeInstance(ServiceKind.tautulli);
    final Instance jelly = makeInstance(ServiceKind.jellyfin);
    await pumpBody(
      tester,
      <Override>[
        tautulliActivityProvider(tau).overrideWith(
          (Ref ref) async => const TautulliActivity(
            streamCount: 1,
            sessions: <TautulliSession>[
              TautulliSession(
                friendlyName: 'Alice',
                fullTitle: 'The Matrix',
                progressPercent: 30,
                state: 'playing',
                player: 'Plex Web',
                videoResolution: '1080p',
                transcodeDecision: 'transcode',
              ),
            ],
          ),
        ),
        jf.jellyfinSessionsProvider(jelly).overrideWith(
              (Ref ref) =>
                  Stream<List<jf.ActiveSession>>.value(<jf.ActiveSession>[
                const jf.ActiveSession(
                  id: 's1',
                  user: 'Bob',
                  device: 'Web',
                  status: 'Playing',
                  showTitle: 'Breaking Bad',
                  episodeName: 'Pilot',
                  progressPercent: 55,
                  timePosition: '0:10:00',
                  timeDuration: '0:45:00',
                  positionTicks: 0,
                  durationTicks: 0,
                  volumeLevel: 100,
                  isMuted: false,
                ),
              ]),
            ),
      ],
      DashboardStreamsWidget(
        tautulliInstances: <Instance>[tau],
        jellyfinInstances: <Instance>[jelly],
        embyInstances: const <Instance>[],
      ),
    );
    expect(find.text('Now streaming'), findsOneWidget);
    expect(find.textContaining('The Matrix'), findsOneWidget);
    expect(find.textContaining('Breaking Bad'), findsOneWidget);
    // Enriched session info: device on the meta line, the resolution chip,
    // and Jellyfin's elapsed / total time.
    expect(find.textContaining('Plex Web'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.textContaining('Web'), findsWidgets);
    expect(find.text('0:10:00 / 0:45:00'), findsOneWidget);
  });

  testWidgets('DashboardUpcomingWidget lists events inside the 7-day window',
      (WidgetTester tester) async {
    final Instance sonarr = makeInstance(ServiceKind.sonarr);
    final DateTime tomorrow = DateTime.now().add(const Duration(days: 1));
    final List<CalendarEvent> events = <CalendarEvent>[
      SonarrCalendarEvent(
        SonarrEpisode(
          id: 1,
          seriesId: 10,
          title: 'Pilot',
          seasonNumber: 1,
          episodeNumber: 1,
          airDateUtc: tomorrow.toUtc().toIso8601String(),
          hasFile: false,
          monitored: true,
          series: const SonarrSeries(id: 10, title: 'Test Show'),
        ),
        sonarr,
      ),
    ];
    await pumpBody(
      tester,
      <Override>[
        for (final DateTime m in upcomingWindowMonths(DateTime.now()))
          globalCalendarProvider((m, false)).overrideWith((Ref ref) async => events),
      ],
      const DashboardUpcomingWidget(),
    );
    expect(find.text('Upcoming releases'), findsOneWidget);
    expect(find.textContaining('Test Show'), findsOneWidget);
  });

  testWidgets('DashboardRecentlyAddedWidget shows newest series and movies',
      (WidgetTester tester) async {
    final Instance sonarr = makeInstance(ServiceKind.sonarr);
    final Instance radarr = makeInstance(ServiceKind.radarr);
    await pumpBody(
      tester,
      <Override>[
        sonarrSeriesProvider(sonarr).overrideWith(
          (Ref ref) async => const <SonarrSeries>[
            SonarrSeries(
              title: 'New Show',
              year: 2024,
              added: '2026-07-10T00:00:00Z',
            ),
            SonarrSeries(
              title: 'Old Show',
              year: 2010,
              added: '2020-01-01T00:00:00Z',
            ),
          ],
        ),
        radarrMoviesProvider(radarr).overrideWith(
          (Ref ref) async => const <RadarrMovie>[
            RadarrMovie(
              title: 'New Movie',
              year: 2025,
              added: '2026-07-12T00:00:00Z',
            ),
          ],
        ),
      ],
      DashboardRecentlyAddedWidget(
        sonarrInstances: <Instance>[sonarr],
        radarrInstances: <Instance>[radarr],
      ),
      pumps: 3,
    );
    expect(find.text('Recently added'), findsOneWidget);
    expect(find.text('New Movie'), findsOneWidget);
    expect(find.text('New Show'), findsOneWidget);
    expect(find.text('Movie · 2025'), findsOneWidget);
  });

  testWidgets('DashboardRequestsWidget shows pending count and newest title',
      (WidgetTester tester) async {
    final Instance seerr = makeInstance(ServiceKind.seerr);
    await pumpBody(
      tester,
      <Override>[
        seerrRequestCountsProvider(seerr).overrideWith(
          (Ref ref) async => const SeerrCounts(total: 3, pending: 2),
        ),
        seerrRequestsProvider(seerr).overrideWith(
          (Ref ref) async => const <SeerrRequest>[
            SeerrRequest(
              id: 1,
              status: 1,
              type: 'movie',
              media: SeerrMedia(mediaType: 'movie', tmdbId: 603),
              requestedBy: SeerrUser(displayName: 'Bob'),
              createdAt: '2026-07-01T00:00:00Z',
            ),
          ],
        ),
        seerrMediaDetailsProvider(
          (instance: seerr, mediaType: 'movie', tmdbId: 603),
        ).overrideWith(
          (Ref ref) async =>
              const SeerrDiscoverResult(id: 603, title: 'The Matrix'),
        ),
      ],
      DashboardRequestsWidget(instances: <Instance>[seerr]),
      pumps: 3,
    );
    expect(find.text('Requests'), findsOneWidget);
    expect(find.text('3 requested'), findsOneWidget);
    expect(find.text('Needs approval'), findsOneWidget);
    expect(find.textContaining('The Matrix'), findsOneWidget);
    expect(find.textContaining('Bob'), findsOneWidget);
  });

  testWidgets('DashboardServerInfoWidget shows CPU, memory, GPU and disks',
      (WidgetTester tester) async {
    final Instance glances = makeInstance(ServiceKind.glances);
    await pumpBody(
      tester,
      <Override>[
        glancesStatsProvider(glances).overrideWith(
          (Ref ref) async => const GlancesStats(
            cpu: GlancesCpu(
              physicalCores: 4,
              logicalCores: 8,
              totalUsage: 42,
              packageTemp: 55,
              cores: <GlancesCpuCore>[],
            ),
            memory: GlancesMemory(
                percentage: 63, used: 8000000000, total: 16000000000),
            swap: GlancesSwap(percentage: 0, used: 0, total: 0),
            network: <GlancesNetwork>[],
            disks: <GlancesDisk>[
              GlancesDisk(
                path: '/data',
                percentage: 71,
                used: 500000000000,
                total: 1000000000000,
              ),
            ],
            uptime: GlancesUptime(
              days: 1,
              hours: 2,
              minutes: 3,
              seconds: 4,
              totalSeconds: 93784,
            ),
            gpus: <GlancesGpu>[
              GlancesGpu(name: 'RTX', proc: 30, mem: 40, temp: 60),
            ],
          ),
        ),
      ],
      DashboardServerInfoWidget(instances: <Instance>[glances]),
      pumps: 3,
    );
    // The gauges fill via a TweenAnimationBuilder, so let it run out before
    // reading the settled percentage.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Server info'), findsOneWidget);
    expect(find.text('CPU'), findsOneWidget);
    expect(find.text('Memory'), findsOneWidget);
    expect(find.text('GPU'), findsOneWidget);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('/data'), findsOneWidget);
  });

  testWidgets('DashboardBoard renders configured widgets and hides others',
      (WidgetTester tester) async {
    final Instance qbit = makeInstance(ServiceKind.qbittorrent);
    final Instance tau = makeInstance(ServiceKind.tautulli);
    await pumpBody(
      tester,
      <Override>[
        activeInstancesProvider.overrideWithValue(<Instance>[qbit, tau]),
        qbitRawTorrentsProvider(qbit).overrideWith(
          (Ref ref) async => const <QbitTorrent>[
            QbitTorrent(
              hash: 'h1',
              name: 'Ubuntu ISO',
              state: 'downloading',
              progress: 0.45,
            ),
          ],
        ),
        qbitTransferProvider(qbit).overrideWith(
          (Ref ref) async => const QbitTransferInfo(dlSpeed: 0),
        ),
        tautulliActivityProvider(tau).overrideWith(
          (Ref ref) async => const TautulliActivity(streamCount: 0),
        ),
      ],
      const DashboardBoard(),
      pumps: 3,
    );
    expect(find.text('Active downloads'), findsOneWidget);
    expect(find.text('Ubuntu ISO'), findsOneWidget);
    // Streams is activity-gated: tautulli is configured but nobody is
    // streaming (streamCount 0), so the widget stays hidden.
    expect(find.text('Now streaming'), findsNothing);
    // No sonarr/radarr, seerr or glances configured:
    expect(find.text('Upcoming releases'), findsNothing);
    expect(find.text('Requests'), findsNothing);
    expect(find.text('Server info'), findsNothing);
  });

  testWidgets('DashboardBoard activity-gates downloads and streams',
      (WidgetTester tester) async {
    final Instance qbit = makeInstance(ServiceKind.qbittorrent);
    final Instance tau = makeInstance(ServiceKind.tautulli);
    await pumpBody(
      tester,
      <Override>[
        activeInstancesProvider.overrideWithValue(<Instance>[qbit, tau]),
        // Only a seeding torrent -> no active download -> widget hidden.
        qbitRawTorrentsProvider(qbit).overrideWith(
          (Ref ref) async => const <QbitTorrent>[
            QbitTorrent(
              hash: 'h1',
              name: 'Seeded ISO',
              state: 'uploading',
              progress: 1.0,
            ),
          ],
        ),
        // One active session -> streams widget shown.
        tautulliActivityProvider(tau).overrideWith(
          (Ref ref) async => const TautulliActivity(
            streamCount: 1,
            sessions: <TautulliSession>[
              TautulliSession(
                friendlyName: 'Alice',
                fullTitle: 'The Matrix',
                progressPercent: 30,
                state: 'playing',
              ),
            ],
          ),
        ),
      ],
      const DashboardBoard(),
      pumps: 3,
    );
    expect(find.text('Active downloads'), findsNothing);
    expect(find.text('Now streaming'), findsOneWidget);
    expect(find.textContaining('The Matrix'), findsOneWidget);
  });

  testWidgets('DashboardBoard edit mode reorders and hides widgets',
      (WidgetTester tester) async {
    final Instance qbit = makeInstance(ServiceKind.qbittorrent);
    await pumpBody(
      tester,
      <Override>[
        activeInstancesProvider.overrideWithValue(<Instance>[qbit]),
        dashboardEditModeProvider.overrideWith((Ref ref) => true),
      ],
      const DashboardBoard(),
    );
    // All eight widgets are arrangeable in edit mode, configured or not.
    // Counted from the enum so adding a widget does not break this.
    expect(
      find.byIcon(Icons.drag_indicator),
      findsNWidgets(DashboardWidgetKind.values.length),
    );
    expect(find.text('Hidden'), findsNothing);
    // Hide the first widget -> it moves to the Hidden section.
    await tester.tap(find.byIcon(Icons.visibility_off_outlined).first);
    await tester.pump();
    expect(find.text('Hidden'), findsOneWidget);
    expect(
      find.byIcon(Icons.drag_indicator),
      findsNWidgets(DashboardWidgetKind.values.length - 1),
    );
    expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);
  });

  /// The tile for one widget, found by its label.
  Finder tileFor(String label) => find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate(
          (Widget w) => w.runtimeType.toString() == '_EditTile',
        ),
      );

  testWidgets('an unavailable widget names the service it needs',
      (WidgetTester tester) async {
    // "Not configured" leaves someone to guess what is missing, which is why
    // a widget that could never fill read as broken rather than unavailable.
    await pumpBody(
      tester,
      <Override>[
        activeInstancesProvider.overrideWithValue(const <Instance>[]),
        dashboardEditModeProvider.overrideWith((Ref ref) => true),
      ],
      const DashboardBoard(),
    );

    expect(find.text('Needs Glances'), findsOneWidget);
    expect(find.text('Needs Seerr'), findsOneWidget);
    expect(find.text('Needs Speedtest Tracker'), findsOneWidget);
    // Upcoming, recently added and recently downloaded all want the same pair.
    expect(find.text('Needs Sonarr or Radarr'), findsNWidgets(3));
    expect(find.text('Needs Tautulli, Jellyfin or Emby'), findsOneWidget);
    expect(find.text('Not configured'), findsNothing);
  });

  testWidgets('a widget nothing can fill cannot be shown',
      (WidgetTester tester) async {
    await pumpBody(
      tester,
      <Override>[
        activeInstancesProvider.overrideWithValue(const <Instance>[]),
        dashboardEditModeProvider.overrideWith((Ref ref) => true),
      ],
      const DashboardBoard(),
    );

    // Hide it so it lands in the Hidden section, where the show button lives.
    await tester.tap(
      find.descendant(
        of: tileFor('Server info'),
        matching: find.byIcon(Icons.visibility_off_outlined),
      ),
    );
    await tester.pump();

    // Showing it again would put it back on a board that filters it straight
    // out, which reads as the button having failed.
    final Finder show = find.descendant(
      of: tileFor('Server info'),
      matching: find.widgetWithIcon(IconButton, Icons.add_circle_outline),
    );
    expect(show, findsOneWidget);
    expect(tester.widget<IconButton>(show).onPressed, isNull);
  });

  testWidgets('a widget with its service configured can still be shown',
      (WidgetTester tester) async {
    final Instance glances = makeInstance(ServiceKind.glances);
    await pumpBody(
      tester,
      <Override>[
        activeInstancesProvider.overrideWithValue(<Instance>[glances]),
        dashboardEditModeProvider.overrideWith((Ref ref) => true),
      ],
      const DashboardBoard(),
    );

    expect(find.text('Needs Glances'), findsNothing);
    await tester.tap(
      find.descendant(
        of: tileFor('Server info'),
        matching: find.byIcon(Icons.visibility_off_outlined),
      ),
    );
    await tester.pump();

    final Finder show = find.descendant(
      of: tileFor('Server info'),
      matching: find.widgetWithIcon(IconButton, Icons.add_circle_outline),
    );
    expect(tester.widget<IconButton>(show).onPressed, isNotNull);
  });
}
