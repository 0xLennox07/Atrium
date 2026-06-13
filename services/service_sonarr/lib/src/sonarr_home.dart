import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_series_screen.dart';
import 'models/sonarr_queue.dart';
import 'models/sonarr_series.dart';
import 'series_detail_screen.dart';
import 'sonarr_api.dart';
import 'sonarr_providers.dart';

/// Sonarr's per-instance UI: a tabbed Series / Calendar / Queue view.
///
/// Series tab renders a 2:3 poster grid (Jellyfin-style) with title +
/// episode-progress overlay and a small monitored badge in the top-right
/// corner. Queue tab is unchanged.
///
/// This widget is the entry point the app shell dispatches to for a Sonarr
/// instance and remains the reference pattern other *arr modules follow.
class SonarrHome extends StatelessWidget {
  const SonarrHome({required this.instance, super.key});

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
                Tab(text: 'Series'),
                Tab(text: 'Queue'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _SeriesTab(instance: instance),
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
              builder: (_) => AddSeriesScreen(instance: instance),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
      ),
    );
  }
}

class _SeriesTab extends ConsumerWidget {
  const _SeriesTab({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SonarrSeries>> series =
        ref.watch(sonarrSeriesProvider(instance));
    final SonarrApi? api =
        ref.watch(sonarrApiProvider(instance)).value;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(sonarrSeriesProvider(instance)),
      child: AsyncValueView<List<SonarrSeries>>(
        value: series,
        onRetry: () => ref.invalidate(sonarrSeriesProvider(instance)),
        data: (List<SonarrSeries> list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.live_tv_outlined,
              title: 'No series',
              message: 'This Sonarr has no series yet.',
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
              final SonarrSeries s = list[index];
              final SonarrImage? poster = s.images
                  .firstWhereOrNull((SonarrImage i) => i.coverType == 'poster');
              return _SeriesCard(
                series: s,
                imageUrl: poster == null ? null : api?.posterUrl(poster),
                // Root navigator: branch-navigator pushes get swept by
                // GoRouter shell rebuilds (see qBit detail for history).
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SeriesDetailScreen(
                      instance: instance,
                      seriesId: s.id,
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

/// Poster card for a single series.
///
/// Visual structure mirrors `service_jellyfin`'s `_PosterCard` so that
/// browsing across services feels consistent.
class _SeriesCard extends StatelessWidget {
  const _SeriesCard({
    required this.series,
    required this.imageUrl,
    required this.onTap,
  });

  final SonarrSeries series;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SonarrSeriesStatistics? stats = series.statistics;
    final double progress = (stats == null || stats.totalEpisodeCount == 0)
        ? 0
        : (stats.episodeFileCount / stats.totalEpisodeCount).clamp(0, 1);

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
                if (series.monitored)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _Badge(
                      color: theme.colorScheme.primary,
                      child: Icon(
                        Icons.bookmark,
                        size: 12,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                if (progress > 0.02 && progress < 0.999)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(
                      value: progress.toDouble(),
                      minHeight: 3,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.xs),
        Text(
          series.title,
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
    final SonarrSeriesStatistics? st = series.statistics;
    final List<String> parts = <String>[
      if (series.year != null) '${series.year}',
      if (st != null)
        '${st.episodeFileCount}/${st.totalEpisodeCount} eps',
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
        Icons.live_tv_outlined,
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
    final AsyncValue<SonarrQueuePage> queue =
        ref.watch(sonarrQueueProvider(instance));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(sonarrQueueProvider(instance)),
      child: AsyncValueView<SonarrQueuePage>(
        value: queue,
        onRetry: () => ref.invalidate(sonarrQueueProvider(instance)),
        data: (SonarrQueuePage page) {
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
              final SonarrQueueRecord r = page.records[index];
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
                    final SonarrApi api =
                        await ref.read(sonarrApiProvider(instance).future);
                    await api.deleteQueueItem(r.id);
                    ref.invalidate(sonarrQueueProvider(instance));
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
