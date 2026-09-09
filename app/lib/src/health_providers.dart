import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_profile/core_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The shared [HealthProbe], built from the networking [DioFactory].
final Provider<HealthProbe> healthProbeProvider = Provider<HealthProbe>((
  Ref ref,
) {
  return HealthProbe(dioFactory: ref.watch(dioFactoryProvider));
});

/// Real per-service health for an instance, used to color the dashboard dot.
///
/// Keyed by `instanceId` (String) so Riverpod caches results across instance
/// object recreations and avoids redundant health probes when scrolling.
final instanceHealthProvider =
    FutureProvider.family<Health, String>((Ref ref, String instanceId) {
  final Instance? instance = ref.watch(instanceByIdProvider(instanceId));
  if (instance == null) return Health.unknown;
  return ref.watch(healthProbeProvider).check(instance);
});

/// Tracks when service health probes were last refreshed across the app.
class LastHealthRefreshNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void markRefreshed() {
    state = DateTime.now();
  }
}

final NotifierProvider<LastHealthRefreshNotifier, DateTime?>
    lastHealthRefreshProvider =
    NotifierProvider<LastHealthRefreshNotifier, DateTime?>(
  LastHealthRefreshNotifier.new,
);
