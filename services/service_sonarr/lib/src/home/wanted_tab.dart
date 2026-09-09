import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/sonarr_episode.dart';
import '../models/sonarr_history_item.dart';
import '../models/sonarr_series.dart';
import '../sonarr_providers.dart';
import '../sonarr_release_search_screen.dart';
import 'manual_import_dialog.dart';

class WantedTab extends ConsumerStatefulWidget {
  const WantedTab({
    required this.instance,
    super.key,
  });

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
        ref.read(sonarrSearchActiveProvider(widget.instance).notifier);
    _resetSearchActive = () => notifier.state = false;
    final String initialQuery =
        ref.read(sonarrWantedSearchQueryProvider(widget.instance));
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
    ref.read(sonarrSearchActiveProvider(widget.instance).notifier).state =
        isActive;
  }

  void _onFocusChange() {
    _updateSearchActiveState();
    setState(() {});
  }

  void _clearSelection() {
    ref.read(sonarrWantedSelectionProvider(widget.instance).notifier).state =
        <int>{};
  }

  /// Re-publishes the selection set after callers mutate it in place, so
  /// watchers (this tab and SonarrHome's back handling) rebuild.
  void _notifySelectionChanged() {
    final notifier =
        ref.read(sonarrWantedSelectionProvider(widget.instance).notifier);
    notifier.state = Set<int>.of(notifier.state);
  }

  Future<void> _searchSelected() async {
    final Set<int> selected =
        ref.read(sonarrWantedSelectionProvider(widget.instance));
    if (selected.isEmpty) return;
    final List<int> ids = selected.toList();
    _clearSelection();

    try {
      final api = await ref.read(sonarrApiProvider(widget.instance).future);
      await api.performEpisodeSearch(ids);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Search started for ${ids.length} selected episodes.'),
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
        ref.read(sonarrWantedSelectionProvider(widget.instance));
    if (selected.isEmpty) return;
    final List<int> ids = selected.toList();
    _clearSelection();

    try {
      final api = await ref.read(sonarrApiProvider(widget.instance).future);
      await api.updateEpisodeMonitor(episodeIds: ids, monitored: false);
      if (!mounted) return;

      // Refresh providers
      ref.invalidate(sonarrWantedMissingProvider(widget.instance));
      ref.invalidate(sonarrWantedCutoffProvider(widget.instance));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unmonitored ${ids.length} selected episodes.')),
      );
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
      final api = await ref.read(sonarrApiProvider(widget.instance).future);
      if (isCutoffTab) {
        await api.performCutoffUnmetEpisodeSearch();
      } else {
        await api.performMissingEpisodeSearch();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isCutoffTab
                  ? 'Cutoff unmet episode search started.'
                  : 'Missing episode search started.',
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

  String _formatAirDate(String? utcString) {
    if (utcString == null || utcString.isEmpty) return 'Unknown';
    try {
      final DateTime dt = DateTime.parse(utcString).toLocal();
      return DateFormat.yMMMd().format(dt);
    } catch (_) {
      return utcString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Set<int> selectedEpisodeIds =
        ref.watch(sonarrWantedSelectionProvider(widget.instance));
    final bool hasSelection = selectedEpisodeIds.isNotEmpty;
    final bool isGrouped =
        ref.watch(sonarrWantedGroupedProvider(widget.instance));

    // Keep the local controller in sync when the search query is cleared
    // externally (SonarrHome unwinds search state on system back).
    ref.listen<String>(sonarrWantedSearchQueryProvider(widget.instance),
        (String? previous, String next) {
      if (next.isEmpty && _searchController.text.isNotEmpty) {
        setState(() {
          _searchController.clear();
        });
        _searchFocusNode.unfocus();
        _updateSearchActiveState();
      }
    });

    ref.listen<int>(sonarrHomeScrollToTopProvider((widget.instance, 2)),
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
                          '${selectedEpisodeIds.length} Selected',
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
                                      sonarrWantedSearchQueryProvider(
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
                                sonarrWantedSearchQueryProvider(widget.instance)
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
                        IconButton(
                          icon: Icon(
                            isGrouped
                                ? Icons.format_list_bulleted
                                : Icons.group_work_outlined,
                          ),
                          tooltip: isGrouped
                              ? 'Switch to plain list'
                              : 'Switch to grouped view',
                          onPressed: () {
                            ref
                                .read(
                                  sonarrWantedGroupedProvider(widget.instance)
                                      .notifier,
                                )
                                .update((state) => !state);
                          },
                        ),
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
              _MissingListView(
                instance: widget.instance,
                selectedIds: selectedEpisodeIds,
                onSelectionChanged: _notifySelectionChanged,
                formatAirDate: _formatAirDate,
                onBulkSearch: () => _bulkSearchAll(false),
              ),
              _CutoffUnmetListView(
                instance: widget.instance,
                selectedIds: selectedEpisodeIds,
                onSelectionChanged: _notifySelectionChanged,
                formatAirDate: _formatAirDate,
                onBulkSearch: () => _bulkSearchAll(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingListView extends ConsumerWidget {
  const _MissingListView({
    required this.instance,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.formatAirDate,
    required this.onBulkSearch,
  });

  final Instance instance;
  final Set<int> selectedIds;
  final VoidCallback onSelectionChanged;
  final String Function(String?) formatAirDate;
  final VoidCallback onBulkSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(sonarrWantedFilteredMissingProvider(instance));
    return _EpisodeListLayout(
      instance: instance,
      listAsync: listAsync,
      onRefresh: () => ref.invalidate(sonarrWantedMissingProvider(instance)),
      selectedIds: selectedIds,
      onSelectionChanged: onSelectionChanged,
      isCutoffTab: false,
      formatAirDate: formatAirDate,
      onBulkSearch: onBulkSearch,
    );
  }
}

class _CutoffUnmetListView extends ConsumerWidget {
  const _CutoffUnmetListView({
    required this.instance,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.formatAirDate,
    required this.onBulkSearch,
  });

  final Instance instance;
  final Set<int> selectedIds;
  final VoidCallback onSelectionChanged;
  final String Function(String?) formatAirDate;
  final VoidCallback onBulkSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(sonarrWantedFilteredCutoffProvider(instance));
    return _EpisodeListLayout(
      instance: instance,
      listAsync: listAsync,
      onRefresh: () => ref.invalidate(sonarrWantedCutoffProvider(instance)),
      selectedIds: selectedIds,
      onSelectionChanged: onSelectionChanged,
      isCutoffTab: true,
      formatAirDate: formatAirDate,
      onBulkSearch: onBulkSearch,
    );
  }
}

class _EpisodeListLayout extends ConsumerWidget {
  const _EpisodeListLayout({
    required this.instance,
    required this.listAsync,
    required this.onRefresh,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.isCutoffTab,
    required this.formatAirDate,
    required this.onBulkSearch,
  });

  final Instance instance;
  final AsyncValue<List<SonarrEpisode>> listAsync;
  final VoidCallback onRefresh;
  final Set<int> selectedIds;
  final VoidCallback onSelectionChanged;
  final bool isCutoffTab;
  final String Function(String?) formatAirDate;
  final VoidCallback onBulkSearch;

  Future<void> _triggerSingleSearch(
    BuildContext context,
    WidgetRef ref,
    int episodeId,
  ) async {
    try {
      final api = await ref.read(sonarrApiProvider(instance).future);
      await api.performEpisodeSearch([episodeId]);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Search started for episode.')),
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

  void _showEpisodeDetails(
    BuildContext context,
    WidgetRef ref,
    SonarrEpisode episode,
  ) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext context) {
        return _EpisodeDetailsSheet(
          instance: instance,
          episode: episode,
          formatAirDate: formatAirDate,
          onSearchTriggered: (id) => _triggerSingleSearch(context, ref, id),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final bool isGrouped = ref.watch(sonarrWantedGroupedProvider(instance));

    return listAsync.when(
      loading: () => const Center(child: ExpressiveProgressIndicator()),
      error: (e, s) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Failed to load episodes',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                e.toString(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onRefresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (List<SonarrEpisode> list) {
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.tv_off_outlined,
                  size: 64,
                  color: theme.colorScheme.outline.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  isCutoffTab
                      ? 'No cutoff unmet episodes'
                      : 'No missing episodes',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        }

        // Grouping logic by seriesId
        final List<Widget> listItems = [];

        if (isGrouped) {
          final Map<int, List<SonarrEpisode>> groupedMap = {};
          final List<SonarrSeries> seriesList = [];

          for (final ep in list) {
            final series = ep.series;
            if (series == null) continue;
            if (!groupedMap.containsKey(series.id)) {
              groupedMap[series.id] = [];
              seriesList.add(series);
            }
            groupedMap[series.id]!.add(ep);
          }

          for (final series in seriesList) {
            final groupEpisodes = groupedMap[series.id]!;
            listItems.add(
              _GroupedEpisodeCard(
                instance: instance,
                series: series,
                episodes: groupEpisodes,
                selectedIds: selectedIds,
                onSelectionChanged: onSelectionChanged,
                isCutoffTab: isCutoffTab,
                formatAirDate: formatAirDate,
                onSearchTriggered: (id) =>
                    _triggerSingleSearch(context, ref, id),
                onShowDetails: (ep) => _showEpisodeDetails(context, ref, ep),
              ),
            );
          }
        } else {
          // Plain list representation
          for (final episode in list) {
            final bool isSelected = selectedIds.contains(episode.id);
            final String airDateStr = formatAirDate(episode.airDateUtc);

            final api = ref.watch(sonarrApiProvider(instance)).value;
            final SonarrImage? posterImage = episode.series?.images.firstWhere(
              (img) => img.coverType == 'poster',
              orElse: () => const SonarrImage(coverType: 'poster'),
            );
            final String? posterUrl = api != null && posterImage != null
                ? api.posterUrl(posterImage, width: 120)
                : null;

            final String sSeason =
                episode.seasonNumber.toString().padLeft(2, '0');
            final String sEpisode =
                episode.episodeNumber.toString().padLeft(2, '0');
            final String episodeCode = 'S${sSeason}E$sEpisode';

            String? qualityLabel;
            if (isCutoffTab && episode.episodeFile != null) {
              final file = episode.episodeFile!;
              final qObj = file['quality'] as Map<String, dynamic>?;
              if (qObj != null && qObj['quality'] != null) {
                final quality = qObj['quality'] as Map<String, dynamic>?;
                qualityLabel = quality?['name'] as String?;
              }
            }

            listItems.add(
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant
                            .withValues(alpha: 0.5),
                    width: isSelected ? 2.0 : 1.0,
                  ),
                ),
                color: isSelected
                    ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
                    : theme.colorScheme.surfaceContainerLow,
                margin: const EdgeInsets.only(bottom: 8),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    final bool hasSelection = selectedIds.isNotEmpty;
                    if (hasSelection) {
                      final notifier = ref.read(sonarrWantedSelectionProvider(instance).notifier);
                      if (isSelected) {
                        notifier.state = selectedIds.where((id) => id != episode.id).toSet();
                      } else {
                        notifier.state = {...selectedIds, episode.id};
                      }
                      onSelectionChanged();
                    } else {
                      _showEpisodeDetails(context, ref, episode);
                    }
                  },
                  onLongPress: () {
                    final notifier = ref.read(sonarrWantedSelectionProvider(instance).notifier);
                    if (isSelected) {
                      notifier.state = selectedIds.where((id) => id != episode.id).toSet();
                    } else {
                      notifier.state = {...selectedIds, episode.id};
                    }
                    onSelectionChanged();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (posterUrl != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: AtriumNetworkImage(
                              imageUrl: posterUrl,
                              width: 48,
                              height: 72,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color: theme.colorScheme.surfaceContainerHigh,
                                width: 48,
                                height: 72,
                                child: const Icon(Icons.movie, size: 20),
                              ),
                              errorWidget: (context, url, error) => Container(
                                color: theme.colorScheme.surfaceContainerHigh,
                                width: 48,
                                height: 72,
                                child: const Icon(Icons.movie, size: 20),
                              ),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHigh,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            width: 48,
                            height: 72,
                            child: const Icon(Icons.movie, size: 20),
                          ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                episode.series?.title ?? 'Unknown Series',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: <Widget>[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          theme.colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      episodeCode,
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: theme
                                            .colorScheme.onSecondaryContainer,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      episode.title,
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 12,
                                    color: theme.colorScheme.outline,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    airDateStr,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                  if (qualityLabel != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color:
                                            theme.colorScheme.tertiaryContainer,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        qualityLabel,
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onTertiaryContainer,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            IconButton(
                              icon: const Icon(Icons.search, size: 20),
                              tooltip: 'Automatic Search',
                              onPressed: () => _triggerSingleSearch(
                                context,
                                ref,
                                episode.id,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.person_search_outlined,
                                size: 20,
                              ),
                              tooltip: 'Interactive Search',
                              onPressed: () {
                                pushScreen<void>(
                                  context,
                                  SonarrReleaseSearchScreen(
                                    instance: instance,
                                    episode: episode,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
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
            onRefresh();
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: listItems.length + 1,
            itemBuilder: (BuildContext context, int index) {
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
                      const SizedBox(width: 8),
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
              return listItems[index - 1];
            },
          ),
        );
      },
    );
  }
}

class _GroupedEpisodeCard extends ConsumerStatefulWidget {
  const _GroupedEpisodeCard({
    required this.instance,
    required this.series,
    required this.episodes,
    required this.selectedIds,
    required this.onSelectionChanged,
    required this.isCutoffTab,
    required this.formatAirDate,
    required this.onSearchTriggered,
    required this.onShowDetails,
  });

  final Instance instance;
  final SonarrSeries series;
  final List<SonarrEpisode> episodes;
  final Set<int> selectedIds;
  final VoidCallback onSelectionChanged;
  final bool isCutoffTab;
  final String Function(String?) formatAirDate;
  final ValueChanged<int> onSearchTriggered;
  final ValueChanged<SonarrEpisode> onShowDetails;

  @override
  ConsumerState<_GroupedEpisodeCard> createState() =>
      _GroupedEpisodeCardState();
}

class _GroupedEpisodeCardState extends ConsumerState<_GroupedEpisodeCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = ref.watch(sonarrApiProvider(widget.instance)).value;

    String? posterUrl;
    final SonarrImage posterImage = widget.series.images.firstWhere(
      (img) => img.coverType == 'poster',
      orElse: () => const SonarrImage(coverType: 'poster'),
    );
    if (api != null) {
      posterUrl = api.posterUrl(posterImage, width: 120);
    }

    // Determine selection checkbox state for the group
    final Set<int> groupEpIds = widget.episodes.map((e) => e.id).toSet();
    final bool allSelected = widget.selectedIds.containsAll(groupEpIds);
    final bool someSelected =
        !allSelected && widget.selectedIds.any(groupEpIds.contains);

    final int selectedCount = widget.episodes.where((e) => widget.selectedIds.contains(e.id)).length;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: allSelected
              ? theme.colorScheme.primary
              : someSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.5)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: allSelected || someSelected ? 2.0 : 1.0,
        ),
      ),
      color: allSelected
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.15)
          : someSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.05)
              : theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: () {
              final bool hasSelection = widget.selectedIds.isNotEmpty;
              if (hasSelection) {
                final notifier = ref.read(sonarrWantedSelectionProvider(widget.instance).notifier);
                if (allSelected) {
                  notifier.state = widget.selectedIds.difference(groupEpIds);
                } else {
                  notifier.state = {...widget.selectedIds, ...groupEpIds};
                }
                widget.onSelectionChanged();
              } else {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              }
            },
            onLongPress: () {
              final notifier = ref.read(sonarrWantedSelectionProvider(widget.instance).notifier);
              if (allSelected) {
                notifier.state = widget.selectedIds.difference(groupEpIds);
              } else {
                notifier.state = {...widget.selectedIds, ...groupEpIds};
              }
              widget.onSelectionChanged();
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[

                  // Poster Thumbnail
                  if (posterUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: AtriumNetworkImage(
                        imageUrl: posterUrl,
                        width: 36,
                        height: 54,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: theme.colorScheme.surfaceContainerHigh,
                          width: 36,
                          height: 54,
                          child: const Icon(Icons.movie, size: 14),
                        ),
                        errorWidget: (context, url, err) => Container(
                          color: theme.colorScheme.surfaceContainerHigh,
                          width: 36,
                          height: 54,
                          child: const Icon(Icons.movie, size: 14),
                        ),
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      width: 36,
                      height: 54,
                      child: const Icon(Icons.movie, size: 14),
                    ),
                  const SizedBox(width: 12),

                  // Series Title and Badges
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.series.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.series.network ?? ''} • ${widget.series.year ?? ''}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Selection / Wanted Count Badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: selectedCount > 0
                          ? theme.colorScheme.primary
                          : theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      selectedCount > 0
                          ? '$selectedCount/${widget.episodes.length} selected'
                          : '${widget.episodes.length} wanted',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: selectedCount > 0
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onPrimaryContainer,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      _isExpanded ? Icons.expand_less : Icons.expand_more,
                    ),
                    color: theme.colorScheme.outline,
                    onPressed: () {
                      setState(() {
                        _isExpanded = !_isExpanded;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.episodes.length,
                itemBuilder: (BuildContext context, int index) {
                  final episode = widget.episodes[index];
                  final bool isEpSelected =
                      widget.selectedIds.contains(episode.id);
                  final String airDateStr =
                      widget.formatAirDate(episode.airDateUtc);

                  final String sSeason =
                      episode.seasonNumber.toString().padLeft(2, '0');
                  final String sEpisode =
                      episode.episodeNumber.toString().padLeft(2, '0');
                  final String episodeCode = 'S${sSeason}E$sEpisode';

                  String? qualityLabel;
                  if (widget.isCutoffTab && episode.episodeFile != null) {
                    final file = episode.episodeFile!;
                    final qObj = file['quality'] as Map<String, dynamic>?;
                    if (qObj != null && qObj['quality'] != null) {
                      final quality = qObj['quality'] as Map<String, dynamic>?;
                      qualityLabel = quality?['name'] as String?;
                    }
                  }

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    color: isEpSelected
                        ? theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.15)
                        : theme.colorScheme.surface.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isEpSelected
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        width: isEpSelected ? 2.0 : 1.0,
                      ),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        final bool hasSelection = widget.selectedIds.isNotEmpty;
                        if (hasSelection) {
                          final notifier = ref.read(sonarrWantedSelectionProvider(widget.instance).notifier);
                          if (isEpSelected) {
                            notifier.state = widget.selectedIds.where((id) => id != episode.id).toSet();
                          } else {
                            notifier.state = {...widget.selectedIds, episode.id};
                          }
                          widget.onSelectionChanged();
                        } else {
                          widget.onShowDetails(episode);
                        }
                      },
                      onLongPress: () {
                        final notifier = ref.read(sonarrWantedSelectionProvider(widget.instance).notifier);
                        if (isEpSelected) {
                          notifier.state = widget.selectedIds.where((id) => id != episode.id).toSet();
                        } else {
                          notifier.state = {...widget.selectedIds, episode.id};
                        }
                        widget.onSelectionChanged();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        child: Row(
                          children: <Widget>[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.secondaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                episodeCode,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSecondaryContainer,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(
                                    episode.title,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        airDateStr,
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.outline,
                                          fontSize: 11,
                                        ),
                                      ),
                                      if (qualityLabel != null) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 1,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme
                                                .colorScheme.tertiaryContainer,
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            qualityLabel,
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: theme.colorScheme
                                                  .onTertiaryContainer,
                                              fontSize: 8,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.search, size: 18),
                              tooltip: 'Automatic Search',
                              onPressed: () =>
                                  widget.onSearchTriggered(episode.id),
                            ),
                          ],
                        ),
                      ),
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

class _EpisodeDetailsSheet extends ConsumerStatefulWidget {
  const _EpisodeDetailsSheet({
    required this.instance,
    required this.episode,
    required this.formatAirDate,
    required this.onSearchTriggered,
  });

  final Instance instance;
  final SonarrEpisode episode;
  final String Function(String?) formatAirDate;
  final ValueChanged<int> onSearchTriggered;

  @override
  ConsumerState<_EpisodeDetailsSheet> createState() =>
      _EpisodeDetailsSheetState();
}

class _EpisodeDetailsSheetState extends ConsumerState<_EpisodeDetailsSheet> {
  List<SonarrHistoryItem> _history = <SonarrHistoryItem>[];
  bool _historyLoading = true;
  String? _historyError;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final api = await ref.read(sonarrApiProvider(widget.instance).future);
      final logs =
          await api.getHistory(pageSize: 50, episodeId: widget.episode.id);
      if (mounted) {
        setState(() {
          _history = logs;
          _historyLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _historyError = e.toString();
          _historyLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final String sSeason =
        widget.episode.seasonNumber.toString().padLeft(2, '0');
    final String sEpisode =
        widget.episode.episodeNumber.toString().padLeft(2, '0');
    final String episodeCode = 'S${sSeason}E$sEpisode';

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.7,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(
                    widget.episode.monitored
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    color: widget.episode.monitored ? cs.primary : cs.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.episode.series?.title ?? 'Episode'} - $episodeCode',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.episode.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TabBar(
              dividerColor:
                  theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: const <Widget>[
                Tab(text: 'Details'),
                Tab(text: 'History'),
                Tab(text: 'Search'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        if (widget.episode.airDateUtc != null) ...[
                          Text(
                            'Airs',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.outline,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.formatAirDate(widget.episode.airDateUtc)}${widget.episode.series?.network != null ? ' on ${widget.episode.series!.network}' : ''}',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          'Monitored',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.outline,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            widget.episode.series?.monitored == true
                                ? 'Yes'
                                : 'No',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'Overview',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.outline,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          widget.episode.overview != null &&
                                  widget.episode.overview!.isNotEmpty
                              ? widget.episode.overview!
                              : 'No overview details are available for this episode.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 32),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            icon: const Icon(Icons.launch, size: 18),
                            label: const Text('Close'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _historyLoading
                      ? const Center(child: ExpressiveProgressIndicator())
                      : _historyError != null
                          ? Center(
                              child: Text(
                                'Failed to load history:\n$_historyError',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: cs.error),
                              ),
                            )
                          : _history.isEmpty
                              ? const Center(
                                  child: Text(
                                    'No history items for this episode.',
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.all(16),
                                  itemCount: _history.length,
                                  itemBuilder:
                                      (BuildContext context, int index) {
                                    final log = _history[index];
                                    final DateTime? dt = log.date != null
                                        ? DateTime.tryParse(log.date!)
                                            ?.toLocal()
                                        : null;
                                    final date = dt != null
                                        ? DateFormat.yMMMd().add_jm().format(dt)
                                        : 'Unknown Date';
                                    final eventType =
                                        log.eventType?.toUpperCase() ??
                                            'UNKNOWN';
                                    return ListTile(
                                      leading: Icon(
                                        log.eventType == 'grabbed'
                                            ? Icons.cloud_download_outlined
                                            : Icons.save_alt_outlined,
                                        color: log.eventType == 'grabbed'
                                            ? cs.primary
                                            : cs.secondary,
                                      ),
                                      title: Text(eventType),
                                      subtitle: Text(
                                        '${log.sourceTitle}\n$date',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    );
                                  },
                                ),
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onSearchTriggered(widget.episode.id);
                          },
                          icon: const Icon(Icons.rocket_launch),
                          label: const Text(
                            'Quick Search',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            pushScreen<void>(
                              context,
                              SonarrReleaseSearchScreen(
                                instance: widget.instance,
                                episode: widget.episode,
                              ),
                            );
                          },
                          icon: const Icon(Icons.person_search_outlined),
                          label: const Text(
                            'Interactive Search',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
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
}
