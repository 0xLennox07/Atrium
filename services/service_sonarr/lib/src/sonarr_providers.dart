import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/sonarr_calendar.dart';
import 'models/sonarr_episode.dart';
import 'models/sonarr_queue.dart';
import 'models/sonarr_release.dart';
import 'models/sonarr_series.dart';
import 'sonarr_api.dart';

/// How often the download queue refreshes while a Sonarr screen is visible.
const Duration sonarrQueuePollInterval = Duration(seconds: 3);

/// How often the series library refreshes. Libraries change rarely, so this
/// is mostly about picking up grabs/imports without a manual pull.
const Duration sonarrLibraryPollInterval = Duration(seconds: 60);

/// A [SonarrApi] bound to a specific instance. Depends on the shared
/// `instanceDioProvider` from core_networking, so it automatically picks up
/// the resolved LAN/WAN base URL and auth.
///
/// The instance's API key (when present) is also threaded through to the
/// client so it can build authenticated mediacover image URLs for
/// `CachedNetworkImage`.
///
/// Deliberately NOT autoDispose: the underlying Dio is shared and cheap to
/// keep; disposing it per-screen would re-run the LAN/WAN probe needlessly.
final sonarrApiProvider =
    FutureProvider.family<SonarrApi, Instance>(
        (Ref ref, Instance instance) async {
  final dio = await ref.watch(instanceDioProvider(instance).future);
  final String? apiKey = switch (instance.auth) {
    InstanceAuthApiKey(:final String apiKey) => apiKey,
    _ => null,
  };
  return SonarrApi(dio, apiKey: apiKey);
});

/// All series for an instance, sorted by title. Polls slowly while watched.
final sonarrSeriesProvider =
    FutureProvider.autoDispose.family<List<SonarrSeries>, Instance>((
  Ref ref,
  Instance instance,
) async {
  ref.pollEvery(sonarrLibraryPollInterval);
  final SonarrApi api = await ref.watch(sonarrApiProvider(instance).future);
  final List<SonarrSeries> series = await api.getSeries();
  series.sort(
    (SonarrSeries a, SonarrSeries b) =>
        a.title.toLowerCase().compareTo(b.title.toLowerCase()),
  );
  return series;
});

/// One series by id. Used by the detail screen; refreshed on demand.
final sonarrSeriesByIdProvider =
    FutureProvider.autoDispose.family<SonarrSeries, (Instance, int)>((
  Ref ref,
  (Instance, int) key,
) async {
  final (Instance instance, int id) = key;
  final SonarrApi api = await ref.watch(sonarrApiProvider(instance).future);
  return api.getSeriesById(id);
});

/// The download queue for an instance. Polls fast while watched.
final sonarrQueueProvider =
    FutureProvider.autoDispose.family<SonarrQueuePage, Instance>((
  Ref ref,
  Instance instance,
) async {
  ref.pollEvery(sonarrQueuePollInterval);
  final SonarrApi api = await ref.watch(sonarrApiProvider(instance).future);
  return api.getQueue();
});

/// The calendar entries for an instance for a given month.
final sonarrCalendarProvider =
    FutureProvider.autoDispose.family<List<SonarrCalendarEntry>, (Instance, DateTime)>((
  Ref ref,
  (Instance, DateTime) key,
) async {
  final (Instance instance, DateTime month) = key;
  final SonarrApi api = await ref.watch(sonarrApiProvider(instance).future);
  
  // Calculate local month boundaries
  final DateTime start = DateTime(month.year, month.month);
  final DateTime end = DateTime(month.year, month.month + 1).subtract(const Duration(seconds: 1));

  final List<SonarrCalendarEntry> entries = await api.getCalendar(
    start: start,
    end: end,
  );

  // Sort entries by UTC air date ascending
  entries.sort((a, b) {
    if (a.airDateUtc == null && b.airDateUtc == null) return 0;
    if (a.airDateUtc == null) return 1;
    if (b.airDateUtc == null) return -1;
    return a.airDateUtc!.compareTo(b.airDateUtc!);
  });

  return entries;
});

/// All episodes for a given series. Auto-dispose, family key is (Instance, seriesId).
final sonarrEpisodesProvider =
    FutureProvider.autoDispose.family<List<SonarrEpisode>, (Instance, int)>((
  Ref ref,
  (Instance, int) key,
) async {
  final (Instance instance, int seriesId) = key;
  final SonarrApi api = await ref.watch(sonarrApiProvider(instance).future);
  return api.getEpisodes(seriesId);
});

/// Fetches releases for a given episode. family key is (Instance, episodeId).
final sonarrReleasesProvider =
    FutureProvider.autoDispose.family<List<SonarrRelease>, (Instance, int)>((
  Ref ref,
  (Instance, int) key,
) async {
  final (Instance instance, int episodeId) = key;
  try {
    final SonarrApi api = await ref.watch(sonarrApiProvider(instance).future);
    return await api.getReleases(episodeId);
  } catch (e, stack) {
    print('Error in sonarrReleasesProvider for episode $episodeId: $e');
    print(stack);
    rethrow;
  }
});

/// Fetches releases for a given season. family key is (Instance, seriesId, seasonNumber).
final sonarrSeasonReleasesProvider =
    FutureProvider.autoDispose.family<List<SonarrRelease>, (Instance, int, int)>((
  Ref ref,
  (Instance, int, int) key,
) async {
  final (Instance instance, int seriesId, int seasonNumber) = key;
  try {
    final SonarrApi api = await ref.watch(sonarrApiProvider(instance).future);
    return await api.getSeasonReleases(seriesId, seasonNumber);
  } catch (e, stack) {
    print('Error in sonarrSeasonReleasesProvider for series $seriesId, season $seasonNumber: $e');
    print(stack);
    rethrow;
  }
});
