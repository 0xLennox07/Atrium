import 'dart:async';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../service_radarr.dart';

class MovieDetailScreen extends ConsumerWidget {
  const MovieDetailScreen({
    required this.instance,
    required this.movieId,
    this.movie,
    super.key,
  });

  final Instance instance;
  final int movieId;
  final RadarrMovie? movie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RadarrMovie> movieAsync =
        ref.watch(radarrMovieByIdProvider((instance, movieId)));

    final RadarrMovie? activeMovie = movieAsync.value ?? movie;

    if (activeMovie != null) {
      return Scaffold(
        body: _MovieDetailBody(
          instance: instance,
          movie: activeMovie,
        ),
      );
    }

    return Scaffold(
      body: movieAsync.when(
        data: (movie) => _MovieDetailBody(
          instance: instance,
          movie: movie,
        ),
        loading: () => const Center(child: ExpressiveProgressIndicator()),
        error: (error, stack) => Scaffold(
          appBar: AppBar(title: const Text('Error')),
          body: ErrorView(
            title: 'Failed to load movie details',
            message: error.toString(),
            onRetry: () =>
                ref.invalidate(radarrMovieByIdProvider((instance, movieId))),
          ),
        ),
      ),
    );
  }
}

class _MovieDetailBody extends ConsumerStatefulWidget {
  const _MovieDetailBody({
    required this.instance,
    required this.movie,
  });

  final Instance instance;
  final RadarrMovie movie;

  @override
  ConsumerState<_MovieDetailBody> createState() => _MovieDetailBodyState();
}

