import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';

import '../models/sonarr_blocklist_item.dart';
import '../models/sonarr_history_item.dart';
import '../models/sonarr_queue_item.dart';
import '../models/sonarr_series.dart';
import '../sonarr_providers.dart';

class ActivityTab extends ConsumerStatefulWidget {
  const ActivityTab({
    required this.instance,
    super.key,
  });

  final Instance instance;

  @override
  ConsumerState<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends ConsumerState<ActivityTab>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final void Function() _resetSearchActive;
  double _lastBottomInset = 0;
  late final TabController _tabController;
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
        ref.read(sonarrActivitySearchQueryProvider(widget.instance));
    _searchController = TextEditingController(text: initialQuery);
    _searchFocusNode = FocusNode()..addListener(_onFocusChange);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        ref.read(sonarrQueueSelectionProvider(widget.instance).notifier).state =
            {};
        ref
            .read(sonarrBlocklistSelectionProvider(widget.instance).notifier)
            .state = {};
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _resetSearchActive();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchFocusNode.dispose();
    _tabController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final grouped = ref.watch(sonarrActivityGroupedProvider(widget.instance));
    final queueSelection =
        ref.watch(sonarrQueueSelectionProvider(widget.instance));
    final blocklistSelection =
        ref.watch(sonarrBlocklistSelectionProvider(widget.instance));
    final activeSelection = _tabController.index == 0
        ? queueSelection
        : _tabController.index == 2
            ? blocklistSelection
            : <int>{};
    final isSelecting = activeSelection.isNotEmpty;

    // Keep the local controller in sync when the search query is cleared
    // externally (SonarrHome unwinds search state on system back).
    ref.listen<String>(sonarrActivitySearchQueryProvider(widget.instance),
        (String? previous, String next) {
      if (next.isEmpty && _searchController.text.isNotEmpty) {
        setState(() {
          _searchController.clear();
        });
        _searchFocusNode.unfocus();
        _updateSearchActiveState();
      }
    });

    ref.listen<int>(sonarrHomeScrollToTopProvider((widget.instance, 1)),
        (previous, next) {
      if (next > 0 && _scrollController.hasClients) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      bottomNavigationBar: isSelecting
          ? _ActivityBulkActionsBar(
              instance: widget.instance,
              selectedIds: activeSelection,
              isQueue: _tabController.index == 0,
              onClear: () {
                ref
                    .read(
                      sonarrQueueSelectionProvider(widget.instance).notifier,
                    )
                    .state = {};
                ref
                    .read(
                      sonarrBlocklistSelectionProvider(widget.instance)
                          .notifier,
                    )
                    .state = {};
              },
            )
          : null,
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
              titleSpacing: isSelecting ? 16 : 0,
              leadingWidth: 56,
              leading: isSelecting
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        ref
                            .read(
                              sonarrQueueSelectionProvider(widget.instance)
                                  .notifier,
                            )
                            .state = {};
                        ref
                            .read(
                              sonarrBlocklistSelectionProvider(
                                widget.instance,
                              ).notifier,
                            )
                            .state = {};
                      },
                    )
                  : IconButton(
                      icon: const Icon(Icons.menu),
                      onPressed: () {
                        // Call on outer context of the build method to resolve the parent Scaffold drawer.
                        Scaffold.of(context).openDrawer();
                      },
                    ),
              title: isSelecting
                  ? Text(
                      '${activeSelection.length} selected',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : SearchBar(
                      focusNode: _searchFocusNode,
                      controller: _searchController,
                      hintText: 'Search activity...',
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
                                    sonarrActivitySearchQueryProvider(
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
                              sonarrActivitySearchQueryProvider(widget.instance)
                                  .notifier,
                            )
                            .state = value;
                        _updateSearchActiveState();
                      },
                    ),
              actions: <Widget>[
                if (!isSelecting) ...[
                  IconButton(
                    icon: Icon(
                      grouped
                          ? Icons.format_list_bulleted
                          : Icons.group_work_outlined,
                    ),
                    tooltip: grouped
                        ? 'Switch to plain list'
                        : 'Switch to grouped view',
                    onPressed: () {
                      ref
                          .read(
                            sonarrActivityGroupedProvider(widget.instance)
                                .notifier,
                          )
                          .state = !grouped;
                    },
                  ),
                ],
                const SizedBox(width: 8),
              ],
              bottom: TabBar(
                controller: _tabController,
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
                  Tab(text: 'Queue'),
                  Tab(text: 'History'),
                  Tab(text: 'Blocklist'),
                ],
              ),
            ),
          ];
        },
        body: TabBarView(
          controller: _tabController,
          children: <Widget>[
            _QueueView(instance: widget.instance),
            _HistoryView(instance: widget.instance),
            _BlocklistView(instance: widget.instance),
          ],
        ),
      ),
    );
  }
}

