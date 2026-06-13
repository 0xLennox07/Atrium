import 'dart:convert';
import 'dart:math' as math;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'add_series_screen.dart';
import 'models/sonarr_blocklist.dart';
import 'models/sonarr_history.dart';
import 'models/sonarr_queue.dart';
import 'models/sonarr_series.dart';
import 'models/sonarr_settings_models.dart';
import 'models/sonarr_system.dart';
import 'models/sonarr_wanted.dart';
import 'series_detail_screen.dart';
import 'sonarr_api.dart';
import 'sonarr_providers.dart';
import 'sonarr_settings_form_screen.dart';

/// Sonarr's per-instance UI: a tabbed Series / Queue / Wanted / History / Blocklist / System view.
class SonarrHome extends StatelessWidget {
  const SonarrHome({required this.instance, super.key});

  final Instance instance;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        body: Column(
          children: <Widget>[
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: <Widget>[
                Tab(text: 'Series'),
                Tab(text: 'Queue'),
                Tab(text: 'Wanted'),
                Tab(text: 'History'),
                Tab(text: 'Blocklist'),
                Tab(text: 'System'),
                Tab(text: 'Settings'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _SeriesTab(instance: instance),
                  _QueueTab(instance: instance),
                  _WantedTab(instance: instance),
                  _HistoryTab(instance: instance),
                  _BlocklistTab(instance: instance),
                  _SystemTab(instance: instance),
                  _SettingsTab(instance: instance),
                ],
              ),
            ),
          ],
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
    return Scaffold(
      body: RefreshIndicator(
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => AddSeriesScreen(instance: instance),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
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

class _WantedTab extends StatefulWidget {
  const _WantedTab({required this.instance});

  final Instance instance;

  @override
  State<_WantedTab> createState() => _WantedTabState();
}

class _WantedTabState extends State<_WantedTab> {
  int _missingPage = 1;
  int _cutoffPage = 1;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: <Widget>[
          const TabBar(
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: <Widget>[
              Tab(text: 'Missing'),
              Tab(text: 'Cutoff Unmet'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _WantedMissingSubTab(
                  instance: widget.instance,
                  page: _missingPage,
                  onPageChanged: (p) => setState(() => _missingPage = p),
                ),
                _WantedCutoffSubTab(
                  instance: widget.instance,
                  page: _cutoffPage,
                  onPageChanged: (p) => setState(() => _cutoffPage = p),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WantedMissingSubTab extends ConsumerWidget {
  const _WantedMissingSubTab({
    required this.instance,
    required this.page,
    required this.onPageChanged,
  });

  final Instance instance;
  final int page;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SonarrWantedPage> missing =
        ref.watch(sonarrWantedMissingProvider((instance, page)));
    final SonarrApi? api = ref.watch(sonarrApiProvider(instance)).value;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(sonarrWantedMissingProvider((instance, page))),
      child: AsyncValueView<SonarrWantedPage>(
        value: missing,
        onRetry: () => ref.invalidate(sonarrWantedMissingProvider((instance, page))),
        data: (SonarrWantedPage dataPage) {
          if (dataPage.records.isEmpty) {
            return const EmptyView(
              icon: Icons.check_circle_outline,
              title: 'No missing episodes',
              message: 'Everything is up to date!',
            );
          }

          final int totalPages = (dataPage.totalRecords / dataPage.pageSize).ceil().clamp(1, double.infinity).toInt();

          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${dataPage.totalRecords} missing episodes',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final apiObj = await ref.read(sonarrApiProvider(instance).future);
                        await apiObj.triggerMissingSearch();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Missing episode search triggered')),
                          );
                        }
                      },
                      icon: const Icon(Icons.search),
                      label: const Text('Search All'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: Insets.pageH,
                  itemCount: dataPage.records.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SonarrWantedRecord record = dataPage.records[index];
                    final poster = record.series?.images.firstWhereOrNull((img) => img.coverType == 'poster');
                    final String? imageUrl = poster != null ? api?.posterUrl(poster) : null;

                    return Card(
                      margin: const EdgeInsets.only(bottom: Insets.sm),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          child: AspectRatio(
                            aspectRatio: Sizes.posterAspect,
                            child: imageUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(color: Colors.grey[800]),
                                    errorWidget: (context, url, err) => Container(color: Colors.grey[800], child: const Icon(Icons.live_tv)),
                                  )
                                : Container(color: Colors.grey[800], child: const Icon(Icons.live_tv)),
                          ),
                        ),
                        title: Text(
                          record.series?.title ?? 'Unknown Series',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'S${record.seasonNumber.toString().padLeft(2, '0')}E${record.episodeNumber.toString().padLeft(2, '0')} • ${record.title ?? ''}\nAir date: ${record.airDate ?? 'Unknown'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: 'Search for this episode',
                          onPressed: () async {
                            final apiObj = await ref.read(sonarrApiProvider(instance).future);
                            await apiObj.searchEpisode(record.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Search triggered for S${record.seasonNumber}E${record.episodeNumber}')),
                              );
                            }
                          },
                        ),
                        onTap: () => Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SeriesDetailScreen(
                              instance: instance,
                              seriesId: record.seriesId,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (totalPages > 1)
                _PaginationBar(
                  currentPage: page,
                  totalPages: totalPages,
                  onPageChanged: onPageChanged,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _WantedCutoffSubTab extends ConsumerWidget {
  const _WantedCutoffSubTab({
    required this.instance,
    required this.page,
    required this.onPageChanged,
  });

  final Instance instance;
  final int page;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SonarrWantedPage> cutoff =
        ref.watch(sonarrWantedCutoffProvider((instance, page)));
    final SonarrApi? api = ref.watch(sonarrApiProvider(instance)).value;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(sonarrWantedCutoffProvider((instance, page))),
      child: AsyncValueView<SonarrWantedPage>(
        value: cutoff,
        onRetry: () => ref.invalidate(sonarrWantedCutoffProvider((instance, page))),
        data: (SonarrWantedPage dataPage) {
          if (dataPage.records.isEmpty) {
            return const EmptyView(
              icon: Icons.check_circle_outline,
              title: 'No cutoff unmet episodes',
              message: 'All episodes meet the cutoff!',
            );
          }

          final int totalPages = (dataPage.totalRecords / dataPage.pageSize).ceil().clamp(1, double.infinity).toInt();

          return Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: Insets.sm),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${dataPage.totalRecords} cutoff unmet episodes',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        final apiObj = await ref.read(sonarrApiProvider(instance).future);
                        await apiObj.triggerCutoffUnmetSearch();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Cutoff unmet search triggered')),
                          );
                        }
                      },
                      icon: const Icon(Icons.search),
                      label: const Text('Search All'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: Insets.pageH,
                  itemCount: dataPage.records.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SonarrWantedRecord record = dataPage.records[index];
                    final poster = record.series?.images.firstWhereOrNull((img) => img.coverType == 'poster');
                    final String? imageUrl = poster != null ? api?.posterUrl(poster) : null;

                    return Card(
                      margin: const EdgeInsets.only(bottom: Insets.sm),
                      clipBehavior: Clip.antiAlias,
                      child: ListTile(
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          child: AspectRatio(
                            aspectRatio: Sizes.posterAspect,
                            child: imageUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: imageUrl,
                                    fit: BoxFit.cover,
                                    placeholder: (context, url) => Container(color: Colors.grey[800]),
                                    errorWidget: (context, url, err) => Container(color: Colors.grey[800], child: const Icon(Icons.live_tv)),
                                  )
                                : Container(color: Colors.grey[800], child: const Icon(Icons.live_tv)),
                          ),
                        ),
                        title: Text(
                          record.series?.title ?? 'Unknown Series',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          'S${record.seasonNumber.toString().padLeft(2, '0')}E${record.episodeNumber.toString().padLeft(2, '0')} • ${record.title ?? ''}\nAir date: ${record.airDate ?? 'Unknown'}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: 'Search for this episode',
                          onPressed: () async {
                            final apiObj = await ref.read(sonarrApiProvider(instance).future);
                            await apiObj.searchEpisode(record.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Search triggered for S${record.seasonNumber}E${record.episodeNumber}')),
                              );
                            }
                          },
                        ),
                        onTap: () => Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SeriesDetailScreen(
                              instance: instance,
                              seriesId: record.seriesId,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (totalPages > 1)
                _PaginationBar(
                  currentPage: page,
                  totalPages: totalPages,
                  onPageChanged: onPageChanged,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _HistoryTab extends ConsumerStatefulWidget {
  const _HistoryTab({required this.instance});

  final Instance instance;

  @override
  ConsumerState<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends ConsumerState<_HistoryTab> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SonarrHistoryPage> history =
        ref.watch(sonarrHistoryProvider((widget.instance, _page)));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(sonarrHistoryProvider((widget.instance, _page))),
      child: AsyncValueView<SonarrHistoryPage>(
        value: history,
        onRetry: () => ref.invalidate(sonarrHistoryProvider((widget.instance, _page))),
        data: (SonarrHistoryPage dataPage) {
          if (dataPage.records.isEmpty) {
            return const EmptyView(
              icon: Icons.history,
              title: 'History is empty',
              message: 'No actions have been logged yet.',
            );
          }

          final int totalPages = (dataPage.totalRecords / dataPage.pageSize).ceil().clamp(1, double.infinity).toInt();

          return Column(
            children: <Widget>[
              Expanded(
                child: ListView.builder(
                  padding: Insets.page,
                  itemCount: dataPage.records.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SonarrHistoryRecord record = dataPage.records[index];
                    final (icon, color) = _getEventVisuals(record.eventType);
                    final String formattedDate = DateFormat.yMMMd().add_jm().format(record.date.toLocal());

                    final String? indexer = record.data['indexer'] as String?;
                    final String? client = record.data['downloadClient'] as String?;
                    final Map<String, dynamic>? qualityMap = record.quality?['quality'] as Map<String, dynamic>?;
                    final String? qualityName = qualityMap?['name'] as String?;

                    final List<String> details = [
                      if (indexer != null) 'Indexer: $indexer',
                      if (client != null) 'Client: $client',
                      if (qualityName != null) 'Quality: $qualityName',
                    ];

                    return Card(
                      margin: const EdgeInsets.only(bottom: Insets.sm),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withValues(alpha: 0.12),
                          child: Icon(icon, color: color),
                        ),
                        title: Text(
                          record.sourceTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: Insets.xxs),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: Insets.xs, vertical: Insets.xxs),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(Radii.sm),
                                  ),
                                  child: Text(
                                    _formatEventType(record.eventType),
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: Insets.sm),
                                Expanded(
                                  child: Text(
                                    formattedDate,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: Theme.of(context).colorScheme.outline,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            if (details.isNotEmpty) ...[
                              const SizedBox(height: Insets.xs),
                              Text(
                                details.join(' • '),
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.outline,
                                    ),
                              ),
                            ],
                          ],
                        ),
                        isThreeLine: true,
                        onTap: () => Navigator.of(context, rootNavigator: true).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SeriesDetailScreen(
                              instance: widget.instance,
                              seriesId: record.seriesId,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (totalPages > 1)
                _PaginationBar(
                  currentPage: _page,
                  totalPages: totalPages,
                  onPageChanged: (p) => setState(() => _page = p),
                ),
            ],
          );
        },
      ),
    );
  }

  (IconData, Color) _getEventVisuals(String eventType) {
    return switch (eventType) {
      'grabbed' => (Icons.downloading, Colors.blue),
      'downloadFolderImported' => (Icons.download_done, Colors.green),
      'episodeFileDeleted' => (Icons.delete_outline, Colors.red),
      'failed' => (Icons.error_outline, Colors.orange),
      _ => (Icons.info_outline, Colors.grey),
    };
  }

  String _formatEventType(String eventType) {
    final matches = RegExp(r'[A-Z]?[a-z]+|[A-Z]+(?=[A-Z]|$)');
    final words = matches.allMatches(eventType).map((m) => m.group(0)!).toList();
    if (words.isEmpty) return eventType;
    return words.map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
  }
}

class _BlocklistTab extends ConsumerStatefulWidget {
  const _BlocklistTab({required this.instance});

  final Instance instance;

  @override
  ConsumerState<_BlocklistTab> createState() => _BlocklistTabState();
}

class _BlocklistTabState extends ConsumerState<_BlocklistTab> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SonarrBlocklistPage> blocklist =
        ref.watch(sonarrBlocklistProvider((widget.instance, _page)));

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(sonarrBlocklistProvider((widget.instance, _page))),
      child: AsyncValueView<SonarrBlocklistPage>(
        value: blocklist,
        onRetry: () => ref.invalidate(sonarrBlocklistProvider((widget.instance, _page))),
        data: (SonarrBlocklistPage dataPage) {
          if (dataPage.records.isEmpty) {
            return const EmptyView(
              icon: Icons.block,
              title: 'Blocklist is empty',
              message: 'No releases have been blocklisted.',
            );
          }

          final int totalPages = (dataPage.totalRecords / dataPage.pageSize).ceil().clamp(1, double.infinity).toInt();

          return Column(
            children: <Widget>[
              Expanded(
                child: ListView.builder(
                  padding: Insets.page,
                  itemCount: dataPage.records.length,
                  itemBuilder: (BuildContext context, int index) {
                    final SonarrBlocklistRecord record = dataPage.records[index];
                    final String formattedDate = record.date != null
                        ? DateFormat.yMMMd().add_jm().format(record.date!.toLocal())
                        : 'Unknown Date';

                    return Card(
                      margin: const EdgeInsets.only(bottom: Insets.sm),
                      child: ListTile(
                        title: Text(
                          record.sourceTitle ?? 'Unknown Release',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: Insets.xs),
                            Text(
                              'Indexer: ${record.indexer ?? 'Unknown'} • Protocol: ${record.protocol ?? 'Unknown'}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            Text(
                              'Blocked: $formattedDate',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (record.message != null && record.message!.isNotEmpty) ...[
                              const SizedBox(height: Insets.xs),
                              Text(
                                'Reason: ${record.message}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.error,
                                    ),
                              ),
                            ],
                          ],
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                          onPressed: () async {
                            final apiObj = await ref.read(sonarrApiProvider(widget.instance).future);
                            await apiObj.deleteBlocklist(record.id);
                            ref.invalidate(sonarrBlocklistProvider((widget.instance, _page)));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Release removed from blocklist')),
                              );
                            }
                          },
                        ),
                        onTap: record.seriesId > 0
                            ? () => Navigator.of(context, rootNavigator: true).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => SeriesDetailScreen(
                                      instance: widget.instance,
                                      seriesId: record.seriesId,
                                    ),
                                  ),
                                )
                            : null,
                      ),
                    );
                  },
                ),
              ),
              if (totalPages > 1)
                _PaginationBar(
                  currentPage: _page,
                  totalPages: totalPages,
                  onPageChanged: (p) => setState(() => _page = p),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SystemTab extends ConsumerWidget {
  const _SystemTab({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SonarrHealth>> health = ref.watch(sonarrHealthProvider(instance));
    final AsyncValue<SonarrSystemStatus> status = ref.watch(sonarrSystemStatusProvider(instance));
    final AsyncValue<List<SonarrDiskSpace>> diskSpace = ref.watch(sonarrDiskSpaceProvider(instance));
    final AsyncValue<List<SonarrSystemTask>> tasks = ref.watch(sonarrSystemTasksProvider(instance));
    final AsyncValue<List<SonarrBackup>> backups = ref.watch(sonarrBackupsProvider(instance));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(sonarrHealthProvider(instance));
        ref.invalidate(sonarrSystemStatusProvider(instance));
        ref.invalidate(sonarrDiskSpaceProvider(instance));
        ref.invalidate(sonarrSystemTasksProvider(instance));
        ref.invalidate(sonarrBackupsProvider(instance));
      },
      child: ListView(
        padding: Insets.page,
        children: <Widget>[
          _HealthWarningsSection(health: health),
          _SystemStatusSection(status: status),
          const SizedBox(height: Insets.lg),
          _DiskSpaceSection(diskSpace: diskSpace),
          const SizedBox(height: Insets.lg),
          _TasksSection(tasks: tasks, instance: instance),
          const SizedBox(height: Insets.lg),
          _BackupsSection(backups: backups, instance: instance),
        ],
      ),
    );
  }
}

class _SystemStatusSection extends StatelessWidget {
  const _SystemStatusSection({required this.status});

  final AsyncValue<SonarrSystemStatus> status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Insets.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('System Status', style: theme.textTheme.titleMedium),
            const Divider(height: Insets.lg),
            AsyncValueView<SonarrSystemStatus>(
              value: status,
              data: (stat) {
                return Column(
                  children: [
                    _infoRow(context, 'Version', stat.version),
                    _infoRow(context, 'OS', '${stat.osName} (${stat.osVersion})'),
                    _infoRow(context, 'Environment', stat.isDocker ? 'Docker' : 'Bare Metal'),
                    if (stat.databaseType != null)
                      _infoRow(context, 'Database', '${stat.databaseType} (v${stat.databaseVersion ?? '?'})'),
                    if (stat.runtimeName != null)
                      _infoRow(context, 'Runtime', '${stat.runtimeName} (${stat.runtimeVersion ?? '?'})'),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiskSpaceSection extends StatelessWidget {
  const _DiskSpaceSection({required this.diskSpace});

  final AsyncValue<List<SonarrDiskSpace>> diskSpace;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Insets.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Disk Space', style: theme.textTheme.titleMedium),
            const Divider(height: Insets.lg),
            AsyncValueView<List<SonarrDiskSpace>>(
              value: diskSpace,
              data: (disks) {
                if (disks.isEmpty) {
                  return const Text('No disk information available');
                }
                return Column(
                  children: disks.map((disk) {
                    final double progress = disk.totalSpace <= 0
                        ? 0
                        : ((disk.totalSpace - disk.freeSpace) / disk.totalSpace).clamp(0, 1);
                    final String freeStr = _formatBytes(disk.freeSpace);
                    final String totalStr = _formatBytes(disk.totalSpace);

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                disk.path,
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'Free: $freeStr / Total: $totalStr',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                              ),
                            ],
                          ),
                          const SizedBox(height: Insets.xs),
                          LinearProgressIndicator(
                            value: progress,
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              progress > 0.9 ? Colors.red : theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (math.log(bytes) / math.log(1024)).floor();
    return '${(bytes / math.pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
  }
}

class _TasksSection extends StatelessWidget {
  const _TasksSection({required this.tasks, required this.instance});

  final AsyncValue<List<SonarrSystemTask>> tasks;
  final Instance instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Insets.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Scheduled Tasks', style: theme.textTheme.titleMedium),
            const Divider(height: Insets.lg),
            AsyncValueView<List<SonarrSystemTask>>(
              value: tasks,
              data: (taskList) {
                if (taskList.isEmpty) {
                  return const Text('No system tasks available');
                }
                return Column(
                  children: taskList.map((task) {
                    final String intervalStr = '${task.interval} min';
                    final String lastRun = task.lastExecution != null
                        ? DateFormat.yMMMd().add_jm().format(task.lastExecution!.toLocal())
                        : 'Never';

                    return Consumer(
                      builder: (context, ref, _) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(task.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                          subtitle: Text(
                            'Interval: $intervalStr\nLast Run: $lastRun',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                          isThreeLine: true,
                          trailing: IconButton(
                            icon: const Icon(Icons.play_arrow),
                            tooltip: 'Run task now',
                            onPressed: () async {
                              final apiObj = await ref.read(sonarrApiProvider(instance).future);
                              await apiObj.runSystemTask(task.taskName);
                              ref.invalidate(sonarrSystemTasksProvider(instance));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Task "${task.name}" triggered')),
                                );
                              }
                            },
                          ),
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.onPageChanged,
  });

  final int currentPage;
  final int totalPages;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm, horizontal: Insets.lg),
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
            ),
            Text(
              'Page $currentPage of $totalPages',
              style: theme.textTheme.bodyMedium,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: currentPage < totalPages ? () => onPageChanged(currentPage + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthWarningsSection extends StatelessWidget {
  const _HealthWarningsSection({required this.health});

  final AsyncValue<List<SonarrHealth>> health;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AsyncValueView<List<SonarrHealth>>(
      value: health,
      data: (healthItems) {
        if (healthItems.isEmpty) return const SizedBox.shrink();
        return Card(
          color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
          margin: const EdgeInsets.only(bottom: Insets.lg),
          child: Padding(
            padding: Insets.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
                    const SizedBox(width: Insets.sm),
                    Text(
                      'System Health Warnings',
                      style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const Divider(),
                ...healthItems.map((item) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                    child: Text(
                      '• ${item.message}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BackupsSection extends StatelessWidget {
  const _BackupsSection({required this.backups, required this.instance});

  final AsyncValue<List<SonarrBackup>> backups;
  final Instance instance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: Insets.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('System Backups', style: theme.textTheme.titleMedium),
                Consumer(
                  builder: (context, ref, _) {
                    return TextButton.icon(
                      icon: const Icon(Icons.backup),
                      label: const Text('Backup Now'),
                      onPressed: () async {
                        final apiObj = await ref.read(sonarrApiProvider(instance).future);
                        await apiObj.runSystemTask('Backup');
                        ref.invalidate(sonarrBackupsProvider(instance));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Backup task triggered')),
                          );
                        }
                      },
                    );
                  },
                ),
              ],
            ),
            const Divider(height: Insets.lg),
            AsyncValueView<List<SonarrBackup>>(
              value: backups,
              data: (backupList) {
                if (backupList.isEmpty) {
                  return const Text('No backups found');
                }
                return Column(
                  children: backupList.map((backup) {
                    final String sizeStr = '${(backup.size / 1024 / 1024).toStringAsFixed(1)} MB';
                    final String timeStr = DateFormat.yMMMd().add_jm().format(backup.time.toLocal());

                    return Consumer(
                      builder: (context, ref, _) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(backup.name, style: theme.textTheme.bodyMedium),
                          subtitle: Text('Size: $sizeStr • Date: $timeStr'),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                            onPressed: () async {
                              final apiObj = await ref.read(sonarrApiProvider(instance).future);
                              await apiObj.deleteBackup(backup.id);
                              ref.invalidate(sonarrBackupsProvider(instance));
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Backup deleted')),
                                );
                              }
                            },
                          ),
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTab extends ConsumerWidget {
  const _SettingsTab({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(sonarrIndexersProvider(instance));
        ref.invalidate(sonarrDownloadClientsProvider(instance));
        ref.invalidate(sonarrNotificationsProvider(instance));
        ref.invalidate(sonarrImportListsProvider(instance));
        ref.invalidate(sonarrTagsProvider(instance));
        ref.invalidate(sonarrHostConfigProvider(instance));
        ref.invalidate(sonarrNamingConfigProvider(instance));
        ref.invalidate(sonarrMediaManagementConfigProvider(instance));
        ref.invalidate(sonarrUiConfigProvider(instance));
        ref.invalidate(sonarrMetadataProvidersProvider(instance));
        ref.invalidate(sonarrDelayProfilesProvider(instance));
        ref.invalidate(sonarrCustomFormatsProvider(instance));
        ref.invalidate(sonarrQualityDefinitionsProvider(instance));
        ref.invalidate(sonarrReleaseProfilesProvider(instance));
        ref.invalidate(sonarrImportListExclusionsProvider(instance));
        ref.invalidate(sonarrAutoTaggingRulesProvider(instance));
        ref.invalidate(sonarrQualityProfilesRawProvider(instance));
        ref.invalidate(sonarrQualityProfilesProvider(instance));
      },
      child: ListView(
        padding: Insets.page,
        children: [
          _IndexerSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _DownloadClientSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _NotificationSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _ImportListSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _TagSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _HostSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _NamingSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _MediaManagementSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _UiSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _MetadataSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _DelayProfileSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _CustomFormatSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _QualityDefinitionSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _QualityProfileSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _ReleaseProfileSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _ImportListExclusionSettingsPanel(instance: instance),
          const SizedBox(height: Insets.md),
          _AutoTaggingSettingsPanel(instance: instance),
        ],
      ),
    );
  }
}

class _IndexerSettingsPanel extends ConsumerWidget {
  const _IndexerSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<List<SonarrIndexer>> indexers = ref.watch(sonarrIndexersProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Indexers', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Indexer',
              onPressed: () {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SonarrSettingsFormScreen(
                      instance: instance,
                      category: 'indexer',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<List<SonarrIndexer>>(
            value: indexers,
            data: (list) {
              if (list.isEmpty) return const Text('No indexers configured.');
              return Column(
                children: list.map((indexer) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Switch(
                      value: indexer.enableRss,
                      onChanged: (val) async {
                        final api = await ref.read(sonarrApiProvider(instance).future);
                        final newRaw = Map<String, dynamic>.of(indexer.raw)..['enableRss'] = val;
                        await api.updateIndexerRaw(newRaw);
                        ref.invalidate(sonarrIndexersProvider(instance));
                      },
                    ),
                    title: Text(indexer.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text('Protocol: ${indexer.protocol}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.science_outlined),
                          tooltip: 'Test Indexer',
                          onPressed: () async {
                            final api = await ref.read(sonarrApiProvider(instance).future);
                            try {
                              await api.testIndexerRaw(indexer.raw);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Indexer test successful!')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Indexer test failed')),
                                );
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit Indexer',
                          onPressed: () {
                            Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SonarrSettingsFormScreen(
                                  instance: instance,
                                  category: 'indexer',
                                  itemRaw: indexer.raw,
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                          tooltip: 'Delete Indexer',
                          onPressed: () async {
                            final api = await ref.read(sonarrApiProvider(instance).future);
                            await api.deleteIndexer(indexer.id);
                            ref.invalidate(sonarrIndexersProvider(instance));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Indexer deleted')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DownloadClientSettingsPanel extends ConsumerWidget {
  const _DownloadClientSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<List<SonarrDownloadClient>> clients = ref.watch(sonarrDownloadClientsProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Download Clients', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Download Client',
              onPressed: () {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SonarrSettingsFormScreen(
                      instance: instance,
                      category: 'downloadclient',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<List<SonarrDownloadClient>>(
            value: clients,
            data: (list) {
              if (list.isEmpty) return const Text('No download clients configured.');
              return Column(
                children: list.map((client) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Switch(
                      value: client.enable,
                      onChanged: (val) async {
                        final api = await ref.read(sonarrApiProvider(instance).future);
                        final newRaw = Map<String, dynamic>.of(client.raw)..['enable'] = val;
                        await api.updateDownloadClientRaw(newRaw);
                        ref.invalidate(sonarrDownloadClientsProvider(instance));
                      },
                    ),
                    title: Text(client.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text('Protocol: ${client.protocol}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.science_outlined),
                          tooltip: 'Test Download Client',
                          onPressed: () async {
                            final api = await ref.read(sonarrApiProvider(instance).future);
                            try {
                              await api.testDownloadClientRaw(client.raw);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Download client test successful!')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Download client test failed')),
                                );
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit Download Client',
                          onPressed: () {
                            Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SonarrSettingsFormScreen(
                                  instance: instance,
                                  category: 'downloadclient',
                                  itemRaw: client.raw,
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                          tooltip: 'Delete Download Client',
                          onPressed: () async {
                            final api = await ref.read(sonarrApiProvider(instance).future);
                            await api.deleteDownloadClient(client.id);
                            ref.invalidate(sonarrDownloadClientsProvider(instance));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Download client deleted')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NotificationSettingsPanel extends ConsumerWidget {
  const _NotificationSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<List<SonarrNotification>> notifications = ref.watch(sonarrNotificationsProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Notifications', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Notification',
              onPressed: () {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SonarrSettingsFormScreen(
                      instance: instance,
                      category: 'notification',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<List<SonarrNotification>>(
            value: notifications,
            data: (list) {
              if (list.isEmpty) return const Text('No notifications configured.');
              return Column(
                children: list.map((notification) {
                  final List<String> activeTriggers = [
                    if (notification.onGrab) 'Grab',
                    if (notification.onDownload) 'Download',
                    if (notification.onUpgrade) 'Upgrade',
                  ];

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(notification.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text('Triggers: ${activeTriggers.isEmpty ? "None" : activeTriggers.join(", ")}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.science_outlined),
                          tooltip: 'Test Notification',
                          onPressed: () async {
                            final api = await ref.read(sonarrApiProvider(instance).future);
                            try {
                              await api.testNotificationRaw(notification.raw);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Notification test successful!')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Notification test failed')),
                                );
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit Notification',
                          onPressed: () {
                            Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SonarrSettingsFormScreen(
                                  instance: instance,
                                  category: 'notification',
                                  itemRaw: notification.raw,
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                          tooltip: 'Delete Notification',
                          onPressed: () async {
                            final api = await ref.read(sonarrApiProvider(instance).future);
                            await api.deleteNotification(notification.id);
                            ref.invalidate(sonarrNotificationsProvider(instance));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Notification deleted')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ImportListSettingsPanel extends ConsumerWidget {
  const _ImportListSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<List<SonarrImportList>> lists = ref.watch(sonarrImportListsProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Import Lists', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Import List',
              onPressed: () {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SonarrSettingsFormScreen(
                      instance: instance,
                      category: 'importlist',
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<List<SonarrImportList>>(
            value: lists,
            data: (list) {
              if (list.isEmpty) return const Text('No import lists configured.');
              return Column(
                children: list.map((importList) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Switch(
                      value: importList.enable,
                      onChanged: (val) async {
                        final api = await ref.read(sonarrApiProvider(instance).future);
                        final newRaw = Map<String, dynamic>.of(importList.raw)..['enable'] = val;
                        await api.updateImportListRaw(newRaw);
                        ref.invalidate(sonarrImportListsProvider(instance));
                      },
                    ),
                    title: Text(importList.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.science_outlined),
                          tooltip: 'Test Import List',
                          onPressed: () async {
                            final api = await ref.read(sonarrApiProvider(instance).future);
                            try {
                              await api.testImportListRaw(importList.raw);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Import list test successful!')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Import list test failed')),
                                );
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit Import List',
                          onPressed: () {
                            Navigator.of(context, rootNavigator: true).push(
                              MaterialPageRoute<void>(
                                builder: (_) => SonarrSettingsFormScreen(
                                  instance: instance,
                                  category: 'importlist',
                                  itemRaw: importList.raw,
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                          tooltip: 'Delete Import List',
                          onPressed: () async {
                            final api = await ref.read(sonarrApiProvider(instance).future);
                            await api.deleteImportList(importList.id);
                            ref.invalidate(sonarrImportListsProvider(instance));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Import list deleted')),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TagSettingsPanel extends ConsumerWidget {
  const _TagSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<List<SonarrTag>> tags = ref.watch(sonarrTagsProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Tags', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Tag',
              onPressed: () => _showAddTagDialog(context, ref),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<List<SonarrTag>>(
            value: tags,
            data: (tagList) {
              if (tagList.isEmpty) return const Text('No tags created yet.');
              return Wrap(
                spacing: Insets.sm,
                runSpacing: Insets.sm,
                children: tagList.map((tag) {
                  return Chip(
                    label: Text(tag.label),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () async {
                      final api = await ref.read(sonarrApiProvider(instance).future);
                      await api.deleteTag(tag.id);
                      ref.invalidate(sonarrTagsProvider(instance));
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddTagDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Tag'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Tag Label'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final label = controller.text.trim();
                if (label.isNotEmpty) {
                  final api = await ref.read(sonarrApiProvider(instance).future);
                  await api.createTag(label);
                  ref.invalidate(sonarrTagsProvider(instance));
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}

class _HostSettingsPanel extends ConsumerWidget {
  const _HostSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<SonarrHostConfig> config = ref.watch(sonarrHostConfigProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Text('General / Host Settings', style: theme.textTheme.titleMedium),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<SonarrHostConfig>(
            value: config,
            data: (c) => _HostSettingsForm(instance: instance, config: c),
          ),
        ],
      ),
    );
  }
}

class _HostSettingsForm extends ConsumerStatefulWidget {
  const _HostSettingsForm({required this.instance, required this.config});

  final Instance instance;
  final SonarrHostConfig config;

  @override
  ConsumerState<_HostSettingsForm> createState() => _HostSettingsFormState();
}

class _HostSettingsFormState extends ConsumerState<_HostSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _portController;
  late final TextEditingController _branchController;
  late final TextEditingController _backupIntervalController;
  late final TextEditingController _backupRetentionController;
  late String _logLevel;
  late bool _enableSsl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _portController = TextEditingController(text: widget.config.port.toString());
    _branchController = TextEditingController(text: widget.config.branch);
    _backupIntervalController = TextEditingController(text: widget.config.backupInterval.toString());
    _backupRetentionController = TextEditingController(text: widget.config.backupRetention.toString());
    _logLevel = widget.config.logLevel;
    _enableSsl = widget.config.enableSsl;
  }

  @override
  void dispose() {
    _portController.dispose();
    _branchController.dispose();
    _backupIntervalController.dispose();
    _backupRetentionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final api = await ref.read(sonarrApiProvider(widget.instance).future);
    final newRaw = Map<String, dynamic>.of(widget.config.raw)
      ..['port'] = int.tryParse(_portController.text) ?? widget.config.port
      ..['branch'] = _branchController.text.trim()
      ..['backupInterval'] = int.tryParse(_backupIntervalController.text) ?? widget.config.backupInterval
      ..['backupRetention'] = int.tryParse(_backupRetentionController.text) ?? widget.config.backupRetention
      ..['logLevel'] = _logLevel
      ..['enableSsl'] = _enableSsl;

    try {
      await api.updateHostConfigRaw(newRaw);
      ref.invalidate(sonarrHostConfigProvider(widget.instance));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Host settings saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save settings: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _portController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Server Port',
              border: OutlineInputBorder(),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Required';
              if (int.tryParse(val) == null) return 'Must be a valid integer';
              return null;
            },
          ),
          const SizedBox(height: Insets.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable SSL'),
            value: _enableSsl,
            onChanged: (val) => setState(() => _enableSsl = val),
          ),
          const SizedBox(height: Insets.sm),
          DropdownButtonFormField<String>(
            initialValue: _logLevel,
            decoration: const InputDecoration(
              labelText: 'Log Level',
              border: OutlineInputBorder(),
            ),
            items: ['trace', 'debug', 'info', 'warn', 'error'].map((level) {
              return DropdownMenuItem<String>(
                value: level,
                child: Text(level.toUpperCase()),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _logLevel = val);
              }
            },
          ),
          const SizedBox(height: Insets.md),
          TextFormField(
            controller: _branchController,
            decoration: const InputDecoration(
              labelText: 'Update Branch',
              border: OutlineInputBorder(),
            ),
            validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: Insets.md),
          TextFormField(
            controller: _backupIntervalController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Backup Interval (days)',
              border: OutlineInputBorder(),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Required';
              if (int.tryParse(val) == null) return 'Must be a valid integer';
              return null;
            },
          ),
          const SizedBox(height: Insets.md),
          TextFormField(
            controller: _backupRetentionController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Backup Retention (backups)',
              border: OutlineInputBorder(),
            ),
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Required';
              if (int.tryParse(val) == null) return 'Must be a valid integer';
              return null;
            },
          ),
          const SizedBox(height: Insets.lg),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}

class _NamingSettingsPanel extends ConsumerWidget {
  const _NamingSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<SonarrNamingConfig> config = ref.watch(sonarrNamingConfigProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Text('Episode Naming', style: theme.textTheme.titleMedium),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<SonarrNamingConfig>(
            value: config,
            data: (c) => _NamingSettingsForm(instance: instance, config: c),
          ),
        ],
      ),
    );
  }
}

class _NamingSettingsForm extends ConsumerStatefulWidget {
  const _NamingSettingsForm({required this.instance, required this.config});

  final Instance instance;
  final SonarrNamingConfig config;

  @override
  ConsumerState<_NamingSettingsForm> createState() => _NamingSettingsFormState();
}

class _NamingSettingsFormState extends ConsumerState<_NamingSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _standardFormatController;
  late final TextEditingController _dailyFormatController;
  late final TextEditingController _animeFormatController;
  late final TextEditingController _seriesFolderFormatController;
  late bool _renameEpisodes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _standardFormatController = TextEditingController(text: widget.config.standardEpisodeFormat);
    _dailyFormatController = TextEditingController(text: widget.config.dailyEpisodeFormat);
    _animeFormatController = TextEditingController(text: widget.config.animeEpisodeFormat);
    _seriesFolderFormatController = TextEditingController(text: widget.config.seriesFolderFormat);
    _renameEpisodes = widget.config.renameEpisodes;
  }

  @override
  void dispose() {
    _standardFormatController.dispose();
    _dailyFormatController.dispose();
    _animeFormatController.dispose();
    _seriesFolderFormatController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final api = await ref.read(sonarrApiProvider(widget.instance).future);
    final newRaw = Map<String, dynamic>.of(widget.config.raw)
      ..['renameEpisodes'] = _renameEpisodes
      ..['standardEpisodeFormat'] = _standardFormatController.text.trim()
      ..['dailyEpisodeFormat'] = _dailyFormatController.text.trim()
      ..['animeEpisodeFormat'] = _animeFormatController.text.trim()
      ..['seriesFolderFormat'] = _seriesFolderFormatController.text.trim();

    try {
      await api.updateNamingConfigRaw(newRaw);
      ref.invalidate(sonarrNamingConfigProvider(widget.instance));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Naming settings saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save settings: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Rename Episodes'),
            value: _renameEpisodes,
            onChanged: (val) => setState(() => _renameEpisodes = val),
          ),
          const SizedBox(height: Insets.sm),
          TextFormField(
            controller: _standardFormatController,
            decoration: const InputDecoration(
              labelText: 'Standard Episode Format',
              border: OutlineInputBorder(),
            ),
            validator: (val) => (_renameEpisodes && (val == null || val.trim().isEmpty)) ? 'Required when Rename is enabled' : null,
          ),
          const SizedBox(height: Insets.md),
          TextFormField(
            controller: _dailyFormatController,
            decoration: const InputDecoration(
              labelText: 'Daily Episode Format',
              border: OutlineInputBorder(),
            ),
            validator: (val) => (_renameEpisodes && (val == null || val.trim().isEmpty)) ? 'Required when Rename is enabled' : null,
          ),
          const SizedBox(height: Insets.md),
          TextFormField(
            controller: _animeFormatController,
            decoration: const InputDecoration(
              labelText: 'Anime Episode Format',
              border: OutlineInputBorder(),
            ),
            validator: (val) => (_renameEpisodes && (val == null || val.trim().isEmpty)) ? 'Required when Rename is enabled' : null,
          ),
          const SizedBox(height: Insets.md),
          TextFormField(
            controller: _seriesFolderFormatController,
            decoration: const InputDecoration(
              labelText: 'Series Folder Format',
              border: OutlineInputBorder(),
            ),
            validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: Insets.lg),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}

class _MediaManagementSettingsPanel extends ConsumerWidget {
  const _MediaManagementSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<SonarrMediaManagementConfig> config = ref.watch(sonarrMediaManagementConfigProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Text('Media Management', style: theme.textTheme.titleMedium),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<SonarrMediaManagementConfig>(
            value: config,
            data: (c) => _MediaManagementSettingsForm(instance: instance, config: c),
          ),
        ],
      ),
    );
  }
}

class _MediaManagementSettingsForm extends ConsumerStatefulWidget {
  const _MediaManagementSettingsForm({required this.instance, required this.config});

  final Instance instance;
  final SonarrMediaManagementConfig config;

  @override
  ConsumerState<_MediaManagementSettingsForm> createState() => _MediaManagementSettingsFormState();
}

class _MediaManagementSettingsFormState extends ConsumerState<_MediaManagementSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late bool _autoUnmonitor;
  late String _downloadPropers;
  late bool _createEmptySeriesFolders;
  late bool _deleteEmptyFolders;
  late bool _copyUsingHardlinks;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _autoUnmonitor = widget.config.autoUnmonitorPreviouslyDownloadedEpisodes;
    _downloadPropers = widget.config.downloadPropersAndRepacks;
    _createEmptySeriesFolders = widget.config.createEmptySeriesFolders;
    _deleteEmptyFolders = widget.config.deleteEmptyFolders;
    _copyUsingHardlinks = widget.config.copyUsingHardlinks;
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final api = await ref.read(sonarrApiProvider(widget.instance).future);
    final newRaw = Map<String, dynamic>.of(widget.config.raw)
      ..['autoUnmonitorPreviouslyDownloadedEpisodes'] = _autoUnmonitor
      ..['downloadPropersAndRepacks'] = _downloadPropers
      ..['createEmptySeriesFolders'] = _createEmptySeriesFolders
      ..['deleteEmptyFolders'] = _deleteEmptyFolders
      ..['copyUsingHardlinks'] = _copyUsingHardlinks;

    try {
      await api.updateMediaManagementConfigRaw(newRaw);
      ref.invalidate(sonarrMediaManagementConfigProvider(widget.instance));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Media management settings saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save settings: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto Unmonitor Downloaded'),
            value: _autoUnmonitor,
            onChanged: (val) => setState(() => _autoUnmonitor = val),
          ),
          DropdownButtonFormField<String>(
            initialValue: _downloadPropers,
            decoration: const InputDecoration(
              labelText: 'Download Propers & Repacks',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'preferAndUpgrade',
                child: Text('Prefer and Upgrade'),
              ),
              DropdownMenuItem(
                value: 'doNotUpgrade',
                child: Text('Do Not Upgrade'),
              ),
              DropdownMenuItem(
                value: 'doNotPrefer',
                child: Text('Do Not Prefer'),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _downloadPropers = val);
              }
            },
          ),
          const SizedBox(height: Insets.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Create Empty Series Folders'),
            value: _createEmptySeriesFolders,
            onChanged: (val) => setState(() => _createEmptySeriesFolders = val),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Delete Empty Folders'),
            value: _deleteEmptyFolders,
            onChanged: (val) => setState(() => _deleteEmptyFolders = val),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Use Hardlinks instead of Copy'),
            value: _copyUsingHardlinks,
            onChanged: (val) => setState(() => _copyUsingHardlinks = val),
          ),
          const SizedBox(height: Insets.lg),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}

class _UiSettingsPanel extends ConsumerWidget {
  const _UiSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<SonarrUiConfig> config = ref.watch(sonarrUiConfigProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Text('UI Configuration', style: theme.textTheme.titleMedium),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<SonarrUiConfig>(
            value: config,
            data: (c) => _UiSettingsForm(instance: instance, config: c),
          ),
        ],
      ),
    );
  }
}

class _UiSettingsForm extends ConsumerStatefulWidget {
  const _UiSettingsForm({required this.instance, required this.config});

  final Instance instance;
  final SonarrUiConfig config;

  @override
  ConsumerState<_UiSettingsForm> createState() => _UiSettingsFormState();
}

class _UiSettingsFormState extends ConsumerState<_UiSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  late String _theme;
  late String _timeFormat;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _theme = widget.config.theme;

    // Normalize timeFormat dropdown value
    final currentFormat = widget.config.timeFormat;
    if (currentFormat.contains('a') || currentFormat.contains('t')) {
      _timeFormat = 'h:mm a';
    } else {
      _timeFormat = 'HH:mm';
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final api = await ref.read(sonarrApiProvider(widget.instance).future);
    final newRaw = Map<String, dynamic>.of(widget.config.raw)
      ..['theme'] = _theme
      ..['timeFormat'] = _timeFormat;

    try {
      await api.updateUiConfigRaw(newRaw);
      ref.invalidate(sonarrUiConfigProvider(widget.instance));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('UI settings saved successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save settings: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _theme,
            decoration: const InputDecoration(
              labelText: 'Theme',
              border: OutlineInputBorder(),
            ),
            items: ['auto', 'dark', 'light'].map((themeName) {
              return DropdownMenuItem<String>(
                value: themeName,
                child: Text(themeName.toUpperCase()),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() => _theme = val);
              }
            },
          ),
          const SizedBox(height: Insets.md),
          DropdownButtonFormField<String>(
            initialValue: _timeFormat,
            decoration: const InputDecoration(
              labelText: 'Time Format',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'h:mm a', child: Text('12h')),
              DropdownMenuItem(value: 'HH:mm', child: Text('24h')),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() => _timeFormat = val);
              }
            },
          ),
          const SizedBox(height: Insets.lg),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }
}

class _MetadataSettingsPanel extends ConsumerWidget {
  const _MetadataSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<List<SonarrMetadataProvider>> providers = ref.watch(sonarrMetadataProvidersProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Text('Metadata Consumers', style: theme.textTheme.titleMedium),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<List<SonarrMetadataProvider>>(
            value: providers,
            data: (list) {
              if (list.isEmpty) return const Text('No metadata consumers.');
              return Column(
                children: list.map((provider) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Switch(
                      value: provider.enable,
                      onChanged: (val) async {
                        final api = await ref.read(sonarrApiProvider(instance).future);
                        final newRaw = Map<String, dynamic>.of(provider.raw)..['enable'] = val;
                        await api.updateMetadataProviderRaw(newRaw);
                        ref.invalidate(sonarrMetadataProvidersProvider(instance));
                      },
                    ),
                    title: Text(provider.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.science_outlined),
                          tooltip: 'Test Metadata Consumer',
                          onPressed: () async {
                            final api = await ref.read(sonarrApiProvider(instance).future);
                            try {
                              await api.testMetadataProviderRaw(provider.raw);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Metadata consumer test successful!')),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Metadata consumer test failed')),
                                );
                              }
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DelayProfileSettingsPanel extends ConsumerWidget {
  const _DelayProfileSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<List<SonarrDelayProfile>> profiles = ref.watch(sonarrDelayProfilesProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Text('Delay Profiles', style: theme.textTheme.titleMedium),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<List<SonarrDelayProfile>>(
            value: profiles,
            data: (list) {
              if (list.isEmpty) return const Text('No delay profiles configured.');
              return Column(
                children: list.map((profile) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable Torrent Delay'),
                        value: profile.enableTorrent,
                        onChanged: (val) async {
                          final api = await ref.read(sonarrApiProvider(instance).future);
                          final newRaw = Map<String, dynamic>.of(profile.raw)..['enableTorrent'] = val;
                          await api.updateDelayProfileRaw(newRaw);
                          ref.invalidate(sonarrDelayProfilesProvider(instance));
                        },
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable Usenet Delay'),
                        value: profile.enableUsenet,
                        onChanged: (val) async {
                          final api = await ref.read(sonarrApiProvider(instance).future);
                          final newRaw = Map<String, dynamic>.of(profile.raw)..['enableUsenet'] = val;
                          await api.updateDelayProfileRaw(newRaw);
                          ref.invalidate(sonarrDelayProfilesProvider(instance));
                        },
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Preferred Protocol'),
                        trailing: DropdownButton<String>(
                          value: profile.preferredProtocol,
                          items: ['usenet', 'torrent'].map((protocol) {
                            return DropdownMenuItem<String>(
                              value: protocol,
                              child: Text(protocol.toUpperCase()),
                            );
                          }).toList(),
                          onChanged: (val) async {
                            if (val != null) {
                              final api = await ref.read(sonarrApiProvider(instance).future);
                              final newRaw = Map<String, dynamic>.of(profile.raw)..['preferredProtocol'] = val;
                              await api.updateDelayProfileRaw(newRaw);
                              ref.invalidate(sonarrDelayProfilesProvider(instance));
                            }
                          },
                        ),
                      ),
                      const Divider(),
                    ],
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CustomFormatSettingsPanel extends ConsumerWidget {
  const _CustomFormatSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<List<SonarrCustomFormat>> formats = ref.watch(sonarrCustomFormatsProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Text('Custom Formats', style: theme.textTheme.titleMedium),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<List<SonarrCustomFormat>>(
            value: formats,
            data: (list) {
              if (list.isEmpty) return const Text('No custom formats configured.');
              return Column(
                children: list.map((format) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(format.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                      tooltip: 'Delete Custom Format',
                      onPressed: () async {
                        final api = await ref.read(sonarrApiProvider(instance).future);
                        await api.deleteCustomFormat(format.id);
                        ref.invalidate(sonarrCustomFormatsProvider(instance));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Custom format deleted')),
                          );
                        }
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QualityDefinitionSettingsPanel extends ConsumerWidget {
  const _QualityDefinitionSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<List<SonarrQualityDefinition>> definitions = ref.watch(sonarrQualityDefinitionsProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Text('Quality Definitions', style: theme.textTheme.titleMedium),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<List<SonarrQualityDefinition>>(
            value: definitions,
            data: (list) {
              if (list.isEmpty) return const Text('No quality definitions.');
              return Column(
                children: list.map((def) {
                  return _QualityDefinitionRow(instance: instance, definition: def);
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _QualityDefinitionRow extends ConsumerStatefulWidget {
  const _QualityDefinitionRow({required this.instance, required this.definition});

  final Instance instance;
  final SonarrQualityDefinition definition;

  @override
  ConsumerState<_QualityDefinitionRow> createState() => _QualityDefinitionRowState();
}

class _QualityDefinitionRowState extends ConsumerState<_QualityDefinitionRow> {
  late double _min;
  late double _max;
  late double _preferred;
  late bool _isUnlimited;
  bool _saving = false;
  late double _sliderMax;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    _min = widget.definition.minSize;
    final rawMax = widget.definition.raw['maxSize'];
    _isUnlimited = rawMax == null || rawMax == 0.0 || widget.definition.maxSize == 0.0;
    _max = _isUnlimited ? 400.0 : widget.definition.maxSize;
    _preferred = widget.definition.preferredSize;
    _sliderMax = 400.0;
    if (!_isUnlimited && widget.definition.maxSize > _sliderMax) {
      _sliderMax = widget.definition.maxSize;
    }
    if (widget.definition.minSize > _sliderMax) {
      _sliderMax = widget.definition.minSize;
    }
    if (widget.definition.preferredSize > _sliderMax) {
      _sliderMax = widget.definition.preferredSize;
    }
    if (_sliderMax <= _min) {
      _sliderMax = _min + 10.0;
    }
  }

  @override
  void didUpdateWidget(covariant _QualityDefinitionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.definition != widget.definition) {
      _reset();
    }
  }

  bool get _hasChanges {
    final double origMin = widget.definition.minSize;
    final double origPref = widget.definition.preferredSize;
    final bool origUnlimited = widget.definition.raw['maxSize'] == null || widget.definition.raw['maxSize'] == 0.0 || widget.definition.maxSize == 0.0;
    final double origMax = origUnlimited ? 400.0 : widget.definition.maxSize;

    return _min != origMin || _preferred != origPref || _isUnlimited != origUnlimited || (!_isUnlimited && _max != origMax);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final api = await ref.read(sonarrApiProvider(widget.instance).future);
    final double targetMax = _isUnlimited ? 0.0 : _max;

    final newRaw = Map<String, dynamic>.of(widget.definition.raw)
      ..['minSize'] = _min
      ..['maxSize'] = targetMax
      ..['preferredSize'] = _preferred;

    try {
      await api.updateQualityDefinitionRaw(newRaw);
      ref.invalidate(sonarrQualityDefinitionsProvider(widget.instance));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Quality definition ${widget.definition.name} saved!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save quality definition: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final String minLabel = '${_min.toStringAsFixed(1)} MB/h';
    final String maxLabel = _isUnlimited ? 'Unlimited' : '${_max.toStringAsFixed(1)} MB/h';
    final String preferredLabel = '${_preferred.toStringAsFixed(1)} MB/h';

    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Material(
      color: isDark ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _hasChanges ? theme.colorScheme.primary.withValues(alpha: 0.5) : theme.colorScheme.outlineVariant,
          width: _hasChanges ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.definition.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _hasChanges ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                  ),
                ),
                Row(
                  children: [
                    if (_hasChanges && !_saving)
                      IconButton(
                        icon: const Icon(Icons.undo, size: 20),
                        tooltip: 'Discard changes',
                        onPressed: () => setState(_reset),
                      ),
                    if (_saving)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else if (_hasChanges)
                      IconButton(
                        icon: Icon(Icons.check, color: theme.colorScheme.primary, size: 20),
                        tooltip: 'Save changes',
                        onPressed: _save,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: Insets.md,
              children: [
                _InfoLabel(label: 'Min', value: minLabel, color: theme.colorScheme.outline),
                _InfoLabel(label: 'Preferred', value: preferredLabel, color: theme.colorScheme.primary),
                _InfoLabel(label: 'Max', value: maxLabel, color: _isUnlimited ? Colors.green : theme.colorScheme.outline),
              ],
            ),
            const SizedBox(height: Insets.md),
            if (_isUnlimited) ...[
              Text('Minimum Size', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              Slider(
                value: _min,
                max: _sliderMax,
                onChanged: (val) {
                  setState(() {
                    _min = val;
                    if (_preferred < _min) _preferred = _min;
                  });
                },
              ),
            ] else ...[
              Text('Size Range (Min - Max)', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
              RangeSlider(
                values: RangeValues(_min, _max),
                max: _sliderMax,
                onChanged: (vals) {
                  setState(() {
                    _min = vals.start;
                    _max = vals.end;
                    if (_preferred < _min) _preferred = _min;
                    if (_preferred > _max) _preferred = _max;
                  });
                },
              ),
            ],
            const SizedBox(height: Insets.xs),
            Text('Preferred Size', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
            Slider(
              value: _preferred,
              min: _min,
              max: _isUnlimited ? _sliderMax : _max,
              onChanged: (val) {
                setState(() {
                  _preferred = val;
                });
              },
            ),
            const SizedBox(height: Insets.xs),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Unlimited Max Size', style: theme.textTheme.bodyMedium),
              value: _isUnlimited,
              onChanged: (val) {
                setState(() {
                  _isUnlimited = val ?? false;
                  if (!_isUnlimited) {
                    _max = _preferred;
                  }
                });
              },
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _InfoLabel extends StatelessWidget {
  const _InfoLabel({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
        Text(value, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}

class _ReleaseProfileSettingsPanel extends ConsumerWidget {
  const _ReleaseProfileSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<List<SonarrReleaseProfile>> profiles = ref.watch(sonarrReleaseProfilesProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Release Profiles', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Release Profile',
              onPressed: () => _showAddProfileDialog(context, ref),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<List<SonarrReleaseProfile>>(
            value: profiles,
            data: (list) {
              if (list.isEmpty) return const Text('No release profiles configured.');
              return Column(
                children: list.map((profile) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Switch(
                      value: profile.enabled,
                      onChanged: (val) async {
                        final api = await ref.read(sonarrApiProvider(instance).future);
                        final newRaw = Map<String, dynamic>.of(profile.raw)..['enabled'] = val;
                        await api.updateReleaseProfileRaw(newRaw);
                        ref.invalidate(sonarrReleaseProfilesProvider(instance));
                      },
                    ),
                    title: Text(profile.name.isEmpty ? 'Unnamed Release Profile' : profile.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text('Required: ${profile.requiredTerms.length} • Ignored: ${profile.ignoredTerms.length} • Preferred: ${profile.preferredTerms.length}'),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                      onPressed: () async {
                        final api = await ref.read(sonarrApiProvider(instance).future);
                        await api.deleteReleaseProfile(profile.id);
                        ref.invalidate(sonarrReleaseProfilesProvider(instance));
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddProfileDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Release Profile'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Profile Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final api = await ref.read(sonarrApiProvider(instance).future);
                  await api.createReleaseProfileRaw(<String, dynamic>{
                    'name': name,
                    'enabled': true,
                    'required': <dynamic>[],
                    'ignored': <dynamic>[],
                    'preferred': <dynamic>[],
                    'tags': <dynamic>[],
                  });
                  ref.invalidate(sonarrReleaseProfilesProvider(instance));
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}

class _ImportListExclusionSettingsPanel extends ConsumerWidget {
  const _ImportListExclusionSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<List<SonarrImportListExclusion>> exclusions = ref.watch(sonarrImportListExclusionsProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Import List Exclusions', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Exclusion',
              onPressed: () => _showAddExclusionDialog(context, ref),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<List<SonarrImportListExclusion>>(
            value: exclusions,
            data: (list) {
              if (list.isEmpty) return const Text('No exclusions configured.');
              return Column(
                children: list.map((exclusion) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(exclusion.title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text('TVDB ID: ${exclusion.tvdbId}'),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                      onPressed: () async {
                        final api = await ref.read(sonarrApiProvider(instance).future);
                        await api.deleteImportListExclusion(exclusion.id);
                        ref.invalidate(sonarrImportListExclusionsProvider(instance));
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddExclusionDialog(BuildContext context, WidgetRef ref) {
    final titleController = TextEditingController();
    final tvdbController = TextEditingController();

    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Import List Exclusion'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Series Title'),
                autofocus: true,
              ),
              TextField(
                controller: tvdbController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'TVDB ID'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final title = titleController.text.trim();
                final tvdbId = int.tryParse(tvdbController.text.trim()) ?? 0;
                if (title.isNotEmpty && tvdbId > 0) {
                  final api = await ref.read(sonarrApiProvider(instance).future);
                  await api.createImportListExclusionRaw(<String, dynamic>{
                    'title': title,
                    'tvdbId': tvdbId,
                  });
                  ref.invalidate(sonarrImportListExclusionsProvider(instance));
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}

class _AutoTaggingSettingsPanel extends ConsumerWidget {
  const _AutoTaggingSettingsPanel({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<List<SonarrAutoTaggingRule>> rules = ref.watch(sonarrAutoTaggingRulesProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Auto Tagging Rules', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Auto Tagging Rule',
              onPressed: () => _showAddRuleDialog(context, ref),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<List<SonarrAutoTaggingRule>>(
            value: rules,
            data: (list) {
              if (list.isEmpty) return const Text('No auto tagging rules.');
              return Column(
                children: list.map((rule) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(rule.name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text('Specifications: ${rule.specifications.length} • Tags: ${rule.tags.length}'),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                      onPressed: () async {
                        final api = await ref.read(sonarrApiProvider(instance).future);
                        await api.deleteAutoTaggingRule(rule.id);
                        ref.invalidate(sonarrAutoTaggingRulesProvider(instance));
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddRuleDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add Auto Tagging Rule'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Rule Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isNotEmpty) {
                  final api = await ref.read(sonarrApiProvider(instance).future);
                  await api.createAutoTaggingRuleRaw(<String, dynamic>{
                    'name': name,
                    'tags': <dynamic>[],
                    'specifications': <dynamic>[],
                  });
                  ref.invalidate(sonarrAutoTaggingRulesProvider(instance));
                }
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
  }
}

class _QualityProfileSettingsPanel extends ConsumerWidget {
  const _QualityProfileSettingsPanel({required this.instance});

  final Instance instance;

  List<Map<String, dynamic>> _getAllowedQualities(List<dynamic> items) {
    final List<Map<String, dynamic>> list = [];
    void helper(List<dynamic> listItems) {
      for (final dynamic item in listItems) {
        final Map<String, dynamic> itemMap = item as Map<String, dynamic>;
        final List<dynamic>? nested = itemMap['items'] as List<dynamic>?;
        if (nested != null && nested.isNotEmpty) {
          helper(nested);
        } else {
          if (itemMap['allowed'] == true) {
            list.add(itemMap);
          }
        }
      }
    }
    helper(items);
    return list;
  }

  Widget _buildQualityItemTile(BuildContext context, Map<String, dynamic> item, StateSetter setState, {bool readOnly = false}) {
    final List<dynamic>? nestedItems = item['items'] as List<dynamic>?;
    final String name = (item['name'] as String?) ?? '';
    final bool allowed = (item['allowed'] as bool?) ?? false;

    if (nestedItems != null && nestedItems.isNotEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        child: ExpansionTile(
          initiallyExpanded: readOnly,
          title: Row(
            children: [
              Checkbox(
                value: allowed,
                onChanged: readOnly ? null : (val) {
                  setState(() {
                    item['allowed'] = val ?? false;
                    for (final dynamic sub in nestedItems) {
                      (sub as Map<String, dynamic>)['allowed'] = val ?? false;
                    }
                  });
                },
              ),
              Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          children: nestedItems.map((dynamic sub) => _buildQualityItemTile(context, sub as Map<String, dynamic>, setState, readOnly: readOnly)).toList(),
        ),
      );
    } else {
      return CheckboxListTile(
        title: Text(name),
        value: allowed,
        onChanged: readOnly ? null : (val) {
          setState(() {
            item['allowed'] = val ?? false;
          });
        },
      );
    }
  }

  void _showEditProfileDialog(BuildContext context, WidgetRef ref, Map<String, dynamic>? profile, {bool readOnly = false}) async {
    final api = await ref.read(sonarrApiProvider(instance).future);
    
    Map<String, dynamic> payload;
    if (profile != null) {
      payload = jsonDecode(jsonEncode(profile)) as Map<String, dynamic>;
    } else {
      final schema = await ref.read(sonarrQualityProfileSchemaProvider(instance).future);
      payload = jsonDecode(jsonEncode(schema)) as Map<String, dynamic>;
      payload['name'] = '';
      payload['upgradeAllowed'] = true;
    }

    if (!context.mounted) return;

    final nameController = TextEditingController(text: payload['name'] as String? ?? '');
    
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final theme = Theme.of(context);
            final itemsList = (payload['items'] as List<dynamic>?) ?? [];
            final allowedQualities = _getAllowedQualities(itemsList);
            
            int cutoffId = (payload['cutoff'] as num? ?? 0).toInt();
            if (cutoffId == 0 && allowedQualities.isNotEmpty) {
              cutoffId = allowedQualities.first['id'] as int;
              payload['cutoff'] = cutoffId;
            } else if (allowedQualities.isNotEmpty && !allowedQualities.any((q) => q['id'] == cutoffId)) {
              cutoffId = allowedQualities.first['id'] as int;
              payload['cutoff'] = cutoffId;
            }

            return AlertDialog(
              title: Text(profile != null ? (readOnly ? 'View Quality Profile' : 'Edit Quality Profile') : 'Add Quality Profile'),
              content: SizedBox(
                width: double.maxFinite,
                height: 500,
                child: ListView(
                  children: [
                    TextField(
                      controller: nameController,
                      enabled: !readOnly,
                      decoration: const InputDecoration(
                        labelText: 'Profile Name',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) => payload['name'] = val.trim(),
                    ),
                    const SizedBox(height: Insets.md),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Upgrades Allowed'),
                      value: (payload['upgradeAllowed'] as bool?) ?? false,
                      onChanged: readOnly ? null : (val) => setState(() => payload['upgradeAllowed'] = val),
                    ),
                    if (payload['upgradeAllowed'] == true && allowedQualities.isNotEmpty) ...[
                      const SizedBox(height: Insets.sm),
                      DropdownButtonFormField<int>(
                        initialValue: cutoffId,
                        decoration: const InputDecoration(
                          labelText: 'Upgrade Cutoff',
                          border: OutlineInputBorder(),
                        ),
                        items: allowedQualities.map((q) {
                          final qName = (q['name'] as String?) ?? '';
                          return DropdownMenuItem<int>(
                            value: q['id'] as int,
                            child: Text(qName),
                          );
                        }).toList(),
                        onChanged: readOnly ? null : (val) {
                          if (val != null) {
                            setState(() => payload['cutoff'] = val);
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: Insets.md),
                    Text('Allowed Qualities', style: theme.textTheme.titleSmall),
                    const SizedBox(height: Insets.xs),
                    ...itemsList.map((dynamic item) => _buildQualityItemTile(context, item as Map<String, dynamic>, setState, readOnly: readOnly)),
                  ],
                ),
              ),
              actions: [
                if (readOnly)
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  )
                else ...[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isNotEmpty) {
                        payload['name'] = name;
                        if (profile != null) {
                          await api.updateQualityProfileRaw(payload);
                        } else {
                          await api.createQualityProfileRaw(payload);
                        }
                        ref.invalidate(sonarrQualityProfilesRawProvider(instance));
                        ref.invalidate(sonarrQualityProfilesProvider(instance));
                      }
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: Text(profile != null ? 'Save' : 'Add'),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final AsyncValue<List<Map<String, dynamic>>> profiles = ref.watch(sonarrQualityProfilesRawProvider(instance));
    final AsyncValue<List<SonarrQualityDefinition>> definitions = ref.watch(sonarrQualityDefinitionsProvider(instance));

    return Card(
      child: ExpansionTile(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Quality Profiles', style: theme.textTheme.titleMedium),
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Quality Profile',
              onPressed: () => _showEditProfileDialog(context, ref, null),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.symmetric(horizontal: Insets.md, vertical: Insets.sm),
        children: [
          AsyncValueView<List<Map<String, dynamic>>>(
            value: profiles,
            data: (list) {
              if (list.isEmpty) return const Text('No quality profiles.');
              return Column(
                children: list.map((profile) {
                  final name = (profile['name'] as String?) ?? '';
                  final upgradeAllowed = (profile['upgradeAllowed'] as bool?) ?? false;
                  final cutoffId = (profile['cutoff'] as num? ?? 0).toInt();

                  final cutoffName = definitions.maybeWhen(
                    data: (defs) => defs.firstWhereOrNull((d) => d.id == cutoffId)?.name ?? 'Unknown',
                    orElse: () => '...',
                  );

                  final itemsList = (profile['items'] as List<dynamic>?) ?? [];
                  final allowedQualities = _getAllowedQualities(itemsList);

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    onTap: () => _showEditProfileDialog(context, ref, profile, readOnly: true),
                    title: Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      'Upgrades: ${upgradeAllowed ? "Yes (Cutoff: $cutoffName)" : "No"}\n'
                      'Allowed: ${allowedQualities.length} qualities',
                    ),
                    isThreeLine: true,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit Quality Profile',
                          onPressed: () => _showEditProfileDialog(context, ref, profile),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                          tooltip: 'Delete Quality Profile',
                          onPressed: () async {
                            final bool? confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Delete Quality Profile?'),
                                content: Text('Are you sure you want to delete profile "$name"?'),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(context).pop(false),
                                    child: const Text('Cancel'),
                                  ),
                                  FilledButton(
                                    style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
                                    onPressed: () => Navigator.of(context).pop(true),
                                    child: const Text('Delete'),
                                  ),
                                ],
                              ),
                            );

                            if (confirm == true) {
                              final api = await ref.read(sonarrApiProvider(instance).future);
                              await api.deleteQualityProfile(profile['id'] as int);
                              ref.invalidate(sonarrQualityProfilesRawProvider(instance));
                              ref.invalidate(sonarrQualityProfilesProvider(instance));
                            }
                          },
                        ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

