import 'package:core_models/core_models.dart';
import 'package:core_router/core_router.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:service_radarr/service_radarr.dart';
import 'package:service_sonarr/service_sonarr.dart';

import '../../arr_artwork.dart';
import '../dashboard_widget_card.dart';
import '../dashboard_widget_kind.dart';

class _RecentItem {
  const _RecentItem({
    required this.title,
    required this.added,
    required this.isMovie,
    required this.instance,
    this.posterUrl,
    this.year,
    this.series,
    this.movieId,
  });

  final String title;
  final DateTime added;
  final bool isMovie;
  final Instance instance;
  final String? posterUrl;
  final int? year;

  /// Set for a series; the detail screen takes the whole object.
  final SonarrSeries? series;

  /// Set for a movie; the detail screen looks it up by id.
  final int? movieId;
}

/// The most recently added Sonarr series and Radarr movies across every
/// instance, merged and shown as a horizontally scrollable poster row.
class DashboardRecentlyAddedWidget extends ConsumerStatefulWidget {
  const DashboardRecentlyAddedWidget({
    required this.sonarrInstances,
    required this.radarrInstances,
    super.key,
  });

  final List<Instance> sonarrInstances;
  final List<Instance> radarrInstances;

  @override
  ConsumerState<DashboardRecentlyAddedWidget> createState() =>
      _DashboardRecentlyAddedWidgetState();
}

class _DashboardRecentlyAddedWidgetState
    extends ConsumerState<DashboardRecentlyAddedWidget> {
  final ScrollController _scrollController = ScrollController();
  bool _needsReset = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    final List<_RecentItem> items = <_RecentItem>[];
    bool anyLoading = false;
    bool anyError = false;

    for (final Instance i in widget.sonarrInstances) {
      final AsyncValue<List<SonarrSeries>> series =
          ref.watch(sonarrSeriesProvider(i));
      anyLoading |= series.isLoading && !series.hasValue;
      anyError |= series.hasError;
      final SonarrApi? sonarrApi = ref.watch(sonarrApiProvider(i)).value;
      for (final SonarrSeries s in series.value ?? const <SonarrSeries>[]) {
        final DateTime? added = DateTime.tryParse(s.added ?? '');
        if (added == null) {
          continue;
        }
        items.add(_RecentItem(
          title: s.title,
          added: added,
          isMovie: false,
          instance: i,
          year: s.year,
          series: s,
          posterUrl: sonarrPosterUrl(sonarrApi, s.images),
        ));
      }
    }
    for (final Instance i in widget.radarrInstances) {
      final AsyncValue<List<RadarrMovie>> movies =
          ref.watch(radarrMoviesProvider(i));
      anyLoading |= movies.isLoading && !movies.hasValue;
      anyError |= movies.hasError;
      final RadarrApi? radarrApi = ref.watch(radarrApiProvider(i)).value;
      for (final RadarrMovie m in movies.value ?? const <RadarrMovie>[]) {
        final DateTime? added = DateTime.tryParse(m.added ?? '');
        if (added == null) {
          continue;
        }
        items.add(_RecentItem(
          title: m.title,
          added: added,
          isMovie: true,
          instance: i,
          year: m.year,
          movieId: m.id,
          posterUrl: radarrPosterUrl(radarrApi, m.images),
        ));
      }
    }

    if (anyLoading) {
      _needsReset = true;
    }

    items.sort((_RecentItem a, _RecentItem b) => b.added.compareTo(a.added));
    final List<_RecentItem> top = items.take(15).toList();

    Widget body;
    if (items.isEmpty && anyLoading) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(Insets.sm),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    } else if (items.isEmpty && anyError) {
      body = DashboardErrorRow(
        onRetry: () {
          for (final Instance i in widget.sonarrInstances) {
            ref.invalidate(sonarrSeriesProvider(i));
          }
          for (final Instance i in widget.radarrInstances) {
            ref.invalidate(radarrMoviesProvider(i));
          }
        },
      );
    } else if (items.isEmpty) {
      body = const DashboardIdleRow(text: 'Nothing added yet');
    } else {
      if (_needsReset) {
        _needsReset = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients &&
              _scrollController.position.hasContentDimensions) {
            _scrollController.jumpTo(0.0);
          }
        });
      }
      body = SizedBox(
        height: 184,
        child: ListView.separated(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          itemCount: top.length,
          separatorBuilder: (_, __) => const SizedBox(width: Insets.sm),
          itemBuilder: (BuildContext context, int index) =>
              _PosterTile(item: top[index]),
        ),
      );
    }

    return DashboardWidgetCard(
      kind: DashboardWidgetKind.recentlyAdded,
      accent: cs.primary,
      child: body,
    );
  }
}

/// Opens the tapped title's own detail screen, falling back to its service
/// when the item arrived without an identity so a tap always lands somewhere.
void _openDetail(BuildContext context, _RecentItem item) {
  if (item.isMovie) {
    final int? movieId = item.movieId;
    if (movieId != null) {
      pushScreen<void>(
        context,
        MovieDetailScreen(instance: item.instance, movieId: movieId),
      );
      return;
    }
  } else {
    final SonarrSeries? series = item.series;
    if (series != null) {
      pushScreen<void>(
        context,
        SeriesDetailScreen(instance: item.instance, series: series),
      );
      return;
    }
  }
  context.go(
    AtriumRoutes.servicePath(item.instance.kind.name, item.instance.id),
  );
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({required this.item});

  final _RecentItem item;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String? poster = item.posterUrl;
    final String subtitle = <String>[
      item.isMovie ? 'Movie' : 'Series',
      if (item.year != null) '${item.year}',
    ].join(' · ');

    return SizedBox(
      width: 94,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openDetail(context, item),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 94,
                height: 140,
                child: (poster == null || poster.isEmpty)
                    ? _posterFallback(cs)
                    : AtriumNetworkImage(
                        imageUrl: poster,
                        fit: BoxFit.cover,
                        memCacheWidth: 220,
                        errorWidget: (_, __, ___) => _posterFallback(cs),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _posterFallback(ColorScheme cs) => Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          item.isMovie ? Icons.movie_outlined : Icons.live_tv_outlined,
          size: 22,
          color: cs.onSurfaceVariant,
        ),
      );
}
