import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator_plus/palette_generator_plus.dart';

import 'models/plex_models.dart';
import 'plex_api.dart';
import 'plex_deep_link.dart';
import 'plex_providers.dart';
import 'plex_season_screen.dart';

/// Detail screen for a Plex movie or episode: backdrop header with a
/// poster-derived accent palette, synopsis, genres, and a Cast strip, with a
/// watched/unwatched toggle and an "Open in Plex" action in the app bar.
/// (Plex has no per-item "favorite", so watched state is the toggle here,
/// unlike the Jellyfin/Emby favorite.)
class PlexItemDetailScreen extends ConsumerStatefulWidget {
  const PlexItemDetailScreen({
    required this.instance,
    required this.ratingKey,
    super.key,
  });

  final Instance instance;
  final String ratingKey;

  @override
  ConsumerState<PlexItemDetailScreen> createState() =>
      _PlexItemDetailScreenState();
}

class _PlexItemDetailScreenState extends ConsumerState<PlexItemDetailScreen> {
  PaletteGenerator? _palette;
  String? _lastPosterUrl;

  /// Samples the poster for an accent palette, once per poster URL.
  ///
  /// `timeout: Duration.zero` disables palette_generator's load-failure
  /// timer: a poster that never resolves simply keeps the default colors
  /// instead of erroring after 15s (and leaves no pending timer behind in
  /// widget tests, where network images always fail).
  void _updatePalette(String? posterUrl) {
    if (posterUrl == null || posterUrl == _lastPosterUrl) {
      return;
    }
    _lastPosterUrl = posterUrl;

    // maximumColorCount is left at its default of 16.
    PaletteGenerator.fromImageProvider(
      atriumImageProvider(posterUrl, maxWidth: 200, maxHeight: 300),
      size: const Size(200, 300),
      timeout: Duration.zero,
    ).then((PaletteGenerator palette) {
      if (mounted) {
        setState(() => _palette = palette);
      }
    }).catchError((_) {});
  }