class _MovieDetailBodyState extends ConsumerState<_MovieDetailBody> {
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
      final api = await ref.read(radarrApiProvider(widget.instance).future);
      await api.runCommand(<String, dynamic>{
        'name': 'RefreshMovie',
        'movieId': widget.movie.id,
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
      }
    }
  }

  void _invalidateProviders() {
    ref.invalidate(radarrMovieByIdProvider((widget.instance, widget.movie.id)));
    ref.invalidate(radarrMoviesProvider(widget.instance));
    ref.invalidate(radarrQueueProvider(widget.instance));
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final RadarrApi? api = ref.watch(radarrApiProvider(widget.instance)).value;

    final RadarrImage? poster = widget.movie.images
        .firstWhereOrNull((RadarrImage i) => i.coverType == 'poster');
    final String? posterUrl =
        poster == null ? null : api?.posterUrl(poster, width: 500);

    final RadarrImage? fanart = widget.movie.images
        .firstWhereOrNull((RadarrImage i) => i.coverType == 'fanart');
    final String? fanartUrl =
        fanart == null ? null : api?.posterUrl(fanart, width: 1080);

    final queueAsync = ref.watch(radarrMovieQueueProvider((widget.instance, widget.movie.id)));
    final download = queueAsync.value?.firstOrNull;

    double? dlProgress;
    if (download != null) {
      final double totalSize = download.size ?? 0.0;
      final double sizeLeft = download.sizeleft ?? 0.0;
      if (totalSize > 0) {
        dlProgress = (totalSize - sizeLeft) / totalSize;
      }
    }

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
                movie: widget.movie,
                onRefreshed: _invalidateProviders,
              ),
            ],
            title: CollapsedTitle(
              controller: _scrollController,
              title: widget.movie.title,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: _Backdrop(fanartUrl: fanartUrl),
            ),
          ),
          const HeaderLocator.sliver(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.sm,
              Insets.lg,
              Insets.xl,
            ),
            sliver: SliverList.list(
              children: <Widget>[
                _HeroInfoCard(
                  movie: widget.movie,
                  posterUrl: posterUrl,
                ),
                if (download != null) ...[
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      side: BorderSide(
                        color: cs.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    color: cs.primaryContainer.withValues(alpha: 0.1),
                    margin: const EdgeInsets.only(top: Insets.lg),
                    child: Padding(
                      padding: const EdgeInsets.all(Insets.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.downloading, color: cs.primary),
                              const SizedBox(width: Insets.sm),
                              Expanded(
                                child: Text(
                                  'Downloading • ETA: ${_formatTimeLeft(download.timeleft)}',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                              if (dlProgress != null)
                                Text(
                                  '${(dlProgress * 100).toStringAsFixed(0)}%',
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: cs.primary,
                                  ),
                                ),
                            ],
                          ),
                          if (dlProgress != null) ...[
                            const SizedBox(height: Insets.sm),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: dlProgress,
                                minHeight: 6,
                                backgroundColor: cs.primaryContainer.withValues(alpha: 0.3),
                                color: cs.primary,
                              ),
                            ),
                          ],
                          const SizedBox(height: Insets.xs),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Client: ${download.downloadClient ?? 'unknown'}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.outline,
                                ),
                              ),
                              Text(
                                'Indexer: ${download.indexer ?? 'unknown'}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.outline,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: Insets.lg),
                _ActionsRow(
                  instance: widget.instance,
                  movie: widget.movie,
                  onRefreshed: _invalidateProviders,
                ),
                if (widget.movie.genres.isNotEmpty) ...[
                  const SizedBox(height: Insets.lg),
                  Wrap(
                    spacing: Insets.sm,
                    runSpacing: Insets.sm,
                    children: widget.movie.genres
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
                if (widget.movie.overview != null &&
                    widget.movie.overview!.isNotEmpty) ...[
                  const SizedBox(height: Insets.lg),
                  _OverviewSection(overview: widget.movie.overview!),
                ],
                const SizedBox(height: Insets.lg),
                _FileSection(movie: widget.movie),
                const SizedBox(height: Insets.lg),
                _ReleaseDatesSection(movie: widget.movie),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }
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
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                cs.surface.withValues(alpha: 0.0),
                cs.surface.withValues(alpha: 0.55),
                cs.surface,
              ],
              stops: const <double>[0.35, 0.75, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroInfoCard extends StatelessWidget {
  const _HeroInfoCard({required this.movie, required this.posterUrl});

  final RadarrMovie movie;
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
          Hero(
            tag: 'movie-poster-${movie.id}',
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
                              Icons.movie_outlined,
                              color: cs.outline,
                            ),
                          ),
                        )
                      : Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.movie_outlined,
                            color: cs.outline,
                            size: 36,
                          ),
                        ),
                ),
              ),
            ),
          ),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  movie.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: Insets.sm),
                Wrap(
                  spacing: Insets.xs,
                  runSpacing: 4,
                  children: <Widget>[
                    if (movie.year != null) _InfoChip(label: '${movie.year}'),
                    if (movie.runtime != null && movie.runtime! > 0)
                      _InfoChip(label: '${movie.runtime} min'),
                    if (movie.studio != null && movie.studio!.isNotEmpty)
                      _InfoChip(label: movie.studio!),
                  ],
                ),
                const SizedBox(height: Insets.sm),
                _StatusPill(movie: movie),
                if (movie.ratings?.tmdb != null &&
                    movie.ratings!.tmdb!.value > 0) ...<Widget>[
                  const SizedBox(height: Insets.md),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.star,
                        size: 14,
                        color: cs.tertiary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        movie.ratings!.tmdb!.value.toStringAsFixed(1),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.outline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.movie});

  final RadarrMovie movie;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final bool hasFile = movie.hasFile;
    final Color background = hasFile ? cs.primaryContainer : cs.errorContainer;
    final Color tint = hasFile ? cs.onPrimaryContainer : cs.onErrorContainer;
    final String label = hasFile ? 'Downloaded' : 'Missing';
    final IconData icon = hasFile ? Icons.check : Icons.warning_amber_rounded;

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: tint),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: tint,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({required this.overview});

  final String overview;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Overview',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: Insets.sm),
            Text(
              overview,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileSection extends StatelessWidget {
  const _FileSection({required this.movie});

  final RadarrMovie movie;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'File Information',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: Insets.md),
            _buildDetailRow(
              context,
              'Status',
              movie.hasFile ? 'File downloaded' : 'File missing',
              icon: movie.hasFile
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              iconColor: movie.hasFile ? cs.primary : cs.error,
            ),
            if (movie.hasFile && movie.sizeOnDisk > 0) ...[
              const Divider(height: 24),
              _buildDetailRow(
                context,
                'Size on Disk',
                _formatSize(movie.sizeOnDisk),
                icon: Icons.sd_storage_outlined,
              ),
            ],
            if (movie.path != null && movie.path!.isNotEmpty) ...[
              const Divider(height: 24),
              _buildDetailRow(
                context,
                'Path',
                movie.path!,
                icon: Icons.folder_open_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    required IconData icon,
    Color? iconColor,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 20, color: iconColor ?? cs.outline),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.outline,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReleaseDatesSection extends StatelessWidget {
  const _ReleaseDatesSection({required this.movie});

  final RadarrMovie movie;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final DateFormat formatter = DateFormat.yMMMd();

    DateTime? inCinemasDate;
    if (movie.inCinemas != null && movie.inCinemas!.isNotEmpty) {
      inCinemasDate = DateTime.tryParse(movie.inCinemas!)?.toLocal();
    }
    DateTime? physicalReleaseDate;
    if (movie.physicalRelease != null && movie.physicalRelease!.isNotEmpty) {
      physicalReleaseDate =
          DateTime.tryParse(movie.physicalRelease!)?.toLocal();
    }
    DateTime? digitalReleaseDate;
    if (movie.digitalRelease != null && movie.digitalRelease!.isNotEmpty) {
      digitalReleaseDate = DateTime.tryParse(movie.digitalRelease!)?.toLocal();
    }

    if (inCinemasDate == null &&
        physicalReleaseDate == null &&
        digitalReleaseDate == null) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(Insets.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Release Dates',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: Insets.md),
            if (inCinemasDate != null)
              _buildReleaseRow(
                context,
                'In Cinemas',
                formatter.format(inCinemasDate),
                Icons.local_play_outlined,
              ),
            if (digitalReleaseDate != null) ...[
              if (inCinemasDate != null) const Divider(height: 24),
              _buildReleaseRow(
                context,
                'Digital Release',
                formatter.format(digitalReleaseDate),
                Icons.language_outlined,
              ),
            ],
            if (physicalReleaseDate != null) ...[
              if (inCinemasDate != null || digitalReleaseDate != null)
                const Divider(height: 24),
              _buildReleaseRow(
                context,
                'Physical Release',
                formatter.format(physicalReleaseDate),
                Icons.album_outlined,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReleaseRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Row(
      children: <Widget>[
        Icon(icon, size: 20, color: cs.outline),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.outline,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionsRow extends ConsumerWidget {
  const _ActionsRow({
    required this.instance,
    required this.movie,
    required this.onRefreshed,
  });

  final Instance instance;
  final RadarrMovie movie;
  final VoidCallback onRefreshed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);

    return Row(
      children: <Widget>[
        Expanded(
          child: movie.monitored
              ? FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.8),
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
                    side: BorderSide(color: theme.colorScheme.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.bookmark_border, size: 20),
                  label: const Text('Unmonitored'),
                  onPressed: () => _toggleMonitored(context, ref),
                ),
        ),
        const SizedBox(width: Insets.md),
        Expanded(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.search, size: 20),
            label: const Text(
              'Search',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              final ScaffoldMessengerState messenger =
                  ScaffoldMessenger.of(context);
              try {
                final RadarrApi api =
                    await ref.read(radarrApiProvider(instance).future);
                await api.runCommand(<String, dynamic>{
                  'name': 'MoviesSearch',
                  'movieIds': <int>[movie.id],
                });
                messenger.showSnackBar(
                  const SnackBar(content: Text('Search started')),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(content: Text('Failed to start search: $e')),
                );
              }
            },
          ),
        ),
        const SizedBox(width: Insets.sm),
        IconButton.filledTonal(
          icon: const Icon(Icons.manage_search),
          tooltip: 'Manual search',
          onPressed: () {
            Navigator.of(context, rootNavigator: true).push(
              FadePageRoute<void>(
                builder: (_) => RadarrReleaseSearchScreen(
                  instance: instance,
                  movie: movie,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _toggleMonitored(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final RadarrApi api = await ref.read(radarrApiProvider(instance).future);
      final Map<String, dynamic> raw = await api.getMovieRaw(movie.id);
      raw['monitored'] = !movie.monitored;
      if (raw['qualityProfileId'] == null || raw['qualityProfileId'] == 0) {
        final profiles = await api.getQualityProfiles();
        if (profiles.isNotEmpty) {
          raw['qualityProfileId'] = profiles.first['id'];
        }
      }
      await api.updateMovieRaw(raw);
      onRefreshed();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to update monitoring: $e')),
      );
    }
  }
}

class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({
    required this.instance,
    required this.movie,
    required this.onRefreshed,
    required this.iconColor,
  });

  final Instance instance;
  final RadarrMovie movie;
  final VoidCallback onRefreshed;
  final Color iconColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: iconColor),
      onSelected: (String v) async {
        if (v == 'delete') {
          await _confirmDelete(context, ref);
        } else if (v == 'delete_file') {
          await _confirmDeleteFile(context, ref);
        } else if (v == 'rename') {
          await _showRenameDialog(context);
        } else if (v == 'edit') {
          _showEditScreen(context);
        } else if (v == 'history') {
          _showHistoryScreen(context);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('Edit settings'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'rename',
          child: ListTile(
            leading: Icon(Icons.drive_file_rename_outline),
            title: Text('Rename files'),
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
        if (movie.hasFile && movie.movieFileId != null)
          const PopupMenuItem<String>(
            value: 'delete_file',
            child: ListTile(
              leading: Icon(Icons.delete_sweep_outlined),
              title: Text('Delete movie file'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Delete movie'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  void _showEditScreen(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      FadePageRoute<void>(
        builder: (_) => RadarrSettingsFormScreen(
          instance: instance,
          movie: movie,
        ),
      ),
    );
  }

  void _showHistoryScreen(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      FadePageRoute<void>(
        builder: (_) => RadarrMovieHistoryScreen(
          instance: instance,
          movie: movie,
        ),
      ),
    );
  }

  Future<void> _showRenameDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) => RadarrRenameDialog(
        instance: instance,
        movieId: movie.id,
      ),
    );
  }

  Future<void> _confirmDeleteFile(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    bool unmonitor = false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => AlertDialog(
          title: const Text('Delete movie file?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Are you sure you want to delete the file for "${movie.title}" from disk? The movie entry will remain in Radarr.',
              ),
              const SizedBox(height: Insets.sm),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Unmonitor movie'),
                subtitle: const Text('Prevent automatic re-downloads'),
                value: unmonitor,
                onChanged: (bool? v) => setState(() => unmonitor = v ?? false),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete File'),
            ),
          ],
        ),
      ),
    );
    if (!(ok ?? false)) return;
    if (!context.mounted) return;
    try {
      final RadarrApi api = await ref.read(radarrApiProvider(instance).future);
      if (movie.movieFileId != null) {
        await api.deleteMovieFile(movie.movieFileId!);
      }
      bool unmonitored = false;
      Object? unmonitorError;
      if (unmonitor) {
        try {
          final Map<String, dynamic> raw = await api.getMovieRaw(movie.id);
          raw['monitored'] = false;
          if (raw['qualityProfileId'] == null || raw['qualityProfileId'] == 0) {
            final profiles = await api.getQualityProfiles();
            if (profiles.isNotEmpty) {
              raw['qualityProfileId'] = profiles.first['id'];
            }
          }
          await api.updateMovieRaw(raw);
          unmonitored = true;
        } catch (e) {
          unmonitorError = e;
        }
      }
      ref.invalidate(radarrMovieByIdProvider((instance, movie.id)));
      ref.invalidate(radarrMoviesProvider(instance));
      onRefreshed();
      if (unmonitor && !unmonitored) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'File deleted, but failed to unmonitor movie: $unmonitorError',
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              unmonitored
                  ? 'File deleted and movie unmonitored.'
                  : 'File deleted from disk.',
            ),
          ),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete file: $e')),
      );
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    bool deleteFiles = false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => AlertDialog(
          title: const Text('Delete movie?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(movie.title),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Also delete file on disk'),
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
    if (!(ok ?? false)) return;
    if (!context.mounted) return;
    try {
      final RadarrApi api = await ref.read(radarrApiProvider(instance).future);
      await api.deleteMovie(movie.id, deleteFiles: deleteFiles);
      ref.invalidate(radarrMoviesProvider(instance));
      if (context.mounted) {
        // Pop back to movie list screen
        Navigator.of(context).pop();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to delete movie: $e')),
      );
    }
  }
}

String _formatSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  final i = (log(bytes) / log(1024)).floor();
  return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
}

