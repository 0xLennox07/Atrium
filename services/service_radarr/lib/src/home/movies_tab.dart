import 'dart:async';
import 'dart:math';
import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../service_radarr.dart';

class MoviesTab extends ConsumerStatefulWidget {
  const MoviesTab({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<MoviesTab> createState() => _MoviesTabState();
}

class _MoviesTabState extends ConsumerState<MoviesTab>
    with WidgetsBindingObserver {
  late final TextEditingController _searchController;
  late final ScrollController _scrollController;
  late final FocusNode _searchFocusNode;
  late final void Function() _resetSearchActive;
  double _lastBottomInset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifier =
        ref.read(radarrSearchActiveProvider(widget.instance).notifier);
    _resetSearchActive = () => notifier.state = false;
    final String initialQuery =
        ref.read(radarrSearchQueryProvider(widget.instance));
    _searchController = TextEditingController(text: initialQuery);
    _scrollController = ScrollController()..addListener(_onScroll);
    _searchFocusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _resetSearchActive();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final double bottomInset = WidgetsBinding
        .instance.platformDispatcher.views.first.viewInsets.bottom;
    if (bottomInset == 0 && _lastBottomInset > 0) {
      if (_searchFocusNode.hasFocus) {
        _searchFocusNode.unfocus();
      }
    }
    _lastBottomInset = bottomInset;
  }

  void _updateSearchActiveState() {
    final bool isActive =
        _searchFocusNode.hasFocus || _searchController.text.isNotEmpty;
    ref.read(radarrSearchActiveProvider(widget.instance).notifier).state =
        isActive;
  }

  void _onFocusChange() {
    _updateSearchActiveState();
    setState(() {});
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.userScrollDirection !=
            ScrollDirection.idle) {
      if (_searchFocusNode.hasFocus) {
        _searchFocusNode.unfocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<RadarrMovie>> filtered =
        ref.watch(radarrFilteredMoviesProvider(widget.instance));
    final RadarrApi? api = ref.watch(radarrApiProvider(widget.instance)).value;
    final RadarrViewMode viewMode =
        ref.watch(radarrViewModeProvider(widget.instance));
    final selection = ref.watch(radarrMoviesSelectionProvider(widget.instance));
    final isSelecting = selection.isNotEmpty;

    ref.listen<int>(radarrHomeScrollToTopProvider((widget.instance, 0)),
        (previous, next) {
      if (next > 0 && _scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });

    ref.listen<String>(radarrSearchQueryProvider(widget.instance),
        (String? previous, String next) {
      if (next.isEmpty && _searchController.text.isNotEmpty) {
        setState(() {
          _searchController.clear();
        });
        _searchFocusNode.unfocus();
        _updateSearchActiveState();
      }
    });

    return Scaffold(
      bottomNavigationBar: isSelecting
          ? _BulkActionsBar(
              instance: widget.instance,
              selectedIds: selection,
              onClear: () {
                ref
                    .read(
                      radarrMoviesSelectionProvider(widget.instance).notifier,
                    )
                    .state = {};
              },
            )
          : null,
      floatingActionButton: !isSelecting &&
              ref.watch(
                    radarrActiveTabBarIndexProvider(widget.instance),
                  ) ==
                  0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                FloatingActionButton.small(
                  heroTag: 'radarr_sort_filter_fab',
                  backgroundColor: theme.colorScheme.secondaryContainer,
                  foregroundColor: theme.colorScheme.onSecondaryContainer,
                  onPressed: () {
                    showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      useRootNavigator: true,
                      builder: (BuildContext context) =>
                          _SortFilterBottomSheet(instance: widget.instance),
                    );
                  },
                  child: const Icon(Icons.tune),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'radarr_add_movie_fab',
                  shape: const StadiumBorder(),
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).push(
                      FadePageRoute<void>(
                        builder: (BuildContext context) =>
                            AddMovieScreen(instance: widget.instance),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Movie'),
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: AsyncValueView<List<RadarrMovie>>(
          value: filtered,
          onRetry: () => ref.invalidate(radarrMoviesProvider(widget.instance)),
          data: (List<RadarrMovie> list) {
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
                ref.invalidate(radarrMoviesProvider(widget.instance));
                await ref.read(radarrMoviesProvider(widget.instance).future);
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                controller: _scrollController,
                slivers: <Widget>[
                  SliverAppBar(
                    floating: true,
                    snap: true,
                    scrolledUnderElevation: 0.0,
                    surfaceTintColor: Colors.transparent,
                    backgroundColor: theme.colorScheme.surface,
                    toolbarHeight: 72,
                    titleSpacing: isSelecting ? 16 : 0,
                    leadingWidth: 56,
                    leading: isSelecting
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              ref
                                  .read(
                                    radarrMoviesSelectionProvider(
                                      widget.instance,
                                    ).notifier,
                                  )
                                  .state = {};
                            },
                          )
                        : IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () {
                              Scaffold.of(context).openDrawer();
                            },
                          ),
                    title: isSelecting
                        ? Text(
                            '${selection.length} selected',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : SearchBar(
                            focusNode: _searchFocusNode,
                            controller: _searchController,
                            hintText: 'Search movies...',
                            onTapOutside: (event) {
                              if (_searchFocusNode.hasFocus) {
                                _searchFocusNode.unfocus();
                              }
                            },
                            elevation: const WidgetStatePropertyAll<double>(0),
                            backgroundColor: WidgetStatePropertyAll<Color>(
                              theme.colorScheme.surfaceContainerHigh,
                            ),
                            trailing: <Widget>[
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                    });
                                    ref
                                        .read(
                                          radarrSearchQueryProvider(
                                            widget.instance,
                                          ).notifier,
                                        )
                                        .state = '';
                                    _updateSearchActiveState();
                                  },
                                ),
                            ],
                            onChanged: (String value) {
                              setState(() {});
                              ref
                                  .read(
                                    radarrSearchQueryProvider(widget.instance)
                                        .notifier,
                                  )
                                  .state = value;
                              _updateSearchActiveState();
                            },
                          ),
                    actions: <Widget>[
                      if (isSelecting) ...<Widget>[
                        if (list.isNotEmpty)
                          if (selection.length < list.length)
                            IconButton(
                              icon: const Icon(Icons.select_all),
                              tooltip: 'Select all',
                              onPressed: () {
                                ref
                                    .read(
                                      radarrMoviesSelectionProvider(
                                        widget.instance,
                                      ).notifier,
                                    )
                                    .state = list.map((m) => m.id).toSet();
                              },
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.deselect),
                              tooltip: 'Deselect all',
                              onPressed: () {
                                ref
                                    .read(
                                      radarrMoviesSelectionProvider(
                                        widget.instance,
                                      ).notifier,
                                    )
                                    .state = {};
                              },
                            ),
                      ] else ...<Widget>[
                        IconButton(
                          icon: Icon(
                            viewMode == RadarrViewMode.grid
                                ? Icons.view_list
                                : Icons.grid_view,
                          ),
                          tooltip: viewMode == RadarrViewMode.grid
                              ? 'Switch to list view'
                              : 'Switch to grid view',
                          onPressed: () {
                            ref
                                .read(
                                  radarrViewModeProvider(widget.instance)
                                      .notifier,
                                )
                                .setViewMode(
                                  viewMode == RadarrViewMode.grid
                                      ? RadarrViewMode.list
                                      : RadarrViewMode.grid,
                                );
                          },
                        ),
                      ],
                      const SizedBox(width: Insets.sm),
                    ],
                  ),
                  const HeaderLocator.sliver(),
                  if (list.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyView(
                        icon: Icons.movie_outlined,
                        title: 'No movies found',
                        message:
                            'Try adjusting your search query or active filters.',
                      ),
                    )
                  else if (viewMode == RadarrViewMode.grid)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.md,
                        Insets.md,
                        Insets.md,
                        80.0,
                      ),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 140,
                          childAspectRatio: 0.5,
                          crossAxisSpacing: Insets.md,
                          mainAxisSpacing: Insets.md,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (BuildContext context, int index) {
                            final RadarrMovie m = list[index];
                            final RadarrImage? poster =
                                m.images.firstWhereOrNull(
                              (RadarrImage i) => i.coverType == 'poster',
                            );
                            final isSelected = selection.contains(m.id);
                            return _MovieCard(
                              movie: m,
                              imageUrl: poster == null
                                  ? null
                                  : api?.posterUrl(poster, width: 500),
                              selected: isSelected,
                              onLongPress: () {
                                final notifier = ref.read(
                                  radarrMoviesSelectionProvider(
                                    widget.instance,
                                  ).notifier,
                                );
                                if (isSelected) {
                                  notifier.state = selection
                                      .where((id) => id != m.id)
                                      .toSet();
                                } else {
                                  notifier.state = {...selection, m.id};
                                }
                              },
                              onTap: () {
                                if (isSelecting) {
                                  final notifier = ref.read(
                                    radarrMoviesSelectionProvider(
                                      widget.instance,
                                    ).notifier,
                                  );
                                  if (isSelected) {
                                    notifier.state = selection
                                        .where((id) => id != m.id)
                                        .toSet();
                                  } else {
                                    notifier.state = {...selection, m.id};
                                  }
                                } else {
                                  Navigator.of(context, rootNavigator: true)
                                      .push(
                                    FadePageRoute<void>(
                                      builder: (BuildContext context) =>
                                          MovieDetailScreen(
                                        instance: widget.instance,
                                        movieId: m.id,
                                        movie: m,
                                      ),
                                    ),
                                  );
                                }
                              },
                            );
                          },
                          childCount: list.length,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.md,
                        0.0,
                        Insets.md,
                        80.0,
                      ),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (BuildContext context, int index) {
                            final RadarrMovie m = list[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: Insets.md),
                              child: _MovieBannerCard(
                                instance: widget.instance,
                                movie: m,
                                selected: selection.contains(m.id),
                                onLongPress: () {
                                  final isSelected = selection.contains(m.id);
                                  final notifier = ref.read(
                                    radarrMoviesSelectionProvider(
                                      widget.instance,
                                    ).notifier,
                                  );
                                  if (isSelected) {
                                    notifier.state = selection
                                        .where((id) => id != m.id)
                                        .toSet();
                                  } else {
                                    notifier.state = {...selection, m.id};
                                  }
                                },
                                onTap: () {
                                  final isSelected = selection.contains(m.id);
                                  if (isSelecting) {
                                    final notifier = ref.read(
                                      radarrMoviesSelectionProvider(
                                        widget.instance,
                                      ).notifier,
                                    );
                                    if (isSelected) {
                                      notifier.state = selection
                                          .where((id) => id != m.id)
                                          .toSet();
                                    } else {
                                      notifier.state = {...selection, m.id};
                                    }
                                  } else {
                                    Navigator.of(context, rootNavigator: true)
                                        .push(
                                      FadePageRoute<void>(
                                        builder: (BuildContext context) =>
                                            MovieDetailScreen(
                                          instance: widget.instance,
                                          movieId: m.id,
                                          movie: m,
                                        ),
                                      ),
                                    );
                                  }
                                },
                              ),
                            );
                          },
                          childCount: list.length,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MovieCard extends StatelessWidget {
  const _MovieCard({
    required this.movie,
    required this.imageUrl,
    required this.onTap,
    this.selected = false,
    this.onLongPress,
  });

  final RadarrMovie movie;
  final String? imageUrl;
  final VoidCallback onTap;
  final bool selected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Hero(
                    tag: 'movie-poster-${movie.id}',
                    child: _Poster(imageUrl: imageUrl, theme: theme),
                  ),
                  if (selected)
                    Positioned.fill(
                      child: Container(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.25),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.check,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!selected) ...[
                    if (movie.hasFile)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: _Badge(
                          color: theme.colorScheme.primary,
                          child: Icon(
                            Icons.check,
                            size: 12,
                            color: theme.colorScheme.onPrimary,
                          ),
                        ),
                      )
                    else if (movie.monitored)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: _Badge(
                          color: theme.colorScheme.secondaryContainer,
                          child: Icon(
                            Icons.bookmark,
                            size: 12,
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Insets.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    movie.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitle(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle() {
    final List<String> parts = <String>[
      if (movie.year != null) '${movie.year}',
      if (movie.sizeOnDisk > 0) _formatSize(movie.sizeOnDisk),
    ];
    return parts.join(' • ');
  }
}

class _MovieBannerCard extends ConsumerWidget {
  const _MovieBannerCard({
    required this.instance,
    required this.movie,
    required this.onTap,
    this.selected = false,
    this.onLongPress,
  });

  final Instance instance;
  final RadarrMovie movie;
  final VoidCallback onTap;
  final bool selected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final RadarrApi? api = ref.watch(radarrApiProvider(instance)).value;

    final RadarrImage? banner = movie.images
        .firstWhereOrNull((RadarrImage i) => i.coverType == 'banner');
    final RadarrImage? fanart = movie.images
        .firstWhereOrNull((RadarrImage i) => i.coverType == 'fanart');
    final RadarrImage? imageToUse = banner ?? fanart;
    final String? bannerUrl = imageToUse == null
        ? null
        : api?.posterUrl(
            imageToUse,
            width: imageToUse.coverType == 'fanart' ? 1080 : null,
          );

    final RadarrImage? poster = movie.images
        .firstWhereOrNull((RadarrImage i) => i.coverType == 'poster');
    final String? posterUrl =
        poster == null ? null : api?.posterUrl(poster, width: 500);

    final Color surfaceColor = theme.colorScheme.surface;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          height: 120,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (bannerUrl != null)
                Positioned.fill(
                  child: AtriumNetworkImage(
                    imageUrl: bannerUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    errorWidget: (_, __, ___) => Container(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
                )
              else
                Positioned.fill(
                  child: Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[
                        surfaceColor,
                        surfaceColor.withValues(alpha: 0.7),
                        surfaceColor.withValues(alpha: 0.1),
                      ],
                      stops: const <double>[0.15, 0.5, 0.85],
                    ),
                  ),
                ),
              ),
              if (selected)
                Positioned.fill(
                  child: Container(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 24.0),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 80,
                    height: double.infinity,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                      ),
                      child: posterUrl != null
                          ? Hero(
                              tag: 'movie-poster-${movie.id}',
                              child: AtriumNetworkImage(
                                imageUrl: posterUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: 500,
                                placeholder: (_, __) => Container(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                ),
                                errorWidget: (_, __, ___) => Container(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: const Icon(
                                    Icons.movie_outlined,
                                    size: 20,
                                  ),
                                ),
                              ),
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.movie_outlined, size: 20),
                            ),
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          Text(
                            movie.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _metaText(),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  if (movie.monitored)
                    Padding(
                      padding: const EdgeInsets.only(right: Insets.md),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.bookmark,
                          color: theme.colorScheme.primary,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _metaText() {
    final List<String> parts = <String>[
      if (movie.year != null) '${movie.year}',
      if (movie.studio != null && movie.studio!.isNotEmpty) movie.studio!,
      if (movie.sizeOnDisk > 0) _formatSize(movie.sizeOnDisk),
    ];
    return parts.join(' • ');
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.imageUrl, required this.theme});

  final String? imageUrl;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.movie_outlined, color: theme.colorScheme.outline),
    );
    if (imageUrl == null) {
      return fallback;
    }
    return AtriumNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      memCacheWidth: 500,
      placeholder: (BuildContext context, String url) =>
          Container(color: theme.colorScheme.surfaceContainerHighest),
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
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: child,
    );
  }
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

