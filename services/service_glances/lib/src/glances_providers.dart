import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glances_api.dart';
import 'models/glances_stats.dart';

final ProviderFamily<Future<GlancesApi>, Instance> glancesApiProvider =
    Provider.family<Future<GlancesApi>, Instance>(
        (ProviderRef<Future<GlancesApi>> ref, Instance instance) async {
  final DioFactory factory = ref.watch(dioFactoryProvider);
  return GlancesApi(await factory.create(instance));
});

final AutoDisposeFutureProviderFamily<GlancesStats, Instance>
    glancesStatsProvider =
    FutureProvider.autoDispose.family<GlancesStats, Instance>(
        (AutoDisposeFutureProviderRef<GlancesStats> ref, Instance instance) async {
  ref.pollEvery(Duration(seconds: instance.pollingIntervalSeconds));
  final GlancesApi api = await ref.watch(glancesApiProvider(instance));
  return api.getStats();
});
