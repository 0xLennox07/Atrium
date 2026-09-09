import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';

import 'models/plex_models.dart';
import 'models/plex_session.dart';
import 'plex_api.dart';
import 'plex_item_detail.dart';
import 'plex_music_screens.dart';
import 'plex_providers.dart';
import 'plex_session_detail_screen.dart';

/// Plex item types that open the detail screen; everything else is a container
/// we drill into. Plex types are reliable and lowercase, so an allowlist is
/// safe here (unlike Jellyfin/Emby, which use a container denylist).
const Set<String> plexPlayableTypes = <String>{'movie', 'episode', 'clip'};

/// Plex's per-instance UI: a Home tab (featured hero, Now Streaming,
/// Continue Watching, Recently Added, then one row per library) plus a chip
/// per library backed by a poster grid with genre filter chips. Tapping a
/// movie/episode opens its detail screen; a show opens its seasons, an artist
/// its albums, and other containers drill into their children.
class PlexHome extends ConsumerStatefulWidget {
  const PlexHome({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<PlexHome> createState() => _PlexHomeState();
}

class _PlexHomeState extends ConsumerState<PlexHome> {
  /// 'home' selects the hub view; any other value is a library section key.
  String _selectedKey = 'home';

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<PlexLibrary>> libraries =
        ref.watch(plexLibrariesProvider(widget.instance));

    return AsyncValueView<List<PlexLibrary>>(
      value: libraries,
      onRetry: () => ref.invalidate(plexLibrariesProvider(widget.instance)),
      data: (List<PlexLibrary> libs) {
        return Column(
          children: <Widget>[
            _LibraryChips(
              libraries: libs,
              selectedKey: _selectedKey,
              onSelect: (String k) => setState(() => _selectedKey = k),
            ),
            Expanded(
              child: _selectedKey == 'home'
                  ? _HomeSections(
                      instance: widget.instance,
                      onSelectLibrary: (String key) =>
                          setState(() => _selectedKey = key),
                    )
                  : _ItemsGrid(
                      // A fresh State per section, so a genre picked in one
                      // library never leaks into another.
                      key: ValueKey<String>(_selectedKey),
                      instance: widget.instance,
                      id: _selectedKey,
                      isSection: true,
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
    required this.selectedKey,
    required this.onSelect,
  });

  final List<PlexLibrary> libraries;
  final String selectedKey;
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
                selected: selectedKey == 'home',
                onSelected: (_) => onSelect('home'),
              ),
            );
          }
          final PlexLibrary lib = libraries[index - 1];
          return Center(
            child: ChoiceChip(
              label: Text(lib.title),
              selected: lib.key == selectedKey,
              onSelected: (_) => onSelect(lib.key),
            ),
          );
        },
      ),
    );
  }
}

/// Grid of items, sourced either from a library section ([isSection] true,
/// [id] = sectionKey) or from a parent's children ([isSection] false, [id] =
/// ratingKey). Section grids carry a genre-chip strip that swaps the grid to
/// a genre-filtered source.
class _ItemsGrid extends ConsumerStatefulWidget {
  const _ItemsGrid({
    required this.instance,
    required this.id,
    required this.isSection,
    super.key,
  });

  final Instance instance;
  final String id;
  final bool isSection;

  @override
  ConsumerState<_ItemsGrid> createState() => _ItemsGridState();
}

class _ItemsGridState extends ConsumerState<_ItemsGrid> {
  /// Selected genre directory key; null means unfiltered ("All").
  String? _genreKey;

