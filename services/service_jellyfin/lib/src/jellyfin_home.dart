import 'package:cached_network_image/cached_network_image.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'jellyfin_client.dart';
import 'jellyfin_item_detail.dart';
import 'jellyfin_providers.dart';
import 'models/jellyfin_item.dart';
import 'models/jellyfin_view.dart';

/// Container types - tapping drills into children. Everything else plays.
/// (See the note in JellyfinHome: we dispatch on "is it a container?" so an
/// item with a missing/odd `Type` still plays rather than dead-ending.)
const Set<String> jellyfinContainerTypes = <String>{
  'Series',
  'Season',
  'BoxSet',
  'Folder',
  'CollectionFolder',
  'UserView',
  'MusicAlbum',
  'MusicArtist',
  'Playlist',
};

/// Jellyfin's per-instance UI: library chips + poster grid. Mirrors JellyfinHome,
/// including tap-to-play and drill-into-folder.
class JellyfinHome extends ConsumerStatefulWidget {
  const JellyfinHome({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<JellyfinHome> createState() => _JellyfinHomeState();
}

class _JellyfinHomeState extends ConsumerState<JellyfinHome> {
  String? _selectedLibraryId;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<JellyfinView>> views =
        ref.watch(jellyfinViewsProvider(widget.instance));

    return AsyncValueView<List<JellyfinView>>(
      value: views,
      onRetry: () => ref.invalidate(jellyfinViewsProvider(widget.instance)),
      data: (List<JellyfinView> libraries) {
        if (libraries.isEmpty) {
          return const EmptyView(
            icon: Icons.theaters_outlined,
            title: 'No libraries',
            message: 'This Jellyfin server has no libraries to show.',
          );
        }
        final String selected = _selectedLibraryId ?? 'home';
        return Column(
          children: <Widget>[
            _LibraryChips(
              libraries: libraries,
              selectedId: selected,
              onSelect: (String id) => setState(() => _selectedLibraryId = id),
            ),
            Expanded(
              child: selected == 'home'
                  ? _HomeSections(instance: widget.instance)
                  : JellyfinItemsGrid(
                      instance: widget.instance,
                      libraryId: selected,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _LibraryChips extends StatelessWidget {
  const _LibraryChips({
    required this.libraries,
    required this.selectedId,
    required this.onSelect,
  });

  final List<JellyfinView> libraries;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
        itemCount: libraries.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: Insets.sm),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Center(
              child: ChoiceChip(
                label: const Text('Home'),
                selected: 'home' == selectedId,
                onSelected: (_) => onSelect('home'),
              ),
            );
          }
          final JellyfinView lib = libraries[index - 1];
          return Center(
            child: ChoiceChip(
              label: Text(lib.name),
              selected: lib.id == selectedId,
              onSelected: (_) => onSelect(lib.id),
            ),
          );
        },
      ),
    );
  }
}

class JellyfinItemsGrid extends ConsumerWidget {
  const JellyfinItemsGrid({required this.instance, required this.libraryId, super.key});

  final Instance instance;
  final String libraryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<JellyfinItem>> items =
        ref.watch(jellyfinItemsProvider((instance, libraryId)));
    final JellyfinClient? client =
        ref.watch(jellyfinClientProvider(instance)).valueOrNull;

    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(jellyfinItemsProvider((instance, libraryId))),
      child: AsyncValueView<List<JellyfinItem>>(
        value: items,
        onRetry: () => ref.invalidate(jellyfinItemsProvider((instance, libraryId))),
        data: (List<JellyfinItem> list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.movie_outlined,
              title: 'Empty library',
              message: 'Nothing in this library yet.',
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
              final JellyfinItem item = list[index];
              return JellyfinPosterCard(
                instance: instance,
                item: item,
                imageUrl: client?.imageUrl(item),
                onTap: client == null
                    ? null
                    : () => _openItem(context, client, item),
              );
            },
          );
        },
      ),
    );
  }

  void _openItem(BuildContext context, JellyfinClient client, JellyfinItem item) {
    if (jellyfinContainerTypes.contains(item.type)) {
      // pushScreen = root navigator; branch-navigator pushes get swept by
      // GoRouter shell rebuilds.
      pushScreen<void>(
        context,
        JellyfinFolderScreen(instance: instance, item: item),
      );
      return;
    }
    pushScreen<void>(
      context,
      JellyfinItemDetailScreen(instance: instance, itemId: item.id),
    );
  }
}