class _QueueView extends ConsumerWidget {
  const _QueueView({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final queueAsync = ref.watch(sonarrQueueProvider(instance));
    final searchQuery =
        ref.watch(sonarrActivitySearchQueryProvider(instance)).toLowerCase();

    return queueAsync.when(
      data: (List<SonarrQueueItem> items) {
        final filteredItems = items.where((item) {
          if (searchQuery.isEmpty) return true;
          final titleMatch =
              item.title?.toLowerCase().contains(searchQuery) ?? false;
          final seriesMatch =
              item.series?.title.toLowerCase().contains(searchQuery) ?? false;
          return titleMatch || seriesMatch;
        }).toList();

        // Group items by downloadId
        final Map<String, List<SonarrQueueItem>> groups = {};
        final List<List<SonarrQueueItem>> groupedList = [];

        for (final item in filteredItems) {
          final String? dlId = item.downloadId;
          if (dlId == null || dlId.isEmpty) {
            groupedList.add([item]);
          } else {
            if (!groups.containsKey(dlId)) {
              groups[dlId] = [];
              groupedList.add(groups[dlId]!);
            }
            groups[dlId]!.add(item);
          }
        }

        if (groupedList.isEmpty) {
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
              try {
                final api = await ref.read(sonarrApiProvider(instance).future);
                await api.runCommand(<String, dynamic>{
                  'name': 'RefreshMonitoredDownloads',
                });
                await Future<void>.delayed(const Duration(seconds: 1));
              } catch (_) {}
              ref.invalidate(sonarrQueueProvider(instance));
              await ref.read(sonarrQueueProvider(instance).future);
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        Icons.queue,
                        size: 48,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        searchQuery.isEmpty
                            ? 'Queue is empty'
                            : 'No items match search',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
            try {
              final api = await ref.read(sonarrApiProvider(instance).future);
              await api.runCommand(<String, dynamic>{
                'name': 'RefreshMonitoredDownloads',
              });
              await Future<void>.delayed(const Duration(seconds: 1));
            } catch (_) {}
            ref.invalidate(sonarrQueueProvider(instance));
            await ref.read(sonarrQueueProvider(instance).future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groupedList.length,
            itemBuilder: (BuildContext context, int index) {
              final group = groupedList[index];
              return _QueueItemCard(instance: instance, group: group);
            },
          ),
        );
      },
      loading: () => const Center(child: ExpressiveProgressIndicator()),
      error: (Object error, StackTrace? stackTrace) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load queue: $error',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.invalidate(sonarrQueueProvider(instance)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QueueItemCard extends ConsumerWidget {
  const _QueueItemCard({
    required this.instance,
    required this.group,
  });

  final Instance instance;
  final List<SonarrQueueItem> group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final api = ref.watch(sonarrApiProvider(instance)).value;
    final item = group.first;
    final selection = ref.watch(sonarrQueueSelectionProvider(instance));
    final isSelecting = selection.isNotEmpty;
    final groupIds = group.map((i) => i.id).toList();
    final isSelected = groupIds.every(selection.contains);

    void toggleSelection() {
      final notifier =
          ref.read(sonarrQueueSelectionProvider(instance).notifier);
      if (isSelected) {
        notifier.state =
            selection.where((id) => !groupIds.contains(id)).toSet();
      } else {
        notifier.state = {...selection, ...groupIds};
      }
    }

    // Calculate aggregated size and progress
    double totalSize = 0.0;
    double totalSizeLeft = 0.0;
    for (final i in group) {
      totalSize += i.size ?? 0.0;
      totalSizeLeft += i.sizeleft ?? 0.0;
    }

    final bool allSizesIdentical =
        group.every((i) => i.size == item.size && i.sizeleft == item.sizeleft);
    final double displaySize =
        allSizesIdentical ? (item.size ?? 0.0) : totalSize;
    final double displaySizeLeft =
        allSizesIdentical ? (item.sizeleft ?? 0.0) : totalSizeLeft;
    final double progress =
        displaySize > 0 ? (displaySize - displaySizeLeft) / displaySize : 0.0;

    // Construct episodes display list (e.g. S01E01, S01E02)
    final List<String> episodeTexts = [];
    for (final i in group) {
      if (i.episode != null) {
        final String seasonStr = i.seasonNumber != null
            ? 'S${i.seasonNumber.toString().padLeft(2, '0')}'
            : '';
        final String epStr =
            'E${i.episode!.episodeNumber.toString().padLeft(2, '0')}';
        episodeTexts.add('$seasonStr$epStr');
      }
    }
    final String episodesDisplay =
        episodeTexts.isNotEmpty ? 'Episodes: ${episodeTexts.join(', ')}' : '';

    String? posterUrl;
    if (item.series?.images != null && api != null) {
      try {
        final img = item.series!.images.firstWhere(
          (i) => i.coverType == 'poster',
        );
        posterUrl = api.posterUrl(img);
      } catch (_) {}
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: theme.colorScheme.surfaceContainerLow,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (isSelecting) {
            toggleSelection();
          } else {
            _showQueueDetails(context, ref, group);
          }
        },
        onLongPress: toggleSelection,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 50,
                  height: 75,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      posterUrl != null
                          ? AtriumNetworkImage(
                              imageUrl: posterUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                              errorWidget: (context, url, err) => Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.live_tv,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.live_tv,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                      if (isSelected)
                        Container(
                          color:
                              theme.colorScheme.primary.withValues(alpha: 0.25),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.series?.title ?? item.title ?? 'Unknown Release',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.title ?? 'No release name',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (episodesDisplay.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        episodesDisplay,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        _buildStatusBadge(context, item.status),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicatorM3E(
                              shape: ProgressM3EShape.flat,
                              value: progress,
                              trackColor:
                                  theme.colorScheme.surfaceContainerHighest,
                              activeColor: item.status == 'warning'
                                  ? theme.colorScheme.error
                                  : theme.colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(progress * 100).toStringAsFixed(0)}%',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          '${_formatSize(displaySize - displaySizeLeft)} of ${_formatSize(displaySize)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (item.timeleft != null &&
                            item.timeleft != '00:00:00')
                          Text(
                            'ETA: ${item.timeleft}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Icons.cancel_outlined,
                  color: theme.colorScheme.error,
                ),
                onPressed: () => _confirmDeleteQueueItem(context, ref, group),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, String? status) {
    final theme = Theme.of(context);
    Color bg;
    Color fg;
    final String label = status?.toLowerCase() ?? 'unknown';

    switch (label) {
      case 'downloading':
        bg = theme.colorScheme.primaryContainer;
        fg = theme.colorScheme.onPrimaryContainer;
        break;
      case 'completed':
        bg = theme.colorScheme.primaryContainer;
        fg = theme.colorScheme.onPrimaryContainer;
        break;
      case 'warning':
        bg = theme.colorScheme.errorContainer;
        fg = theme.colorScheme.onErrorContainer;
        break;
      case 'paused':
        bg = theme.colorScheme.surfaceContainerHighest;
        fg = theme.colorScheme.onSurfaceVariant;
        break;
      case 'queued':
        bg = theme.colorScheme.secondaryContainer;
        fg = theme.colorScheme.onSecondaryContainer;
        break;
      default:
        bg = theme.colorScheme.surfaceContainerHighest;
        fg = theme.colorScheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }

  void _showQueueDetails(
    BuildContext context,
    WidgetRef ref,
    List<SonarrQueueItem> group,
  ) {
    final theme = Theme.of(context);
    final item = group.first;

    // Construct episodes list
    final List<String> episodeTexts = [];
    for (final i in group) {
      if (i.episode != null) {
        final String seasonStr =
            i.seasonNumber != null ? 'S${i.seasonNumber}' : '';
        final String epStr = 'E${i.episode!.episodeNumber}';
        episodeTexts.add('$seasonStr$epStr');
      }
    }
    final String episodesDisplay =
        episodeTexts.isNotEmpty ? episodeTexts.join(', ') : 'None';

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text(
            'Queue Item Details',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _DetailRow(label: 'Title', value: item.title ?? 'No title'),
                _DetailRow(
                  label: 'Series',
                  value: item.series?.title ?? 'Unknown Series',
                ),
                _DetailRow(label: 'Episodes', value: episodesDisplay),
                _DetailRow(label: 'Status', value: item.status ?? 'Unknown'),
                _DetailRow(
                  label: 'Tracked State',
                  value: item.trackedDownloadState ?? 'None',
                ),
                _DetailRow(
                  label: 'Download Client',
                  value: item.downloadClient ?? 'Unknown',
                ),
                _DetailRow(
                  label: 'Download ID',
                  value: item.downloadId ?? 'Unknown',
                ),
                _DetailRow(label: 'Indexer', value: item.indexer ?? 'Unknown'),
                _DetailRow(
                  label: 'Output Path',
                  value: item.outputPath ?? 'Unknown',
                ),
                if (item.errorMessage != null &&
                    item.errorMessage!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Error Message:',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.maxFinite,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: theme.colorScheme.errorContainer),
                    ),
                    child: Text(
                      item.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteQueueItem(
    BuildContext context,
    WidgetRef ref,
    List<SonarrQueueItem> group,
  ) {
    final theme = Theme.of(context);
    bool removeFromClient = true;
    bool blocklist = false;

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              title: Text(
                'Remove from Queue',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.error,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    group.length > 1
                        ? 'Are you sure you want to remove all ${group.length} episodes of this item from the active queue?'
                        : 'Are you sure you want to remove this item from the active queue?',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Remove from download client'),
                    value: removeFromClient,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (bool? val) {
                      setState(() {
                        removeFromClient = val ?? false;
                      });
                    },
                  ),
                  CheckboxListTile(
                    title: const Text('Blocklist this release'),
                    subtitle: const Text(
                      'Prevents Sonarr from grabbing this file again',
                    ),
                    value: blocklist,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (bool? val) {
                      setState(() {
                        blocklist = val ?? false;
                      });
                    },
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  onPressed: () async {
                    Navigator.of(context).pop();
                    try {
                      final api =
                          await ref.read(sonarrApiProvider(instance).future);
                      // Delete all items in the grouped torrent.
                      for (final i in group) {
                        await api.deleteQueueItem(
                          i.id,
                          removeFromClient: removeFromClient,
                          blocklist: blocklist,
                        );
                      }
                      ref.invalidate(sonarrQueueProvider(instance));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              group.length > 1
                                  ? 'All ${group.length} episodes removed from queue.'
                                  : 'Queue item deleted.',
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to delete item: $e')),
                        );
                      }
                    }
                  },
                  child: const Text('Remove'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _HistoryView extends ConsumerWidget {
  const _HistoryView({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final historyAsync = ref.watch(sonarrHistoryProvider(instance));
    final searchQuery =
        ref.watch(sonarrActivitySearchQueryProvider(instance)).toLowerCase();
    final grouped = ref.watch(sonarrActivityGroupedProvider(instance));

    return historyAsync.when(
      data: (List<SonarrHistoryItem> items) {
        final filteredItems = items.where((item) {
          if (searchQuery.isEmpty) return true;
          final titleMatch =
              item.sourceTitle?.toLowerCase().contains(searchQuery) ?? false;
          final seriesMatch =
              item.series?.title.toLowerCase().contains(searchQuery) ?? false;
          final episodeMatch =
              item.episode?.title.toLowerCase().contains(searchQuery) ?? false;
          return titleMatch || seriesMatch || episodeMatch;
        }).toList();

        if (filteredItems.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.history,
                  size: 48,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  searchQuery.isEmpty
                      ? 'No history records'
                      : 'No history matches search',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        if (grouped) {
          // Group by series
          final Map<int, List<SonarrHistoryItem>> groupedMap = {};
          final List<SonarrSeries> seriesList = [];
          final List<SonarrHistoryItem> unknownSeriesItems = [];

          for (final item in filteredItems) {
            if (item.series != null) {
              final seriesId = item.series!.id;
              if (!groupedMap.containsKey(seriesId)) {
                groupedMap[seriesId] = [];
                seriesList.add(item.series!);
              }
              groupedMap[seriesId]!.add(item);
            } else {
              unknownSeriesItems.add(item);
            }
          }

          // Sort series by date of latest event
          seriesList.sort((a, b) {
            final latestA = groupedMap[a.id]!.first.date ?? '';
            final latestB = groupedMap[b.id]!.first.date ?? '';
            return latestB.compareTo(latestA);
          });

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
              ref.invalidate(sonarrHistoryProvider(instance));
              await ref.read(sonarrHistoryProvider(instance).future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount:
                  seriesList.length + (unknownSeriesItems.isNotEmpty ? 1 : 0),
              itemBuilder: (BuildContext context, int index) {
                if (index < seriesList.length) {
                  final series = seriesList[index];
                  final seriesItems = groupedMap[series.id]!;
                  return _GroupedHistoryCard(
                    instance: instance,
                    series: series,
                    items: seriesItems,
                  );
                } else {
                  return _GroupedHistoryCard(
                    instance: instance,
                    series: null,
                    items: unknownSeriesItems,
                  );
                }
              },
            ),
          );
        } else {
          // Plain list layout
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
              ref.invalidate(sonarrHistoryProvider(instance));
              await ref.read(sonarrHistoryProvider(instance).future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredItems.length,
              itemBuilder: (BuildContext context, int index) {
                final item = filteredItems[index];
                return _PlainHistoryCard(instance: instance, item: item);
              },
            ),
          );
        }
      },
      loading: () => const Center(child: ExpressiveProgressIndicator()),
      error: (Object error, StackTrace? stackTrace) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load history: $error',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.invalidate(sonarrHistoryProvider(instance)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GroupedHistoryCard extends ConsumerStatefulWidget {
  const _GroupedHistoryCard({
    required this.instance,
    required this.series,
    required this.items,
  });

  final Instance instance;
  final SonarrSeries? series;
  final List<SonarrHistoryItem> items;

  @override
  ConsumerState<_GroupedHistoryCard> createState() =>
      _GroupedHistoryCardState();
}

class _GroupedHistoryCardState extends ConsumerState<_GroupedHistoryCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = ref.watch(sonarrApiProvider(widget.instance)).value;

    String? posterUrl;
    if (widget.series?.images != null && api != null) {
      try {
        final img =
            widget.series!.images.firstWhere((i) => i.coverType == 'poster');
        posterUrl = api.posterUrl(img);
      } catch (_) {}
    }

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
          // Header Row wrapped in InkWell to toggle expansion
          InkWell(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(_isExpanded ? 0 : 20),
              bottomRight: Radius.circular(_isExpanded ? 0 : 20),
            ),
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 36,
                      height: 54,
                      child: posterUrl != null
                          ? AtriumNetworkImage(
                              imageUrl: posterUrl,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                              errorWidget: (context, url, err) => Container(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.live_tv,
                                  size: 18,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.live_tv,
                                size: 18,
                                color: theme.colorScheme.outline,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.series?.title ?? 'Other / Unknown Releases',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.series != null)
                          Text(
                            '${widget.series!.network ?? ''} • ${widget.series!.year ?? ''}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
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
                      '${widget.items.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.outline,
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
                itemCount: widget.items.length,
                itemBuilder: (BuildContext context, int index) {
                  final item = widget.items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: <Widget>[
                        _buildHistoryEventIcon(context, item.eventType),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                item.episode != null
                                    ? 'S${item.episode!.seasonNumber.toString().padLeft(2, '0')}E${item.episode!.episodeNumber.toString().padLeft(2, '0')} - ${item.episode!.title}'
                                    : item.sourceTitle ?? 'Unknown Episode',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDateTime(item.date),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.info_outline, size: 20),
                          onPressed: () => _showHistoryDetails(
                            context,
                            ref,
                            widget.instance,
                            item,
                          ),
                        ),
                      ],
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

class _PlainHistoryCard extends ConsumerWidget {
  const _PlainHistoryCard({
    required this.instance,
    required this.item,
  });

  final Instance instance;
  final SonarrHistoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      color: theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: _buildHistoryEventIcon(context, item.eventType),
        title: Text(
          item.episode != null
              ? 'S${item.episode!.seasonNumber.toString().padLeft(2, '0')}E${item.episode!.episodeNumber.toString().padLeft(2, '0')} - ${item.episode!.title}'
              : item.sourceTitle ?? 'Unknown Release',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.series != null)
              Text(
                item.series!.title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            Text(
              _formatDateTime(item.date),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontSize: 10,
              ),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.info_outline, size: 20),
          onPressed: () => _showHistoryDetails(context, ref, instance, item),
        ),
      ),
    );
  }
}

class _BlocklistView extends ConsumerWidget {
  const _BlocklistView({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final blocklistAsync = ref.watch(sonarrBlocklistProvider(instance));
    final searchQuery =
        ref.watch(sonarrActivitySearchQueryProvider(instance)).toLowerCase();
    final grouped = ref.watch(sonarrActivityGroupedProvider(instance));

    return blocklistAsync.when(
      data: (List<SonarrBlocklistItem> items) {
        final filteredItems = items.where((item) {
          if (searchQuery.isEmpty) return true;
          final titleMatch =
              item.sourceTitle?.toLowerCase().contains(searchQuery) ?? false;
          final seriesMatch =
              item.series?.title.toLowerCase().contains(searchQuery) ?? false;
          final messageMatch =
              item.message?.toLowerCase().contains(searchQuery) ?? false;
          return titleMatch || seriesMatch || messageMatch;
        }).toList();

        if (filteredItems.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.block,
                  size: 48,
                  color: theme.colorScheme.outlineVariant,
                ),
                const SizedBox(height: 16),
                Text(
                  searchQuery.isEmpty
                      ? 'No blocklisted items'
                      : 'No blocklist matches search',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          );
        }

        if (grouped) {
          // Group by series
          final Map<int, List<SonarrBlocklistItem>> groupedMap = {};
          final List<SonarrSeries> seriesList = [];
          final List<SonarrBlocklistItem> unknownSeriesItems = [];

          for (final item in filteredItems) {
            if (item.series != null) {
              final seriesId = item.series!.id;
              if (!groupedMap.containsKey(seriesId)) {
                groupedMap[seriesId] = [];
                seriesList.add(item.series!);
              }
              groupedMap[seriesId]!.add(item);
            } else {
              unknownSeriesItems.add(item);
            }
          }

          // Sort series by date of latest event
          seriesList.sort((a, b) {
            final latestA = groupedMap[a.id]!.first.date ?? '';
            final latestB = groupedMap[b.id]!.first.date ?? '';
            return latestB.compareTo(latestA);
          });

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
              ref.invalidate(sonarrBlocklistProvider(instance));
              await ref.read(sonarrBlocklistProvider(instance).future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount:
                  seriesList.length + (unknownSeriesItems.isNotEmpty ? 1 : 0),
              itemBuilder: (BuildContext context, int index) {
                if (index < seriesList.length) {
                  final series = seriesList[index];
                  final seriesItems = groupedMap[series.id]!;
                  return _GroupedBlocklistCard(
                    instance: instance,
                    series: series,
                    items: seriesItems,
                  );
                } else {
                  return _GroupedBlocklistCard(
                    instance: instance,
                    series: null,
                    items: unknownSeriesItems,
                  );
                }
              },
            ),
          );
        } else {
          // Plain list layout
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
              ref.invalidate(sonarrBlocklistProvider(instance));
              await ref.read(sonarrBlocklistProvider(instance).future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredItems.length,
              itemBuilder: (BuildContext context, int index) {
                final item = filteredItems[index];
                return _PlainBlocklistCard(instance: instance, item: item);
              },
            ),
          );
        }
      },
      loading: () => const Center(child: ExpressiveProgressIndicator()),
      error: (Object error, StackTrace? stackTrace) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  Icons.error_outline,
                  size: 48,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  'Failed to load blocklist: $error',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () =>
                      ref.invalidate(sonarrBlocklistProvider(instance)),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GroupedBlocklistCard extends ConsumerStatefulWidget {
  const _GroupedBlocklistCard({
    required this.instance,
    required this.series,
    required this.items,
  });

  final Instance instance;
  final SonarrSeries? series;
  final List<SonarrBlocklistItem> items;

  @override
  ConsumerState<_GroupedBlocklistCard> createState() =>
      _GroupedBlocklistCardState();
}

class _GroupedBlocklistCardState extends ConsumerState<_GroupedBlocklistCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = ref.watch(sonarrApiProvider(widget.instance)).value;
    final selection =
        ref.watch(sonarrBlocklistSelectionProvider(widget.instance));
    final isSelecting = selection.isNotEmpty;
    final groupIds = widget.items.map((i) => i.id).toList();
    final isGroupSelected = groupIds.every(selection.contains);

    void toggleGroupSelection() {
      final notifier =
          ref.read(sonarrBlocklistSelectionProvider(widget.instance).notifier);
      if (isGroupSelected) {
        notifier.state =
            selection.where((id) => !groupIds.contains(id)).toSet();
      } else {
        notifier.state = {...selection, ...groupIds};
      }
    }

    String? posterUrl;
    if (widget.series?.images != null && api != null) {
      try {
        final img =
            widget.series!.images.firstWhere((i) => i.coverType == 'poster');
        posterUrl = api.posterUrl(img);
      } catch (_) {}
    }

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
          // Header Row wrapped in InkWell to toggle expansion
          InkWell(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(_isExpanded ? 0 : 20),
              bottomRight: Radius.circular(_isExpanded ? 0 : 20),
            ),
            onTap: () {
              if (isSelecting) {
                toggleGroupSelection();
              } else {
                setState(() {
                  _isExpanded = !_isExpanded;
                });
              }
            },
            onLongPress: toggleGroupSelection,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 36,
                      height: 54,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          posterUrl != null
                              ? AtriumNetworkImage(
                                  imageUrl: posterUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                  ),
                                  errorWidget: (context, url, err) => Container(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                    child: Icon(
                                      Icons.live_tv,
                                      size: 18,
                                      color: theme.colorScheme.outline,
                                    ),
                                  ),
                                )
                              : Container(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.live_tv,
                                    size: 18,
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                          if (isGroupSelected)
                            Container(
                              color: theme.colorScheme.primary
                                  .withValues(alpha: 0.25),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.all(3),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.check,
                                    size: 10,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          widget.series?.title ?? 'Other / Unknown Releases',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.series != null)
                          Text(
                            '${widget.series!.network ?? ''} • ${widget.series!.year ?? ''}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${widget.items.length}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    _isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.outline,
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
                itemCount: widget.items.length,
                itemBuilder: (BuildContext context, int index) {
                  final item = widget.items[index];
                  final isItemSelected = selection.contains(item.id);

                  void toggleItemSelection() {
                    final notifier = ref.read(
                      sonarrBlocklistSelectionProvider(widget.instance)
                          .notifier,
                    );
                    if (isItemSelected) {
                      notifier.state =
                          selection.where((id) => id != item.id).toSet();
                    } else {
                      notifier.state = {...selection, item.id};
                    }
                  }

                  return InkWell(
                    onTap: isSelecting ? toggleItemSelection : null,
                    onLongPress: toggleItemSelection,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: <Widget>[
                          isSelecting
                              ? Padding(
                                  padding: const EdgeInsets.only(right: 4.0),
                                  child: Checkbox(
                                    value: isItemSelected,
                                    onChanged: (_) => toggleItemSelection(),
                                  ),
                                )
                              : Icon(
                                  Icons.block_outlined,
                                  color: theme.colorScheme.error,
                                  size: 20,
                                ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  item.sourceTitle ?? 'Unknown Release',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (item.message != null &&
                                    item.message!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      item.message!,
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.error,
                                        fontSize: 11,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                const SizedBox(height: 2),
                                Row(
                                  children: <Widget>[
                                    if (item.indexer != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 1,
                                        ),
                                        margin: const EdgeInsets.only(right: 6),
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          item.indexer!,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    Text(
                                      _formatDateTime(item.date),
                                      style:
                                          theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.outline,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (!isSelecting)
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: theme.colorScheme.error,
                              ),
                              onPressed: () => _confirmDeleteBlocklistItem(
                                context,
                                ref,
                                widget.instance,
                                item,
                              ),
                            ),
                        ],
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

class _PlainBlocklistCard extends ConsumerWidget {
  const _PlainBlocklistCard({
    required this.instance,
    required this.item,
  });

  final Instance instance;
  final SonarrBlocklistItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selection = ref.watch(sonarrBlocklistSelectionProvider(instance));
    final isSelecting = selection.isNotEmpty;
    final isSelected = selection.contains(item.id);

    void toggleSelection() {
      final notifier =
          ref.read(sonarrBlocklistSelectionProvider(instance).notifier);
      if (isSelected) {
        notifier.state = selection.where((id) => id != item.id).toSet();
      } else {
        notifier.state = {...selection, item.id};
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      color: theme.colorScheme.surfaceContainerLow,
      child: ListTile(
        onTap: isSelecting ? toggleSelection : null,
        onLongPress: toggleSelection,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: isSelecting
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => toggleSelection(),
              )
            : Icon(
                Icons.block_outlined,
                color: theme.colorScheme.error,
                size: 22,
              ),
        title: Text(
          item.sourceTitle ?? 'Unknown Release',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.series != null)
              Text(
                item.series!.title,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            if (item.message != null && item.message!.isNotEmpty)
              Text(
                item.message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                  fontSize: 11,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            Text(
              _formatDateTime(item.date),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
                fontSize: 10,
              ),
            ),
          ],
        ),
        trailing: isSelecting
            ? null
            : IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                onPressed: () =>
                    _confirmDeleteBlocklistItem(context, ref, instance, item),
              ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface,
            ),
          ),
          const Divider(height: 8),
        ],
      ),
    );
  }
}

// File level helper utilities to avoid code duplication
Widget _buildHistoryEventIcon(BuildContext context, String? eventType) {
  final theme = Theme.of(context);
  final String label = eventType?.toLowerCase() ?? '';

  IconData icon;
  Color color;

  switch (label) {
    case 'grabbed':
      icon = Icons.cloud_download_outlined;
      color = theme.colorScheme.secondary;
      break;
    case 'downloadfolderimported':
    case 'seriesfolderimported':
      icon = Icons.download_done_outlined;
      color = theme.colorScheme.primary;
      break;
    case 'downloadfailed':
      icon = Icons.error_outline;
      color = theme.colorScheme.error;
      break;
    case 'episodefiledeleted':
      icon = Icons.delete_outline;
      color = theme.colorScheme.outline;
      break;
    case 'episodefilerenamed':
      icon = Icons.edit_outlined;
      color = theme.colorScheme.primary;
      break;
    case 'downloadignored':
      icon = Icons.block_outlined;
      color = theme.colorScheme.outline;
      break;
    default:
      icon = Icons.history;
      color = theme.colorScheme.onSurfaceVariant;
  }

  return Icon(icon, color: color, size: 22);
}

void _showHistoryDetails(
  BuildContext context,
  WidgetRef ref,
  Instance instance,
  SonarrHistoryItem item,
) {
  final theme = Theme.of(context);
  final String eventType = item.eventType ?? 'Unknown';

  showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          'History Event Details',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _DetailRow(label: 'Event Type', value: eventType.toUpperCase()),
              _DetailRow(label: 'Date', value: _formatDateTime(item.date)),
              _DetailRow(
                label: 'Source Title',
                value: item.sourceTitle ?? 'None',
              ),
              if (item.downloadId != null)
                _DetailRow(label: 'Download ID', value: item.downloadId!),
              if (item.data != null && item.data!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Metadata:',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.maxFinite,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: item.data!.entries.map((e) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${e.key}: ${e.value}',
                          style: theme.textTheme.bodySmall,
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: <Widget>[
          if (eventType.toLowerCase() == 'grabbed')
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  final api =
                      await ref.read(sonarrApiProvider(instance).future);
                  await api.failHistoryItem(item.id);
                  ref.invalidate(sonarrHistoryProvider(instance));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Marked release as failed. Sonarr will search for replacements.',
                        ),
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Failed to flag release: $e')),
                    );
                  }
                }
              },
              child: const Text('Mark as Failed'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

void _confirmDeleteBlocklistItem(
  BuildContext context,
  WidgetRef ref,
  Instance instance,
  SonarrBlocklistItem item,
) {
  final theme = Theme.of(context);
  showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        title: Text(
          'Remove from Blocklist',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.error,
          ),
        ),
        content: Text(
          'Are you sure you want to remove this release from the blocklist? This allows Sonarr to grab this release again.',
          style: theme.textTheme.bodyMedium,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                final api = await ref.read(sonarrApiProvider(instance).future);
                await api.deleteBlocklistItem(item.id);
                ref.invalidate(sonarrBlocklistProvider(instance));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Item removed from blocklist.'),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to remove item: $e')),
                  );
                }
              }
            },
            child: const Text('Remove'),
          ),
        ],
      );
    },
  );
}

String _formatSize(double bytes) {
  if (bytes <= 0) return '0 B';
  final double gb = bytes / (1024 * 1024 * 1024);
  if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
  final double mb = bytes / (1024 * 1024);
  return '${mb.toStringAsFixed(1)} MB';
}

String _formatDateTime(String? isoDate) {
  if (isoDate == null) return 'Unknown Date';
  try {
    final DateTime dt = DateTime.parse(isoDate).toLocal();
    final String monthStr = dt.month.toString().padLeft(2, '0');
    final String dayStr = dt.day.toString().padLeft(2, '0');
    final String hourStr = dt.hour.toString().padLeft(2, '0');
    final String minStr = dt.minute.toString().padLeft(2, '0');
    return '${dt.year}-$monthStr-$dayStr $hourStr:$minStr';
  } catch (_) {
    return isoDate;
  }
}

class _ActivityBulkActionsBar extends StatelessWidget {
  const _ActivityBulkActionsBar({
    required this.instance,
    required this.selectedIds,
    required this.isQueue,
    required this.onClear,
  });

