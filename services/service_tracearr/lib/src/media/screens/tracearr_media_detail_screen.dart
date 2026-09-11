import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../providers/tracearr_providers.dart';
import 'widgets/media_availability_card.dart';
import 'widgets/media_dedicated_history_feed.dart';
import 'widgets/media_tv_hierarchy_view.dart';
import 'widgets/media_watchers_leaderboard.dart';

/// Deep media intelligence detail screen for Tracearr in Atrium.
class TracearrMediaDetailScreen extends ConsumerStatefulWidget {
  const TracearrMediaDetailScreen({
    required this.instance,
    required this.mediaRef,
    this.initialTitle,
    this.initialShowTitle,
    this.initialPosterUrl,
    this.initialSeasonNumber,
    this.initialEpisodeNumber,
    super.key,
  });

  final Instance instance;
  final String mediaRef;
  final String? initialTitle;
  final String? initialShowTitle;
  final String? initialPosterUrl;
  final int? initialSeasonNumber;
  final int? initialEpisodeNumber;

  static Future<void> navigate(
    BuildContext context, {
    required Instance instance,
    required String mediaRef,
    String? initialTitle,
    String? initialShowTitle,
    String? initialPosterUrl,
    int? initialSeasonNumber,
    int? initialEpisodeNumber,
  }) {
    return pushScreen<void>(
      context,
      TracearrMediaDetailScreen(
        instance: instance,
        mediaRef: mediaRef,
        initialTitle: initialTitle,
        initialShowTitle: initialShowTitle,
        initialPosterUrl: initialPosterUrl,
        initialSeasonNumber: initialSeasonNumber,
        initialEpisodeNumber: initialEpisodeNumber,
      ),
    );
  }

  @override
  ConsumerState<TracearrMediaDetailScreen> createState() =>
      _TracearrMediaDetailScreenState();
}

