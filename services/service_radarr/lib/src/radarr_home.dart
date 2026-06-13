import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_movie_screen.dart';
import 'models/radarr_movie.dart';
import 'models/radarr_queue.dart';
import 'movie_detail_screen.dart';
import 'radarr_api.dart';
import 'radarr_providers.dart';

/// Radarr's per-instance UI: a tabbed Movies / Queue view. Mirrors
/// `SonarrHome` - the Movies tab is a 2:3 poster grid with a downloaded
/// check overlay and a monitored bookmark badge.
class RadarrHome extends StatelessWidget {
  const RadarrHome({required this.instance, super.key});

  final Instance instance;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        body: Column(
          children: <Widget>[
            const TabBar(
              tabs: <Widget>[
                Tab(text: 'Movies'),
                Tab(text: 'Queue'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _MoviesTab(instance: instance),
                  _QueueTab(instance: instance),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          // Root navigator: see qBit detail history.
          onPressed: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              builder: (_) => AddMovieScreen(instance: instance),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
      ),
    );
  }
}

class _MoviesTab extends ConsumerWidget {
  const _MoviesTab({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RadarrMovie>> movies =
        ref.watch(radarrMoviesProvider(instance));
    final RadarrApi? api = ref.watch(radarrApiProvider(instance)).value;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(radarrMoviesProvider(instance)),
      child: AsyncValueView<List<RadarrMovie>>(
        value: movies,
        onRetry: () => ref.invalidate(radarrMoviesProvider(instance)),
        data: (List<RadarrMovie> list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.movie_outlined,
              title: 'No movies',
              message: 'This Radarr has no movies yet.',
            );
          }
          return GridView.builder(
            padding: Insets.page,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              childAspectRatio: 0.52,
              crossAxisSpacing: Insets.md,
              mainAxisSpacing: Insets.md,
            ),
            itemCount: list.length,
            itemBuilder: (BuildContext context, int index) {
              final RadarrMovie m = list[index];
              final RadarrImage? poster = m.images
                  .firstWhereOrNull((RadarrImage i) => i.coverType == 'poster');
              return _MovieCard(
                movie: m,
                imageUrl: poster == null ? null : api?.posterUrl(poster),
                // Root navigator: branch-navigator pushes get swept by
                // GoRouter shell rebuilds (see qBit detail for history).
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MovieDetailScreen(
                      instance: instance,
                      movieId: m.id,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _MovieCard extends StatelessWidget {
  const _MovieCard({
    required this.movie,
    required this.imageUrl,
    required this.onTap,
  });

  final RadarrMovie movie;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: Radii.card,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: Radii.card,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _Poster(imageUrl: imageUrl, theme: theme),
                if (movie.hasFile)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _Badge(
                      color: theme.colorScheme.primary,
                      child: Icon(
                        Icons.check,
                        size: 12,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  )
                else if (movie.monitored)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _Badge(
                      color: theme.colorScheme.secondaryContainer,
                      child: Icon(
                        Icons.bookmark,
                        size: 12,
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.xs),
        Text(
          movie.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium,
        ),
        Text(
          _subtitle(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
      ),
    );
  }

  String _subtitle() {
    final List<String> parts = <String>[
      if (movie.year != null) '${movie.year}',
      if (movie.hasFile) 'Downloaded' else 'Missing',
    ];
    return parts.join(' • ');
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.imageUrl, required this.theme});

  final String? imageUrl;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.movie_outlined,
        color: theme.colorScheme.outline,
      ),
    );
    if (imageUrl == null) {
      return fallback;
    }
    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      memCacheWidth: 200,
      placeholder: (BuildContext context, String url) =>
          Container(color: theme.colorScheme.surfaceContainerHighest),
      errorWidget: (BuildContext context, String url, Object error) =>
          fallback,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: child,
    );
  }
}

class _QueueTab extends ConsumerWidget {
  const _QueueTab({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RadarrQueuePage> queue =
        ref.watch(radarrQueueProvider(instance));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(radarrQueueProvider(instance)),
      child: AsyncValueView<RadarrQueuePage>(
        value: queue,
        onRetry: () => ref.invalidate(radarrQueueProvider(instance)),
        data: (RadarrQueuePage page) {
          if (page.records.isEmpty) {
            return const EmptyView(
              icon: Icons.download_done_outlined,
              title: 'Queue is empty',
              message: 'Nothing downloading right now.',
            );
          }
          return ListView.builder(
            padding: Insets.pageH,
            itemCount: page.records.length,
            itemBuilder: (BuildContext context, int index) {
              final RadarrQueueRecord r = page.records[index];
              final double progress = r.size <= 0
                  ? 0
                  : ((r.size - r.sizeleft) / r.size).clamp(0, 1).toDouble();
              return ListTile(
                title: Text(
                  r.title ?? 'Item ${r.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SizedBox(height: Insets.xs),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: Insets.xs),
                    Text(
                      <String?>[
                        r.status,
                        if (r.timeleft != null) r.timeleft,
                      ].whereType<String>().join(' • '),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    final RadarrApi api =
                        await ref.read(radarrApiProvider(instance).future);
                    await api.deleteQueueItem(r.id);
                    ref.invalidate(radarrQueueProvider(instance));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