  final Instance instance;
  final Set<int> selectedIds;
  final bool isQueue;
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
          if (isQueue) ...[
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
              ),
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (BuildContext context) => _QueueBulkGrabDialog(
                    instance: instance,
                    selectedIds: selectedIds,
                    onClear: onClear,
                  ),
                ).ignore();
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Force Grab'),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (BuildContext context) => _QueueBulkDeleteDialog(
                    instance: instance,
                    selectedIds: selectedIds,
                    onClear: onClear,
                  ),
                ).ignore();
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove'),
            ),
          ] else ...[
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (BuildContext context) => _BlocklistBulkDeleteDialog(
                    instance: instance,
                    selectedIds: selectedIds,
                    onClear: onClear,
                  ),
                ).ignore();
              },
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove'),
            ),
          ],
        ],
      ),
    );
  }
}

class _QueueBulkGrabDialog extends ConsumerWidget {
  const _QueueBulkGrabDialog({
    required this.instance,
    required this.selectedIds,
    required this.onClear,
  });

  final Instance instance;
  final Set<int> selectedIds;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Text('Force Grab ${selectedIds.length} Releases?'),
      content: const Text(
        'Are you sure you want to force download the selected releases from the queue?',
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
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => const PopScope<Object?>(
                canPop: false,
                child: Center(child: ExpressiveProgressIndicator()),
              ),
            ).ignore();

