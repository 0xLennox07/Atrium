import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/tautulli_activity.dart';
import 'models/tautulli_models.dart';
import 'tautulli_api.dart';

/// How often the activity tab refreshes while visible. Streams start, pause,
/// and progress constantly; 10s matches the Tautulli web UI cadence.
const Duration tautulliActivityPollInterval = Duration(seconds: 10);

/// A [TautulliApi] for an instance, over the shared `instanceDioProvider`.
///
/// Deliberately NOT autoDispose: the underlying Dio is shared and cheap to
/// keep; disposing it per-screen would re-run the LAN/WAN probe needlessly.
final tautulliApiProvider =
    FutureProvider.family<TautulliApi, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final dio = await ref.watch(instanceDioProvider(instance).future);
      return TautulliApi(dio);
    });

/// Current activity (active streams). Polls while watched.
final tautulliActivityProvider =
    FutureProvider.autoDispose.family<TautulliActivity, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      ref.pollEvery(tautulliActivityPollInterval);
      final TautulliApi api =
          await ref.watch(tautulliApiProvider(instance).future);
      return api.getActivity();
    });

/// Watch history, newest first. Refreshed on demand (pull-to-refresh).
final tautulliHistoryProvider =
    FutureProvider.autoDispose.family<TautulliHistoryPage, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final TautulliApi api =
          await ref.watch(tautulliApiProvider(instance).future);
      return api.getHistory();
    });

/// Home statistics for the last 30 days. Refreshed on demand.
final tautulliHomeStatsProvider =
    FutureProvider.autoDispose.family<List<TautulliHomeStat>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final TautulliApi api =
          await ref.watch(tautulliApiProvider(instance).future);
      return api.getHomeStats();
    });

/// Users with play counts, most plays first. Refreshed on demand.
final tautulliUsersProvider =
    FutureProvider.autoDispose.family<List<TautulliUser>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final TautulliApi api =
          await ref.watch(tautulliApiProvider(instance).future);
      return api.getUsers();
    });
