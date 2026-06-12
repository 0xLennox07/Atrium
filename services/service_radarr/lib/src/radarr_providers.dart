import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/radarr_movie.dart';
import 'models/radarr_queue.dart';
import 'radarr_api.dart';

/// How often the download queue refreshes while a Radarr screen is visible.
const Duration radarrQueuePollInterval = Duration(seconds: 3);

/// How often the movie library refreshes.
const Duration radarrLibraryPollInterval = Duration(seconds: 60);

/// A [RadarrApi] bound to a specific instance. Depends on the shared
/// `instanceDioProvider` from core_networking, so it picks up the resolved
/// LAN/WAN base URL and auth automatically.
///
/// The instance's API key is also threaded through to the client so it can
/// build authenticated mediacover image URLs for `CachedNetworkImage`.
///
/// Deliberately NOT autoDispose: the underlying Dio is shared and cheap to
/// keep; disposing it per-screen would re-run the LAN/WAN probe needlessly.
final radarrApiProvider =
    FutureProvider.family<RadarrApi, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final dio = await ref.watch(instanceDioProvider(instance).future);
      final String? apiKey = switch (instance.auth) {
        InstanceAuthApiKey(:final String apiKey) => apiKey,
        _ => null,
      };
      return RadarrApi(dio, apiKey: apiKey);
    });

/// All movies for an instance, sorted by title. Polls slowly while watched.
final radarrMoviesProvider =
    FutureProvider.autoDispose.family<List<RadarrMovie>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      ref.pollEvery(radarrLibraryPollInterval);
      final RadarrApi api = await ref.watch(radarrApiProvider(instance).future);
      final List<RadarrMovie> movies = await api.getMovies();
      movies.sort(
        (RadarrMovie a, RadarrMovie b) =>
            a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
      return movies;
    });

/// One movie by id. Used by the detail screen; refreshed on demand.
final radarrMovieByIdProvider =
    FutureProvider.autoDispose.family<RadarrMovie, (Instance, int)>((
      Ref ref,
      (Instance, int) key,
    ) async {
      final (Instance instance, int id) = key;
      final RadarrApi api = await ref.watch(radarrApiProvider(instance).future);
      return api.getMovieById(id);
    });

/// The download queue for an instance. Polls fast while watched.
final radarrQueueProvider =
    FutureProvider.autoDispose.family<RadarrQueuePage, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      ref.pollEvery(radarrQueuePollInterval);
      final RadarrApi api = await ref.watch(radarrApiProvider(instance).future);
      return api.getQueue();
    });
