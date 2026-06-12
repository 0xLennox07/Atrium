import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bazarr_api.dart';
import 'models/bazarr_models.dart';

/// A [BazarrApi] for an instance, over the shared `instanceDioProvider`.
final bazarrApiProvider =
    FutureProvider.family<BazarrApi, Instance>((Ref ref, Instance instance) async {
      final dio = await ref.watch(instanceDioProvider(instance).future);
      return BazarrApi(dio);
    });

/// Summary badge counts for an instance.
final bazarrBadgesProvider =
    FutureProvider.family<BazarrBadges, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
      return api.getBadges();
    });

/// The unified "wanted subtitles" list (episodes + movies) for an instance.
final bazarrWantedProvider =
    FutureProvider.family<List<BazarrWantedRow>, Instance>((
      Ref ref,
      Instance instance,
    ) async {
      final BazarrApi api = await ref.watch(bazarrApiProvider(instance).future);
      final List<BazarrWantedEpisode> eps = await api.getWantedEpisodes();
      final List<BazarrWantedMovie> movies = await api.getWantedMovies();
      return <BazarrWantedRow>[
        for (final BazarrWantedEpisode e in eps)
          BazarrWantedRow(
            title: e.seriesTitle,
            subtitle: <String>[
              if (e.episodeNumber.isNotEmpty) e.episodeNumber,
              if (e.episodeTitle.isNotEmpty) e.episodeTitle,
            ].join(' · '),
            missing: e.missingSubtitles,
            isMovie: false,
          ),
        for (final BazarrWantedMovie m in movies)
          BazarrWantedRow(
            title: m.title,
            subtitle: 'Movie',
            missing: m.missingSubtitles,
            isMovie: true,
          ),
      ];
    });