class JellyfinFolderScreen extends ConsumerWidget {
  const JellyfinFolderScreen({required this.instance, required this.item, super.key});

  final Instance instance;
  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final JellyfinClient? client =
        ref.watch(jellyfinClientProvider(instance)).valueOrNull;
    final AsyncValue<JellyfinItem> itemAsync =
        ref.watch(jellyfinItemDetailsProvider((instance, item.id)));
        
    final JellyfinItem currentItem = itemAsync.valueOrNull ?? item;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentItem.name),
        actions: <Widget>[
          if (client != null)
            IconButton(
              icon: Icon(
                currentItem.userData?.isFavorite == true
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: currentItem.userData?.isFavorite == true
                    ? Colors.red
                    : null,
              ),
              onPressed: () async {
                final bool isFav = currentItem.userData?.isFavorite == true;
                await client.markFavorite(currentItem.id, !isFav);
                ref.invalidate(jellyfinItemDetailsProvider((instance, currentItem.id)));
                ref.invalidate(jellyfinFavoritesProvider(instance));
              },
            ),
        ],
      ),
      body: JellyfinItemsGrid(instance: instance, libraryId: currentItem.id),
    );
  }
}

class JellyfinPosterCard extends ConsumerWidget {
  const JellyfinPosterCard({
    required this.instance,
    required this.item,
    required this.imageUrl,
    required this.onTap,
    super.key,
  });

  final Instance instance;
  final JellyfinItem item;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final double progress = (item.userData?.playedPercentage ?? 0) / 100.0;
    final bool played = item.userData?.played ?? false;

    return InkWell(
      onTap: onTap,
      onLongPress: () {
        showModalBottomSheet<void>(
          context: context,
          builder: (BuildContext context) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ListTile(
                    leading: Icon(
                      item.userData?.isFavorite == true
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: item.userData?.isFavorite == true
                          ? Colors.red
                          : null,
                    ),
                    title: Text(item.userData?.isFavorite == true
                        ? 'Remove from Favorites'
                        : 'Add to Favorites',),
                    onTap: () async {
                      Navigator.of(context).pop();
                      final JellyfinClient? client =
                          ref.read(jellyfinClientProvider(instance)).valueOrNull;
                      if (client != null) {
                        final bool isFav =
                            item.userData?.isFavorite == true;
                        await client.markFavorite(item.id, !isFav);
                        // Invalidate to refresh UI
                        ref.invalidate(
                            jellyfinItemDetailsProvider((instance, item.id)),);
                        ref.invalidate(jellyfinFavoritesProvider(instance));
                        ref.invalidate(jellyfinItemsProvider);
                        ref.invalidate(jellyfinNextUpProvider(instance));
                        ref.invalidate(jellyfinResumeItemsProvider(instance));
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
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
                  _poster(theme),
                  if (played)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: _Badge(
                        color: theme.colorScheme.primary,
                        child: Icon(
                          Icons.check,
                          size: 14,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  if (!played && progress > 0.02)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: LinearProgressIndicator(
                        value: progress.clamp(0, 1),
                        minHeight: 3,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Insets.xs),
          Text(
            item.seriesName ?? item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium,
          ),
          if (item.seriesName != null)
            Text(
              (item.parentIndexNumber != null && item.indexNumber != null)
                  ? 'S${item.parentIndexNumber}:E${item.indexNumber} — ${item.name}'
                  : item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            )
          else if (item.productionYear != null)
            Text(
              '${item.productionYear}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
        ],
      ),
    );
  }

  Widget _poster(ThemeData theme) {
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
      placeholder: (BuildContext context, String url) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      errorWidget: (BuildContext context, String url, Object error) => fallback,
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
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: child,
    );
  }
}

class _HomeSections extends ConsumerWidget {
  const _HomeSections({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(jellyfinResumeItemsProvider(instance));
        ref.invalidate(jellyfinFavoritesProvider(instance));
        ref.invalidate(jellyfinNextUpProvider(instance));
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: Insets.md),
        children: <Widget>[
          _VerticalSection(
            instance: instance,
            title: 'Currently Watching',
            provider: jellyfinResumeItemsProvider(instance),
          ),
          _HorizontalSection(
            instance: instance,
            title: 'Favorites',
            provider: jellyfinFavoritesProvider(instance),
          ),
        ],
      ),
    );
  }
}

class _HorizontalSection extends ConsumerWidget {
  const _HorizontalSection({
    required this.instance,
    required this.title,
    required this.provider,
  });

  final Instance instance;
  final String title;
  final ProviderListenable<AsyncValue<List<JellyfinItem>>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<JellyfinItem>> items = ref.watch(provider);
    final JellyfinClient? client =
        ref.watch(jellyfinClientProvider(instance)).valueOrNull;

    return AsyncValueView<List<JellyfinItem>>(
      value: items,
      onRetry: () {},
      data: (List<JellyfinItem> list) {
        if (list.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.lg,
                vertical: Insets.sm,
              ),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            SizedBox(
              height: 240,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(width: Insets.md),
                itemBuilder: (BuildContext context, int index) {
                  final JellyfinItem item = list[index];
                  return SizedBox(
                    width: 120,
                    child: JellyfinPosterCard(
                      instance: instance,
                      item: item,
                      imageUrl: client?.imageUrl(item),
                      onTap: client == null
                          ? null
                          : () {
                              if (jellyfinContainerTypes.contains(item.type)) {
                                pushScreen<void>(
                                  context,
                                  JellyfinFolderScreen(
                                    instance: instance,
                                    item: item,
                                  ),
                                );
                              } else {
                                pushScreen<void>(
                                  context,
                                  JellyfinItemDetailScreen(
                                    instance: instance,
                                    itemId: item.id,
                                  ),
                                );
                              }
                            },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: Insets.lg),
          ],
        );
      },
    );
  }
}

class _VerticalSection extends ConsumerWidget {
  const _VerticalSection({
    required this.instance,
    required this.title,
    required this.provider,
  });

  final Instance instance;
  final String title;
  final ProviderListenable<AsyncValue<List<JellyfinItem>>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<JellyfinItem>> items = ref.watch(provider);
    final JellyfinClient? client =
        ref.watch(jellyfinClientProvider(instance)).valueOrNull;

    return AsyncValueView<List<JellyfinItem>>(
      value: items,
      onRetry: () {},
      data: (List<JellyfinItem> list) {
        if (list.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.lg,
                vertical: Insets.sm,
              ),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: Insets.md),
              itemBuilder: (BuildContext context, int index) {
                final JellyfinItem item = list[index];
                return _VerticalCard(
                  instance: instance,
                  item: item,
                  imageUrl: client?.imageUrl(item),
                  onTap: client == null
                      ? null
                      : () {
                          if (jellyfinContainerTypes.contains(item.type)) {
                            pushScreen<void>(
                              context,
                              JellyfinFolderScreen(
                                instance: instance,
                                item: item,
                              ),
                            );
                          } else {
                            pushScreen<void>(
                              context,
                              JellyfinItemDetailScreen(
                                instance: instance,
                                itemId: item.id,
                              ),
                            );
                          }
                        },
                );
              },
            ),
            const SizedBox(height: Insets.lg),
          ],
        );
      },
    );
  }
}