  Future<void> _toggleWatched(PlexApi api, PlexMetadata item) async {
    final bool watched = _watched(item);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await api.setWatched(widget.ratingKey, watched: !watched);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not update watched state')),
      );
      return;
    }
    if (!mounted) {
      return;
    }
    ref.invalidate(
      plexItemDetailProvider((widget.instance, widget.ratingKey)),
    );
    ref.invalidate(plexOnDeckProvider(widget.instance));
    ref.invalidate(plexRecentlyAddedProvider(widget.instance));
    ref.invalidate(plexItemsProvider);
  }

  /// Watched when a movie/episode has a play count, or when every episode of a
  /// show has been seen.
  static bool _watched(PlexMetadata item) =>
      item.viewCount > 0 ||
      (item.leafCount != null &&
          item.leafCount! > 0 &&
          item.viewedLeafCount == item.leafCount);

  @override
  Widget build(BuildContext context) {
    final AsyncValue<PlexMetadata?> itemAsync = ref.watch(
      plexItemDetailProvider((widget.instance, widget.ratingKey)),
    );
    final PlexApi? api = ref.watch(plexApiProvider(widget.instance)).value;
    final PlexMetadata? current = itemAsync.value;

    _updatePalette(api?.imageUrl(current?.thumb));

    ThemeData theme = Theme.of(context);
    if (_palette != null) {
      final Color vibrant = _palette!.vibrantColor?.color ??
          _palette!.lightVibrantColor?.color ??
          _palette!.dominantColor?.color ??
          theme.colorScheme.primary;
      theme = theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: vibrant,
          onPrimary: _palette!.vibrantColor?.titleTextColor ??
              theme.colorScheme.onPrimary,
          secondaryContainer: vibrant.withValues(alpha: 0.25),
          onSecondaryContainer: vibrant,
        ),
      );
    }

    // The header renders the backdrop (or the poster) behind the transparent
    // app bar; white icons stay legible over the scrimmed image.
    final bool overImage = current != null &&
        api != null &&
        (api.imageUrl(current.art) ?? api.imageUrl(current.thumb)) != null;

    return Theme(
      data: theme,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: overImage ? Colors.white : null,
          actions: <Widget>[
            if (current != null && api != null)
              IconButton(
                tooltip:
                    _watched(current) ? 'Mark as unwatched' : 'Mark as watched',
                icon: Icon(
                  _watched(current)
                      ? Icons.check_circle
                      : Icons.check_circle_outline,
                  color: _watched(current) ? theme.colorScheme.primary : null,
                ),
                onPressed: () => _toggleWatched(api, current),
              ),
            IconButton(
              tooltip: 'Open in Plex',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => launchPlexDeepLink(context),
            ),
          ],
        ),
        body: AsyncValueView<PlexMetadata?>(
          value: itemAsync,
          onRetry: () => ref.invalidate(
            plexItemDetailProvider((widget.instance, widget.ratingKey)),
          ),
          data: (PlexMetadata? item) {
            if (item == null) {
              return const EmptyView(
                icon: Icons.error_outline,
                title: 'Not found',
                message: 'This item is no longer on the server.',
              );
            }
            return CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(
                  child: _BackdropHeader(
                    item: item,
                    api: api,
                    backdropUrl:
                        api?.imageUrl(item.art) ?? api?.imageUrl(item.thumb),
                  ),
                ),
                if (item.type == 'show')
                  SliverToBoxAdapter(
                    child: _ShowSeasons(
                      instance: widget.instance,
                      showRatingKey: item.ratingKey,
                    ),
                  ),
                if (item.summary != null && item.summary!.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.lg,
                        Insets.lg,
                        Insets.lg,
                        0,
                      ),
                      child: Card(
                        elevation: 0,
                        margin: EdgeInsets.zero,
                        color: theme.colorScheme.surfaceContainerLow,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(Insets.lg),
                          child: Text(
                            item.summary!,
                            style: theme.textTheme.bodyLarge,
                          ),
                        ),
                      ),
                    ),
                  ),
                if (item.genres.isNotEmpty)
                  SliverToBoxAdapter(child: _GenreChips(genres: item.genres)),
                if (item.roles.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _CastRow(roles: item.roles, api: api),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: Insets.xl)),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Backdrop art behind the header row, dimmed and faded into the surface so
/// the title block stays legible; falls back to a plain header when the item
/// has no artwork.
class _BackdropHeader extends StatelessWidget {
  const _BackdropHeader({
    required this.item,
    required this.api,
    required this.backdropUrl,
  });