class _TracearrMediaDetailScreenState
    extends ConsumerState<TracearrMediaDetailScreen> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _formatWatchTime(int ms) {
    if (ms <= 0) return '0h';
    final double hours = ms / (1000 * 60 * 60);
    return '${hours.toStringAsFixed(1)}h';
  }

  Future<void> _openExternalLink(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not open link: $url'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  Widget _buildFallbackHero(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerLow,
      child: Center(
        child: Icon(
          Icons.movie_outlined,
          size: 64,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final detailAsync = ref.watch(
      tracearrMediaDetailProvider((widget.instance, widget.mediaRef)),
    );

    return Scaffold(
      body: detailAsync.when(
        loading: () => Scaffold(
          appBar: AppBar(
            title: Text(widget.initialTitle ?? 'Media Detail'),
          ),
          body: const Center(child: ExpressiveProgressIndicator()),
        ),
        error: (err, stack) => Scaffold(
          appBar: AppBar(
            title: Text(widget.initialTitle ?? 'Media Detail'),
          ),
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(Insets.md),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.error_outline, size: 48, color: colorScheme.error),
                  const SizedBox(height: Insets.md),
                  Text(
                    'Failed to load media details',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    err.toString(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: Insets.md),
                  FilledButton.tonalIcon(
                    onPressed: () => ref.invalidate(
                      tracearrMediaDetailProvider(
                        (
                          widget.instance,
                          widget.mediaRef,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
        data: (detail) {
          final isEpisode = detail.mediaType.toLowerCase() == 'episode';
          final isSeason = detail.mediaType.toLowerCase() == 'season';
          final hasParentShow = (isEpisode || isSeason) &&
              detail.showMediaId != null &&
              detail.showMediaId!.isNotEmpty;

          final parentShowAsync = hasParentShow
              ? ref.watch(
                  tracearrMediaDetailProvider(
                    (
                      widget.instance,
                      detail.showMediaId!,
                    ),
                  ),
                )
              : null;

          final parentPosterUrl = parentShowAsync?.value?.posterUrl;
          final resolvedShowTitle =
              widget.initialShowTitle ?? parentShowAsync?.value?.title;

          final effectivePosterUrl = (isEpisode || isSeason)
              ? (widget.initialPosterUrl ?? parentPosterUrl ?? detail.posterUrl)
              : (detail.posterUrl ?? widget.initialPosterUrl);

          final heroFallbackPoster = widget.initialPosterUrl ?? parentPosterUrl;

          return CustomScrollView(
            controller: _scrollController,
            slivers: [
              // Hero AppBar with Media Poster
              SliverAppBar(
                expandedHeight: 300,
                pinned: true,
                title: CollapsedTitle(
                  controller: _scrollController,
                  title: isEpisode &&
                          (widget.initialSeasonNumber != null ||
                              widget.initialEpisodeNumber != null)
                      ? 'S${widget.initialSeasonNumber ?? 1}:E${widget.initialEpisodeNumber ?? 1} • ${detail.title}'
                      : detail.title,
                ),
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (effectivePosterUrl != null &&
                          effectivePosterUrl.isNotEmpty)
                        AtriumNetworkImage(
                          imageUrl: effectivePosterUrl,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) {
                            if (heroFallbackPoster != null &&
                                heroFallbackPoster.isNotEmpty &&
                                heroFallbackPoster != effectivePosterUrl) {
                              return AtriumNetworkImage(
                                imageUrl: heroFallbackPoster,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    _buildFallbackHero(colorScheme),
                              );
                            }
                            return _buildFallbackHero(colorScheme);
                          },
                        )
                      else if (heroFallbackPoster != null &&
                          heroFallbackPoster.isNotEmpty)
                        AtriumNetworkImage(
                          imageUrl: heroFallbackPoster,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) =>
                              _buildFallbackHero(colorScheme),
                        )
                      else
                        _buildFallbackHero(colorScheme),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black54,
                              Colors.black87,
                            ],
                            stops: [0.4, 0.75, 1.0],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Detail Sections
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(Insets.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Full Unclipped Title Header
                      if (isEpisode) ...[
                        if (resolvedShowTitle != null &&
                            resolvedShowTitle.isNotEmpty) ...[
                          Text(
                            resolvedShowTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: Insets.xxs),
                        ],
                        Text(
                          (widget.initialSeasonNumber != null ||
                                  widget.initialEpisodeNumber != null)
                              ? 'S${widget.initialSeasonNumber ?? 1}:E${widget.initialEpisodeNumber ?? 1} • ${detail.title}'
                              : detail.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ] else if (isSeason) ...[
                        if (resolvedShowTitle != null &&
                            resolvedShowTitle.isNotEmpty) ...[
                          Text(
                            resolvedShowTitle,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: Insets.xxs),
                        ],
                        Text(
                          detail.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ] else ...[
                        Text(
                          detail.title,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                      const SizedBox(height: Insets.sm),

                      // 1. Metadata Chips Row (S/E numbering promoted ahead)
                      Wrap(
                        spacing: Insets.xs,
                        runSpacing: Insets.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (detail.mediaType.toLowerCase() == 'episode' &&
                              (widget.initialSeasonNumber != null ||
                                  widget.initialEpisodeNumber != null))
                            Chip(
                              label: Text(
                                'S${widget.initialSeasonNumber ?? 1}:E${widget.initialEpisodeNumber ?? 1}',
                              ),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: colorScheme.primaryContainer,
                              labelStyle: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          if (detail.year != null)
                            Chip(
                              label: Text('${detail.year}'),
                              visualDensity: VisualDensity.compact,
                            ),
                          Chip(
                            label: Text(detail.mediaType.toUpperCase()),
                            visualDensity: VisualDensity.compact,
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                            labelStyle: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          ...detail.genres.map(
                            (genre) => Chip(
                              label: Text(genre),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Insets.sm),

                      // External ID Link Chips & Parent Series Navigation
                      if (detail.showMediaId != null ||
                          detail.imdbId != null ||
                          detail.tmdbId != null ||
                          detail.tvdbId != null) ...[
                        Wrap(
                          spacing: Insets.xs,
                          runSpacing: Insets.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (detail.imdbId != null)
                              ActionChip(
                                avatar: const Icon(Icons.link, size: 14),
                                label: const Text('IMDb'),
                                onPressed: () {
                                  final id = detail.imdbId!;
                                  final imdbPath =
                                      id.startsWith('tt') ? id : 'tt$id';
                                  _openExternalLink(
                                    context,
                                    'https://www.imdb.com/title/$imdbPath',
                                  );
                                },
                              ),
                            if (detail.tmdbId != null &&
                                (detail.mediaType.toLowerCase() == 'movie' ||
                                    detail.mediaType.toLowerCase() == 'show'))
                              ActionChip(
                                avatar: const Icon(Icons.link, size: 14),
                                label: const Text('TMDb'),
                                onPressed: () {
                                  final mType = detail.mediaType.toLowerCase();
                                  final tmdbPath =
                                      mType == 'show' ? 'tv' : 'movie';
                                  _openExternalLink(
                                    context,
                                    'https://www.themoviedb.org/$tmdbPath/${detail.tmdbId}',
                                  );
                                },
                              ),
                            if (detail.showMediaId != null &&
                                detail.showMediaId!.isNotEmpty)
                              ActionChip(
                                avatar: const Icon(Icons.tv_outlined, size: 14),
                                label: Text(
                                  resolvedShowTitle != null &&
                                          resolvedShowTitle.isNotEmpty
                                      ? 'Series: $resolvedShowTitle'
                                      : 'Series',
                                ),
                                onPressed: () =>
                                    TracearrMediaDetailScreen.navigate(
                                  context,
                                  instance: widget.instance,
                                  mediaRef: detail.showMediaId!,
                                  initialTitle: resolvedShowTitle,
                                  initialPosterUrl: parentPosterUrl,
                                  initialSeasonNumber:
                                      widget.initialSeasonNumber,
                                  initialEpisodeNumber:
                                      widget.initialEpisodeNumber,
                                ),
                              ),
                            if (detail.tvdbId != null)
                              ActionChip(
                                avatar: const Icon(Icons.link, size: 14),
                                label: const Text('TheTVDB'),
                                onPressed: () {
                                  final mType = detail.mediaType.toLowerCase();
                                  final tvdbType = mType == 'movie'
                                      ? 'movie'
                                      : (mType == 'episode'
                                          ? 'episode'
                                          : (mType == 'season'
                                              ? 'season'
                                              : 'series'));
                                  _openExternalLink(
                                    context,
                                    'https://thetvdb.com/dereferrer/$tvdbType/${detail.tvdbId}',
                                  );
                                },
                              ),
                          ],
                        ),
                        const SizedBox(height: Insets.lg),
                      ] else
                        const SizedBox(height: Insets.md),

                      // 2. TV Hierarchy Accordion (Promoted to top for shows/seasons)
                      if (detail.children.isNotEmpty) ...[
                        MediaTvHierarchyView(
                          instance: widget.instance,
                          children: detail.children,
                          initialSeasonNumber: widget.initialSeasonNumber,
                          initialEpisodeNumber: widget.initialEpisodeNumber,
                        ),
                        const SizedBox(height: Insets.lg),
                      ],

                      // 3. Multi-Server Availability Matrix
                      if (detail.availability.isNotEmpty) ...[
                        MediaAvailabilityCard(
                          instance: widget.instance,
                          availability: detail.availability,
                        ),
                        const SizedBox(height: Insets.lg),
                      ],

                      // 4. Lifetime Telemetry Stats Grid
                      Container(
                        padding: const EdgeInsets.all(Insets.md),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            _StatTile(
                              label: 'TOTAL PLAYS',
                              value: '${detail.allTimePlays}',
                              color: colorScheme.primary,
                            ),
                            _StatTile(
                              label: 'WATCH TIME',
                              value:
                                  _formatWatchTime(detail.allTimeWatchTimeMs),
                              color: colorScheme.secondary,
                            ),
                            _StatTile(
                              label: '30D PLAYS',
                              value: '${detail.last30DaysPlays}',
                              color: const Color(0xFF4CAF50),
                            ),
                            _StatTile(
                              label: '7D PLAYS',
                              value: '${detail.last7DaysPlays}',
                              color: const Color(0xFFFF9800),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: Insets.lg),

                      // 5. Top Watchers Leaderboard
                      if (detail.watchers.isNotEmpty) ...[
                        MediaWatchersLeaderboard(
                          watchers: detail.watchers,
                          instance: widget.instance,
                        ),
                        const SizedBox(height: Insets.lg),
                      ],

                      // 6. Dedicated Playback History
                      MediaDedicatedHistoryFeed(
                        instance: widget.instance,
                        mediaRef: widget.mediaRef,
                      ),
                      const SizedBox(height: Insets.xl),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
