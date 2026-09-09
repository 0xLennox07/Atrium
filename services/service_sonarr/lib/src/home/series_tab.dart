import 'dart:async';
import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../service_sonarr.dart';

class SeriesTab extends ConsumerStatefulWidget {
  const SeriesTab({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<SeriesTab> createState() => _SeriesTabState();
}

class _SeriesTabState extends ConsumerState<SeriesTab>
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
        ref.read(sonarrSearchActiveProvider(widget.instance).notifier);
    _resetSearchActive = () => notifier.state = false;
    final String initialQuery =
        ref.read(sonarrSearchQueryProvider(widget.instance));
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
    ref.read(sonarrSearchActiveProvider(widget.instance).notifier).state =
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
    final AsyncValue<List<SonarrSeries>> filtered =
        ref.watch(sonarrFilteredSeriesProvider(widget.instance));
    final SonarrApi? api = ref.watch(sonarrApiProvider(widget.instance)).value;
    final SonarrViewMode viewMode =
        ref.watch(sonarrViewModeProvider(widget.instance));
    final selection = ref.watch(sonarrSeriesSelectionProvider(widget.instance));
    final isSelecting = selection.isNotEmpty;

    ref.listen<int>(sonarrHomeScrollToTopProvider((widget.instance, 0)),
        (previous, next) {
      if (next > 0 && _scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });

    // Keep the local controller in sync when the search query is cleared
    // externally (SonarrHome unwinds search state on system back).
    ref.listen<String>(sonarrSearchQueryProvider(widget.instance),
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
                      sonarrSeriesSelectionProvider(widget.instance).notifier,
                    )
                    .state = {};
              },
            )
          : null,
      floatingActionButton: !isSelecting &&
              ref.watch(
                    sonarrActiveTabBarIndexProvider(widget.instance),
                  ) ==
                  0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                FloatingActionButton.small(
                  heroTag: 'sonarr_sort_filter_fab',
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
                  heroTag: 'sonarr_add_series_fab',
                  shape: const StadiumBorder(),
                  backgroundColor: theme.colorScheme.primaryContainer,
                  foregroundColor: theme.colorScheme.onPrimaryContainer,
                  onPressed: () {
                    Navigator.of(context, rootNavigator: true).push(
                      FadePageRoute<void>(
                        builder: (BuildContext context) =>
                            SonarrAddSeriesSearchScreen(
                          instance: widget.instance,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Series'),
                ),
              ],
            )
          : null,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: AsyncValueView<List<SonarrSeries>>(
          value: filtered,
          onRetry: () => ref.invalidate(sonarrSeriesProvider(widget.instance)),
          data: (List<SonarrSeries> list) {
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
                ref.invalidate(sonarrSeriesProvider(widget.instance));
                await ref.read(sonarrSeriesProvider(widget.instance).future);
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                controller: _scrollController,
                slivers: <Widget>[
                  // Built-in Material 3 SliverAppBar with floating & snap animation
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
                                    sonarrSeriesSelectionProvider(
                                      widget.instance,
                                    ).notifier,
                                  )
                                  .state = {};
                            },
                          )
                        : IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () {
                              openDrawer(context);
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
                            hintText: 'Search series...',
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
                                          sonarrSearchQueryProvider(
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
                                    sonarrSearchQueryProvider(widget.instance)
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
                                      sonarrSeriesSelectionProvider(
                                        widget.instance,
                                      ).notifier,
                                    )
                                    .state = list.map((s) => s.id).toSet();
                              },
                            )
                          else
                            IconButton(
                              icon: const Icon(Icons.deselect),
                              tooltip: 'Deselect all',
                              onPressed: () {
                                ref
                                    .read(
                                      sonarrSeriesSelectionProvider(
                                        widget.instance,
                                      ).notifier,
                                    )
                                    .state = {};
                              },
                            ),
                      ] else ...<Widget>[
                        IconButton(
                          icon: Icon(
                            viewMode == SonarrViewMode.grid
                                ? Icons.view_list
                                : Icons.grid_view,
                          ),
                          tooltip: viewMode == SonarrViewMode.grid
                              ? 'Switch to list view'
                              : 'Switch to grid view',
                          onPressed: () {
                            ref
                                .read(
                                  sonarrViewModeProvider(widget.instance)
                                      .notifier,
                                )
                                .setViewMode(
                                  viewMode == SonarrViewMode.grid
                                      ? SonarrViewMode.list
                                      : SonarrViewMode.grid,
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
                        icon: Icons.live_tv_outlined,
                        title: 'No series found',
                        message:
                            'Try adjusting your search query or active filters.',
                      ),
                    )
                  else if (viewMode == SonarrViewMode.grid)
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
                            final SonarrSeries s = list[index];
                            final SonarrImage? poster =
                                s.images.firstWhereOrNull(
                              (SonarrImage i) => i.coverType == 'poster',
                            );
                            final isSelected = selection.contains(s.id);
                            return _SeriesCard(
                              series: s,
                              imageUrl: poster == null
                                  ? null
                                  : api?.posterUrl(poster, width: 500),
                              selected: isSelected,
                              onLongPress: () {
                                final notifier = ref.read(
                                  sonarrSeriesSelectionProvider(
                                    widget.instance,
                                  ).notifier,
                                );
                                if (isSelected) {
                                  notifier.state = selection
                                      .where((id) => id != s.id)
                                      .toSet();
                                } else {
                                  notifier.state = {...selection, s.id};
                                }
                              },
                              onTap: () {
                                if (isSelecting) {
                                  final notifier = ref.read(
                                    sonarrSeriesSelectionProvider(
                                      widget.instance,
                                    ).notifier,
                                  );
                                  if (isSelected) {
                                    notifier.state = selection
                                        .where((id) => id != s.id)
                                        .toSet();
                                  } else {
                                    notifier.state = {...selection, s.id};
                                  }
                                } else {
                                  Navigator.of(context, rootNavigator: true)
                                      .push(
                                    FadePageRoute<void>(
                                      builder: (BuildContext context) =>
                                          SeriesDetailScreen(
                                        instance: widget.instance,
                                        series: s,
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
                            final SonarrSeries s = list[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: Insets.md),
                              child: _SeriesBannerCard(
                                instance: widget.instance,
                                series: s,
                                selected: selection.contains(s.id),
                                onLongPress: () {
                                  final isSelected = selection.contains(s.id);
                                  final notifier = ref.read(
                                    sonarrSeriesSelectionProvider(
                                      widget.instance,
                                    ).notifier,
                                  );
                                  if (isSelected) {
                                    notifier.state = selection
                                        .where((id) => id != s.id)
                                        .toSet();
                                  } else {
                                    notifier.state = {...selection, s.id};
                                  }
                                },
                                onTap: () {
                                  final isSelected = selection.contains(s.id);
                                  if (isSelecting) {
                                    final notifier = ref.read(
                                      sonarrSeriesSelectionProvider(
                                        widget.instance,
                                      ).notifier,
                                    );
                                    if (isSelected) {
                                      notifier.state = selection
                                          .where((id) => id != s.id)
                                          .toSet();
                                    } else {
                                      notifier.state = {...selection, s.id};
                                    }
                                  } else {
                                    Navigator.of(context, rootNavigator: true)
                                        .push(
                                      FadePageRoute<void>(
                                        builder: (BuildContext context) =>
                                            SeriesDetailScreen(
                                          instance: widget.instance,
                                          series: s,
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

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({
    required this.series,
    required this.imageUrl,
    required this.onTap,
    this.selected = false,
    this.onLongPress,
  });

  final SonarrSeries series;
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
                    tag: 'series-poster-${series.id}',
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
                  if (series.monitored)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _Badge(
                        color: theme.colorScheme.primary,
                        child: Icon(
                          Icons.bookmark,
                          size: 12,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(Insets.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    series.title,
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
    final int sizeOnDisk = series.statistics?.sizeOnDisk ?? 0;
    final List<String> parts = <String>[
      if (series.year != null) '${series.year}',
      if (series.status != null) series.status!,
      if (sizeOnDisk > 0) _formatSize(sizeOnDisk),
    ];
    return parts.join(' • ');
  }
}

class _SeriesBannerCard extends ConsumerWidget {
  const _SeriesBannerCard({
    required this.instance,
    required this.series,
    required this.onTap,
    this.selected = false,
    this.onLongPress,
  });

  final Instance instance;
  final SonarrSeries series;
  final VoidCallback onTap;
  final bool selected;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final SonarrApi? api = ref.watch(sonarrApiProvider(instance)).value;

    final SonarrImage? banner = series.images
        .firstWhereOrNull((SonarrImage i) => i.coverType == 'banner');
    final String? bannerUrl = banner == null ? null : api?.posterUrl(banner);

    final SonarrImage? poster = series.images
        .firstWhereOrNull((SonarrImage i) => i.coverType == 'poster');
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
                              tag: 'series-poster-${series.id}',
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
                                  child: const Icon(Icons.live_tv, size: 20),
                                ),
                              ),
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.live_tv, size: 20),
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
                            series.title,
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
                  if (series.monitored)
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
    final int sizeOnDisk = series.statistics?.sizeOnDisk ?? 0;
    final List<String> parts = <String>[
      if (series.year != null) '${series.year}',
      if (series.network != null && series.network!.isNotEmpty) series.network!,
      if (series.status != null && series.status!.isNotEmpty) series.status!,
      if (sizeOnDisk > 0) _formatSize(sizeOnDisk),
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
      child: Icon(Icons.live_tv_outlined, color: theme.colorScheme.outline),
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
  String? _seriesType;
  String? _rootFolderPath;

  @override
  Widget build(BuildContext context) {
    final profilesAsync =
        ref.watch(sonarrQualityProfilesProvider(widget.instance));
    final foldersAsync = ref.watch(sonarrRootFoldersProvider(widget.instance));

    return AlertDialog(
      title: const Text('Bulk Edit Series'),
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
            DropdownButtonFormField<String?>(
              initialValue: _seriesType,
              decoration: const InputDecoration(
                labelText: 'Series Type',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(child: Text('Keep current')),
                DropdownMenuItem(value: 'standard', child: Text('Standard')),
                DropdownMenuItem(value: 'daily', child: Text('Daily')),
                DropdownMenuItem(value: 'anime', child: Text('Anime')),
              ],
              onChanged: (val) => setState(() => _seriesType = val),
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
              'seriesIds': widget.selectedIds.toList(),
              if (_monitored != null) 'monitored': _monitored,
              if (_qualityProfileId != null)
                'qualityProfileId': _qualityProfileId,
              if (_seriesType != null) 'seriesType': _seriesType,
              if (_rootFolderPath != null) 'rootFolderPath': _rootFolderPath,
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
                  await ref.read(sonarrApiProvider(widget.instance).future);
              await api.bulkUpdateSeries(payload);
            } catch (e) {
              error = e;
            } finally {
              if (nav.mounted) nav.pop(); // pop loading
            }

            if (!context.mounted) return;
            if (error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error updating series: $error')),
              );
              return;
            }
            ref.invalidate(sonarrSeriesProvider(widget.instance));
            ref
                .read(sonarrSeriesSelectionProvider(widget.instance).notifier)
                .state = {};
            Navigator.pop(context); // pop dialog

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Successfully updated series')),
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
      title: Text('Delete ${widget.selectedIds.length} Series?'),
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
              title: Text('Delete series entry'),
              subtitle: Text('Remove from Sonarr library'),
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
                  Text('Keep entry in Sonarr library to free disk space'),
              value: _DeleteMode.deleteFilesOnly,
              contentPadding: EdgeInsets.zero,
            ),
            if (_mode == _DeleteMode.deleteFilesOnly)
              Padding(
                padding: const EdgeInsets.only(left: Insets.lg),
                child: CheckboxListTile(
                  title: const Text('Unmonitor series'),
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
                  await ref.read(sonarrApiProvider(widget.instance).future);
              if (_mode == _DeleteMode.deleteEntry) {
                await api.bulkDeleteSeries(
                  widget.selectedIds.toList(),
                  deleteFiles: _deleteFiles,
                );
              } else {
                for (final id in widget.selectedIds) {
                  try {
                    final files = await api.getEpisodeFiles(id);
                    for (final f in files) {
                      final int? fId = f['id'] as int?;
                      if (fId != null) {
                        await api.deleteEpisodeFile(fId);
                      }
                    }
                    if (_unmonitor) {
                      try {
                        final raw = await api.getSeriesRaw(id);
                        raw['monitored'] = false;
                        await api.updateSeriesRaw(raw);
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
            ref.invalidate(sonarrSeriesProvider(widget.instance));
            ref
                .read(sonarrSeriesSelectionProvider(widget.instance).notifier)
                .state = <int>{};
            Navigator.pop(context); // pop dialog

            final String msg;
            if (_mode == _DeleteMode.deleteEntry) {
              msg = 'Successfully deleted ${widget.selectedIds.length} series';
            } else if (failedCount == 0) {
              msg = _unmonitor
                  ? 'Successfully deleted files and unmonitored $successCount series'
                  : 'Successfully deleted files for $successCount series';
            } else {
              msg = 'Deleted files for $successCount series. Failed for $failedCount series';
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

    final sortField = ref.watch(sonarrSeriesSortFieldProvider(instance));
    final sortAscending =
        ref.watch(sonarrSeriesSortAscendingProvider(instance));
    final filter = ref.watch(sonarrSeriesFilterProvider(instance));

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
                runSpacing: 4,
                children: SonarrSeriesFilter.values.map((f) {
                  final label = switch (f) {
                    SonarrSeriesFilter.all => 'All',
                    SonarrSeriesFilter.monitoredOnly => 'Monitored Only',
                    SonarrSeriesFilter.unmonitoredOnly => 'Unmonitored Only',
                    SonarrSeriesFilter.continuingOnly => 'Continuing Only',
                    SonarrSeriesFilter.endedOnly => 'Ended Only',
                    SonarrSeriesFilter.missingEpisodes => 'Missing Episodes',
                  };
                  final selected = filter == f;
                  return ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (val) {
                      if (val) {
                        ref
                            .read(sonarrSeriesFilterProvider(instance).notifier)
                            .state = f;
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                'Sort By',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: SonarrSeriesSortField.values.map((field) {
                  final label = switch (field) {
                    SonarrSeriesSortField.monitoredStatus => 'Monitored/Status',
                    SonarrSeriesSortField.title => 'Title',
                    SonarrSeriesSortField.network => 'Network',
                    SonarrSeriesSortField.nextAiring => 'Next Airing',
                    SonarrSeriesSortField.previousAiring => 'Previous Airing',
                    SonarrSeriesSortField.added => 'Added',
                    SonarrSeriesSortField.seasons => 'Seasons',
                    SonarrSeriesSortField.episodes => 'Episodes',
                    SonarrSeriesSortField.episodeCount => 'Episode Count',
                    SonarrSeriesSortField.sizeOnDisk => 'Size on Disk',
                  };
                  final selected = sortField == field;
                  return ChoiceChip(
                    label: Text(label),
                    selected: selected,
                    onSelected: (val) {
                      if (val) {
                        ref
                            .read(
                              sonarrSeriesSortFieldProvider(instance).notifier,
                            )
                            .state = field;
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                'Order',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
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
                        sonarrSeriesSortAscendingProvider(instance).notifier,
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
  const List<String> suffixes = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  int i = 0;
  double dBytes = bytes.toDouble();
  while (dBytes >= 1024 && i < suffixes.length - 1) {
    dBytes /= 1024;
    i++;
  }
  return '${dBytes.toStringAsFixed(1)} ${suffixes[i]}';
}