  FutureProvider<List<PlexMetadata>> get _provider {
    if (!widget.isSection) {
      return plexChildrenProvider((widget.instance, widget.id));
    }
    final String? genreKey = _genreKey;
    if (genreKey != null) {
      return plexGenreItemsProvider((widget.instance, widget.id, genreKey));
    }
    return plexItemsProvider((widget.instance, widget.id));
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<PlexMetadata>> items = ref.watch(_provider);
    final PlexApi? api = ref.watch(plexApiProvider(widget.instance)).value;

    final Widget grid = AsyncValueView<List<PlexMetadata>>(
          value: items,
        onRetry: () => ref.invalidate(_provider),
          data: (List<PlexMetadata> list) {
            
          if (list.isEmpty) {
            return EasyRefresh(
        header: const ClassicHeader(
          dragText: 'Pull to refresh',
          armedText: 'Release ready',
          readyText: 'Refreshing...',
          processingText: 'Refreshing...',
          processedText: 'Succeeded',
          failedText: 'Failed',
          messageText: 'Last updated at %T',
        ),
        onRefresh: () async {
        ref.invalidate(_provider);
        if (widget.isSection) {
          ref.invalidate(plexGenresProvider((widget.instance, widget.id)));
        }
      },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const <Widget>[
            SizedBox(height: 100),
            EmptyView(
              icon: Icons.movie_outlined,
              title: 'Empty',
              message: 'Nothing here yet.',
            ),
          ],
        ),
      );
          }
          return EasyRefresh(
      header: const ClassicHeader(
        dragText: 'Pull to refresh',
        armedText: 'Release ready',
        readyText: 'Refreshing...',
        processingText: 'Refreshing...',
        processedText: 'Succeeded',
        failedText: 'Failed',
        messageText: 'Last updated at %T',
      ),
      onRefresh: () async {
        ref.invalidate(_provider);
        if (widget.isSection) {
          ref.invalidate(plexGenresProvider((widget.instance, widget.id)));
        }
      },
      child: MasonryGridView.extent(
            padding: Insets.page,
            maxCrossAxisExtent: 140,
            crossAxisSpacing: Insets.md,
            mainAxisSpacing: Insets.md,
            itemCount: list.length,
            itemBuilder: (BuildContext context, int index) {
              final PlexMetadata item = list[index];
              return PlexPosterCard(
                instance: widget.instance,
                item: item,
                imageUrl: api?.imageUrl(item.thumb),
                onTap: () => openPlexItem(context, widget.instance, item),
              );
            },
          ),
    );
        
          },
        );

    if (!widget.isSection) {
      return grid;
    }
    return Column(
      children: <Widget>[
        _genreStrip(),
        Expanded(child: grid),
      ],
    );
  }

  /// Horizontal genre filter chips for a section. Renders nothing until the
  /// genre list first loads, and whenever it is empty, so the grid is never
  /// blocked. Once loaded, `.value` keeps the last-known genres through a
  /// later refresh error rather than dropping the strip.
  Widget _genreStrip() {
    final List<PlexGenreDir> genres =
        ref.watch(plexGenresProvider((widget.instance, widget.id))).value ??
            const <PlexGenreDir>[];
    if (genres.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
        itemCount: genres.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: Insets.sm),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Center(
              child: FilterChip(
                label: const Text('All'),
                selected: _genreKey == null,
                onSelected: (_) => setState(() => _genreKey = null),
              ),
            );
          }
          final PlexGenreDir genre = genres[index - 1];
          return Center(
            child: FilterChip(
              label: Text(genre.title),
              selected: _genreKey == genre.key,
              onSelected: (bool selected) =>
                  setState(() => _genreKey = selected ? genre.key : null),
            ),
          );
        },
      ),
    );
  }
}

/// Opens [item]: a playable type goes to its detail screen, a show to its
/// season list, an artist/album into the music flow, and any other container
/// drills into a child grid. Uses the root navigator so GoRouter's shell
/// rebuilds don't sweep the pushed route.
void openPlexItem(BuildContext context, Instance instance, PlexMetadata item) {
  if (plexPlayableTypes.contains(item.type) || item.type == 'show') {
    // Shows open the detail screen too (synopsis, cast, and their seasons
    // shown inline), matching how movies and the Emby/Jellyfin modules behave.
    pushScreen<void>(
      context,
      PlexItemDetailScreen(instance: instance, ratingKey: item.ratingKey),
    );
  } else if (item.type == 'artist') {
    pushScreen<void>(
      context,
      PlexArtistScreen(instance: instance, artist: item),
    );
  } else if (item.type == 'album') {
    pushScreen<void>(
      context,
      PlexAlbumScreen(instance: instance, album: item),
    );
  } else {
    pushScreen<void>(
      context,
      _FolderScreen(instance: instance, item: item),
    );
  }
}

class _FolderScreen extends StatelessWidget {
  const _FolderScreen({required this.instance, required this.item});

  final Instance instance;
  final PlexMetadata item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: _ItemsGrid(
        instance: instance,
        id: item.ratingKey,
        isSection: false,
      ),
    );
  }
}

/// Hub view: featured hero, Now Streaming (active sessions), Continue
/// Watching (on deck), Recently Added, then one horizontal row per library.
/// A library row's "See all" jumps to that library's full grid via
/// [onSelectLibrary], the same switch a library chip performs.
class _HomeSections extends ConsumerWidget {
  const _HomeSections({
    required this.instance,
    required this.onSelectLibrary,
  });