class _BulkActionsBar extends StatelessWidget {
  const _BulkActionsBar({
    required this.instance,
    required this.selectedIds,
    required this.onClear,
  });

  final Instance instance;
  final Set<int> selectedIds;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        Insets.md,
        Insets.sm,
        Insets.md,
        Insets.sm + MediaQuery.paddingOf(context).bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.primary,
            ),
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (BuildContext context) => _BulkEditDialog(
                  instance: instance,
                  selectedIds: selectedIds,
                ),
              );
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () {
              showDialog<void>(
                context: context,
                builder: (BuildContext context) => _BulkDeleteDialog(
                  instance: instance,
                  selectedIds: selectedIds,
                ),
              );
            },
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _BulkEditDialog extends ConsumerStatefulWidget {
  const _BulkEditDialog({
    required this.instance,
    required this.selectedIds,
  });

  final Instance instance;
  final Set<int> selectedIds;

  @override
  ConsumerState<_BulkEditDialog> createState() => _BulkEditDialogState();
}

class _BulkEditDialogState extends ConsumerState<_BulkEditDialog> {
  bool? _monitored;
  int? _qualityProfileId;
  String? _rootFolderPath;
  bool _moveFiles = true;

  @override
  Widget build(BuildContext context) {
    final profilesAsync =
        ref.watch(radarrQualityProfilesProvider(widget.instance));
    final foldersAsync = ref.watch(radarrRootFoldersProvider(widget.instance));

    return AlertDialog(
      title: const Text('Bulk Edit Movies'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: Insets.sm),
            DropdownButtonFormField<bool?>(
              initialValue: _monitored,
              decoration: const InputDecoration(
                labelText: 'Monitored',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(child: Text('Keep current')),
                DropdownMenuItem(value: true, child: Text('Monitored')),
                DropdownMenuItem(value: false, child: Text('Unmonitored')),
              ],
              onChanged: (val) => setState(() => _monitored = val),
            ),
            const SizedBox(height: Insets.md),
            profilesAsync.when(
              data: (profiles) => DropdownButtonFormField<int?>(
                initialValue: _qualityProfileId,
                decoration: const InputDecoration(
                  labelText: 'Quality Profile',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(child: Text('Keep current')),
                  ...profiles.map(
                    (p) => DropdownMenuItem(
                      value: p['id'] as int,
                      child: Text(p['name'] as String),
                    ),
                  ),
                ],
                onChanged: (val) => setState(() => _qualityProfileId = val),
              ),
              loading: () => const SizedBox(
                height: 50,
                child: Center(child: ExpressiveProgressIndicator()),
              ),
              error: (_, __) => const Text('Error loading profiles'),
            ),
            const SizedBox(height: Insets.md),
            foldersAsync.when(
              data: (folders) => DropdownButtonFormField<String?>(
                initialValue: _rootFolderPath,
                decoration: const InputDecoration(
                  labelText: 'Root Folder',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(child: Text('Keep current')),
                  ...folders.map(
                    (f) => DropdownMenuItem(
                      value: f['path'] as String,
                      child: Text(f['path'] as String),
                    ),
                  ),
                ],
                onChanged: (val) => setState(() => _rootFolderPath = val),
              ),
              loading: () => const SizedBox(
                height: 50,
                child: Center(child: ExpressiveProgressIndicator()),
              ),
              error: (_, __) => const Text('Error loading folders'),
            ),
            if (_rootFolderPath != null) ...[
              const SizedBox(height: Insets.sm),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Move files to the new folder'),
                subtitle: const Text(
                  'Off leaves the files behind in the old folder',
                ),
                value: _moveFiles,
                onChanged: (val) => setState(() => _moveFiles = val),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () async {
            final NavigatorState nav =
                Navigator.of(context, rootNavigator: true);
            final payload = <String, dynamic>{
              'movieIds': widget.selectedIds.toList(),
              if (_monitored != null) 'monitored': _monitored,
              if (_qualityProfileId != null)
                'qualityProfileId': _qualityProfileId,
              if (_rootFolderPath != null) 'rootFolderPath': _rootFolderPath,
              // Changing the root folder without moveFiles orphans the
              // files on disk, so send the user's explicit choice.
              if (_rootFolderPath != null) 'moveFiles': _moveFiles,
            };

            unawaited(
              showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => const PopScope<Object?>(
                  canPop: false,
                  child: Center(child: ExpressiveProgressIndicator()),
                ),
              ),
            );

            Object? error;
            try {
              final api =
                  await ref.read(radarrApiProvider(widget.instance).future);
              await api.bulkUpdateMovies(payload);
            } catch (e) {
              error = e;
            } finally {
              if (nav.mounted) nav.pop(); // pop loading
            }

            if (!context.mounted) return;
            if (error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error updating movies: $error')),
              );
              return;
            }
            ref.invalidate(radarrMoviesProvider(widget.instance));
            ref
                .read(radarrMoviesSelectionProvider(widget.instance).notifier)
                .state = {};
            Navigator.pop(context); // pop dialog

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Successfully updated movies')),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

enum _DeleteMode {
  deleteEntry,
  deleteFilesOnly,
}

class _BulkDeleteDialog extends ConsumerStatefulWidget {
  const _BulkDeleteDialog({
    required this.instance,
    required this.selectedIds,
  });

  final Instance instance;
  final Set<int> selectedIds;

  @override
  ConsumerState<_BulkDeleteDialog> createState() => _BulkDeleteDialogState();
}

class _BulkDeleteDialogState extends ConsumerState<_BulkDeleteDialog> {
  _DeleteMode _mode = _DeleteMode.deleteEntry;
  bool _deleteFiles = false;
  bool _unmonitor = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Delete ${widget.selectedIds.length} Movies?'),
      content: RadioGroup<_DeleteMode>(
        groupValue: _mode,
        onChanged: (_DeleteMode? val) => setState(() {
          if (val != null) _mode = val;
        }),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const RadioListTile<_DeleteMode>(
              title: Text('Delete movie entry'),
              subtitle: Text('Remove from Radarr library'),
              value: _DeleteMode.deleteEntry,
              contentPadding: EdgeInsets.zero,
            ),
            if (_mode == _DeleteMode.deleteEntry)
              Padding(
                padding: const EdgeInsets.only(left: Insets.lg),
                child: CheckboxListTile(
                  title: const Text('Also delete files from disk'),
                  value: _deleteFiles,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setState(() => _deleteFiles = val ?? false),
                ),
              ),
            const RadioListTile<_DeleteMode>(
              title: Text('Delete files only'),
              subtitle:
                  Text('Keep entry in Radarr library to free disk space'),
              value: _DeleteMode.deleteFilesOnly,
              contentPadding: EdgeInsets.zero,
            ),
            if (_mode == _DeleteMode.deleteFilesOnly)
              Padding(
                padding: const EdgeInsets.only(left: Insets.lg),
                child: CheckboxListTile(
                  title: const Text('Unmonitor movie'),
                  subtitle: const Text('Prevent automatic re-downloads'),
                  value: _unmonitor,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) => setState(() => _unmonitor = val ?? false),
                ),
              ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () async {
            final NavigatorState nav =
                Navigator.of(context, rootNavigator: true);
            unawaited(
              showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => const PopScope<Object?>(
                  canPop: false,
                  child: Center(child: ExpressiveProgressIndicator()),
                ),
              ),
            );

            Object? error;
            int successCount = 0;
            int failedCount = 0;
            try {
              final api =
                  await ref.read(radarrApiProvider(widget.instance).future);
              if (_mode == _DeleteMode.deleteEntry) {
                await api.bulkDeleteMovies(
                  widget.selectedIds.toList(),
                  deleteFiles: _deleteFiles,
                );
              } else {
                for (final id in widget.selectedIds) {
                  try {
                    final movie = await api.getMovieById(id);
                    if (movie.movieFileId != null) {
                      await api.deleteMovieFile(movie.movieFileId!);
                    }
                    if (_unmonitor) {
                      try {
                        final Map<String, dynamic> raw =
                            await api.getMovieRaw(id);
                        raw['monitored'] = false;
                        if (raw['qualityProfileId'] == null ||
                            raw['qualityProfileId'] == 0) {
                          final profiles = await api.getQualityProfiles();
                          if (profiles.isNotEmpty) {
                            raw['qualityProfileId'] = profiles.first['id'];
                          }
                        }
                        await api.updateMovieRaw(raw);
                      } catch (_) {}
                    }
                    successCount++;
                  } catch (_) {
                    failedCount++;
                  }
                }
              }
            } catch (e) {
              error = e;
            } finally {
              if (nav.mounted) nav.pop(); // pop loading
            }

            if (!context.mounted) return;
            if (error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $error')),
              );
              return;
            }
            ref.invalidate(radarrMoviesProvider(widget.instance));
            ref
                .read(radarrMoviesSelectionProvider(widget.instance).notifier)
                .state = <int>{};
            Navigator.pop(context); // pop dialog

            final String msg;
            if (_mode == _DeleteMode.deleteEntry) {
              msg = 'Successfully deleted ${widget.selectedIds.length} movie(s)';
            } else if (failedCount == 0) {
              msg = _unmonitor
                  ? 'Successfully deleted files and unmonitored $successCount movie(s)'
                  : 'Successfully deleted files for $successCount movie(s)';
            } else {
              msg = 'Deleted files for $successCount movie(s). Failed for $failedCount movie(s)';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(msg)),
            );
          },
          child: const Text('Delete'),
        ),
      ],
    );
  }
}