            Object? error;
            try {
              final api = await ref.read(sonarrApiProvider(instance).future);
              await api.grabQueueItems(selectedIds.toList());
            } catch (e) {
              error = e;
            } finally {
              if (nav.mounted) nav.pop(); // pop loading
            }

            if (!context.mounted) return;
            if (error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error grabbing items: $error')),
              );
              return;
            }
            ref.invalidate(sonarrQueueProvider(instance));
            onClear();
            Navigator.pop(context); // pop dialog

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Forced grab successfully triggered'),
              ),
            );
          },
          child: const Text('Force Grab'),
        ),
      ],
    );
  }
}

class _QueueBulkDeleteDialog extends ConsumerStatefulWidget {
  const _QueueBulkDeleteDialog({
    required this.instance,
    required this.selectedIds,
    required this.onClear,
  });

  final Instance instance;
  final Set<int> selectedIds;
  final VoidCallback onClear;

  @override
  ConsumerState<_QueueBulkDeleteDialog> createState() =>
      _QueueBulkDeleteDialogState();
}

class _QueueBulkDeleteDialogState
    extends ConsumerState<_QueueBulkDeleteDialog> {
  bool _blocklist = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Remove ${widget.selectedIds.length} items from Queue?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Are you sure you want to remove these items from download client queue?',
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text('Add items to blocklist'),
            value: _blocklist,
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _blocklist = val ?? false),
          ),
        ],
      ),
      actions: [
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
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => const PopScope<Object?>(
                canPop: false,
                child: Center(child: ExpressiveProgressIndicator()),
              ),
            ).ignore();

            Object? error;
            try {
              final api =
                  await ref.read(sonarrApiProvider(widget.instance).future);
              await api.bulkDeleteQueue(
                widget.selectedIds.toList(),
                blocklist: _blocklist,
              );
            } catch (e) {
              error = e;
            } finally {
              if (nav.mounted) nav.pop(); // pop loading
            }

            if (!context.mounted) return;
            if (error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error removing items: $error')),
              );
              return;
            }
            ref.invalidate(sonarrQueueProvider(widget.instance));
            widget.onClear();
            Navigator.pop(context); // pop dialog

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Successfully removed items')),
            );
          },
          child: const Text('Remove'),
        ),
      ],
    );
  }
}

