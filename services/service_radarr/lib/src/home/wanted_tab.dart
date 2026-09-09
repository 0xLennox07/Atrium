import 'dart:async';
import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../service_radarr.dart';
import 'manual_import_dialog.dart';

class WantedTab extends ConsumerStatefulWidget {
  const WantedTab({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<WantedTab> createState() => _WantedTabState();
}

class _WantedTabState extends ConsumerState<WantedTab>
    with WidgetsBindingObserver {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final void Function() _resetSearchActive;
  double _lastBottomInset = 0;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addObserver(this);
    final notifier =
        ref.read(radarrSearchActiveProvider(widget.instance).notifier);
    _resetSearchActive = () => notifier.state = false;
    final String initialQuery =
        ref.read(radarrWantedSearchQueryProvider(widget.instance));
    _searchController = TextEditingController(text: initialQuery);
    _searchFocusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _resetSearchActive();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchFocusNode.dispose();
    _scrollController.dispose();
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

  void _clearSelection() {
    ref.read(radarrWantedSelectionProvider(widget.instance).notifier).state =
        <int>{};
  }

  Future<void> _searchSelected() async {
    final Set<int> selected =
        ref.read(radarrWantedSelectionProvider(widget.instance));
    if (selected.isEmpty) return;
    final List<int> ids = selected.toList();
    _clearSelection();

    try {
      final api = await ref.read(radarrApiProvider(widget.instance).future);
      await api.runCommand(<String, dynamic>{
        'name': 'MoviesSearch',
        'movieIds': ids,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Search started for ${ids.length} selected movies.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start search: $e')),
        );
      }
    }
  }

  Future<void> _unmonitorSelected() async {
    final Set<int> selected =
        ref.read(radarrWantedSelectionProvider(widget.instance));
    if (selected.isEmpty) return;
    final List<int> ids = selected.toList();
    _clearSelection();

    try {
      final api = await ref.read(radarrApiProvider(widget.instance).future);
      // Construct bulk updates
      for (final id in ids) {
        final Map<String, dynamic> raw = await api.getMovieRaw(id);
        raw['monitored'] = false;
        await api.updateMovieRaw(raw);
      }

      ref.invalidate(radarrWantedMissingProvider(widget.instance));
      ref.invalidate(radarrWantedCutoffProvider(widget.instance));
      ref.invalidate(radarrMoviesProvider(widget.instance));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unmonitored ${ids.length} selected movies.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update monitoring: $e')),
        );
      }
    }
  }

