import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/prowlarr_indexer.dart';
import 'models/prowlarr_indexer_stats.dart';
import 'prowlarr_api.dart';

/// How often the indexer list and stats refresh while a Prowlarr screen is
/// visible. Indexer config changes rarely; this mostly picks up health and
/// grab/query counters.
const Duration prowlarrPollInterval = Duration(seconds: 60);

/// A [ProwlarrApi] bound to a specific instance.
///
/// Deliberately NOT autoDispose: the underlying Dio is shared and cheap to
/// keep; disposing it per-screen would re-run the LAN/WAN probe needlessly.
final prowlarrApiProvider =
    FutureProvider.family<ProwlarrApi, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final dio = await ref.watch(instanceDioProvider(instance).future);
      return ProwlarrApi(dio);
    });

/// All indexers for an instance, sorted by name. Polls slowly while watched.
final prowlarrIndexersProvider =
    FutureProvider.autoDispose.family<List<ProwlarrIndexer>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      ref.pollEvery(prowlarrPollInterval);
      final ProwlarrApi api = await ref.watch(
        prowlarrApiProvider(instance).future,
      );
      final List<ProwlarrIndexer> indexers = await api.getIndexers();
      indexers.sort(
        (ProwlarrIndexer a, ProwlarrIndexer b) =>
            a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      return indexers;
    });

/// Indexer stats keyed by indexerId, for badge counts in the list. Polls
/// slowly while watched.
final prowlarrStatsByIdProvider =
    FutureProvider.autoDispose
        .family<Map<int, ProwlarrIndexerStat>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      ref.pollEvery(prowlarrPollInterval);
      final ProwlarrApi api = await ref.watch(
        prowlarrApiProvider(instance).future,
      );
      final ProwlarrIndexerStats stats = await api.getIndexerStats();
      return <int, ProwlarrIndexerStat>{
        for (final ProwlarrIndexerStat s in stats.indexers) s.indexerId: s,
      };
    });
