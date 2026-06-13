import 'package:cached_network_image/cached_network_image.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/plex_models.dart';
import 'plex_api.dart';
import 'plex_providers.dart';

/// Detail screen for a Plex movie or episode: poster header, synopsis, genres,
/// and a Cast strip, with a watched/unwatched toggle in the app bar. (Plex has
/// no per-item "favorite", so watched state is the toggle here, unlike the
/// Jellyfin/Emby favorite.)
class PlexItemDetailScreen extends ConsumerWidget {
  const PlexItemDetailScreen({
    required this.instance,
    required this.ratingKey,
    super.key,
  });

  final Instance instance;
  final String ratingKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<PlexMetadata?> itemAsync =
        ref.watch(plexItemDetailProvider((instance, ratingKey)));
    final PlexApi? api = ref.watch(plexApiProvider(instance)).value;

    return Scaffold(
      appBar: AppBar(
        actions: <Widget>[
          if (itemAsync.value != null && api != null)
            IconButton(
              tooltip: _watched(itemAsync.value!)
                  ? 'Mark as unwatched'
                  : 'Mark as watched',
              icon: Icon(
                _watched(itemAsync.value!)
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
                color: _watched(itemAsync.value!)
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              onPressed: () async {
                final bool watched = _watched(itemAsync.value!);
                await api.setWatched(ratingKey, watched: !watched);
                ref.invalidate(plexItemDetailProvider((instance, ratingKey)));
                ref.invalidate(plexOnDeckProvider(instance));
                ref.invalidate(plexRecentlyAddedProvider(instance));
                ref.invalidate(plexItemsProvider);
              },
            ),
        ],
      ),
      body: AsyncValueView<PlexMetadata?>(
        value: itemAsync,
        onRetry: () =>
            ref.invalidate(plexItemDetailProvider((instance, ratingKey))),
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
              SliverToBoxAdapter(child: _Header(item: item, api: api)),
              if (item.summary != null && item.summary!.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(Insets.lg),
                    child: Text(
                      item.summary!,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
              if (item.genres.isNotEmpty)
                SliverToBoxAdapter(child: _GenreChips(genres: item.genres)),
              if (item.roles.isNotEmpty)
                SliverToBoxAdapter(child: _CastRow(roles: item.roles, api: api)),
              const SliverToBoxAdapter(child: SizedBox(height: Insets.xl)),
            ],
          );
        },
      ),
    );
  }

  /// Watched when a movie/episode has a play count, or when every episode of a
  /// show has been seen.
  static bool _watched(PlexMetadata item) =>
      item.viewCount > 0 ||
      (item.leafCount != null &&
          item.leafCount! > 0 &&
          item.viewedLeafCount == item.leafCount);
}

class _Header extends StatelessWidget {
  const _Header({required this.item, required this.api});

  final PlexMetadata item;
  final PlexApi? api;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? posterUrl = api?.imageUrl(item.thumb);
    final int minutes =
        item.duration != null ? item.duration! ~/ 60000 : 0;
    final bool isEpisode = item.grandparentTitle != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: Radii.card,
            child: posterUrl != null
                ? CachedNetworkImage(
                    imageUrl: posterUrl,
                    width: 140,
                    height: 210,
                    fit: BoxFit.cover,
                    memCacheWidth: 280,
                    errorWidget: (_, __, ___) => _posterFallback(theme),
                  )
                : _posterFallback(theme),
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
                        ?.copyWith(color: theme.colorScheme.outline),
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
                if (item.tagline != null && item.tagline!.isNotEmpty) ...<Widget>[
                  const SizedBox(height: Insets.sm),
                  Text(
                    item.tagline!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.outline,
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
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: Radii.card,
        ),
        child: const Icon(Icons.movie_outlined, size: 48),
      );

  String _episodeLabel(PlexMetadata item) {
    final String se = (item.parentIndex != null && item.index != null)
        ? 'S${item.parentIndex} E${item.index}'
        : '';
    return se.isEmpty ? item.title : '$se - ${item.title}';
  }
}

class _GenreChips extends StatelessWidget {
  const _GenreChips({required this.genres});

  final List<PlexGenre> genres;

  @override
  Widget build(BuildContext context) {
    final List<String> labels = genres
        .map((PlexGenre g) => g.tag)
        .whereType<String>()
        .where((String t) => t.isNotEmpty)
        .toList();
    if (labels.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.sm),
      child: Wrap(
        spacing: Insets.sm,
        runSpacing: Insets.xs,
        children: <Widget>[
          for (final String label in labels)
            Chip(
              label: Text(label),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
          child: Text(
            'Cast',
            style: theme.textTheme.titleMedium
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
                          ? CachedNetworkImageProvider(image)
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