  final Instance instance;
  final ValueChanged<String> onSelectLibrary;

  /// Library rows stop early; the full list lives in the grid behind
  /// "See all".
  static const int _libraryRowCap = 20;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Already loaded by the parent's AsyncValueView, so `.value` is the data.
    final List<PlexLibrary> libraries =
        ref.watch(plexLibrariesProvider(instance)).value ??
            const <PlexLibrary>[];
    return EasyRefresh(
          header: const ClassicHeader(
            dragText: 'Pull to refresh',
            armedText: 'Release ready',
            readyText: 'Refreshing...',
            processingText: 'Refreshing...',
            processedText: 'Succeeded',
            failedText: 'Failed',
            messageText: 'Last updated at %T',
          ),
      onRefresh: () async {
        ref.invalidate(plexSessionsProvider(instance));
        ref.invalidate(plexOnDeckProvider(instance));
        ref.invalidate(plexRecentlyAddedProvider(instance));
        for (final PlexLibrary lib in libraries) {
          ref.invalidate(plexItemsProvider((instance, lib.key)));
        }
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: Insets.md),
        children: <Widget>[
          _FeaturedHero(instance: instance),
          _NowStreamingSection(instance: instance),
          _PlexSection(
            instance: instance,
            title: 'Continue Watching',
            provider: plexOnDeckProvider(instance),
          ),
          _PlexSection(
            instance: instance,
            title: 'Recently Added',
            provider: plexRecentlyAddedProvider(instance),
          ),
          for (final PlexLibrary lib in libraries)
            _PlexSection(
              instance: instance,
              title: lib.title,
              provider: plexItemsProvider((instance, lib.key)),
              maxItems: _libraryRowCap,
              onSeeAll: () => onSelectLibrary(lib.key),
            ),
        ],
      ),
    );
  }
}

/// Spotlight banner at the top of the hub: the first on-deck item, else the
/// first recently-added one. Backdrop art under a bottom-up scrim with the
/// title, a meta line, and a Resume/Details action overlaid bottom-left.
/// Renders nothing while the sources load and when both are empty.
class _FeaturedHero extends ConsumerWidget {
  const _FeaturedHero({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<PlexMetadata> onDeck =
        ref.watch(plexOnDeckProvider(instance)).value ?? const <PlexMetadata>[];
    final List<PlexMetadata> recent =
        ref.watch(plexRecentlyAddedProvider(instance)).value ??
            const <PlexMetadata>[];
    final PlexMetadata? item = onDeck.isNotEmpty
        ? onDeck.first
        : (recent.isNotEmpty ? recent.first : null);
    if (item == null) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final PlexApi? api = ref.watch(plexApiProvider(instance)).value;
    final String? backdropUrl = api?.imageUrl(item.art ?? item.thumb);
    final bool resume = item.viewOffset != null && item.viewOffset! > 0;
    final String meta = _metaLine(item);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.lg),
      child: SizedBox(
        height: 230,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (backdropUrl != null)
                Image(
                  image: atriumImageProvider(backdropUrl),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                )
              else
                Container(color: theme.colorScheme.surfaceContainerHighest),
              // Bottom-up scrim so the white overlay stays legible over any
              // art (and over the plain fallback container).
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(Insets.lg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.grandparentTitle ?? item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (meta.isNotEmpty) ...<Widget>[
                        const SizedBox(height: Insets.xs),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: Colors.white70),
                        ),
                      ],
                      const SizedBox(height: Insets.md),
                      FilledButton.icon(
                        onPressed: () => openPlexItem(context, instance, item),
                        icon: const Icon(Icons.play_arrow),
                        label: Text(resume ? 'Resume' : 'Details'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Year, capitalized type, and SxEy for an episode, dot-separated.
  String _metaLine(PlexMetadata item) {
    final List<String> parts = <String>[
      if (item.year != null) '${item.year}',
      if (item.type.isNotEmpty)
        '${item.type[0].toUpperCase()}${item.type.substring(1)}',
      if (item.type == 'episode' &&
          item.parentIndex != null &&
          item.index != null)
        'S${item.parentIndex}E${item.index}',
    ];
    return parts.join(' · ');
  }
}

/// "Now Streaming" - active sessions, polled while the hub is visible.
/// Additive row: it renders nothing until the poll first returns data, and
/// whenever the session list is empty, so the hub is never blocked by the
/// sessions poller. If a later poll errors, `.value` keeps the last-known
/// sessions on screen rather than dropping the row (no error/retry UI here
/// by design). Tapping a card opens the now-playing controller for that
/// stream.
class _NowStreamingSection extends ConsumerWidget {
  const _NowStreamingSection({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<PlexSession> sessions =
        ref.watch(plexSessionsProvider(instance)).value ??
            const <PlexSession>[];
    if (sessions.isEmpty) {
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
            'Now Streaming',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const SizedBox(width: Insets.md),
            itemBuilder: (BuildContext context, int index) {
              return _SessionCard(
                instance: instance,
                session: sessions[index],
              );
            },
          ),
        ),
        const SizedBox(height: Insets.lg),
      ],
    );
  }
}

/// Backdrop card for one active stream: session art under a bottom-heavy
/// scrim, the watching user top-left, the title bottom-left, and a live
/// progress bar hugging the bottom edge. White/white70 only over the image.
/// Tap opens the now-playing controller for that stream.
class _SessionCard extends ConsumerWidget {
  const _SessionCard({
    required this.instance,
    required this.session,
  });