  final PlexMetadata item;
  final PlexApi? api;
  final String? backdropUrl;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (backdropUrl == null) {
      return SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: Insets.lg),
          child: _Header(item: item, api: api),
        ),
      );
    }
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.5,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: AtriumNetworkImage(
              key: ValueKey<String>(backdropUrl!),
              imageUrl: backdropUrl!,
              fit: BoxFit.cover,
              errorWidget: (BuildContext context, String url, Object error) =>
                  ColoredBox(color: cs.surfaceContainerHighest),
            ),
          ),
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
          ),
          Positioned.fill(
            child: DecoratedBox(
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
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _Header(item: item, api: api),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item, required this.api});

  final PlexMetadata item;
  final PlexApi? api;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? posterUrl = api?.imageUrl(item.thumb);
    final int minutes = item.duration != null ? item.duration! ~/ 60000 : 0;
    final bool isEpisode = item.grandparentTitle != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: posterUrl != null
                  ? AtriumNetworkImage(
                      imageUrl: posterUrl,
                      width: 140,
                      height: 210,
                      fit: BoxFit.cover,
                      memCacheWidth: 280,
                      errorWidget:
                          (BuildContext context, String url, Object error) =>
                              _posterFallback(theme),
                    )
                  : _posterFallback(theme),
            ),
          ),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  isEpisode ? item.grandparentTitle! : item.title,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (isEpisode) ...<Widget>[
                  const SizedBox(height: Insets.xs),
                  Text(
                    _episodeLabel(item),
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: Insets.sm),
                Wrap(
                  spacing: Insets.sm,
                  runSpacing: Insets.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    if (item.year != null)
                      Text('${item.year}', style: theme.textTheme.bodyMedium),
                    if (minutes > 0)
                      Text('$minutes min', style: theme.textTheme.bodyMedium),
                    if (item.contentRating != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outline),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.contentRating!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (item.rating != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.star,
                            size: 16,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            item.rating!.toStringAsFixed(1),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                  ],
                ),
                if (item.tagline != null &&
                    item.tagline!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Insets.sm),
                  Text(
                    item.tagline!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _posterFallback(ThemeData theme) => Container(
        width: 140,
        height: 210,
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Icon(Icons.movie_outlined, size: 48),
      );

  String _episodeLabel(PlexMetadata item) {
    final String se = (item.parentIndex != null && item.index != null)
        ? 'S${item.parentIndex} E${item.index}'
        : '';
    return se.isEmpty ? item.title : '$se - ${item.title}';
  }
}

/// Inline seasons on a show's detail: a header plus one [PlexSeasonCard] per
/// season, each opening that season's [PlexEpisodeList]. Renders nothing while
/// the seasons load or when the show has none.
class _ShowSeasons extends ConsumerWidget {
  const _ShowSeasons({required this.instance, required this.showRatingKey});

  final Instance instance;
  final String showRatingKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final List<PlexMetadata> seasons =
        ref.watch(plexChildrenProvider((instance, showRatingKey))).value ??
            const <PlexMetadata>[];
    if (seasons.isEmpty) {
      return const SizedBox.shrink();
    }
    final PlexApi? api = ref.watch(plexApiProvider(instance)).value;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Seasons',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: Insets.md),
          for (final PlexMetadata season in seasons) ...<Widget>[
            PlexSeasonCard(
              instance: instance,
              season: season,
              imageUrl: api?.imageUrl(season.thumb),
            ),
            const SizedBox(height: Insets.md),
          ],
        ],
      ),
    );
  }
}

/// Non-interactive tonal genre pills. Detail metadata carries only genre
/// display tags, not the section key + genre directory key that
/// `plexGenreItemsProvider` needs, so these stay display-only rather than
/// guessing at a section. Genre browsing lives on the library grid instead.
class _GenreChips extends StatelessWidget {
  const _GenreChips({required this.genres});

  final List<PlexGenre> genres;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final List<String> labels = genres
        .map((PlexGenre g) => g.tag)
        .whereType<String>()
        .where((String t) => t.isNotEmpty)
        .toList();
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, 0),
      child: Wrap(
        spacing: Insets.sm,
        runSpacing: Insets.sm,
        children: <Widget>[
          for (final String label in labels)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.md,
                vertical: Insets.xs,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CastRow extends StatelessWidget {
  const _CastRow({required this.roles, required this.api});

  final List<PlexRole> roles;
  final PlexApi? api;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
            child: Text(
              'Cast',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: Insets.sm),
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
              itemCount: roles.length,
              separatorBuilder: (_, __) => const SizedBox(width: Insets.md),
              itemBuilder: (BuildContext context, int index) {
                final PlexRole person = roles[index];
                final String? image = _roleImage(person.thumb);
                return SizedBox(
                  width: 100,
                  child: Column(
                    children: <Widget>[
                      CircleAvatar(
                        radius: 50,
                        backgroundImage: image != null
                            ? atriumImageProvider(image)
                            : null,
                        child: image == null
                            ? const Icon(Icons.person, size: 40)
                            : null,
                      ),
                      const SizedBox(height: Insets.xs),
                      if (person.tag != null)
                        Text(
                          person.tag!,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                      if (person.role != null)
                        Text(
                          person.role!,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Cast thumbs are sometimes absolute (a Plex CDN URL) and sometimes a
  /// relative server path needing the token.
  String? _roleImage(String? thumb) {
    if (thumb == null || thumb.isEmpty) {
      return null;
    }
    if (thumb.startsWith('http')) {
      return thumb;
    }
    return api?.imageUrl(thumb);
  }
}