class _BlocklistBulkDeleteDialog extends ConsumerWidget {
  const _BlocklistBulkDeleteDialog({
    required this.instance,
    required this.selectedIds,
    required this.onClear,
  });

  final Instance instance;
  final Set<int> selectedIds;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AlertDialog(
      title: Text('Remove ${selectedIds.length} items from Blocklist?'),
      content: const Text(
        'Are you sure you want to remove these items from blocklist? Sonarr will be able to search and grab these releases again.',
      ),
      actions: [
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
            showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => const PopScope<Object?>(
                canPop: false,
                child: Center(child: ExpressiveProgressIndicator()),
              ),
            ).ignore();

            Object? error;
            try {
              final api = await ref.read(sonarrApiProvider(instance).future);
              await api.bulkDeleteBlocklist(selectedIds.toList());
            } catch (e) {
              error = e;
            } finally {
              if (nav.mounted) nav.pop(); // pop loading
            }

            if (!context.mounted) return;
            if (error != null) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error removing items: $error')),
              );
              return;
            }
            ref.invalidate(sonarrBlocklistProvider(instance));
            onClear();
            Navigator.pop(context); // pop dialog

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Successfully removed items from blocklist'),
              ),
            );
          },
          child: const Text('Remove'),
        ),
      ],
    );
  }
}
