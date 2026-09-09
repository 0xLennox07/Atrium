import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';

import 'home/sonarr_rename_dialog.dart';
import 'models/sonarr_episode.dart';
import 'models/sonarr_history_item.dart';
import 'models/sonarr_queue_item.dart';
import 'models/sonarr_series.dart';
import 'sonarr_api.dart';
import 'sonarr_providers.dart';
import 'sonarr_release_search_screen.dart';
import 'sonarr_settings_form_screen.dart';

class SeriesDetailScreen extends ConsumerWidget {
  const SeriesDetailScreen({
    required this.instance,
    required this.series,
    super.key,
  });

  final Instance instance;
  final SonarrSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SonarrSeries> seriesAsync =
        ref.watch(sonarrSeriesByIdProvider((instance, series.id)));
    final AsyncValue<List<SonarrEpisode>> episodesAsync =
        ref.watch(sonarrEpisodesProvider((instance, series.id)));

    final SonarrSeries activeSeries = seriesAsync.value ?? series;

    return Scaffold(
      body: _SeriesDetailBody(
        instance: instance,
        series: activeSeries,
        episodesAsync: episodesAsync,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main body
// ---------------------------------------------------------------------------

class _SeriesDetailBody extends ConsumerStatefulWidget {
  const _SeriesDetailBody({
    required this.instance,
    required this.series,
    required this.episodesAsync,
  });

  final Instance instance;
  final SonarrSeries series;
  final AsyncValue<List<SonarrEpisode>> episodesAsync;

  @override
  ConsumerState<_SeriesDetailBody> createState() => _SeriesDetailBodyState();
}

class _SeriesDetailBodyState extends ConsumerState<_SeriesDetailBody> {
  final Set<int> _expandedSeasons = {};
  final Map<int, GlobalKey> _seasonKeys = {};
  final GlobalKey _seasonsHeaderKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showBackToTop = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    final threshold = MediaQuery.sizeOf(context).height * 0.5;
    if (_scrollController.hasClients && _scrollController.offset >= threshold) {
      if (!_showBackToTop.value) {
        _showBackToTop.value = true;
      }
    } else {
      if (_showBackToTop.value) {
        _showBackToTop.value = false;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _showBackToTop.dispose();
    super.dispose();
  }

  Future<void> _refresh(BuildContext context) async {
    try {
      final api = await ref.read(sonarrApiProvider(widget.instance).future);
      await api.runCommand(<String, dynamic>{
        'name': 'RefreshSeries',
        'seriesId': widget.series.id,
      });
      try {
        await api.runCommand(<String, dynamic>{
          'name': 'RefreshMonitoredDownloads',
        });
      } catch (_) {}
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh: $e')),
        );
      }
    } finally {
      if (mounted) {
        _invalidateProviders();
        setState(_expandedSeasons.clear);
      }
    }
  }

  void _invalidateProviders() {
    ref.invalidate(
      sonarrSeriesByIdProvider((widget.instance, widget.series.id)),
    );
    ref.invalidate(sonarrEpisodesProvider((widget.instance, widget.series.id)));
    ref.invalidate(sonarrSeriesProvider(widget.instance));
    ref.invalidate(sonarrQueueProvider(widget.instance));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final SonarrApi? api = ref.watch(sonarrApiProvider(widget.instance)).value;

    final SonarrImage? poster = widget.series.images
        .firstWhereOrNull((SonarrImage i) => i.coverType == 'poster');
    final String? posterUrl =
        poster == null ? null : api?.posterUrl(poster, width: 500);

    final SonarrImage? fanart = widget.series.images
        .firstWhereOrNull((SonarrImage i) => i.coverType == 'fanart');
    final String? fanartUrl =
        fanart == null ? null : api?.posterUrl(fanart, width: 1080);

    final int downloadedCount = widget.series.statistics?.episodeFileCount ?? 0;
    final int totalEpisodes = widget.series.statistics?.episodeCount ?? 0;

    return Scaffold(
      floatingActionButton: ValueListenableBuilder<bool>(
        valueListenable: _showBackToTop,
        builder: (context, show, child) {
          return AnimatedScale(
            scale: show ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: AnimatedOpacity(
              opacity: show ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: FloatingActionButton.small(
                onPressed: () {
                  _scrollController.animateTo(
                    0.0,
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                  );
                },
                child: const Icon(Icons.arrow_upward),
              ),
            ),
          );
        },
      ),
      body: EasyRefresh(
          header: const ClassicHeader(
            position: IndicatorPosition.locator,
            dragText: 'Pull to refresh',
            armedText: 'Release ready',
            readyText: 'Refreshing...',
            processingText: 'Refreshing...',
            processedText: 'Succeeded',
            failedText: 'Failed',
            messageText: 'Last updated at %T',
          ),
      onRefresh: () => _refresh(context),
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          // -- AppBar --
          SliverAppBar(
            expandedHeight: 250.0,
            pinned: true,
            backgroundColor: cs.surface,
            surfaceTintColor: cs.surfaceTint,
            leading: _AppBarLeading(controller: _scrollController),
            actions: <Widget>[
              _AppBarActions(
                controller: _scrollController,
                instance: widget.instance,
                series: widget.series,
                onRefreshed: _invalidateProviders,
              ),
            ],
            title: CollapsedTitle(
              controller: _scrollController,
              title: widget.series.title,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _Backdrop(fanartUrl: fanartUrl),
            ),
          ),
          const HeaderLocator.sliver(),

          // -- Content --
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.sm,
              Insets.lg,
              Insets.xl,
            ),
            sliver: SliverList.list(
              children: <Widget>[
                // Hero info card
                _HeroInfoCard(
                  series: widget.series,
                  posterUrl: posterUrl,
                ),

                const SizedBox(height: Insets.lg),

                // Stats card with progress bar
                _StatsCard(
                  downloadedCount: downloadedCount,
                  totalEpisodes: totalEpisodes,
                  sizeOnDisk: widget.series.statistics?.sizeOnDisk ?? 0,
                ),

                const SizedBox(height: Insets.lg),

                // Action buttons row
                _ActionsRow(
                  instance: widget.instance,
                  series: widget.series,
                  onRefreshed: _invalidateProviders,
                ),

                // Genre chips
                if (widget.series.genres.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Insets.lg),
                  Wrap(
                    spacing: Insets.sm,
                    runSpacing: Insets.sm,
                    children: widget.series.genres
                        .map(
                          (String g) => Chip(
                            label: Text(g),
                            backgroundColor: cs.tertiaryContainer,
                            labelStyle: TextStyle(
                              color: cs.onTertiaryContainer,
                              fontSize: 12,
                            ),
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                          ),
                        )
                        .toList(),
                  ),
                ],

                // Overview
                if (widget.series.overview != null &&
                    widget.series.overview!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Insets.lg),
                  _OverviewSection(overview: widget.series.overview!),
                ],

                // Info section (path, next airing)
                if (widget.series.path != null ||
                    widget.series.nextAiring != null) ...<Widget>[
                  const SizedBox(height: Insets.lg),
                  _InfoSection(series: widget.series),
                ],

                const SizedBox(height: Insets.xl),

                // Season & Episodes header
                Text(
                  'Seasons & Episodes',
                  key: _seasonsHeaderKey,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: Insets.md),

                // Episodes content
                ...(() {
                  final asyncVal = widget.episodesAsync;
                  
                  List<Widget> buildData(List<SonarrEpisode> episodes) {
                    final Map<int, List<SonarrEpisode>> episodesBySeason =
                        groupBy(episodes, (e) => e.seasonNumber);
                    final List<int> sortedSeasons = episodesBySeason.keys
                        .toList()
                      ..sort((a, b) => b.compareTo(a)); // newest first

                    for (final seasonNum in sortedSeasons) {
                      _seasonKeys.putIfAbsent(seasonNum, GlobalKey.new);
                    }

                    return <Widget>[
                      if (sortedSeasons.isNotEmpty) ...[
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding:
                              const EdgeInsets.symmetric(vertical: Insets.xs),
                          child: Row(
                            children: [
                              ActionChip(
                                label: const Text('All'),
                                onPressed: () {
                                  if (_seasonsHeaderKey.currentContext !=
                                      null) {
                                    Scrollable.ensureVisible(
                                      _seasonsHeaderKey.currentContext!,
                                      duration:
                                          const Duration(milliseconds: 500),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                },
                              ),
                              ...sortedSeasons.map((seasonNum) {
                                final label = seasonNum == 0
                                    ? 'Specials'
                                    : 'Season $seasonNum';
                                return Padding(
                                  padding:
                                      const EdgeInsets.only(left: Insets.xs),
                                  child: ActionChip(
                                    label: Text(label),
                                    onPressed: () {
                                      if (!_expandedSeasons
                                          .contains(seasonNum)) {
                                        setState(() {
                                          _expandedSeasons.add(seasonNum);
                                        });
                                      }
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        final key = _seasonKeys[seasonNum];
                                        if (key?.currentContext != null) {
                                          Scrollable.ensureVisible(
                                            key!.currentContext!,
                                            duration: const Duration(
                                              milliseconds: 500,
                                            ),
                                            curve: Curves.easeInOut,
                                          );
                                        }
                                      });
                                    },
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: Insets.md),
                      ],
                      Column(
                        children: _buildSeasonCards(
                          context,
                          episodesBySeason,
                          sortedSeasons,
                        ),
                      ),
                    ];
                  }

                  if (asyncVal.hasValue) {
                    return buildData(asyncVal.value!);
                  }

                  return asyncVal.when(
                    data: buildData,
                    loading: () => <Widget>[
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: Insets.xl),
                          child: ExpressiveProgressIndicator(),
                        ),
                      ),
                    ],
                    error: (error, stack) => <Widget>[
                      Center(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: Insets.xl),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                'Failed to load episodes.',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: cs.error,
                                ),
                              ),
                              const SizedBox(height: Insets.sm),
                              FilledButton.tonal(
                                onPressed: () => ref.invalidate(
                                  sonarrEpisodesProvider(
                                    (widget.instance, widget.series.id),
                                  ),
                                ),
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                })(),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  List<Widget> _buildSeasonCards(
    BuildContext context,
    Map<int, List<SonarrEpisode>> episodesBySeason,
    List<int> sortedSeasons,
  ) {
    return sortedSeasons.map((int seasonNum) {
      final List<SonarrEpisode> seasonEpisodes = episodesBySeason[seasonNum]!
        ..sort((a, b) => b.episodeNumber.compareTo(a.episodeNumber));

      final SonarrSeason? seasonMeta = widget.series.seasons
          .firstWhereOrNull((s) => s.seasonNumber == seasonNum);

      return Padding(
        padding: const EdgeInsets.only(bottom: Insets.md),
        child: _SeasonCard(
          key: _seasonKeys[seasonNum],
          instance: widget.instance,
          series: widget.series,
          seasonNumber: seasonNum,
          episodes: seasonEpisodes,
          seasonMeta: seasonMeta,
          isExpanded: _expandedSeasons.contains(seasonNum),
          onToggleExpand: (expanded) {
            setState(() {
              if (expanded) {
                _expandedSeasons.add(seasonNum);
              } else {
                _expandedSeasons.remove(seasonNum);
              }
            });
          },
          onRefreshed: () => _refresh(context),
        ),
      );
    }).toList();
  }
}

// ---------------------------------------------------------------------------
// Hero Info Card — poster + metadata on a tinted surface
// ---------------------------------------------------------------------------

class _HeroInfoCard extends StatelessWidget {
  const _HeroInfoCard({required this.series, required this.posterUrl});

  final SonarrSeries series;
  final String? posterUrl;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      padding: const EdgeInsets.all(Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Poster
          Hero(
            tag: 'series-poster-${series.id}',
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.md),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.md),
                child: SizedBox(
                  width: 110,
                  height: 165,
                  child: posterUrl != null
                      ? AtriumNetworkImage(
                          imageUrl: posterUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 500,
                          placeholder: (_, __) => Container(
                            color: cs.surfaceContainerHighest,
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    ExpressiveProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              Icons.live_tv,
                              color: cs.outline,
                              size: 32,
                            ),
                          ),
                        )
                      : Container(
                          color: cs.surfaceContainerHighest,
                          child:
                              Icon(Icons.live_tv, color: cs.outline, size: 32),
                        ),
                ),
              ),
            ),
          ),

          const SizedBox(width: Insets.lg),

          // Metadata column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  series.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: Insets.md),
                // Info chips row
                Wrap(
                  spacing: Insets.xs,
                  runSpacing: Insets.xs,
                  children: <Widget>[
                    if (series.year != null) _MetaChip(label: '${series.year}'),
                    if (series.network != null)
                      _MetaChip(label: series.network!),
                    if (series.runtime != null && series.runtime! > 0)
                      _MetaChip(label: '${series.runtime} min'),
                    if (series.certification != null &&
                        series.certification!.isNotEmpty)
                      _MetaChip(label: series.certification!),
                    if (series.seriesType != null)
                      _MetaChip(label: _capitalise(series.seriesType!)),
                  ],
                ),

                const SizedBox(height: Insets.md),

                // Status pill
                _StatusPill(status: series.status),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ---------------------------------------------------------------------------
// Stats Card — progress bar + numbers
// ---------------------------------------------------------------------------

class _StatsCard extends StatelessWidget {
  const _StatsCard({
    required this.downloadedCount,
    required this.totalEpisodes,
    required this.sizeOnDisk,
  });

  final int downloadedCount;
  final int totalEpisodes;
  final int sizeOnDisk;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final double progress =
        totalEpisodes > 0 ? downloadedCount / totalEpisodes : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: cs.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.tv, size: 18, color: cs.onSecondaryContainer),
              const SizedBox(width: Insets.xs),
              Text(
                '$downloadedCount of $totalEpisodes episodes',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Icon(Icons.storage, size: 18, color: cs.onSecondaryContainer),
              const SizedBox(width: Insets.xs),
              Text(
                _formatSize(sizeOnDisk),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.sm),
            child: LinearProgressIndicatorM3E(
              shape: ProgressM3EShape.flat,
              value: progress,
              trackColor: cs.surfaceContainerHighest,
              activeColor: progress >= 1.0 ? cs.tertiary : cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Actions Row — pill-shaped tonal buttons
// ---------------------------------------------------------------------------

class _ActionsRow extends ConsumerWidget {
  const _ActionsRow({
    required this.instance,
    required this.series,
    required this.onRefreshed,
  });

  final Instance instance;
  final SonarrSeries series;
  final VoidCallback onRefreshed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Row(
      children: <Widget>[
        // Monitor toggle
        Expanded(
          child: series.monitored
              ? FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.secondaryContainer,
                    foregroundColor: cs.onSecondaryContainer,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.bookmark, size: 20),
                  label: const Text(
                    'Monitored',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: () => _toggleMonitored(context, ref),
                )
              : OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: cs.outline),
                    shape: const StadiumBorder(),
                  ),
                  icon: const Icon(Icons.bookmark_border, size: 20),
                  label: const Text('Unmonitored'),
                  onPressed: () => _toggleMonitored(context, ref),
                ),
        ),

        const SizedBox(width: Insets.sm),

        // Search button
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: const StadiumBorder(),
            ),
            icon: const Icon(Icons.search, size: 20),
            label: const Text(
              'Search',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () => _searchSeries(context, ref),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleMonitored(BuildContext context, WidgetRef ref) async {
    try {
      final api = await ref.read(sonarrApiProvider(instance).future);
      final raw = await api.getSeriesRaw(series.id);
      raw['monitored'] = !series.monitored;
      await api.updateSeriesRaw(raw);
      onRefreshed();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !series.monitored ? 'Series monitored.' : 'Series unmonitored.',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update monitoring: $e')),
        );
      }
    }
  }

  Future<void> _searchSeries(BuildContext context, WidgetRef ref) async {
    final api = await ref.read(sonarrApiProvider(instance).future);
    try {
      await api.runCommand(<String, dynamic>{
        'name': 'SeriesSearch',
        'seriesId': series.id,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Search started for series.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to trigger search: $e')),
        );
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Overview Section — expandable synopsis
// ---------------------------------------------------------------------------

class _OverviewSection extends StatefulWidget {
  const _OverviewSection({required this.overview});

  final String overview;

  @override
  State<_OverviewSection> createState() => _OverviewSectionState();
}

class _OverviewSectionState extends State<_OverviewSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Overview',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: Insets.sm),
          AnimatedCrossFade(
            firstChild: Text(
              widget.overview,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            secondChild: Text(
              widget.overview,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
          if (widget.overview.length > 150) ...<Widget>[
            const SizedBox(height: Insets.xs),
            GestureDetector(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Text(
                _expanded ? 'Show less' : 'Show more',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info Section — path, next airing
// ---------------------------------------------------------------------------

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.series});

  final SonarrSeries series;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (series.path != null) ...<Widget>[
            _InfoRow(
              icon: Icons.folder_outlined,
              label: 'Path',
              value: series.path!,
            ),
          ],
          if (series.nextAiring != null) ...<Widget>[
            if (series.path != null) const SizedBox(height: Insets.sm),
            _InfoRow(
              icon: Icons.schedule,
              label: 'Next Airing',
              value: _formatDateTime(series.nextAiring!),
            ),
          ],
          if (series.previousAiring != null) ...<Widget>[
            const SizedBox(height: Insets.sm),
            _InfoRow(
              icon: Icons.history,
              label: 'Previous Airing',
              value: _formatDateTime(series.previousAiring!),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDateTime(String isoDate) {
    try {
      final DateTime dt = DateTime.parse(isoDate).toLocal();
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return isoDate;
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 16, color: cs.outline),
        const SizedBox(width: Insets.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cs.outline,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Season Card — expandable card with progress bar
// ---------------------------------------------------------------------------

class _SeasonCard extends ConsumerWidget {
  const _SeasonCard({
    super.key,
    required this.instance,
    required this.series,
    required this.seasonNumber,
    required this.episodes,
    required this.seasonMeta,
    required this.isExpanded,
    required this.onToggleExpand,
    required this.onRefreshed,
  });

  final Instance instance;
  final SonarrSeries series;
  final int seasonNumber;
  final List<SonarrEpisode> episodes;
  final SonarrSeason? seasonMeta;
  final bool isExpanded;
  final ValueChanged<bool> onToggleExpand;
  final VoidCallback onRefreshed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final int downloaded = episodes.where((e) => e.hasFile).length;
    final int total = episodes.length;
    final double progress = total > 0 ? downloaded / total : 0.0;
    final bool isMonitored = seasonMeta?.monitored ?? false;

    final double seasonSizeBytes = episodes
        .where((e) => e.hasFile)
        .map((e) => (e.episodeFile?['size'] as num?)?.toDouble() ?? 0.0)
        .sum;
    final String seasonSizeStr =
        seasonSizeBytes > 0 ? ' • ${_formatSize(seasonSizeBytes.toInt())}' : '';

    final queue = ref.watch(sonarrQueueProvider(instance)).value ?? <SonarrQueueItem>[];
    final Map<String, List<SonarrQueueItem>> groupedByDownload = {};
    for (final item in queue) {
      final dlId = item.downloadId;
      if (dlId != null) {
        groupedByDownload.putIfAbsent(dlId, () => []).add(item);
      }
    }
    final seasonPackDownloadIds = groupedByDownload.entries
        .where((e) => e.value.length > 1)
        .map((e) => e.key)
        .toSet();

    final seasonPackDownload = queue.firstWhereOrNull(
      (item) =>
          item.seriesId == series.id &&
          item.seasonNumber == seasonNumber &&
          (item.episodeId == null ||
              (item.downloadId != null && seasonPackDownloadIds.contains(item.downloadId))),
    );

    double? dlProgress;
    if (seasonPackDownload != null) {
      final double totalSize = seasonPackDownload.size ?? 0.0;
      final double sizeLeft = seasonPackDownload.sizeleft ?? 0.0;
      if (totalSize > 0) {
        dlProgress = (totalSize - sizeLeft) / totalSize;
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          // Header
          InkWell(
            onTap: () => onToggleExpand(!isExpanded),
            borderRadius: BorderRadius.circular(Radii.lg),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.md,
                Insets.sm,
                Insets.md,
              ),
              child: Row(
                children: <Widget>[
                  // Monitor indicator (Togglable IconButton)
                  IconButton(
                    icon: Icon(
                      isMonitored ? Icons.bookmark : Icons.bookmark_border,
                      size: 18,
                      color: isMonitored ? cs.primary : cs.outline,
                    ),
                    tooltip:
                        isMonitored ? 'Unmonitor Season' : 'Monitor Season',
                    onPressed: () =>
                        _toggleSeasonMonitoring(context, ref, isMonitored),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                  const SizedBox(width: Insets.sm),

                  // Season title
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          seasonNumber == 0
                              ? 'Specials'
                              : 'Season $seasonNumber',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: <Widget>[
                            // Progress bar (inline)
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicatorM3E(
                                  shape: ProgressM3EShape.flat,
                                  value: progress,
                                  trackColor: cs.surfaceContainerHighest,
                                  activeColor: progress >= 1.0
                                      ? cs.tertiary
                                      : cs.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: Insets.sm),
                            Text(
                              '$downloaded/$total$seasonSizeStr',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.outline,
                              ),
                            ),
                          ],
                        ),
                        if (seasonPackDownload != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            children: <Widget>[
                              Icon(
                                Icons.downloading,
                                size: 14,
                                color: cs.primary,
                              ),
                              const SizedBox(width: Insets.xs),
                              Expanded(
                                child: Text(
                                  'Downloading Season Pack • ETA: ${_formatTimeLeft(seasonPackDownload.timeleft)}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (dlProgress != null)
                                Text(
                                  '${(dlProgress * 100).toStringAsFixed(0)}%',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                            ],
                          ),
                          if (dlProgress != null) ...[
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: dlProgress,
                                minHeight: 3,
                                backgroundColor: cs.primaryContainer.withValues(alpha: 0.3),
                                color: cs.primary,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),

                  // Expand indicator
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more, size: 24),
                  ),
                ],
              ),
            ),
          ),

          // Episode list
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.md,
                    vertical: Insets.xs,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: TextButton.icon(
                          icon: const Icon(Icons.search, size: 16),
                          label: const Text(
                            'Search',
                            style: TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () =>
                              _searchSeason(context, ref, seasonNumber),
                        ),
                      ),
                      const SizedBox(width: Insets.xs),
                      Expanded(
                        child: TextButton.icon(
                          icon: const Icon(Icons.person_search, size: 16),
                          label: const Text(
                            'Interactive',
                            style: TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () => _openSeasonInteractiveSearch(
                            context,
                            seasonNumber,
                          ),
                        ),
                      ),
                      if (downloaded > 0) ...[
                        const SizedBox(width: Insets.xs),
                        Expanded(
                          child: TextButton.icon(
                            icon: Icon(
                              Icons.delete_outline,
                              color: cs.error,
                              size: 16,
                            ),
                            label: Text(
                              'Delete',
                              style: TextStyle(color: cs.error, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onPressed: () =>
                                _confirmDeleteSeasonFiles(context, ref),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
                if (isExpanded)
                  ...episodes.map(
                    (SonarrEpisode episode) {
                      final downloadingItem = queue.firstWhereOrNull(
                        (item) =>
                            item.episodeId == episode.id &&
                            (item.downloadId == null || !seasonPackDownloadIds.contains(item.downloadId)),
                      );

                      double? dlProgress;
                      if (downloadingItem != null) {
                        final double totalSize = downloadingItem.size ?? 0.0;
                        final double sizeLeft = downloadingItem.sizeleft ?? 0.0;
                        if (totalSize > 0) {
                          dlProgress = (totalSize - sizeLeft) / totalSize;
                        }
                      }

                      return _EpisodeRow(
                        instance: instance,
                        series: series,
                        episode: episode,
                        downloadingItem: downloadingItem,
                        dlProgress: dlProgress,
                      );
                    },
                  ),
              ],
            ),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSeasonMonitoring(
    BuildContext context,
    WidgetRef ref,
    bool currentMonitored,
  ) async {
    try {
      final api = await ref.read(sonarrApiProvider(instance).future);
      final raw = await api.getSeriesRaw(series.id);

      final List<dynamic> seasons = raw['seasons'] as List<dynamic>;
      for (final dynamic s in seasons) {
        final Map<String, dynamic> season = s as Map<String, dynamic>;
        if (season['seasonNumber'] == seasonNumber) {
          season['monitored'] = !currentMonitored;
          break;
        }
      }

      await api.updateSeriesRaw(raw);

      if (!context.mounted) return;
      ref.invalidate(sonarrSeriesByIdProvider((instance, series.id)));
      ref.invalidate(sonarrSeriesProvider(instance));
      onRefreshed();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !currentMonitored
                ? 'Season $seasonNumber monitored.'
                : 'Season $seasonNumber unmonitored.',
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update monitoring: $e')),
        );
      }
    }
  }

  Future<void> _confirmDeleteSeasonFiles(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final theme = Theme.of(context);
    bool unmonitor = false;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Delete Season $seasonNumber Files'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Are you sure you want to delete all episode files for Season $seasonNumber? This will delete the files from disk and cannot be undone.',
              ),
              const SizedBox(height: Insets.sm),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Unmonitor season'),
                subtitle: const Text('Prevent automatic re-downloads'),
                value: unmonitor,
                onChanged: (v) => setState(() => unmonitor = v ?? false),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Deleting season files...'),
          duration: Duration(seconds: 1),
        ),
      );

      int deletedCount = 0;
      int failedCount = 0;

      final fileIds = episodes
          .where((e) => e.hasFile && e.episodeFileId != null)
          .map((e) => e.episodeFileId!)
          .toList();

      bool unmonitored = false;
      Object? unmonitorError;

      try {
        final api = await ref.read(sonarrApiProvider(instance).future);
        for (final fileId in fileIds) {
          try {
            await api.deleteEpisodeFile(fileId);
            deletedCount++;
          } catch (e) {
            failedCount++;
          }
        }
        if (unmonitor) {
          try {
            final Map<String, dynamic> raw = await api.getSeriesRaw(series.id);
            final List<dynamic> seasons = (raw['seasons'] as List<dynamic>?) ?? <dynamic>[];
            for (final dynamic s in seasons) {
              if (s is Map<String, dynamic> && s['seasonNumber'] == seasonNumber) {
                s['monitored'] = false;
                break;
              }
            }
            await api.updateSeriesRaw(raw);
            unmonitored = true;
          } catch (e) {
            unmonitorError = e;
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete season files: $e')),
          );
        }
        return;
      }

      if (!context.mounted) return;
      ref.invalidate(sonarrEpisodesProvider((instance, series.id)));
      ref.invalidate(sonarrSeriesByIdProvider((instance, series.id)));
      ref.invalidate(sonarrSeriesProvider(instance));
      onRefreshed();

      if (context.mounted) {
        if (unmonitor && !unmonitored) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Deleted $deletedCount file(s), but failed to unmonitor season: $unmonitorError',
              ),
            ),
          );
        } else if (failedCount == 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                unmonitored
                    ? 'Successfully deleted $deletedCount file(s) and unmonitored season.'
                    : 'Successfully deleted $deletedCount file(s).',
              ),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Deleted $deletedCount file(s). Failed to delete $failedCount file(s).',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _searchSeason(
    BuildContext context,
    WidgetRef ref,
    int seasonNum,
  ) async {
    try {
      final api = await ref.read(sonarrApiProvider(instance).future);
      await api.runCommand(<String, dynamic>{
        'name': 'SeasonSearch',
        'seriesId': series.id,
        'seasonNumber': seasonNum,
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search queued for Season $seasonNum.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  void _openSeasonInteractiveSearch(BuildContext context, int seasonNum) {
    pushScreen<void>(
      context,
      SonarrReleaseSearchScreen(
        instance: instance,
        series: series,
        seasonNumber: seasonNum,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Episode Row — clean row with popup menu
// ---------------------------------------------------------------------------

class _EpisodeRow extends ConsumerWidget {
  const _EpisodeRow({
    required this.instance,
    required this.series,
    required this.episode,
    required this.downloadingItem,
    required this.dlProgress,
  });

  final Instance instance;
  final SonarrSeries series;
  final SonarrEpisode episode;
  final SonarrQueueItem? downloadingItem;
  final double? dlProgress;

  Future<void> _toggleEpisodeMonitored(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final api = await ref.read(sonarrApiProvider(instance).future);
      final updated = episode.copyWith(monitored: !episode.monitored);
      await api.updateEpisode(updated.toJson());
      ref.invalidate(sonarrEpisodesProvider((instance, series.id)));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final bool isDownloaded = episode.hasFile;
    final bool isMonitored = episode.monitored;

    bool isFuture = false;
    if (episode.airDateUtc != null && episode.airDateUtc!.isNotEmpty) {
      final DateTime? airDate = DateTime.tryParse(episode.airDateUtc!);
      if (airDate != null && airDate.isAfter(DateTime.now())) {
        isFuture = true;
      }
    }

    Color badgeBorderColor;
    Color badgeBgColor;
    Color badgeTextColor;

    if (isDownloaded) {
      badgeBorderColor = cs.tertiary;
      badgeBgColor = cs.tertiary.withValues(alpha: 0.15);
      badgeTextColor = cs.tertiary;
    } else if (!isMonitored) {
      badgeBorderColor = cs.outlineVariant;
      badgeBgColor = cs.surfaceContainerHighest.withValues(alpha: 0.4);
      badgeTextColor = cs.outline;
    } else if (isFuture) {
      badgeBorderColor = cs.primary;
      badgeBgColor = cs.primary.withValues(alpha: 0.08);
      badgeTextColor = cs.primary;
    } else {
      // Missing & Monitored
      badgeBorderColor = cs.error;
      badgeBgColor = cs.error.withValues(alpha: 0.1);
      badgeTextColor = cs.error;
    }

    final Map<String, dynamic>? fileMap = episode.episodeFile;
    final Map<String, dynamic>? qualityObj =
        fileMap?['quality'] as Map<String, dynamic>?;
    final Map<String, dynamic>? qualityInner =
        qualityObj?['quality'] as Map<String, dynamic>?;
    final String? quality = qualityInner?['name'] as String?;
    final int? sizeBytes = fileMap?['size'] as int?;
    final String? sizeStr = sizeBytes != null ? _formatSize(sizeBytes) : null;

    final String subtitleText = [
      if (episode.airDate != null) episode.airDate!,
      if (quality != null) quality,
      if (sizeStr != null) sizeStr,
    ].join(' • ');

    // downloadingItem and dlProgress are now passed in from the parent SeasonCard
    final downloadingItem = this.downloadingItem;
    final dlProgress = this.dlProgress;

    return InkWell(
      onTap: () => _showEpisodeBottomSheet(
        context: context,
        ref: ref,
        instance: instance,
        series: series,
        episode: episode,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.lg,
          vertical: Insets.sm,
        ),
        child: Row(
          children: <Widget>[
            // Episode number circle
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: badgeBgColor,
                border: Border.all(color: badgeBorderColor, width: 1.5),
              ),
              child: Center(
                child: Text(
                  '${episode.episodeNumber}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: badgeTextColor,
                  ),
                ),
              ),
            ),

            const SizedBox(width: Insets.md),

            // Title + air date
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    episode.title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (downloadingItem != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.downloading,
                          size: 12,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Downloading • ETA: ${_formatTimeLeft(downloadingItem.timeleft)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (dlProgress != null)
                          Text(
                            '${(dlProgress * 100).toStringAsFixed(0)}%',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ),
                    if (dlProgress != null) ...[
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: dlProgress,
                          minHeight: 2,
                          backgroundColor: cs.primaryContainer.withValues(alpha: 0.3),
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ] else
                    Text(
                      subtitleText,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // Monitored indicator
            IconButton(
              icon: Icon(
                episode.monitored ? Icons.bookmark : Icons.bookmark_border,
                size: 20,
                color: episode.monitored ? cs.primary : cs.outline,
              ),
              tooltip: episode.monitored ? 'Unmonitor' : 'Monitor',
              onPressed: () => _toggleEpisodeMonitored(context, ref),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

void _showEpisodeBottomSheet({
  required BuildContext context,
  required WidgetRef ref,
  required Instance instance,
  required SonarrSeries series,
  required SonarrEpisode episode,
}) {
  final ThemeData theme = Theme.of(context);
  final ColorScheme cs = theme.colorScheme;

  final Map<String, dynamic>? fileMap = episode.episodeFile;
  final Map<String, dynamic>? qualityObj =
      fileMap?['quality'] as Map<String, dynamic>?;
  final Map<String, dynamic>? qualityInner =
      qualityObj?['quality'] as Map<String, dynamic>?;
  final String? quality = qualityInner?['name'] as String?;
  final int? sizeBytes = fileMap?['size'] as int?;
  final String? sizeStr = sizeBytes != null ? _formatSize(sizeBytes) : null;
  final String? relativePath = fileMap?['relativePath'] as String?;

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (BuildContext context) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding:
                const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Title / Header
                Text(
                  'Season ${episode.seasonNumber}, Episode ${episode.episodeNumber}',
                  style:
                      theme.textTheme.labelSmall?.copyWith(color: cs.outline),
                ),
                const SizedBox(height: Insets.xs),
                Text(
                  episode.title,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: Insets.sm),

                // Air date + File size / Quality row
                Wrap(
                  spacing: Insets.xs,
                  runSpacing: Insets.xs,
                  children: <Widget>[
                    if (episode.airDate != null)
                      _MetaChip(label: 'Aired: ${episode.airDate}'),
                    if (quality != null) _MetaChip(label: quality),
                    if (sizeStr != null) _MetaChip(label: sizeStr),
                    _MetaChip(
                      label: episode.monitored ? 'Monitored' : 'Unmonitored',
                    ),
                  ],
                ),
                const SizedBox(height: Insets.md),

                // Synopsis / Overview
                Text(
                  'Overview',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: Insets.xs),
                Text(
                  episode.overview != null && episode.overview!.isNotEmpty
                      ? episode.overview!
                      : 'No overview available.',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: Insets.md),

                // File Path (if downloaded)
                if (relativePath != null) ...[
                  Text(
                    'Path',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    relativePath,
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: cs.outline),
                  ),
                  const SizedBox(height: Insets.md),
                ],

                // Action buttons bar (Single row, clean layout)
                Row(
                  children: <Widget>[
                    // Monitor/Unmonitor Toggle
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          try {
                            final api = await ref
                                .read(sonarrApiProvider(instance).future);
                            final updated =
                                episode.copyWith(monitored: !episode.monitored);
                            await api.updateEpisode(updated.toJson());
                            ref.invalidate(
                              sonarrEpisodesProvider((instance, series.id)),
                            );
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed: $e')),
                              );
                            }
                          }
                        },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(
                              episode.monitored
                                  ? Icons.bookmark
                                  : Icons.bookmark_border,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                episode.monitored ? 'Unmonitor' : 'Monitor',
                                style: const TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Automatic Search
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          Navigator.pop(context);
                          try {
                            final api = await ref
                                .read(sonarrApiProvider(instance).future);
                            await api.runCommand(<String, dynamic>{
                              'name': 'EpisodeSearch',
                              'episodeIds': <int>[episode.id],
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Search queued for episode.'),
                                ),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to queue search: $e'),
                                ),
                              );
                            }
                          }
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(Icons.search, size: 16),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Auto Search',
                                style: TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),

                    // Interactive Search
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          pushScreen<void>(
                            context,
                            SonarrReleaseSearchScreen(
                              instance: instance,
                              episode: episode,
                            ),
                          );
                        },
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Icon(Icons.person_search, size: 16),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Interactive',
                                style: TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Delete file (if has file)
                    if (episode.hasFile && episode.episodeFileId != null) ...[
                      const SizedBox(width: Insets.xs),
                      Tooltip(
                        message: 'Delete File',
                        child: IconButton.filledTonal(
                          icon: Icon(Icons.delete_outline, color: cs.error),
                          onPressed: () async {
                            Navigator.pop(context);
                            bool unmonitor = false;
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (context) => StatefulBuilder(
                                builder: (context, setState) => AlertDialog(
                                  title: const Text('Delete Episode File'),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      const Text(
                                        'Are you sure? This will delete the file from disk and cannot be undone.',
                                      ),
                                      const SizedBox(height: Insets.sm),
                                      CheckboxListTile(
                                        contentPadding: EdgeInsets.zero,
                                        title: const Text('Unmonitor episode'),
                                        subtitle: const Text('Prevent automatic re-downloads'),
                                        value: unmonitor,
                                        onChanged: (v) => setState(() => unmonitor = v ?? false),
                                      ),
                                    ],
                                  ),
                                  actions: <Widget>[
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Cancel'),
                                    ),
                                    FilledButton(
                                      style: FilledButton.styleFrom(
                                        backgroundColor: cs.error,
                                        foregroundColor: cs.onError,
                                      ),
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('Delete'),
                                    ),
                                  ],
                                ),
                              ),
                            );

                            if (confirm == true) {
                              try {
                                final api = await ref
                                    .read(sonarrApiProvider(instance).future);
                                await api
                                    .deleteEpisodeFile(episode.episodeFileId!);
                                bool unmonitored = false;
                                Object? unmonitorError;
                                if (unmonitor) {
                                  try {
                                    await api.updateEpisodeMonitor(
                                      episodeIds: <int>[episode.id],
                                      monitored: false,
                                    );
                                    unmonitored = true;
                                  } catch (e) {
                                    unmonitorError = e;
                                  }
                                }
                                ref.invalidate(
                                  sonarrEpisodesProvider(
                                    (instance, series.id),
                                  ),
                                );
                                if (context.mounted) {
                                  if (unmonitor && !unmonitored) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'File deleted, but failed to unmonitor episode: $unmonitorError',
                                        ),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          unmonitored
                                              ? 'File deleted and episode unmonitored.'
                                              : 'File deleted.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to delete: $e'),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Overflow Menu — edit, rename, delete
// ---------------------------------------------------------------------------

class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({
    required this.instance,
    required this.series,
    required this.onRefreshed,
    required this.iconColor,
  });

  final Instance instance;
  final SonarrSeries series;
  final VoidCallback onRefreshed;
  final Color iconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: iconColor),
      onSelected: (String value) => _handleAction(context, ref, value),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit Series'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.drive_file_rename_outline),
            title: Text('Rename Files'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'monitoring_options',
          child: ListTile(
            leading: Icon(Icons.settings_suggest_outlined),
            title: Text('Monitoring Options'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'history',
          child: ListTile(
            leading: Icon(Icons.history),
            title: Text('History'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete Series',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  void _handleAction(BuildContext context, WidgetRef ref, String action) {
    switch (action) {
      case 'edit':
        pushScreen<void>(
          context,
          SonarrSettingsFormScreen(
            instance: instance,
            series: series,
          ),
        );

      case 'rename':
        showDialog<void>(
          context: context,
          builder: (_) => SonarrRenameDialog(
            instance: instance,
            seriesId: series.id,
          ),
        );

      case 'monitoring_options':
        _showMonitorSeriesDialog(
          context: context,
          ref: ref,
          instance: instance,
          series: series,
          onRefreshed: onRefreshed,
        );

      case 'history':
        pushScreen<void>(
          context,
          SonarrSeriesHistoryScreen(
            instance: instance,
            series: series,
          ),
        );

      case 'delete':
        _confirmDelete(context, ref);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    bool deleteFiles = false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setState) => AlertDialog(
          title: const Text('Delete Series'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Are you sure you want to delete "${series.title}"?'),
              const SizedBox(height: Insets.md),
              CheckboxListTile(
                title: const Text(
                  'Delete files from disk',
                  style: TextStyle(fontSize: 14),
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: deleteFiles,
                onChanged: (val) {
                  if (val != null) setState(() => deleteFiles = val);
                },
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      try {
        final api = await ref.read(sonarrApiProvider(instance).future);
        await api.deleteSeries(series.id, deleteFiles: deleteFiles);
        if (!context.mounted) return;
        ref.invalidate(sonarrSeriesProvider(instance));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Series deleted.')),
        );
        Navigator.pop(context);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e')),
          );
        }
      }
    }
  }
}

void _showMonitorSeriesDialog({
  required BuildContext context,
  required WidgetRef ref,
  required Instance instance,
  required SonarrSeries series,
  required VoidCallback onRefreshed,
}) {
  final theme = Theme.of(context);
  String selectedType = series.monitored ? 'all' : 'none';

  final Map<String, String> options = {
    'all': 'All Episodes',
    'future': 'Future Episodes',
    'missing': 'Missing Episodes',
    'existing': 'Existing Episodes',
    'firstSeason': 'First Season',
    'lastSeason': 'Last Season',
    'pilot': 'Pilot Episode',
    'recent': 'Recent Episodes',
    'monitorSpecials': 'Monitor Specials',
    'unmonitorSpecials': 'Unmonitor Specials',
    'none': 'None (Unmonitor All)',
  };

  showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            title: Text(
              'Monitor Series',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Choose which episodes of "${series.title}" should be monitored by Sonarr:',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: InputDecoration(
                    labelText: 'Monitoring',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: options.entries.map((e) {
                    return DropdownMenuItem<String>(
                      value: e.key,
                      child: Text(e.value),
                    );
                  }).toList(),
                  onChanged: (String? val) {
                    if (val != null) {
                      setState(() {
                        selectedType = val;
                      });
                    }
                  },
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  try {
                    final api =
                        await ref.read(sonarrApiProvider(instance).future);
                    await api.updateSeasonPass(
                      seriesIds: [series.id],
                      monitorType: selectedType,
                    );
                    onRefreshed();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            selectedType == 'none'
                                ? 'Series unmonitored.'
                                : 'Series monitoring updated to ${options[selectedType]}.',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to update monitoring: $e'),
                        ),
                      );
                    }
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Small reusable widgets
// ---------------------------------------------------------------------------

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cs.outlineVariant.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(Radii.xl),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isContinuing = status?.toLowerCase() == 'continuing';
    final Color tint =
        isContinuing ? theme.colorScheme.tertiary : theme.colorScheme.outline;
    final String label = status ?? 'Unknown';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.xl),
        border: Border.all(color: tint.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _capitalise(label),
            style: theme.textTheme.labelSmall?.copyWith(
              color: tint,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

String _formatSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  double size = bytes.toDouble();
  while (size >= 1024 && i < suffixes.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(1)} ${suffixes[i]}';
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.fanartUrl});

  final String? fanartUrl;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (fanartUrl != null)
          AtriumNetworkImage(
            imageUrl: fanartUrl!,
            fit: BoxFit.cover,
            memCacheWidth: 1080,
            errorWidget: (_, __, ___) =>
                ColoredBox(color: cs.surfaceContainerHigh),
          )
        else
          ColoredBox(color: cs.surfaceContainerHigh),
        // Top-down dark scrim for status bar and action icons contrast
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                Colors.black.withValues(alpha: 0.45),
                Colors.transparent,
              ],
              stops: const <double>[0.0, 0.45],
            ),
          ),
        ),
        // Scrim so the title stays legible and the image melts into the surface.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                cs.surface.withValues(alpha: 0.0),
                cs.surface.withValues(alpha: 0.6),
                cs.surface,
              ],
              stops: const <double>[0.3, 0.75, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

class _AppBarLeading extends StatefulWidget {
  final ScrollController controller;
  const _AppBarLeading({required this.controller});

  @override
  State<_AppBarLeading> createState() => _AppBarLeadingState();
}

class _AppBarLeadingState extends State<_AppBarLeading> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void didUpdateWidget(covariant _AppBarLeading oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !widget.controller.hasClients) return;
    final offset = widget.controller.offset;
    const double expandedHeight = 250.0;
    const double collapseThreshold = expandedHeight - kToolbarHeight;
    final newProgress = (offset / collapseThreshold).clamp(0.0, 1.0);
    if (newProgress != _progress) {
      setState(() {
        _progress = newProgress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final iconColor = Color.lerp(Colors.white, cs.onSurface, _progress)!;
    final bubbleOpacity = 1.0 - _progress;

    return Center(
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.35 * bubbleOpacity),
        ),
        child: IconButton(
          icon: Icon(Icons.arrow_back, size: 20, color: iconColor),
          onPressed: () => Navigator.maybePop(context),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _AppBarActions extends StatefulWidget {
  final ScrollController controller;
  final Instance instance;
  final SonarrSeries series;
  final VoidCallback onRefreshed;

  const _AppBarActions({
    required this.controller,
    required this.instance,
    required this.series,
    required this.onRefreshed,
  });

  @override
  State<_AppBarActions> createState() => _AppBarActionsState();
}

class _AppBarActionsState extends State<_AppBarActions> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void didUpdateWidget(covariant _AppBarActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !widget.controller.hasClients) return;
    final offset = widget.controller.offset;
    const double expandedHeight = 250.0;
    const double collapseThreshold = expandedHeight - kToolbarHeight;
    final newProgress = (offset / collapseThreshold).clamp(0.0, 1.0);
    if (newProgress != _progress) {
      setState(() {
        _progress = newProgress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final iconColor = Color.lerp(Colors.white, cs.onSurface, _progress)!;
    final bubbleOpacity = 1.0 - _progress;

    return Center(
      child: Container(
        width: 38,
        height: 38,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.35 * bubbleOpacity),
        ),
        child: _OverflowMenu(
          instance: widget.instance,
          series: widget.series,
          onRefreshed: widget.onRefreshed,
          iconColor: iconColor,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Series History Screen
// ---------------------------------------------------------------------------

class SonarrSeriesHistoryScreen extends ConsumerWidget {
  const SonarrSeriesHistoryScreen({
    super.key,
    required this.instance,
    required this.series,
  });

  final Instance instance;
  final SonarrSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final historyAsync = ref.watch(
      sonarrSeriesHistoryProvider((instance, series.id)),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${series.title} - History'),
        surfaceTintColor: Colors.transparent,
      ),
      body: historyAsync.when(
        loading: () => const Center(child: ExpressiveProgressIndicator()),
        error: (Object error, StackTrace? _) => ErrorView(
          title: 'Failed to load history',
          message: error.toString(),
          onRetry: () => ref.invalidate(sonarrSeriesHistoryProvider((instance, series.id))),
        ),
        data: (List<SonarrHistoryItem> items) {
          if (items.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.history,
                    size: 48,
                    color: cs.outline,
                  ),
                  const SizedBox(height: Insets.lg),
                  Text(
                    'No history items found.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.outline,
                    ),
                  ),
                ],
              ),
            );
          }

          return EasyRefresh(
            onRefresh: () async {
              ref.invalidate(sonarrSeriesHistoryProvider((instance, series.id)));
              await ref.read(sonarrSeriesHistoryProvider((instance, series.id)).future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(Insets.md),
              itemCount: items.length,
              separatorBuilder: (BuildContext context, int index) => const Divider(
                height: 1,
                indent: Insets.lg,
                endIndent: Insets.lg,
              ),
              itemBuilder: (BuildContext context, int index) {
                final SonarrHistoryItem item = items[index];
                final String formattedDate = _formatDateTime(item.date);

                String epInfo = '';
                if (item.episode != null) {
                  final String season = item.episode!.seasonNumber.toString().padLeft(2, '0');
                  final String ep = item.episode!.episodeNumber.toString().padLeft(2, '0');
                  epInfo = 'S${season}E$ep';
                }

                final String subtitle = [
                  if (epInfo.isNotEmpty) epInfo,
                  if (item.sourceTitle != null) item.sourceTitle!,
                ].join(' • ');

                return ListTile(
                  leading: _buildHistoryEventIcon(context, item.eventType),
                  title: Text(
                    item.eventType?.toUpperCase() ?? 'UNKNOWN',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    formattedDate,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: cs.outline,
                    ),
                  ),
                  onTap: () => _showHistoryDetails(context, ref, instance, series.id, item),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(String? isoDate) {
  if (isoDate == null) return 'Unknown Date';
  try {
    final DateTime dt = DateTime.parse(isoDate).toLocal();
    final String monthStr = dt.month.toString().padLeft(2, '0');
    final String dayStr = dt.day.toString().padLeft(2, '0');
    final String hourStr = dt.hour.toString().padLeft(2, '0');
    final String minStr = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$monthStr-$dayStr $hourStr:$minStr';
  } catch (_) {
    return isoDate;
  }
}

Widget _buildHistoryEventIcon(BuildContext context, String? eventType) {
  final ThemeData theme = Theme.of(context);
  final String label = eventType?.toLowerCase() ?? '';

  IconData icon;
  Color color;

  switch (label) {
    case 'grabbed':
      icon = Icons.cloud_download_outlined;
      color = theme.colorScheme.secondary;
      break;
    case 'downloadfolderimported':
    case 'seriesfolderimported':
      icon = Icons.download_done_outlined;
      color = theme.colorScheme.primary;
      break;
    case 'downloadfailed':
      icon = Icons.error_outline;
      color = theme.colorScheme.error;
      break;
    case 'episodefiledeleted':
      icon = Icons.delete_outline;
      color = theme.colorScheme.outline;
      break;
    case 'episodefilerenamed':
      icon = Icons.edit_outlined;
      color = theme.colorScheme.primary;
      break;
    case 'downloadignored':
      icon = Icons.block_outlined;
      color = theme.colorScheme.outline;
      break;
    default:
      icon = Icons.history;
      color = theme.colorScheme.onSurfaceVariant;
  }

  return Icon(icon, color: color, size: 22);
}

void _showHistoryDetails(
  BuildContext context,
  WidgetRef ref,
  Instance instance,
  int seriesId,
  SonarrHistoryItem item,
) {
  final ThemeData theme = Theme.of(context);
  final String eventType = item.eventType ?? 'Unknown';

  showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          'History Event Details',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _DetailRow(label: 'Event Type', value: eventType.toUpperCase()),
              _DetailRow(label: 'Date', value: _formatDateTime(item.date)),
              _DetailRow(
                label: 'Source Title',
                value: item.sourceTitle ?? 'None',
              ),
              if (item.downloadId != null)
                _DetailRow(label: 'Download ID', value: item.downloadId!),
              if (item.data != null && item.data!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Metadata:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.maxFinite,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: item.data!.entries.map((MapEntry<String, String?> e) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${e.key}: ${e.value}',
                          style: theme.textTheme.bodySmall,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          if (eventType.toLowerCase() == 'grabbed')
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  final SonarrApi api =
                      await ref.read(sonarrApiProvider(instance).future);
                  await api.failHistoryItem(item.id);
                  ref.invalidate(sonarrSeriesHistoryProvider((instance, seriesId)));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Marked release as failed. Sonarr will search for replacements.',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to flag release: $e')),
                    );
                  }
                }
              },
              child: const Text('Mark Failed'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

String _formatTimeLeft(String? timeleft) {
  if (timeleft == null || timeleft == '00:00:00' || timeleft.isEmpty) {
    return 'calculating...';
  }
  try {
    final List<String> parts = timeleft.split(':');
    if (parts.length < 3) return timeleft;

    final String hoursPart = parts[0];
    final String minutesPart = parts[1];

    int days = 0;
    int hours = 0;

    if (hoursPart.contains('.')) {
      final List<String> hourSplit = hoursPart.split('.');
      days = int.tryParse(hourSplit[0]) ?? 0;
      hours = int.tryParse(hourSplit[1]) ?? 0;
    } else {
      hours = int.tryParse(hoursPart) ?? 0;
    }

    final int minutes = int.tryParse(minutesPart) ?? 0;

    final List<String> result = [];
    if (days > 0) result.add('${days}d');
    if (hours > 0) result.add('${hours}h');
    if (days == 0 && hours == 0 && minutes > 0) result.add('${minutes}m');

    if (result.isEmpty) return 'few seconds';
    return result.join(' ');
  } catch (_) {
    return timeleft;
  }
}

