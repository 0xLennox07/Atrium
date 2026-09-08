import 'package:atrium/src/dashboard/dashboard_layout.dart';
import 'package:atrium/src/dashboard/dashboard_widget_kind.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wake-on-LAN is the first widget with no service behind it.
///
/// Issue #151: it points at machines rather than servers, so its devices live
/// on the profile. Every other widget is "configured" when one of its
/// [DashboardWidgetKindX.serviceKinds] has an instance, and that test would
/// call this one unconfigured forever, leaving it permanently hidden.
void main() {
  test('wake on lan claims no service kinds', () {
    expect(DashboardWidgetKind.wakeOnLan.serviceKinds, isEmpty);
  });

  test('it is the one kind flagged as device backed', () {
    final List<DashboardWidgetKind> deviceBacked = <DashboardWidgetKind>[
      for (final DashboardWidgetKind k in DashboardWidgetKind.values)
        if (k.isDeviceBacked) k,
    ];

    expect(deviceBacked, <DashboardWidgetKind>[DashboardWidgetKind.wakeOnLan]);
  });

  test('every other kind names at least one service that fills it', () {
    // A widget with neither a service nor the device-backed flag can never be
    // shown, which is the trap this pair of ideas exists to close.
    for (final DashboardWidgetKind kind in DashboardWidgetKind.values) {
      if (kind.isDeviceBacked) {
        continue;
      }
      expect(
        kind.serviceKinds,
        isNotEmpty,
        reason: '${kind.name} has no services and is not device backed, so '
            'nothing could ever make it appear',
      );
    }
  });

  test('it has a label and an icon like any other widget', () {
    expect(DashboardWidgetKind.wakeOnLan.label, 'Wake on LAN');
    expect(DashboardWidgetKind.wakeOnLan.icon, isNotNull);
  });

  group('layout', () {
    test('a saved layout from before it existed gains it, enabled', () {
      // mergeLayout appends kinds it has not seen, so an existing dashboard
      // picks the widget up without a migration.
      final List<DashboardWidgetConfig> stored = <DashboardWidgetConfig>[
        const DashboardWidgetConfig(
          kind: DashboardWidgetKind.downloads,
          enabled: true,
        ),
      ];

      final List<DashboardWidgetConfig> merged = mergeLayout(stored);
      final DashboardWidgetConfig wol = merged.firstWhere(
        (DashboardWidgetConfig c) => c.kind == DashboardWidgetKind.wakeOnLan,
      );

      expect(wol.enabled, isTrue);
      // The stored one keeps its place at the front.
      expect(merged.first.kind, DashboardWidgetKind.downloads);
    });

    test('it round-trips by name, so the order of the enum can change', () {
      // Storing an index would repoint every saved dashboard the moment a
      // value is inserted above it.
      final List<DashboardWidgetConfig> layout = <DashboardWidgetConfig>[
        const DashboardWidgetConfig(
          kind: DashboardWidgetKind.wakeOnLan,
          enabled: false,
        ),
      ];

      final List<DashboardWidgetConfig> back = decodeLayout(
        encodeLayout(layout),
      );

      expect(back.single.kind, DashboardWidgetKind.wakeOnLan);
      expect(back.single.enabled, isFalse);
      expect(encodeLayout(layout), contains('wakeOnLan'));
    });
  });
}
