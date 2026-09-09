import 'package:atrium/src/health_providers.dart';
import 'package:atrium/src/screens/dashboard_screen.dart';
import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Profile _testProfile() => const Profile(
      id: 'p1',
      name: 'Home',
      instances: <Instance>[
        Instance(
          id: 'i1',
          name: 'Sonarr',
          kind: ServiceKind.sonarr,
          localUrl: 'http://localhost:8989',
          externalUrl: '',
          urlMode: UrlMode.auto,
          auth: InstanceAuth.apiKey(apiKey: 'k1'),
        ),
      ],
    );

class _FakeProfileListController extends ProfileListController {
  @override
  Future<List<Profile>> build() async => <Profile>[_testProfile()];
}

void main() {
  testWidgets('ServicesDrawer renders RefreshIndicator and triggers refresh on pull', (
    WidgetTester tester,
  ) async {
    int probeCount = 0;
    final Profile profile = _testProfile();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeProfileProvider.overrideWith((Ref ref) => profile),
          profileListProvider.overrideWith(_FakeProfileListController.new),
          instanceHealthProvider.overrideWith((Ref ref, String id) {
            probeCount++;
            return Health.ok;
          }),
        ],
        child: MaterialApp(
          theme: AtriumTheme.light(null),
          home: Scaffold(
            drawer: ServicesDrawer(
              instances: profile.instances,
              profile: profile,
            ),
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                child: const Text('Open Drawer'),
              ),
            ),
          ),
        ),
      ),
    );

    // Open the drawer.
    await tester.tap(find.text('Open Drawer'));
    await tester.pumpAndSettle();

    // Verify RefreshIndicator exists around the service list.
    expect(find.byType(RefreshIndicator), findsOneWidget);
    expect(find.text('Sonarr'), findsOneWidget);

    final int initialProbes = probeCount;
    expect(initialProbes, greaterThanOrEqualTo(1));

    // Pull down on the service list to trigger pull-to-refresh.
    await tester.fling(find.text('Sonarr'), const Offset(0, 300), 1000);
    await tester.pump();
    // Allow RefreshIndicator animation and async future to complete.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Verify health was re-probed.
    expect(probeCount, greaterThan(initialProbes));
  });

  testWidgets('ServicesDrawer refreshes health on open if stale (>60s)', (
    WidgetTester tester,
  ) async {
    int probeCount = 0;
    final Profile profile = _testProfile();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        activeProfileProvider.overrideWith((Ref ref) => profile),
        profileListProvider.overrideWith(_FakeProfileListController.new),
        instanceHealthProvider.overrideWith((Ref ref, String id) {
          probeCount++;
          return Health.ok;
        }),
      ],
    );

    // Set last health refresh to 5 minutes ago (stale).
    container.read(lastHealthRefreshProvider.notifier).state =
        DateTime.now().subtract(const Duration(minutes: 5));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AtriumTheme.light(null),
          home: Scaffold(
            drawer: ServicesDrawer(
              instances: profile.instances,
              profile: profile,
            ),
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(probeCount, 0);

    // Open drawer.
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Freshness check triggers post-frame refresh when stale.
    expect(probeCount, greaterThanOrEqualTo(1));
    expect(
      container.read(lastHealthRefreshProvider),
      isNotNull,
    );
  });

  testWidgets('ServicesDrawer polls health every 30s while open, stops when closed', (
    WidgetTester tester,
  ) async {
    int probeCount = 0;
    final Profile profile = _testProfile();
    final ProviderContainer container = ProviderContainer(
      overrides: [
        activeProfileProvider.overrideWith((Ref ref) => profile),
        profileListProvider.overrideWith(_FakeProfileListController.new),
        instanceHealthProvider.overrideWith((Ref ref, String id) {
          probeCount++;
          return Health.ok;
        }),
      ],
    );

    // Mark as just refreshed so opening doesn't trigger staleness check.
    container.read(lastHealthRefreshProvider.notifier).state = DateTime.now();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AtriumTheme.light(null),
          home: Scaffold(
            drawer: ServicesDrawer(
              instances: profile.instances,
              profile: profile,
            ),
            body: Builder(
              builder: (BuildContext context) => ElevatedButton(
                onPressed: () => Scaffold.of(context).openDrawer(),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    // Open drawer.
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final int countAfterOpen = probeCount;

    // Advance by 31 seconds while drawer is open.
    await tester.pump(const Duration(seconds: 31));
    await tester.pumpAndSettle();

    // Verify polling triggered a probe.
    final int countAfter30s = probeCount;
    expect(countAfter30s, greaterThan(countAfterOpen));

    // Close the drawer.
    final ScaffoldState scaffold = tester.state(find.byType(Scaffold));
    scaffold.closeDrawer();
    await tester.pumpAndSettle();

    // Verify ServicesDrawer is no longer in the tree.
    expect(find.byType(ServicesDrawer), findsNothing);

    // Advance time another 60 seconds with drawer closed.
    await tester.pump(const Duration(seconds: 60));
    await tester.pumpAndSettle();

    // Verify no additional probes occurred while closed.
    expect(probeCount, equals(countAfter30s));
  });
}