class _SortFilterBottomSheet extends ConsumerWidget {
  const _SortFilterBottomSheet({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final sortOption = ref.watch(radarrMovieSortFieldProvider(instance));
    final sortAscending = ref.watch(radarrMovieSortAscendingProvider(instance));
    final filter = ref.watch(radarrMovieFilterProvider(instance));

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Filter',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All Status'),
                    selected: filter == RadarrMovieFilter.all,
                    onSelected: (val) {
                      if (val) {
                        ref
                            .read(radarrMovieFilterProvider(instance).notifier)
                            .state = RadarrMovieFilter.all;
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Downloaded Only'),
                    selected: filter == RadarrMovieFilter.downloaded,
                    onSelected: (val) {
                      if (val) {
                        ref
                            .read(radarrMovieFilterProvider(instance).notifier)
                            .state = RadarrMovieFilter.downloaded;
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Missing Only'),
                    selected: filter == RadarrMovieFilter.missing,
                    onSelected: (val) {
                      if (val) {
                        ref
                            .read(radarrMovieFilterProvider(instance).notifier)
                            .state = RadarrMovieFilter.missing;
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Monitored Only'),
                    selected: filter == RadarrMovieFilter.monitoredOnly,
                    onSelected: (val) {
                      if (val) {
                        ref
                            .read(radarrMovieFilterProvider(instance).notifier)
                            .state = RadarrMovieFilter.monitoredOnly;
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Unmonitored Only'),
                    selected: filter == RadarrMovieFilter.unmonitoredOnly,
                    onSelected: (val) {
                      if (val) {
                        ref
                            .read(radarrMovieFilterProvider(instance).notifier)
                            .state = RadarrMovieFilter.unmonitoredOnly;
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Sort',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Title'),
                    selected: sortOption == RadarrMovieSortField.title,
                    onSelected: (val) {
                      if (val) {
                        if (sortOption == RadarrMovieSortField.title) {
                          ref
                              .read(
                                radarrMovieSortAscendingProvider(instance)
                                    .notifier,
                              )
                              .state = !sortAscending;
                        } else {
                          ref
                              .read(
                                radarrMovieSortFieldProvider(instance).notifier,
                              )
                              .state = RadarrMovieSortField.title;
                          ref
                              .read(
                                radarrMovieSortAscendingProvider(instance)
                                    .notifier,
                              )
                              .state = true;
                        }
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Year'),
                    selected: sortOption == RadarrMovieSortField.year,
                    onSelected: (val) {
                      if (val) {
                        if (sortOption == RadarrMovieSortField.year) {
                          ref
                              .read(
                                radarrMovieSortAscendingProvider(instance)
                                    .notifier,
                              )
                              .state = !sortAscending;
                        } else {
                          ref
                              .read(
                                radarrMovieSortFieldProvider(instance).notifier,
                              )
                              .state = RadarrMovieSortField.year;
                          ref
                              .read(
                                radarrMovieSortAscendingProvider(instance)
                                    .notifier,
                              )
                              .state = false;
                        }
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Date Added'),
                    selected: sortOption == RadarrMovieSortField.added,
                    onSelected: (val) {
                      if (val) {
                        if (sortOption == RadarrMovieSortField.added) {
                          ref
                              .read(
                                radarrMovieSortAscendingProvider(instance)
                                    .notifier,
                              )
                              .state = !sortAscending;
                        } else {
                          ref
                              .read(
                                radarrMovieSortFieldProvider(instance).notifier,
                              )
                              .state = RadarrMovieSortField.added;
                          ref
                              .read(
                                radarrMovieSortAscendingProvider(instance)
                                    .notifier,
                              )
                              .state = false;
                        }
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Size on Disk'),
                    selected: sortOption == RadarrMovieSortField.sizeOnDisk,
                    onSelected: (val) {
                      if (val) {
                        if (sortOption == RadarrMovieSortField.sizeOnDisk) {
                          ref
                              .read(
                                radarrMovieSortAscendingProvider(instance)
                                    .notifier,
                              )
                              .state = !sortAscending;
                        } else {
                          ref
                              .read(
                                radarrMovieSortFieldProvider(instance).notifier,
                              )
                              .state = RadarrMovieSortField.sizeOnDisk;
                          ref
                              .read(
                                radarrMovieSortAscendingProvider(instance)
                                    .notifier,
                              )
                              .state = false;
                        }
                      }
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Monitored Status'),
                    selected:
                        sortOption == RadarrMovieSortField.monitoredStatus,
                    onSelected: (val) {
                      if (val) {
                        if (sortOption ==
                            RadarrMovieSortField.monitoredStatus) {
                          ref
                              .read(
                                radarrMovieSortAscendingProvider(instance)
                                    .notifier,
                              )
                              .state = !sortAscending;
                        } else {
                          ref
                              .read(
                                radarrMovieSortFieldProvider(instance).notifier,
                              )
                              .state = RadarrMovieSortField.monitoredStatus;
                          ref
                              .read(
                                radarrMovieSortAscendingProvider(instance)
                                    .notifier,
                              )
                              .state = true;
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const <ButtonSegment<bool>>[
                  ButtonSegment<bool>(
                    value: true,
                    label: Text('Ascending'),
                    icon: Icon(Icons.arrow_upward),
                  ),
                  ButtonSegment<bool>(
                    value: false,
                    label: Text('Descending'),
                    icon: Icon(Icons.arrow_downward),
                  ),
                ],
                selected: {sortAscending},
                onSelectionChanged: (val) {
                  ref
                      .read(
                        radarrMovieSortAscendingProvider(instance).notifier,
                      )
                      .state = val.first;
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

String _formatSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  final i = (log(bytes) / log(1024)).floor();
  return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
}