class FadePageRoute<T> extends PageRouteBuilder<T> {
  FadePageRoute({required WidgetBuilder builder, super.settings})
      : super(
          pageBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
          ) =>
              builder(context),
          transitionsBuilder: (
            BuildContext context,
            Animation<double> animation,
            Animation<double> secondaryAnimation,
            Widget child,
          ) {
            return FadeTransition(
              opacity: animation,
              child: child,
            );
          },
          transitionDuration: const Duration(milliseconds: 300),
          reverseTransitionDuration: const Duration(milliseconds: 250),
        );
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
  final RadarrMovie movie;
  final VoidCallback onRefreshed;

  const _AppBarActions({
    required this.controller,
    required this.instance,
    required this.movie,
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
          movie: widget.movie,
          onRefreshed: widget.onRefreshed,
          iconColor: iconColor,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Movie History Screen
// ---------------------------------------------------------------------------

class RadarrMovieHistoryScreen extends ConsumerWidget {
  const RadarrMovieHistoryScreen({
    super.key,
    required this.instance,
    required this.movie,
  });

  final Instance instance;
  final RadarrMovie movie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final historyAsync = ref.watch(
      radarrMovieHistoryProvider((instance, movie.id)),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${movie.title} - History'),
        surfaceTintColor: Colors.transparent,
      ),
      body: historyAsync.when(
        loading: () => const Center(child: ExpressiveProgressIndicator()),
        error: (Object error, StackTrace? _) => ErrorView(
          title: 'Failed to load history',
          message: error.toString(),
          onRetry: () => ref.invalidate(radarrMovieHistoryProvider((instance, movie.id))),
        ),
        data: (List<RadarrHistoryItem> items) {
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
              ref.invalidate(radarrMovieHistoryProvider((instance, movie.id)));
              await ref.read(radarrMovieHistoryProvider((instance, movie.id)).future);
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
                final RadarrHistoryItem item = items[index];
                final String formattedDate = _formatDateTime(item.date);

                return ListTile(
                  leading: _buildHistoryEventIcon(context, item.eventType),
                  title: Text(
                    item.eventType?.toUpperCase() ?? 'UNKNOWN',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    item.sourceTitle ?? 'No release title',
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
                  onTap: () => _showHistoryDetails(context, ref, instance, movie.id, item),
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
      icon = Icons.download_done_outlined;
      color = theme.colorScheme.primary;
      break;
    case 'failed':
      icon = Icons.error_outline;
      color = theme.colorScheme.error;
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
  int movieId,
  RadarrHistoryItem item,
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
                  final RadarrApi api =
                      await ref.read(radarrApiProvider(instance).future);
                  await api.failHistoryItem(item.id);
                  ref.invalidate(radarrMovieHistoryProvider((instance, movieId)));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Marked release as failed. Radarr will search for replacements.',
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

