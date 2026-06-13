import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/sonarr_series.dart';
import 'models/sonarr_episode.dart';
import 'sonarr_api.dart';
import 'sonarr_providers.dart';
import 'sonarr_release_search_screen.dart';
import 'package:intl/intl.dart';

/// Detail view for one Sonarr series: poster header, stats, season list with
/// per-season monitor toggles and search, plus series-level actions
/// (monitor toggle, search all, delete).
class SeriesDetailScreen extends ConsumerWidget {
  const SeriesDetailScreen({
    required this.instance,
    required this.seriesId,
    super.key,
  });

  final Instance instance;
  final int seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SonarrSeries> series =
        ref.watch(sonarrSeriesByIdProvider((instance, seriesId)));

    return Scaffold(
      appBar: AppBar(
        title: Text(series.value?.title ?? 'Series'),
        actions: <Widget>[
          if (series.hasValue)
            _SeriesMenu(
              instance: instance,
              series: series.requireValue,
            ),
        ],
      ),
      body: AsyncValueView<SonarrSeries>(
        value: series,
        onRetry: () =>
            ref.invalidate(sonarrSeriesByIdProvider((instance, seriesId))),
        data: (SonarrSeries s) => _Body(instance: instance, series: s),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.instance, required this.series});

  final Instance instance;
  final SonarrSeries series;

