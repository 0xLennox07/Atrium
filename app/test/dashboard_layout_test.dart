import 'package:atrium/src/dashboard/dashboard_layout.dart';
import 'package:atrium/src/dashboard/dashboard_widget_kind.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('decodeLayout', () {
    test('null / empty / corrupt input decodes to empty list', () {
      expect(decodeLayout(null), isEmpty);
      expect(decodeLayout(''), isEmpty);
      expect(decodeLayout('not json'), isEmpty);
      expect(decodeLayout('{"kind":"downloads"}'), isEmpty); // not a list
    });

    test('unknown kinds are dropped, enabled defaults to true', () {
      final List<DashboardWidgetConfig> out = decodeLayout(
        '[{"kind":"streams","enabled":false},'
        '{"kind":"someFutureWidget","enabled":true},'
        '{"kind":"downloads"}]',
      );
      expect(out, hasLength(2));
      expect(out[0].kind, DashboardWidgetKind.streams);
      expect(out[0].enabled, isFalse);
      expect(out[1].kind, DashboardWidgetKind.downloads);
      expect(out[1].enabled, isTrue);
    });
  });

  group('mergeLayout', () {
    test('keeps stored order, appends missing kinds enabled, drops dupes', () {
      final List<DashboardWidgetConfig> merged =
          mergeLayout(<DashboardWidgetConfig>[
        const DashboardWidgetConfig(
            kind: DashboardWidgetKind.requests, enabled: false),
        const DashboardWidgetConfig(
            kind: DashboardWidgetKind.downloads, enabled: true),
        const DashboardWidgetConfig(
            kind: DashboardWidgetKind.requests, enabled: true), // dupe
      ]);
      expect(merged, hasLength(DashboardWidgetKind.values.length));
      expect(merged[0].kind, DashboardWidgetKind.requests);
      expect(merged[0].enabled, isFalse); // first occurrence wins
      expect(merged[1].kind, DashboardWidgetKind.downloads);
      // The remaining kinds follow in enum order, enabled.
      expect(merged[2].kind, DashboardWidgetKind.streams);
      expect(
          merged.skip(2).every((DashboardWidgetConfig c) => c.enabled), isTrue);
    });

    test('empty stored input yields the default layout', () {
      final List<DashboardWidgetConfig> merged =
          mergeLayout(const <DashboardWidgetConfig>[]);
      expect(
        merged.map((DashboardWidgetConfig c) => c.kind).toList(),
        DashboardWidgetKind.values,
      );
      expect(merged.every((DashboardWidgetConfig c) => c.enabled), isTrue);
    });
  });

  test('encodeLayout round-trips through decodeLayout', () {
    final List<DashboardWidgetConfig> layout = <DashboardWidgetConfig>[
      const DashboardWidgetConfig(
          kind: DashboardWidgetKind.serverInfo, enabled: false),
      const DashboardWidgetConfig(
          kind: DashboardWidgetKind.upcoming, enabled: true),
    ];
    final List<DashboardWidgetConfig> back = decodeLayout(encodeLayout(layout));
    expect(back, hasLength(2));
    expect(back[0].kind, DashboardWidgetKind.serverInfo);
    expect(back[0].enabled, isFalse);
    expect(back[1].kind, DashboardWidgetKind.upcoming);
  });

  group('DashboardLayoutController (no Hive booted - in-memory)', () {
    test('build returns defaults; setEnabled flips one kind', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      expect(
        container.read(dashboardLayoutProvider),
        hasLength(DashboardWidgetKind.values.length),
      );
      container
          .read(dashboardLayoutProvider.notifier)
          .setEnabled(DashboardWidgetKind.requests, false);
      final DashboardWidgetConfig requests = container
          .read(dashboardLayoutProvider)
          .firstWhere((DashboardWidgetConfig c) =>
              c.kind == DashboardWidgetKind.requests);
      expect(requests.enabled, isFalse);
    });

    test('moveEnabled reorders within the enabled subset', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);
      final DashboardLayoutController controller =
          container.read(dashboardLayoutProvider.notifier);
      // Hide one widget so enabled != full list.
      controller.setEnabled(DashboardWidgetKind.streams, false);
      // Enabled order is now: downloads, upcoming, recentlyAdded,
      // recentlyDownloaded, requests, serverInfo, speedtestResults.
      controller.moveEnabled(0, 2); // drag downloads down two slots
      final List<DashboardWidgetKind> enabled = container
          .read(dashboardLayoutProvider)
          .where((DashboardWidgetConfig c) => c.enabled)
          .map((DashboardWidgetConfig c) => c.kind)
          .toList();
      // Derived rather than frozen: a new widget kind appends to this list,
      // and spelling it out here means every one of them breaks this test for
      // no reason. moveEnabled(0, 2) is just a remove-and-insert.
      final List<DashboardWidgetKind> expected = <DashboardWidgetKind>[
        for (final DashboardWidgetKind k in DashboardWidgetKind.values)
          if (k != DashboardWidgetKind.streams) k,
      ];
      expected.insert(2, expected.removeAt(0));
      expect(enabled, expected);
      // The disabled widget is still present, at the end.
      final List<DashboardWidgetConfig> all =
          container.read(dashboardLayoutProvider);
      expect(all.last.kind, DashboardWidgetKind.streams);
      expect(all.last.enabled, isFalse);
    });
  });
}
