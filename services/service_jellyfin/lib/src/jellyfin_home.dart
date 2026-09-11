import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:palette_generator_plus/palette_generator_plus.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';

import 'jellyfin_client.dart';
import 'jellyfin_identify_screen.dart';
import 'jellyfin_item_detail.dart';
import 'jellyfin_music_screens.dart';
import 'jellyfin_providers.dart';
import 'jellyfin_season_screen.dart';
import 'jellyfin_session_detail_screen.dart';
import 'models/jellyfin_item.dart';
import 'models/jellyfin_session.dart';
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
  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<JellyfinView>> viewsAsync =
        ref.watch(jellyfinViewsProvider(widget.instance));
    final int index =
        ref.watch(jellyfinActiveTabBarIndexProvider(widget.instance));

    return AsyncValueView<List<JellyfinView>>(
      value: viewsAsync,
      onRetry: () => ref.invalidate(jellyfinViewsProvider(widget.instance)),
      data: (List<JellyfinView> libraries) {
        if (libraries.isEmpty) {
          return const EmptyView(
            icon: Icons.theaters_outlined,
            title: 'No Libraries',
            message: 'This Jellyfin server has no libraries to show.',
          );
        }

        final String libsKey =
            libraries.map((JellyfinView l) => l.id).join(',');
        final int targetLength = libraries.length + 3;
        final int initialIndex = (index < targetLength) ? index : 0;

        return DefaultTabController(
          key: ValueKey<String>(libsKey),
          length: targetLength,
          initialIndex: initialIndex,
          child: _TabObserver(
            instance: widget.instance,
            child: Column(
              children: <Widget>[
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: <Widget>[
                    const Tab(text: 'Home'),
                    for (final JellyfinView lib in libraries)
                      Tab(text: lib.name),
                    const Tab(text: 'Watched'),
                    const Tab(text: 'Unwatched'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: <Widget>[
                      _HomeSections(instance: widget.instance),
                      for (final JellyfinView lib in libraries)
                        JellyfinLibraryGrid(
                          instance: widget.instance,
                          view: lib,
                        ),
                      JellyfinItemsGrid(
                        instance: widget.instance,
                        libraryId: 'watched',
                      ),
                      JellyfinItemsGrid(
                        instance: widget.instance,
                        libraryId: 'unwatched',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TabObserver extends ConsumerStatefulWidget {
  const _TabObserver({required this.instance, required this.child});
  final Instance instance;
  final Widget child;
  @override
  ConsumerState<_TabObserver> createState() => _TabObserverState();
}

class _TabObserverState extends ConsumerState<_TabObserver> {
  TabController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final TabController? controller = DefaultTabController.maybeOf(context);
    if (_controller != controller) {
      _controller?.removeListener(_onTabChanged);
      _controller = controller;
      _controller?.addListener(_onTabChanged);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _controller != null) {
          ref
              .read(jellyfinActiveTabBarIndexProvider(widget.instance).notifier)
              .state = _controller!.index;
        }
      });
    }
  }

  @override
  void dispose() {
    _controller?.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() {
    if (_controller != null && !_controller!.indexIsChanging) {
      ref
          .read(jellyfinActiveTabBarIndexProvider(widget.instance).notifier)
          .state = _controller!.index;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class JellyfinLibraryGrid extends ConsumerWidget {
  const JellyfinLibraryGrid({
    required this.instance,
    required this.view,
    super.key,
  });

  final Instance instance;
  final JellyfinView view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<JellyfinItem>> items =
        ref.watch(jellyfinLibraryItemsProvider((instance, view)));
    final JellyfinClient? client =
        ref.watch(jellyfinClientProvider(instance)).value;

    return AsyncValueView<List<JellyfinItem>>(
          value: items,
        onRetry: () =>
            ref.invalidate(jellyfinLibraryItemsProvider((instance, view))),
          data: (List<JellyfinItem> list) {
            
          if (list.isEmpty) {
            return EasyRefresh(
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
        onRefresh: () async =>
          ref.invalidate(jellyfinLibraryItemsProvider((instance, view))),
        child: const CustomScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            HeaderLocator.sliver(),
            SliverToBoxAdapter(child: SizedBox(height: 100)),
            SliverToBoxAdapter(
              child: EmptyView(
                icon: Icons.movie_outlined,
                title: 'Empty library',
                message: 'Nothing in this library yet.',
              ),
            ),
          ],
        ),
      );
          }
          final JellyfinViewMode viewMode =
              ref.watch(jellyfinViewModeProvider(instance));

          return EasyRefresh(
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
      onRefresh: () async =>
          ref.invalidate(jellyfinLibraryItemsProvider((instance, view))),
      child: _buildJellyfinGridOrList(
            context,
            list,
            viewMode,
            (BuildContext context, int index, JellyfinItem item) {
              return PerformanceLoggerWidget(
                name: 'JellyfinLibraryItem',
                child: viewMode == JellyfinViewMode.list
                    ? JellyfinBannerCard(
                        instance: instance,
                        item: item,
                        imageUrl: client?.imageUrl(item),
                        backdropUrl: client?.bannerOrPosterUrl(item),
                        onTap: client == null
                            ? null
                            : () {
                                if (item.type == 'MusicAlbum') {
                                  pushScreen<void>(
                                    context,
                                    JellyfinAlbumScreen(
                                      instance: instance,
                                      albumId: item.id,
                                      albumName: item.name,
                                      albumArtist: item.artists.isNotEmpty
                                          ? item.artists.first
                                          : 'Unknown Artist',
                                      albumOverview: item.overview,
                                      albumGenres: item.genres,
                                      albumImageUrl: client.imageUrl(item),
                                    ),
                                  );
                                } else if (item.type == 'Series') {
                                  pushScreen<void>(
                                    context,
                                    JellyfinItemDetailScreen(
                                      instance: instance,
                                      itemId: item.id,
                                    ),
                                  );
                                } else if (item.type == 'Season') {
                                  pushScreen<void>(
                                    context,
                                    JellyfinSeasonScreen(
                                      instance: instance,
                                      seriesId:
                                          item.seriesId ?? item.parentId ?? '',
                                      seasonId: item.id,
                                      seasonName: item.name,
                                      seasonImageUrl: client.imageUrl(item),
                                    ),
                                  );
                                } else if (jellyfinContainerTypes
                                    .contains(item.type)) {
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
                      )
                    : JellyfinPosterCard(
                        instance: instance,
                        item: item,
                        imageUrl: client?.imageUrl(item),
                        onTap: client == null
                            ? null
                            : () {
                                if (item.type == 'MusicAlbum') {
                                  pushScreen<void>(
                                    context,
                                    JellyfinAlbumScreen(
                                      instance: instance,
                                      albumId: item.id,
                                      albumName: item.name,
                                      albumArtist: item.artists.isNotEmpty
                                          ? item.artists.first
                                          : 'Unknown Artist',
                                      albumOverview: item.overview,
                                      albumGenres: item.genres,
                                      albumImageUrl: client.imageUrl(item),
                                    ),
                                  );
                                } else if (item.type == 'Series') {
                                  pushScreen<void>(
                                    context,
                                    JellyfinItemDetailScreen(
                                      instance: instance,
                                      itemId: item.id,
                                    ),
                                  );
                                } else if (item.type == 'Season') {
                                  pushScreen<void>(
                                    context,
                                    JellyfinSeasonScreen(
                                      instance: instance,
                                      seriesId:
                                          item.seriesId ?? item.parentId ?? '',
                                      seasonId: item.id,
                                      seasonName: item.name,
                                      seasonImageUrl: client.imageUrl(item),
                                    ),
                                  );
                                } else if (jellyfinContainerTypes
                                    .contains(item.type)) {
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
    );
        
          },
        );
  }
}

class JellyfinItemsGrid extends ConsumerWidget {
  const JellyfinItemsGrid({
    required this.instance,
    required this.libraryId,
    super.key,
  });

  final Instance instance;
  final String libraryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<JellyfinItem>> items =
        ref.watch(jellyfinItemsProvider((instance, libraryId)));
    final JellyfinClient? client =
        ref.watch(jellyfinClientProvider(instance)).value;

    return AsyncValueView<List<JellyfinItem>>(
          value: items,
        onRetry: () =>
            ref.invalidate(jellyfinItemsProvider((instance, libraryId))),
          data: (List<JellyfinItem> list) {
            
          if (list.isEmpty) {
            return EasyRefresh(
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
        onRefresh: () async =>
          ref.invalidate(jellyfinItemsProvider((instance, libraryId))),
        child: const CustomScrollView(
          physics: AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            HeaderLocator.sliver(),
            SliverToBoxAdapter(child: SizedBox(height: 100)),
            SliverToBoxAdapter(
              child: EmptyView(
                icon: Icons.movie_outlined,
                title: 'Empty library',
                message: 'Nothing in this library yet.',
              ),
            ),
          ],
        ),
      );
          }
          final JellyfinViewMode viewMode =
              ref.watch(jellyfinViewModeProvider(instance));

          // (Replaced with _buildJellyfinGridOrList)

          return EasyRefresh(
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
      onRefresh: () async =>
          ref.invalidate(jellyfinItemsProvider((instance, libraryId))),
      child: _buildJellyfinGridOrList(
            context,
            list,
            viewMode,
            (BuildContext context, int index, JellyfinItem item) {
              return PerformanceLoggerWidget(
                name: 'JellyfinItemsItem',
                child: viewMode == JellyfinViewMode.list
                    ? JellyfinBannerCard(
                        instance: instance,
                        item: item,
                        imageUrl: client?.imageUrl(item),
                        backdropUrl: client?.bannerOrPosterUrl(item),
                        onTap: client == null
                            ? null
                            : () => _openItem(context, client, item),
                      )
                    : JellyfinPosterCard(
                        instance: instance,
                        item: item,
                        imageUrl: client?.imageUrl(item),
                        onTap: client == null
                            ? null
                            : () => _openItem(context, client, item),
                      ),
              );
            },
          ),
    );
        
          },
        );
  }

  void _openItem(
    BuildContext context,
    JellyfinClient client,
    JellyfinItem item,
  ) {
    if (item.type == 'MusicAlbum' || item.type == 'Playlist') {
      pushScreen<void>(
        context,
        JellyfinAlbumScreen(
          instance: instance,
          albumId: item.id,
          albumName: item.name,
          albumArtist:
              item.artists.isNotEmpty ? item.artists.first : 'Playlist',
          albumOverview: item.overview,
          albumGenres: item.genres,
          albumImageUrl: client.imageUrl(item),
        ),
      );
      return;
    }
    if (item.type == 'Series') {
      pushScreen<void>(
        context,
        JellyfinItemDetailScreen(instance: instance, itemId: item.id),
      );
      return;
    }
    if (item.type == 'Season') {
      pushScreen<void>(
        context,
        JellyfinSeasonScreen(
          instance: instance,
          seriesId: item.seriesId ?? item.parentId ?? '',
          seasonId: item.id,
          seasonName: item.name,
          seasonImageUrl: client.imageUrl(item),
        ),
      );
      return;
    }
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
  const JellyfinFolderScreen({
    required this.instance,
    required this.item,
    super.key,
  });

  final Instance instance;
  final JellyfinItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final JellyfinClient? client =
        ref.watch(jellyfinClientProvider(instance)).value;
    final AsyncValue<JellyfinItem> itemAsync =
        ref.watch(jellyfinItemDetailsProvider((instance, item.id)));

    final JellyfinItem currentItem = itemAsync.value ?? item;

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
                ref.invalidate(
                  jellyfinItemDetailsProvider((instance, currentItem.id)),
                );
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
          useRootNavigator: true,
          // The sheet context only pops the sheet. Post-await work runs
          // against the card's context/ref, which outlive the sheet.
          builder: (BuildContext sheetContext) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ListTile(
                    leading: Icon(
                      item.userData?.played == true
                          ? Icons.check_circle
                          : Icons.check_circle_outline,
                    ),
                    title: Text(
                      item.userData?.played == true
                          ? 'Mark as Unwatched'
                          : 'Mark as Watched',
                    ),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      final toggle =
                          ref.read(jellyfinToggleWatchedProvider(instance));
                      await toggle(item.id, !(item.userData?.played == true));
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      item.userData?.isFavorite == true
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color:
                          item.userData?.isFavorite == true ? Colors.red : null,
                    ),
                    title: Text(
                      item.userData?.isFavorite == true
                          ? 'Remove from Favorites'
                          : 'Add to Favorites',
                    ),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      final JellyfinClient? client =
                          ref.read(jellyfinClientProvider(instance)).value;
                      if (client != null) {
                        final bool isFav = item.userData?.isFavorite == true;
                        await client.markFavorite(item.id, !isFav);
                        if (!context.mounted) return;
                        // Invalidate to refresh UI
                        ref.invalidate(
                          jellyfinItemDetailsProvider((instance, item.id)),
                        );
                        ref.invalidate(jellyfinFavoritesProvider(instance));
                        ref.invalidate(jellyfinItemsProvider);
                        ref.invalidate(jellyfinNextUpProvider(instance));
                        ref.invalidate(jellyfinResumeItemsProvider(instance));
                      }
                    },
                  ),
                  // RemoteSearch only exists for movies and series; episodes
                  // and music would 404.
                  if (item.type == 'Movie' || item.type == 'Series')
                    ListTile(
                      leading: const Icon(Icons.search),
                      title: const Text('Identify'),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        final bool? changed = await pushScreen<bool>(
                          context,
                          JellyfinIdentifyScreen(
                            instance: instance,
                            item: item,
                          ),
                        );
                        if (changed == true && context.mounted) {
                          ref.invalidate(
                            jellyfinItemDetailsProvider((instance, item.id)),
                          );
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
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AspectRatio(
            aspectRatio: item.type == 'Episode'
                ? (2 / 3)
                : ((item.primaryImageAspectRatio != null &&
                        item.primaryImageAspectRatio! > 0.0)
                    ? item.primaryImageAspectRatio!
                    : (item.type == 'MusicAlbum' ||
                            item.type == 'Audio' ||
                            item.type == 'MusicArtist'
                        ? 1.0
                        : (2 / 3))),
            child: Container(
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
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _poster(theme),
                    if (played)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: _Badge(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.85),
                          child: Icon(
                            Icons.check,
                            size: 16,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    if (!played && progress > 0.02)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicatorM3E(
                              size: LinearProgressM3ESize.s,
                              shape: ProgressM3EShape.flat,
                              value: progress.clamp(0, 1),
                              trackColor: Colors.black.withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
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
                  ? 'S${item.parentIndexNumber}:E${item.indexNumber} - ${item.name}'
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
    final bool isMusic = item.type == 'MusicAlbum' ||
        item.type == 'MusicArtist' ||
        item.type == 'Audio';
    final Widget fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        isMusic ? Icons.album_outlined : Icons.movie_outlined,
        color: theme.colorScheme.outline,
      ),
    );
    if (imageUrl == null) {
      return fallback;
    }
    return AtriumNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      memCacheWidth: 300,
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
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context)
              .colorScheme
              .outlineVariant
              .withValues(alpha: 0.3),
        ),
      ),
      child: child,
    );
  }
}

class JellyfinBannerCard extends ConsumerWidget {
  const JellyfinBannerCard({
    required this.instance,
    required this.item,
    required this.imageUrl,
    this.backdropUrl,
    required this.onTap,
    super.key,
  });

  final Instance instance;
  final JellyfinItem item;
  final String? imageUrl;
  final String? backdropUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final double progress = (item.userData?.playedPercentage ?? 0) / 100.0;
    final bool played = item.userData?.played ?? false;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: Insets.sm),
      clipBehavior: Clip.hardEdge,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        onTap: onTap,
        onLongPress: () {
          // Same long press menu as PosterCard
          showModalBottomSheet<void>(
            context: context,
            useRootNavigator: true,
            // The sheet context only pops the sheet. Post-await work runs
            // against the card's context/ref, which outlive the sheet.
            builder: (BuildContext sheetContext) {
              return SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ListTile(
                      leading: Icon(
                        item.userData?.played == true
                            ? Icons.check_circle
                            : Icons.check_circle_outline,
                      ),
                      title: Text(
                        item.userData?.played == true
                            ? 'Mark as Unwatched'
                            : 'Mark as Watched',
                      ),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        final toggle =
                            ref.read(jellyfinToggleWatchedProvider(instance));
                        await toggle(item.id, !(item.userData?.played == true));
                      },
                    ),
                    ListTile(
                      leading: Icon(
                        item.userData?.isFavorite == true
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: item.userData?.isFavorite == true
                            ? Colors.red
                            : null,
                      ),
                      title: Text(
                        item.userData?.isFavorite == true
                            ? 'Remove from Favorites'
                            : 'Add to Favorites',
                      ),
                      onTap: () async {
                        Navigator.of(sheetContext).pop();
                        final JellyfinClient? client =
                            ref.read(jellyfinClientProvider(instance)).value;
                        if (client != null) {
                          try {
                            final bool isFav =
                                item.userData?.isFavorite == true;
                            await client.markFavorite(item.id, !isFav);
                            if (!context.mounted) return;
                            ref.invalidate(
                              jellyfinItemDetailsProvider((instance, item.id)),
                            );
                            ref.invalidate(jellyfinFavoritesProvider(instance));
                            ref.invalidate(jellyfinItemsProvider);
                            ref.invalidate(jellyfinNextUpProvider(instance));
                            ref.invalidate(
                              jellyfinResumeItemsProvider(instance),
                            );
                          } catch (_) {
                            // Action failed; no revert needed.
                          }
                        }
                      },
                    ),
                    // RemoteSearch only exists for movies and series;
                    // episodes and music would 404.
                    if (item.type == 'Movie' || item.type == 'Series')
                      ListTile(
                        leading: const Icon(Icons.search),
                        title: const Text('Identify'),
                        onTap: () async {
                          Navigator.of(sheetContext).pop();
                          final bool? changed = await pushScreen<bool>(
                            context,
                            JellyfinIdentifyScreen(
                              instance: instance,
                              item: item,
                            ),
                          );
                          if (changed == true && context.mounted) {
                            ref.invalidate(
                              jellyfinItemDetailsProvider((instance, item.id)),
                            );
                            ref.invalidate(jellyfinItemsProvider);
                            ref.invalidate(jellyfinNextUpProvider(instance));
                            ref.invalidate(
                              jellyfinResumeItemsProvider(instance),
                            );
                          }
                        },
                      ),
                  ],
                ),
              );
            },
          );
        },
        child: SizedBox(
          height: 142,
          child: SizedBox(
            height: 142,
            child: Stack(
              children: <Widget>[
                // Backdrop
                if ((backdropUrl ?? imageUrl) != null)
                  Positioned.fill(
                    child: Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        AtriumNetworkImage(
                          imageUrl: (backdropUrl ?? imageUrl)!,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorWidget: (_, __, ___) => const SizedBox.shrink(),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: <Color>[
                                theme.colorScheme.surfaceContainerLow,
                                theme.colorScheme.surfaceContainerLow
                                    .withValues(alpha: 0.65),
                                theme.colorScheme.surfaceContainerLow
                                    .withValues(alpha: 0.5),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Positioned.fill(
                    child: Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),

                // Content
                Padding(
                  padding: const EdgeInsets.all(Insets.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // Poster
                      ConstrainedBox(
                        constraints:
                            const BoxConstraints(maxWidth: 120, maxHeight: 126),
                        child: AspectRatio(
                          aspectRatio: item.type == 'Episode'
                              ? (2 / 3)
                              : ((item.primaryImageAspectRatio != null &&
                                      item.primaryImageAspectRatio! > 0.0)
                                  ? item.primaryImageAspectRatio!
                                  : (item.type == 'MusicAlbum' ||
                                          item.type == 'Audio' ||
                                          item.type == 'MusicArtist'
                                      ? 1.0
                                      : (2 / 3))),
                          child: Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Stack(
                                fit: StackFit.expand,
                                children: <Widget>[
                                  _poster(theme),
                                  if (played)
                                    Positioned(
                                      top: 6,
                                      right: 6,
                                      child: _Badge(
                                        color: theme.colorScheme.primary
                                            .withValues(alpha: 0.85),
                                        child: Icon(
                                          Icons.check,
                                          size: 16,
                                          color: theme.colorScheme.onPrimary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Insets.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Text(
                              item.seriesName ?? item.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (item.seriesName != null)
                              Text(
                                (item.parentIndexNumber != null &&
                                        item.indexNumber != null)
                                    ? 'S${item.parentIndexNumber}:E${item.indexNumber} - ${item.name}'
                                    : item.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              )
                            else if (item.productionYear != null)
                              Text(
                                '${item.productionYear}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (!played && progress > 0.02) ...<Widget>[
                              const SizedBox(height: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: LinearProgressIndicatorM3E(
                                  size: LinearProgressM3ESize.s,
                                  shape: ProgressM3EShape.flat,
                                  value: progress.clamp(0, 1),
                                  trackColor:
                                      Colors.black.withValues(alpha: 0.1),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _poster(ThemeData theme) {
    final bool isMusic = item.type == 'MusicAlbum' ||
        item.type == 'MusicArtist' ||
        item.type == 'Audio';
    final Widget fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        isMusic ? Icons.album_outlined : Icons.movie_outlined,
        color: theme.colorScheme.outline,
      ),
    );
    if (imageUrl == null) {
      return fallback;
    }
    return AtriumNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      placeholder: (BuildContext context, String url) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      errorWidget: (BuildContext context, String url, Object error) => fallback,
    );
  }
}

class _HomeSections extends ConsumerWidget {
  const _HomeSections({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return EasyRefresh(
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
      onRefresh: () async {
        ref.invalidate(jellyfinSessionsProvider(instance));
        ref.invalidate(jellyfinResumeItemsProvider(instance));
        ref.invalidate(jellyfinLatestItemsProvider(instance));
        ref.invalidate(jellyfinFavoritesProvider(instance));
        ref.invalidate(jellyfinNextUpProvider(instance));
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: <Widget>[
          const HeaderLocator.sliver(),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(0, Insets.md, 0, Insets.xxl),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                <Widget>[
                  _ActiveSessionsSection(instance: instance),
                  _HorizontalSection(
                    instance: instance,
                    title: 'Currently Watching',
                    provider: jellyfinResumeItemsProvider(instance),
                  ),
                  _HorizontalSection(
                    instance: instance,
                    title: 'Next Up',
                    provider: jellyfinNextUpProvider(instance),
                  ),
                  _HorizontalSection(
                    instance: instance,
                    title: 'Recently Added',
                    provider: jellyfinLatestItemsProvider(instance),
                  ),
                  _HorizontalSection(
                    instance: instance,
                    title: 'Favorites',
                    provider: jellyfinFavoritesProvider(instance),
                  ),
                  const SizedBox(height: Insets.xl),
                ],
              ),
            ),
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
  final FutureProvider<List<JellyfinItem>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<JellyfinItem>> items = ref.watch(provider);
    final JellyfinClient? client =
        ref.watch(jellyfinClientProvider(instance)).value;

    return AsyncValueView<List<JellyfinItem>>(
      value: items,
      loading: const SizedBox.shrink(),
      onRetry: () => ref.invalidate(provider),
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
                  final String type = item.type;
                  final double rawRatio = item.type == 'Episode'
                      ? (2 / 3)
                      : (item.primaryImageAspectRatio ?? 0.0);
                  final double ratio = rawRatio > 0.0
                      ? rawRatio
                      : (type == 'MusicAlbum' ||
                              type == 'Audio' ||
                              type == 'MusicArtist'
                          ? 1.0
                          : (2 / 3));

                  final double exactWidth = 190.0 * ratio;
                  final double cardWidth = exactWidth.clamp(80.0, 400.0);

                  return SizedBox(
                    width: cardWidth,
                    child: PerformanceLoggerWidget(
                      name: 'JellyfinHorizontalGridItem',
                      child: JellyfinPosterCard(
                        instance: instance,
                        item: item,
                        imageUrl: client?.imageUrl(item),
                        onTap: client == null
                            ? null
                            : () {
                                if (item.type == 'MusicAlbum') {
                                  pushScreen<void>(
                                    context,
                                    JellyfinAlbumScreen(
                                      instance: instance,
                                      albumId: item.id,
                                      albumName: item.name,
                                      albumArtist: item.artists.isNotEmpty
                                          ? item.artists.first
                                          : 'Unknown Artist',
                                      albumOverview: item.overview,
                                      albumImageUrl: client.imageUrl(item),
                                    ),
                                  );
                                } else if (item.type == 'Series') {
                                  pushScreen<void>(
                                    context,
                                    JellyfinItemDetailScreen(
                                      instance: instance,
                                      itemId: item.id,
                                    ),
                                  );
                                } else if (item.type == 'Season') {
                                  pushScreen<void>(
                                    context,
                                    JellyfinSeasonScreen(
                                      instance: instance,
                                      seriesId:
                                          item.seriesId ?? item.parentId ?? '',
                                      seasonId: item.id,
                                      seasonName: item.name,
                                      seasonImageUrl: client.imageUrl(item),
                                    ),
                                  );
                                } else if (jellyfinContainerTypes
                                    .contains(item.type)) {
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

class _ActiveSessionsSection extends ConsumerWidget {
  const _ActiveSessionsSection({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ActiveSession>> sessions =
        ref.watch(jellyfinSessionsProvider(instance));

    return AsyncValueView<List<ActiveSession>>(
      value: sessions,
      loading: const SizedBox.shrink(),
      onRetry: () => ref.invalidate(jellyfinSessionsProvider(instance)),
      data: (List<ActiveSession> list) {
        if (list.isEmpty) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.lg,
                  vertical: Insets.sm,
                ),
                child: Text(
                  'Currently Streaming',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              SizedBox(
                height:
                    168, // Fixed height for horizontal scroll, leaves room for elevation shadow
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(width: Insets.md),
                  itemBuilder: (BuildContext context, int index) {
                    return SizedBox(
                      width:
                          330, // Limit width of the card so it fits nicely in the horizontal list
                      child: _SessionCard(
                        session: list[index],
                        instance: instance,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SessionCard extends StatefulWidget {
  const _SessionCard({
    required this.session,
    required this.instance,
  });

  final ActiveSession session;
  final Instance instance;

  @override
  State<_SessionCard> createState() => _SessionCardState();
}

class _SessionCardState extends State<_SessionCard> {
  PaletteGenerator? _palette;
  String? _lastPosterUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateColorScheme();
  }

  @override
  void didUpdateWidget(covariant _SessionCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session.posterUrl != widget.session.posterUrl) {
      _updateColorScheme();
    }
  }

  void _updateColorScheme() {
    final String? posterUrl = widget.session.posterUrl;
    if (posterUrl == null || posterUrl == _lastPosterUrl) return;
    _lastPosterUrl = posterUrl;

    PaletteGenerator.fromImageProvider(
      atriumImageProvider(posterUrl, maxWidth: 200, maxHeight: 300),
      size: const Size(200, 300),
    ).then((PaletteGenerator palette) {
      if (mounted) {
        setState(() {
          _palette = palette;
        });
      }
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final ActiveSession session = widget.session;
    ThemeData theme = Theme.of(context);

    if (_palette != null) {
      final Color dominant =
          _palette!.dominantColor?.color ?? theme.colorScheme.surface;
      final Color vibrant = _palette!.vibrantColor?.color ??
          _palette!.lightVibrantColor?.color ??
          dominant;
      theme = theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: vibrant,
        ),
      );
    }

    final double pct = session.progressPercent / 100.0;
    final bool playing = session.status == 'Playing';

    return Theme(
      data: theme,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        color: theme.colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
        child: InkWell(
          onTap: () => pushScreen<void>(
            context,
            JellyfinSessionDetailScreen(
              initialSession: session,
              instance: widget.instance,
            ),
          ),
          child: Stack(
            children: <Widget>[
              // Backdrop
              if (session.posterUrl != null)
                Positioned.fill(
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Image.network(
                        session.posterUrl!,
                        headers: ArtworkHeaders.forUrl(session.posterUrl!),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              theme.colorScheme.surfaceContainerLow
                                  .withValues(alpha: 0.3),
                              theme.colorScheme.surfaceContainerLow
                                  .withValues(alpha: 0.85),
                              theme.colorScheme.surfaceContainerLow
                                  .withValues(alpha: 0.95),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Content
              Padding(
                padding: const EdgeInsets.all(Insets.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // Poster
                    ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 120, maxHeight: 126),
                      child: AspectRatio(
                        aspectRatio: session.aspectRatio != null &&
                                session.aspectRatio! > 0.0
                            ? session.aspectRatio!
                            : (2 / 3),
                        child: Container(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.25),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                            image: session.posterUrl != null
                                ? DecorationImage(
                                    image: NetworkImage(session.posterUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: session.posterUrl == null
                              ? Icon(
                                  Icons.movie_outlined,
                                  color: theme.colorScheme.outline,
                                  size: 32,
                                )
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: Insets.lg),

                    // Details
                    Expanded(
                      child: SizedBox(
                        height: 126,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            // Title
                            Text(
                              session.showTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                shadows: <Shadow>[
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.8),
                                    offset: const Offset(0, 2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),

                            if (session.episodeName != null)
                              Text(
                                session.episodeName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  shadows: <Shadow>[
                                    Shadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.8),
                                      offset: const Offset(0, 1),
                                      blurRadius: 3,
                                    ),
                                  ],
                                ),
                              ),

                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest
                                    .withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(
                                    Icons.person,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      '${session.user}: ${session.device}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const Spacer(),

                            // Progress Header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Text(
                                  session.timePosition,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  session.timeDuration,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),

                            // Progress Bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicatorM3E(
                                shape: ProgressM3EShape.flat,
                                value: pct.clamp(0.0, 1.0),
                                trackColor:
                                    theme.colorScheme.surfaceContainerHighest,
                                activeColor: playing
                                    ? theme.colorScheme.primary
                                    : theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _buildJellyfinGridOrList(
  BuildContext context,
  List<JellyfinItem> list,
  JellyfinViewMode viewMode,
  Widget Function(BuildContext, int, JellyfinItem) itemBuilder,
) {
  final List<JellyfinItem> albums =
      list.where((e) => e.type == 'MusicAlbum').toList();
  final List<JellyfinItem> playlists =
      list.where((e) => e.type == 'Playlist').toList();
  final List<JellyfinItem> others = list
      .where((e) => e.type != 'MusicAlbum' && e.type != 'Playlist')
      .toList();

  final bool showSections =
      albums.isNotEmpty && playlists.isNotEmpty && others.isEmpty;
  final ThemeData theme = Theme.of(context);

  if (showSections) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        const HeaderLocator.sliver(),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.lg,
            Insets.lg,
            Insets.sm,
          ),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Albums',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
          sliver: viewMode == JellyfinViewMode.list
              ? SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) =>
                        itemBuilder(context, index, albums[index]),
                    childCount: albums.length,
                  ),
                )
              : SliverMasonryGrid.extent(
                  maxCrossAxisExtent: 140.0,
                  crossAxisSpacing: Insets.md,
                  mainAxisSpacing: Insets.md,
                  childCount: albums.length,
                  itemBuilder: (BuildContext context, int index) =>
                      itemBuilder(context, index, albums[index]),
                ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.xl,
            Insets.lg,
            Insets.sm,
          ),
          sliver: SliverToBoxAdapter(
            child: Text(
              'Playlists',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.lg)
              .copyWith(bottom: Insets.lg),
          sliver: viewMode == JellyfinViewMode.list
              ? SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) =>
                        itemBuilder(context, index, playlists[index]),
                    childCount: playlists.length,
                  ),
                )
              : SliverMasonryGrid.extent(
                  maxCrossAxisExtent: 140.0,
                  crossAxisSpacing: Insets.md,
                  mainAxisSpacing: Insets.md,
                  childCount: playlists.length,
                  itemBuilder: (BuildContext context, int index) =>
                      itemBuilder(context, index, playlists[index]),
                ),
        ),
      ],
    );
  }

  return CustomScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    slivers: <Widget>[
      const HeaderLocator.sliver(),
      SliverPadding(
        padding: Insets.page,
        sliver: viewMode == JellyfinViewMode.list
            ? SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int index) =>
                      itemBuilder(context, index, list[index]),
                  childCount: list.length,
                ),
              )
            : SliverMasonryGrid.extent(
                maxCrossAxisExtent: 140.0,
                crossAxisSpacing: Insets.md,
                mainAxisSpacing: Insets.md,
                childCount: list.length,
                itemBuilder: (BuildContext context, int index) =>
                    itemBuilder(context, index, list[index]),
              ),
      ),
    ],
  );
}