  Future<void> _bulkSearchAll(bool isCutoffTab) async {
    try {
      final api = await ref.read(radarrApiProvider(widget.instance).future);
      await api.runCommand(<String, dynamic>{
        'name': isCutoffTab ? 'CutoffUnmetMoviesSearch' : 'MissingMoviesSearch',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCutoffTab
                  ? 'Cutoff unmet movie search started.'
                  : 'Missing movie search started.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start bulk search: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Set<int> selectedMovieIds =
        ref.watch(radarrWantedSelectionProvider(widget.instance));
    final bool hasSelection = selectedMovieIds.isNotEmpty;

    ref.listen<String>(radarrWantedSearchQueryProvider(widget.instance),
        (String? previous, String next) {
      if (next.isEmpty && _searchController.text.isNotEmpty) {
        setState(() {
          _searchController.clear();
        });
        _searchFocusNode.unfocus();
        _updateSearchActiveState();
      }
    });

    ref.listen<int>(radarrHomeScrollToTopProvider((widget.instance, 2)),
        (previous, next) {
      if (next > 0 && _scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: NestedScrollView(
          controller: _scrollController,
          headerSliverBuilder:
              (BuildContext innerContext, bool innerBoxIsScrolled) {
            return <Widget>[
              SliverAppBar(
                floating: true,
                snap: true,
                pinned: true,
                scrolledUnderElevation: 0.0,
                surfaceTintColor: Colors.transparent,
                backgroundColor: theme.colorScheme.surface,
                toolbarHeight: 72,
                titleSpacing: 0,
                leadingWidth: 56,
                leading: hasSelection
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: _clearSelection,
                      )
                    : IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () {
                          Scaffold.of(context).openDrawer();
                        },
                      ),
                title: hasSelection
                    ? Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: Text(
                          '${selectedMovieIds.length} Selected',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : SearchBar(
                        focusNode: _searchFocusNode,
                        controller: _searchController,
                        hintText: 'Search wanted...',
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
                                      radarrWantedSearchQueryProvider(
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
                                radarrWantedSearchQueryProvider(widget.instance)
                                    .notifier,
                              )
                              .state = value;
                          _updateSearchActiveState();
                        },
                      ),
                actions: hasSelection
                    ? <Widget>[
                        IconButton(
                          icon: const Icon(Icons.search),
                          tooltip: 'Search Selected',
                          onPressed: _searchSelected,
                        ),
                        IconButton(
                          icon: const Icon(Icons.bookmark_border),
                          tooltip: 'Unmonitor Selected',
                          onPressed: _unmonitorSelected,
                        ),
                        const SizedBox(width: 8),
                      ]
                    : <Widget>[
                        const SizedBox(width: 48),
                        const SizedBox(width: 8),
                      ],
                bottom: TabBar(
                  dividerColor: Colors.transparent,
                  indicatorColor: theme.colorScheme.primary,
                  labelColor: theme.colorScheme.primary,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelStyle: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  unselectedLabelStyle: theme.textTheme.titleSmall,
                  tabs: const <Widget>[
                    Tab(text: 'Missing'),
                    Tab(text: 'Cutoff Unmet'),
                  ],
                ),
              ),
            ];
          },
          body: TabBarView(
            children: <Widget>[
              _WantedListView(
                instance: widget.instance,
                isCutoffTab: false,
                onBulkSearch: () => _bulkSearchAll(false),
              ),
              _WantedListView(
                instance: widget.instance,
                isCutoffTab: true,
                onBulkSearch: () => _bulkSearchAll(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WantedListView extends ConsumerWidget {
  const _WantedListView({
    required this.instance,
    required this.isCutoffTab,
    required this.onBulkSearch,
  });

  final Instance instance;
  final bool isCutoffTab;
  final VoidCallback onBulkSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = isCutoffTab
        ? ref.watch(radarrWantedFilteredCutoffProvider(instance))
        : ref.watch(radarrWantedFilteredMissingProvider(instance));

    // The unfiltered page carries the server-side total, so the tab can say
    // when the single fetched page does not cover everything.
    final RadarrWantedPage? page = isCutoffTab
        ? ref.watch(radarrWantedCutoffProvider(instance)).value
        : ref.watch(radarrWantedMissingProvider(instance)).value;
    final int fetchedCount = page?.records.length ?? 0;
    final int totalRecords = page?.totalRecords ?? 0;

    final selectedIds = ref.watch(radarrWantedSelectionProvider(instance));
    final hasSelection = selectedIds.isNotEmpty;

    return listAsync.when(
      loading: () => const Center(child: ExpressiveProgressIndicator()),
      error: (e, s) => ErrorView(
        title: 'Failed to load movies',
        message: e.toString(),
        onRetry: () {
          if (isCutoffTab) {
            ref.invalidate(radarrWantedCutoffProvider(instance));
          } else {
            ref.invalidate(radarrWantedMissingProvider(instance));
          }
        },
      ),
      data: (List<RadarrMovie> movies) {
        if (movies.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.movie_outlined,
                  size: 48,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                const Text(
                  'No movies matching filter found',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          );
        }

        final Widget content = EasyRefresh(
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
            if (isCutoffTab) {
              ref.invalidate(radarrWantedCutoffProvider(instance));
              await ref.read(radarrWantedCutoffProvider(instance).future);
            } else {
              ref.invalidate(radarrWantedMissingProvider(instance));
              await ref.read(radarrWantedMissingProvider(instance).future);
            }
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(Insets.md),
            itemCount: movies.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: onBulkSearch,
                          icon: const Icon(Icons.search, size: 18),
                          label: Text(
                            isCutoffTab
                                ? 'Search Cutoff'
                                : 'Search All',
                          ),
                        ),
                      ),
                      const SizedBox(width: Insets.md),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            showManualImportFlow(context, ref, instance);
                          },
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text('Manual Import'),
                        ),
                      ),
                    ],
                  ),
                );
              }
              final movie = movies[index - 1];
              final isSelected = selectedIds.contains(movie.id);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _WantedMovieCard(
                  instance: instance,
                  movie: movie,
                  isSelected: isSelected,
                  hasSelection: hasSelection,
                  isCutoffTab: isCutoffTab,
                ),
              );
            },
          ),
        );

        if (totalRecords <= fetchedCount) return content;

        // Only one page is fetched; be honest about the rest.
        final ThemeData theme = Theme.of(context);
        return Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.md,
                Insets.sm,
                Insets.md,
                0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Showing $fetchedCount of $totalRecords',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            Expanded(child: content),
          ],
        );
      },
    );
  }
}

