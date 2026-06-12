import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The shared [HealthProbe], built from the networking [DioFactory].
final Provider<HealthProbe> healthProbeProvider = Provider<HealthProbe>((
  Ref ref,
) {
  return HealthProbe(dioFactory: ref.watch(dioFactoryProvider));
});

/// Real per-service health for an instance, used to color the dashboard dot.
///
/// Delegates to [HealthProbe], which hits each service's own status endpoint
/// with its real auth and distinguishes ok / warning (bad creds) / error
/// (unreachable) - far more meaningful than a blind `GET /`.
final instanceHealthProvider =
    FutureProvider.family<Health, Instance>((Ref ref, Instance instance) {
      return ref.watch(healthProbeProvider).check(instance);
    });