  void _refresh(WidgetRef ref) {
    ref.invalidate(sonarrSeriesByIdProvider((instance, series.id)));
    ref.invalidate(sonarrSeriesProvider(instance));
    ref.invalidate(sonarrEpisodesProvider((instance, series.id)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SonarrApi? api = ref.watch(sonarrApiProvider(instance)).value;
    final SonarrImage? poster = series.images
        .firstWhereOrNull((SonarrImage i) => i.coverType == 'poster');
    final String? imageUrl = poster == null ? null : api?.posterUrl(poster);
    final List<SonarrSeasonStats> seasons = series.seasons
        .where((SonarrSeasonStats s) => s.seasonNumber > 0)
        .sorted(
          (SonarrSeasonStats a, SonarrSeasonStats b) =>
              b.seasonNumber - a.seasonNumber,
        );
    final SonarrSeasonStats? specials = series.seasons
        .firstWhereOrNull((SonarrSeasonStats s) => s.seasonNumber == 0);

    final AsyncValue<List<SonarrEpisode>> episodesValue =
        ref.watch(sonarrEpisodesProvider((instance, series.id)));

    return RefreshIndicator(
      onRefresh: () async => _refresh(ref),
      child: ListView(
        padding: Insets.page,
        children: <Widget>[
          _Header(series: series, imageUrl: imageUrl),
          const SizedBox(height: Insets.md),
          _ActionsRow(instance: instance, series: series, onChanged: _refresh),
          if (series.overview != null && series.overview!.isNotEmpty) ...<
              Widget>[
            const SizedBox(height: Insets.md),
            Text(
              series.overview!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: Insets.lg),
          Text('Seasons', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: Insets.sm),
          for (final SonarrSeasonStats season in seasons)
            _SeasonTile(
              instance: instance,
              series: series,
              season: season,
              onChanged: _refresh,
              episodesValue: episodesValue,
            ),
          if (specials != null)
            _SeasonTile(
              instance: instance,
              series: series,
              season: specials,
              onChanged: _refresh,
              episodesValue: episodesValue,
            ),
          const SizedBox(height: Insets.xl),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.series, required this.imageUrl});

  final SonarrSeries series;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SonarrSeriesStatistics? st = series.statistics;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ClipRRect(
          borderRadius: Radii.card,
          child: SizedBox(
            width: 110,
            height: 165,
            child: imageUrl == null
                ? Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: Icon(
                      Icons.live_tv_outlined,
                      color: theme.colorScheme.outline,
                    ),
                  )
                : CachedNetworkImage(
                    imageUrl: imageUrl!,
                    fit: BoxFit.cover,
                    memCacheWidth: 200,
                    errorWidget: (_, __, ___) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.live_tv_outlined,
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(series.title, style: theme.textTheme.titleLarge),
              const SizedBox(height: Insets.xs),
              Text(
                <String>[
                  if (series.year != null) '${series.year}',
                  if (series.network != null && series.network!.isNotEmpty)
                    series.network!,
                  if (series.status != null) series.status!,
                ].join(' • '),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              if (st != null) ...<Widget>[
                const SizedBox(height: Insets.sm),
                Text(
                  '${st.episodeFileCount}/${st.totalEpisodeCount} episodes',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: Insets.xs),
                LinearProgressIndicator(
                  value: st.totalEpisodeCount == 0
                      ? 0
                      : (st.episodeFileCount / st.totalEpisodeCount)
                          .clamp(0, 1)
                          .toDouble(),
                ),
                const SizedBox(height: Insets.xs),
                Text(
                  _fmtSize(st.sizeOnDisk),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionsRow extends ConsumerWidget {
  const _ActionsRow({
    required this.instance,
    required this.series,
    required this.onChanged,
  });

  final Instance instance;
  final SonarrSeries series;
  final void Function(WidgetRef) onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: <Widget>[
        Expanded(
          child: FilledButton.tonalIcon(
            icon: Icon(
              series.monitored ? Icons.bookmark : Icons.bookmark_border,
            ),
            label: Text(series.monitored ? 'Monitored' : 'Unmonitored'),
            onPressed: () async {
              final SonarrApi api =
                  await ref.read(sonarrApiProvider(instance).future);
              final Map<String, dynamic> raw =
                  await api.getSeriesRaw(series.id);
              raw['monitored'] = !series.monitored;
              await api.updateSeriesRaw(raw);
              onChanged(ref);
            },
          ),
        ),
        const SizedBox(width: Insets.sm),
        Expanded(
          child: FilledButton.icon(
            icon: const Icon(Icons.search),
            label: const Text('Search all'),
            onPressed: () async {
              final SonarrApi api =
                  await ref.read(sonarrApiProvider(instance).future);
              await api.searchSeries(series.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Search started for all monitored episodes'),
                  ),
                );
              }
            },
          ),
        ),
      ],
    );
  }
}

class _SeasonTile extends ConsumerWidget {
  const _SeasonTile({
    required this.instance,
    required this.series,
    required this.season,
    required this.onChanged,
    required this.episodesValue,
  });

  final Instance instance;
  final SonarrSeries series;
  final SonarrSeasonStats season;
  final void Function(WidgetRef) onChanged;
  final AsyncValue<List<SonarrEpisode>> episodesValue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SonarrSeasonStatistics? st = season.statistics;
    final String label = season.seasonNumber == 0
        ? 'Specials'
        : 'Season ${season.seasonNumber}';

    final String statsStr = st == null
        ? ''
        : '${st.episodeFileCount}/${st.totalEpisodeCount} episodes'
            '${st.sizeOnDisk > 0 ? ' • ${_fmtSize(st.sizeOnDisk)}' : ''}';

    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        title: Text(label),
        subtitle: Text(statsStr),
        leading: IconButton(
          tooltip: season.monitored ? 'Unmonitor season' : 'Monitor season',
          icon: Icon(
            season.monitored ? Icons.bookmark : Icons.bookmark_border,
          ),
          onPressed: () => _toggleSeason(ref),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'Manual search',
              icon: const Icon(Icons.manage_search),
              onPressed: () {
                Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SonarrReleaseSearchScreen(
                      instance: instance,
                      seriesId: series.id,
                      seasonNumber: season.seasonNumber,
                      seriesTitle: series.title,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: 'Search season',
              icon: const Icon(Icons.search),
              onPressed: () async {
                final SonarrApi api =
                    await ref.read(sonarrApiProvider(instance).future);
                await api.searchSeason(series.id, season.seasonNumber);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Search started for $label')),
                  );
                }
              },
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        children: <Widget>[
          const Divider(height: 1),
          episodesValue.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: Insets.md),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (Object err, StackTrace? stack) => Padding(
              padding: const EdgeInsets.all(Insets.md),
              child: Center(
                child: Text(
                  'Error loading episodes: $err',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ),
            data: (List<SonarrEpisode> list) {
              final List<SonarrEpisode> seasonEpisodes = list
                  .where((SonarrEpisode ep) => ep.seasonNumber == season.seasonNumber)
                  .toList();

              if (seasonEpisodes.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: Insets.md),
                  child: Center(child: Text('No episodes found')),
                );
              }

              // Sort by episode number ascending
              seasonEpisodes.sort((SonarrEpisode a, SonarrEpisode b) =>
                  a.episodeNumber - b.episodeNumber);

              return Column(
                children: <Widget>[
                  for (final SonarrEpisode ep in seasonEpisodes) ...[
                    _EpisodeTile(
                      instance: instance,
                      seriesId: series.id,
                      episode: ep,
                    ),
                    if (ep != seasonEpisodes.last) const Divider(height: 1, indent: Insets.xl),
                  ],
                  const SizedBox(height: Insets.xs),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSeason(WidgetRef ref) async {
    final SonarrApi api = await ref.read(sonarrApiProvider(instance).future);
    final Map<String, dynamic> raw = await api.getSeriesRaw(series.id);
    final List<dynamic> seasons = raw['seasons'] as List<dynamic>;
    for (final dynamic s in seasons) {
      final Map<String, dynamic> sm = s as Map<String, dynamic>;
      if (sm['seasonNumber'] == season.seasonNumber) {
        sm['monitored'] = !season.monitored;
      }
    }
    await api.updateSeriesRaw(raw);
    onChanged(ref);
  }
}

class _EpisodeTile extends ConsumerWidget {
  const _EpisodeTile({
    required this.instance,
    required this.seriesId,
    required this.episode,
  });

  final Instance instance;
  final int seriesId;
  final SonarrEpisode episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final String epCode = 'E${episode.episodeNumber.toString().padLeft(2, '0')}';
    final DateTime? airDate = episode.airDateUtc?.toLocal();
    final String airDateStr = airDate != null
        ? DateFormat('yMMMd').format(airDate)
        : 'Unknown air date';

    final bool isFuture = airDate != null && airDate.isAfter(DateTime.now());
    final (String label, Color bg, Color fg) = episode.hasFile
        ? (
            'Downloaded',
            theme.colorScheme.primaryContainer,
            theme.colorScheme.onPrimaryContainer,
          )
        : isFuture
            ? (
                'Upcoming',
                theme.colorScheme.secondaryContainer,
                theme.colorScheme.onSecondaryContainer,
              )
            : (
                'Missing',
                theme.colorScheme.errorContainer,
                theme.colorScheme.onErrorContainer,
              );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: Insets.md),
      child: Row(
        children: <Widget>[
          // Monitored Toggle
          IconButton(
            icon: Icon(
              episode.monitored ? Icons.bookmark : Icons.bookmark_border,
              size: 20,
              color: episode.monitored ? theme.colorScheme.primary : theme.colorScheme.outline,
            ),
            tooltip: episode.monitored ? 'Stop monitoring' : 'Monitor episode',
            onPressed: () async {
              final SonarrApi api = await ref.read(sonarrApiProvider(instance).future);
              await api.updateEpisode(episode.copyWith(monitored: !episode.monitored));
              ref.invalidate(sonarrEpisodesProvider((instance, seriesId)));
            },
          ),
          const SizedBox(width: Insets.xs),
          // Episode info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$epCode • ${episode.title ?? "Episode ${episode.episodeNumber}"}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  airDateStr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: fg,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: Insets.xs),
          // Manual Search Button
          IconButton(
            icon: const Icon(Icons.manage_search, size: 20),
            tooltip: 'Manual search',
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  builder: (_) => SonarrReleaseSearchScreen(
                    instance: instance,
                    episode: episode,
                  ),
                ),
              );
            },
          ),
          // Search Button (Automatic)
          IconButton(
            icon: const Icon(Icons.search, size: 20),
            tooltip: 'Automatic search',
            onPressed: () async {
              final SonarrApi api = await ref.read(sonarrApiProvider(instance).future);
              await api.searchEpisode(episode.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Search started for $epCode • ${episode.title ?? "Episode"}',
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

class _SeriesMenu extends ConsumerWidget {
  const _SeriesMenu({required this.instance, required this.series});

  final Instance instance;
  final SonarrSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (String v) async {
        if (v == 'delete') {
          await _confirmDelete(context, ref);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Delete series'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    bool deleteFiles = false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => AlertDialog(
          title: const Text('Delete series?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(series.title),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Also delete files on disk'),
                value: deleteFiles,
                onChanged: (bool? v) =>
                    setState(() => deleteFiles = v ?? false),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (ok ?? false) {
      final SonarrApi api = await ref.read(sonarrApiProvider(instance).future);
      await api.deleteSeries(series.id, deleteFiles: deleteFiles);
      ref.invalidate(sonarrSeriesProvider(instance));
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

String _fmtSize(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final String text =
      value >= 100 || unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}