class _WantedMovieCard extends ConsumerWidget {
  const _WantedMovieCard({
    required this.instance,
    required this.movie,
    required this.isSelected,
    required this.hasSelection,
    required this.isCutoffTab,
  });

  final Instance instance;
  final RadarrMovie movie;
  final bool isSelected;
  final bool hasSelection;
  final bool isCutoffTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final api = ref.watch(radarrApiProvider(instance)).value;

    String? posterUrl;
    if (movie.images.isNotEmpty && api != null) {
      final img = movie.images.firstWhereOrNull((i) => i.coverType == 'poster');
      if (img != null) {
        posterUrl = api.posterUrl(img);
      }
    }

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: isSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
          : theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (hasSelection) {
            final notifier =
                ref.read(radarrWantedSelectionProvider(instance).notifier);
            if (isSelected) {
              notifier.state =
                  selectedIds(ref).where((id) => id != movie.id).toSet();
            } else {
              notifier.state = {...selectedIds(ref), movie.id};
            }
          } else {
            pushScreen<void>(
              context,
              MovieDetailScreen(
                instance: instance,
                movieId: movie.id,
                movie: movie,
              ),
            );
          }
        },
        onLongPress: () {
          final notifier =
              ref.read(radarrWantedSelectionProvider(instance).notifier);
          if (isSelected) {
            notifier.state =
                selectedIds(ref).where((id) => id != movie.id).toSet();
          } else {
            notifier.state = {...selectedIds(ref), movie.id};
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 50,
                  height: 75,
                  child: posterUrl != null
                      ? AtriumNetworkImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.movie_outlined),
                          ),
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.movie_outlined),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      movie.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${movie.year ?? "Unknown Year"} • ${movie.studio ?? "Unknown Studio"}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isCutoffTab) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Below quality cutoff',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!hasSelection) ...[
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _triggerSearch(context, ref),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Set<int> selectedIds(WidgetRef ref) =>
      ref.read(radarrWantedSelectionProvider(instance));

  Future<void> _triggerSearch(BuildContext context, WidgetRef ref) async {
    try {
      final api = await ref.read(radarrApiProvider(instance).future);
      await api.runCommand(<String, dynamic>{
        'name': 'MoviesSearch',
        'movieIds': <int>[movie.id],
      });
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Search started for movie.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      }
    }
  }
}

class _GroupedWantedCard extends ConsumerStatefulWidget {
  const _GroupedWantedCard({
    required this.instance,
    required this.studioName,
    required this.movies,
    required this.selectedIds,
    required this.hasSelection,
    required this.isCutoffTab,
  });

  final Instance instance;
  final String studioName;
  final List<RadarrMovie> movies;
  final Set<int> selectedIds;
  final bool hasSelection;
  final bool isCutoffTab;

  @override
  ConsumerState<_GroupedWantedCard> createState() => _GroupedWantedCardState();
}

class _GroupedWantedCardState extends ConsumerState<_GroupedWantedCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(_expanded ? 0 : 20),
              bottomRight: Radius.circular(_expanded ? 0 : 20),
            ),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.business_outlined,
                      size: 18,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.studioName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.movies.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.movies.length,
                itemBuilder: (context, index) {
                  final movie = widget.movies[index];
                  final isSelected = widget.selectedIds.contains(movie.id);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: _WantedMovieCard(
                      instance: widget.instance,
                      movie: movie,
                      isSelected: isSelected,
                      hasSelection: widget.hasSelection,
                      isCutoffTab: widget.isCutoffTab,
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