  final Instance instance;
  final PlexSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final PlexApi? api = ref.watch(plexApiProvider(instance)).value;
    final String? backdropUrl = api?.imageUrl(session.art ?? session.thumb);
    final String? avatarUrl = api?.imageUrl(session.user?.thumb);
    final String title = session.grandparentTitle ?? session.title;
    final String userTitle = session.user?.title ?? '';

    return SizedBox(
      width: 320,
      child: Card(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: theme.colorScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        child: InkWell(
          onTap: () => pushScreen<void>(
            context,
            PlexSessionDetailScreen(
              instance: instance,
              initialSession: session,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (backdropUrl != null)
                Image(
                  image: atriumImageProvider(backdropUrl),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              // Bottom-heavy scrim: keeps the white overlay legible over any
              // backdrop (and over the plain card when there is no art).
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.25),
                      Colors.black.withValues(alpha: 0.45),
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Insets.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (userTitle.isNotEmpty)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          CircleAvatar(
                            radius: 10,
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.4),
                            foregroundImage: avatarUrl == null
                                ? null
                                : atriumImageProvider(avatarUrl),
                            onForegroundImageError:
                                avatarUrl == null ? null : (_, __) {},
                            child: const Icon(
                              Icons.person,
                              size: 12,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(width: Insets.xs),
                          Text(
                            userTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    const Spacer(),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (session.grandparentTitle != null &&
                        session.title.isNotEmpty)
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: Colors.white70),
                      ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicatorM3E(
                  shape: ProgressM3EShape.flat,
                  value: session.progress,
                  trackColor: Colors.white.withValues(alpha: 0.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One horizontal poster row on the hub view. Renders nothing when empty so a
/// server with no on-deck items doesn't show a stray header. [onSeeAll], when
/// set, renders a trailing "See all" action in the header, and [maxItems]
/// caps how many posters the row shows.
class _PlexSection extends ConsumerWidget {
  const _PlexSection({
    required this.instance,
    required this.title,
    required this.provider,
    this.onSeeAll,
    this.maxItems,
  });

  final Instance instance;
  final String title;
  final ProviderListenable<AsyncValue<List<PlexMetadata>>> provider;
  final VoidCallback? onSeeAll;
  final int? maxItems;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PlexMetadata>> items = ref.watch(provider);
    final PlexApi? api = ref.watch(plexApiProvider(instance)).value;

    return items.maybeWhen(
      data: (List<PlexMetadata> list) {
        if (list.isEmpty) {
          return const SizedBox.shrink();
        }
        final List<PlexMetadata> row =
            (maxItems != null && list.length > maxItems!)
                ? list.sublist(0, maxItems!)
                : list;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.lg,
                vertical: Insets.sm,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (onSeeAll != null)
                    TextButton(
                      onPressed: onSeeAll,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('See all'),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: _rowHeight(context),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
                itemCount: row.length,
                separatorBuilder: (_, __) => const SizedBox(width: Insets.md),
                itemBuilder: (BuildContext context, int index) {
                  final PlexMetadata item = row[index];
                  final double ratio = item.type == 'album' ||
                          item.type == 'artist' ||
                          item.type == 'track'
                      ? 1.0
                      : (item.type == 'episode' ? (16 / 9) : (2 / 3));

                  final double exactWidth = 190.0 * ratio;
                  final double cardWidth = exactWidth.clamp(80.0, 400.0);

                  return SizedBox(
                    width: cardWidth,
                    child: PlexPosterCard(
                      instance: instance,
                      item: item,
                      imageUrl: api?.imageUrl(item.thumb),
                      onTap: () => openPlexItem(context, instance, item),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: Insets.lg),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }

  /// Height for the horizontal card list. The poster image is a fixed 190
  /// logical px tall (card width is 190 * aspect ratio, so [AspectRatio]
  /// resolves back to 190), but the caption below it is two single-line
  /// texts that grow with the user's font scale, so the row height has to
  /// grow with the scaled line heights instead of staying a constant.
  static double _rowHeight(BuildContext context) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    double lineHeight(TextStyle? style) =>
        (style?.height ?? 1.5) * textScaler.scale(style?.fontSize ?? 12);
    return 190 +
        Insets.xs +
        lineHeight(textTheme.labelMedium) +
        lineHeight(textTheme.labelSmall) +
        Insets.md;
  }
}

/// A poster tile for a Plex item, with a watched badge, resume-progress bar,
/// and a long-press menu to toggle watched state.
class PlexPosterCard extends ConsumerWidget {
  const PlexPosterCard({
    required this.instance,
    required this.item,
    required this.imageUrl,
    required this.onTap,
    super.key,
  });

  final Instance instance;
  final PlexMetadata item;
  final String? imageUrl;
  final VoidCallback? onTap;

  bool get _watched =>
      item.viewCount > 0 ||
      (item.leafCount != null &&
          item.leafCount! > 0 &&
          item.viewedLeafCount == item.leafCount);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final double progress =
        (item.viewOffset != null && item.duration != null && item.duration! > 0)
            ? item.viewOffset! / item.duration!
            : 0;
    final bool isEpisode = item.grandparentTitle != null;

    return InkWell(
      onTap: onTap,
      onLongPress: () => _showActions(context, ref),
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AspectRatio(
            aspectRatio: item.type == 'album' ||
                    item.type == 'artist' ||
                    item.type == 'track'
                ? 1.0
                : (item.type == 'episode' ? (16 / 9) : (2 / 3)),
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
                    if (_watched)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary
                                .withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Icon(
                            Icons.check,
                            size: 14,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      ),
                    if (!_watched && progress > 0.02)
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.all(Insets.sm),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicatorM3E(
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
            isEpisode ? item.grandparentTitle! : item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium,
          ),
          if (isEpisode)
            Text(
              _episodeLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            )
          else if (item.year != null)
            Text(
              '${item.year}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
        ],
      ),
    );
  }

  String get _episodeLabel {
    final String se = (item.parentIndex != null && item.index != null)
        ? 'S${item.parentIndex}:E${item.index}'
        : '';
    return se.isEmpty ? item.title : '$se - ${item.title}';
  }

  Widget _poster(ThemeData theme) {
    final bool isMusic =
        item.type == 'album' || item.type == 'artist' || item.type == 'track';
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
      memCacheWidth: 400,
      placeholder: (BuildContext context, String url) =>
          Container(color: theme.colorScheme.surfaceContainerHighest),
      errorWidget: (BuildContext context, String url, Object error) => fallback,
    );
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    final bool watched = _watched;
    showModalBottomSheet<void>(
      context: context,
      // Root navigator: a branch-navigator sheet gets swept by GoRouter's
      // shell rebuilds.
      useRootNavigator: true,
      builder: (BuildContext sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: Icon(watched ? Icons.remove_done : Icons.done_all),
                title: Text(watched ? 'Mark as unwatched' : 'Mark as watched'),
                onTap: () async {
                  Navigator.of(sheetContext).pop();
                  final PlexApi? api =
                      ref.read(plexApiProvider(instance)).value;
                  if (api == null) {
                    return;
                  }
                  // The card's context, not the sheet's: the messenger must
                  // outlive the just-popped sheet, and ref belongs to the
                  // card's element.
                  final ScaffoldMessengerState messenger =
                      ScaffoldMessenger.of(context);
                  try {
                    await api.setWatched(item.ratingKey, watched: !watched);
                  } catch (_) {
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Text('Could not update watched state'),
                      ),
                    );
                    return;
                  }
                  if (!context.mounted) {
                    return;
                  }
                  ref.invalidate(plexItemsProvider);
                  ref.invalidate(plexOnDeckProvider(instance));
                  ref.invalidate(plexRecentlyAddedProvider(instance));
                  ref.invalidate(
                    plexItemDetailProvider((instance, item.ratingKey)),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