class _VerticalCard extends StatelessWidget {
  const _VerticalCard({
    required this.instance,
    required this.item,
    required this.imageUrl,
    required this.onTap,
  });

  final Instance instance;
  final JellyfinItem item;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double progress = (item.userData?.playedPercentage ?? 0) / 100.0;

    String titleText = item.seriesName ?? item.name;
    if (item.seriesName != null &&
        item.parentIndexNumber != null &&
        item.indexNumber != null) {
      titleText =
          '${item.seriesName} — S${item.parentIndexNumber}:E${item.indexNumber} — ${item.name}';
    } else if (item.seriesName != null) {
      titleText = '${item.seriesName} — ${item.name}';
    }

    return InkWell(
      onTap: onTap,
      borderRadius: Radii.card,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: Radii.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SizedBox(
              width: 80,
              child: ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(Radii.md),),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _poster(theme),
                    if (progress > 0.02)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: LinearProgressIndicator(
                          value: progress.clamp(0, 1),
                          minHeight: 3,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: Insets.sm, horizontal: Insets.xs,),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      titleText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: Insets.xs),
                    Expanded(
                      child: Text(
                        item.overview != null && item.overview!.isNotEmpty
                            ? item.overview!
                            : 'No description available.',
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: Insets.sm),
          ],
        ),
      ),
    );
  }

  Widget _poster(ThemeData theme) {
    final Widget fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.movie_outlined, color: theme.colorScheme.outline),
    );
    if (imageUrl == null) {
      return fallback;
    }
    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      placeholder: (_, __) =>
          Container(color: theme.colorScheme.surfaceContainerHighest),
      errorWidget: (_, __, ___) => fallback,
    );
  }
}



