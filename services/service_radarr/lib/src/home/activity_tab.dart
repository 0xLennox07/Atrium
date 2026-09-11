import 'dart:async';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';

import '../../service_radarr.dart';

class ActivityTab extends ConsumerStatefulWidget {
  const ActivityTab({required this.instance, super.key});

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
        ref.read(radarrSearchActiveProvider(widget.instance).notifier);
    _resetSearchActive = () => notifier.state = false;
    final String initialQuery =
        ref.read(radarrActivitySearchQueryProvider(widget.instance));
    _searchController = TextEditingController(text: initialQuery);
    _searchFocusNode = FocusNode()..addListener(_onFocusChange);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        ref.read(radarrQueueSelectionProvider(widget.instance).notifier).state =
            {};
        ref
            .read(radarrBlocklistSelectionProvider(widget.instance).notifier)
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
    ref.read(radarrSearchActiveProvider(widget.instance).notifier).state =
        isActive;
  }

  void _onFocusChange() {
    _updateSearchActiveState();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final grouped = ref.watch(radarrActivityGroupedProvider(widget.instance));
    final queueSelection =
        ref.watch(radarrQueueSelectionProvider(widget.instance));
    final blocklistSelection =
        ref.watch(radarrBlocklistSelectionProvider(widget.instance));
    final activeSelection = _tabController.index == 0
        ? queueSelection
        : _tabController.index == 2
            ? blocklistSelection
            : <int>{};
    final isSelecting = activeSelection.isNotEmpty;

    ref.listen<String>(radarrActivitySearchQueryProvider(widget.instance),
        (String? previous, String next) {
      if (next.isEmpty && _searchController.text.isNotEmpty) {
        setState(() {
          _searchController.clear();
        });
        _searchFocusNode.unfocus();
        _updateSearchActiveState();
      }
    });

    ref.listen<int>(radarrHomeScrollToTopProvider((widget.instance, 1)),
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
                      radarrQueueSelectionProvider(widget.instance).notifier,
                    )
                    .state = {};
                ref
                    .read(
                      radarrBlocklistSelectionProvider(widget.instance)
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
                              radarrQueueSelectionProvider(widget.instance)
                                  .notifier,
                            )
                            .state = {};
                        ref
                            .read(
                              radarrBlocklistSelectionProvider(
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
                                    radarrActivitySearchQueryProvider(
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
                              radarrActivitySearchQueryProvider(widget.instance)
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
                            radarrActivityGroupedProvider(widget.instance)
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
    final queueAsync = ref.watch(radarrQueueProvider(instance));
    final searchQuery =
        ref.watch(radarrActivitySearchQueryProvider(instance)).toLowerCase();

    return queueAsync.when(
      data: (List<RadarrQueueItem> items) {
        final filteredItems = items.where((item) {
          if (searchQuery.isEmpty) return true;
          final titleMatch =
              item.title?.toLowerCase().contains(searchQuery) ?? false;
          final movieMatch =
              item.movie?.title.toLowerCase().contains(searchQuery) ?? false;
          return titleMatch || movieMatch;
        }).toList();

        if (filteredItems.isEmpty) {
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
                final api = await ref.read(radarrApiProvider(instance).future);
                await api.runCommand(<String, dynamic>{
                  'name': 'RefreshMonitoredDownloads',
                });
                await Future<void>.delayed(const Duration(seconds: 1));
              } catch (_) {}
              ref.invalidate(radarrQueueProvider(instance));
              await ref.read(radarrQueueProvider(instance).future);
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
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Your active queue is empty',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
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
              final api = await ref.read(radarrApiProvider(instance).future);
              await api.runCommand(<String, dynamic>{
                'name': 'RefreshMonitoredDownloads',
              });
              await Future<void>.delayed(const Duration(seconds: 1));
            } catch (_) {}
            ref.invalidate(radarrQueueProvider(instance));
            await ref.read(radarrQueueProvider(instance).future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(Insets.md),
            itemCount: filteredItems.length,
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              return _QueueCard(
                instance: instance,
                item: item,
              );
            },
          ),
        );
      },
      loading: () => const Center(child: ExpressiveProgressIndicator()),
      error: (err, __) => ErrorView(
        title: 'Failed to load queue',
        message: err.toString(),
        onRetry: () => ref.invalidate(radarrQueueProvider(instance)),
      ),
    );
  }
}

class _QueueCard extends ConsumerWidget {
  const _QueueCard({
    required this.instance,
    required this.item,
  });

  final Instance instance;
  final RadarrQueueItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final api = ref.watch(radarrApiProvider(instance)).value;
    final selection = ref.watch(radarrQueueSelectionProvider(instance));
    final isSelected = selection.contains(item.id);

    final double size = item.size ?? 0;
    final double sizeleft = item.sizeleft ?? 0;
    final double progress = size > 0 ? (size - sizeleft) / size : 0.0;

    String? posterUrl;
    if (item.movie?.images != null && api != null) {
      final img =
          item.movie!.images.firstWhereOrNull((i) => i.coverType == 'poster');
      if (img != null) {
        posterUrl = api.posterUrl(img);
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
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
          if (selection.isNotEmpty) {
            final notifier =
                ref.read(radarrQueueSelectionProvider(instance).notifier);
            if (isSelected) {
              notifier.state = selection.where((id) => id != item.id).toSet();
            } else {
              notifier.state = {...selection, item.id};
            }
          } else {
            _showDetails(context, item);
          }
        },
        onLongPress: () {
          final notifier =
              ref.read(radarrQueueSelectionProvider(instance).notifier);
          if (isSelected) {
            notifier.state = selection.where((id) => id != item.id).toSet();
          } else {
            notifier.state = {...selection, item.id};
          }
        },
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
                  children: <Widget>[
                    Text(
                      item.movie?.title ?? item.title ?? 'Unknown Movie',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
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
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(
                          '${_formatSize((size - sizeleft).toInt())} of ${_formatSize(size.toInt())}',
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
              if (selection.isEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.cancel_outlined,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],
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

  void _showDetails(BuildContext context, RadarrQueueItem i) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Text(
            'Queue Details',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailRow(label: 'Title', value: i.title ?? 'No title'),
                _DetailRow(label: 'Movie', value: i.movie?.title ?? 'Unknown'),
                _DetailRow(label: 'Status', value: i.status ?? 'Unknown'),
                _DetailRow(
                  label: 'Tracked State',
                  value: i.trackedDownloadState ?? 'None',
                ),
                _DetailRow(
                  label: 'Download Client',
                  value: i.downloadClient ?? 'Unknown',
                ),
                _DetailRow(
                  label: 'Download ID',
                  value: i.downloadId ?? 'Unknown',
                ),
                _DetailRow(label: 'Indexer', value: i.indexer ?? 'Unknown'),
                _DetailRow(
                  label: 'Output Path',
                  value: i.outputPath ?? 'Unknown',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    bool blocklist = false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Cancel Download?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Are you sure you want to cancel this download?'),
              CheckboxListTile(
                title: const Text('Add release to blocklist'),
                value: blocklist,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setState(() => blocklist = val ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Cancel Download'),
            ),
          ],
        ),
      ),
    );

    if ((ok ?? false) && context.mounted) {
      try {
        final api = await ref.read(radarrApiProvider(instance).future);
        await api.deleteQueueItem(item.id, blocklist: blocklist);
        ref.invalidate(radarrQueueProvider(instance));
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to cancel: $e')),
        );
      }
    }
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryView extends ConsumerWidget {
  const _HistoryView({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final historyAsync = ref.watch(radarrHistoryProvider(instance));
    final grouped = ref.watch(radarrActivityGroupedProvider(instance));
    final searchQuery =
        ref.watch(radarrActivitySearchQueryProvider(instance)).toLowerCase();

    return historyAsync.when(
      data: (List<RadarrHistoryItem> items) {
        final filteredItems = items.where((item) {
          if (searchQuery.isEmpty) return true;
          final titleMatch =
              item.sourceTitle?.toLowerCase().contains(searchQuery) ?? false;
          final movieMatch =
              item.movie?.title.toLowerCase().contains(searchQuery) ?? false;
          return titleMatch || movieMatch;
        }).toList();

        if (filteredItems.isEmpty) {
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
              ref.invalidate(radarrHistoryProvider(instance));
              await ref.read(radarrHistoryProvider(instance).future);
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
                        Icons.history,
                        size: 48,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No history entries found',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        if (grouped) {
          final groupedMap = groupBy(
            filteredItems,
            (RadarrHistoryItem item) => item.movie?.id ?? 0,
          );
          final keys = groupedMap.keys.toList();
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
              ref.invalidate(radarrHistoryProvider(instance));
              await ref.read(radarrHistoryProvider(instance).future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(Insets.md),
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final movieGroup = groupedMap[keys[index]]!;
                final movie = movieGroup.first.movie;
                return _GroupedHistoryCard(
                  instance: instance,
                  movie: movie,
                  items: movieGroup,
                );
              },
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
            ref.invalidate(radarrHistoryProvider(instance));
            await ref.read(radarrHistoryProvider(instance).future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(Insets.md),
            itemCount: filteredItems.length,
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              return _HistoryCard(
                instance: instance,
                item: item,
              );
            },
          ),
        );
      },
      loading: () => const Center(child: ExpressiveProgressIndicator()),
      error: (err, __) => ErrorView(
        title: 'Failed to load history',
        message: err.toString(),
        onRetry: () => ref.invalidate(radarrHistoryProvider(instance)),
      ),
    );
  }
}

// ─── Top-level helpers ───────────────────────────────────────────────────────

Widget _buildHistoryEventIcon(BuildContext context, String? eventType) {
  final theme = Theme.of(context);
  final label = (eventType ?? 'unknown').toLowerCase();

  IconData icon;
  Color color;
  switch (label) {
    case 'grabbed':
      icon = Icons.download_rounded;
      color = theme.colorScheme.primary;
      break;
    case 'downloadfolderimported':
    case 'imported':
      icon = Icons.check_circle_rounded;
      color = Colors.green;
      break;
    case 'downloadfailed':
    case 'failed':
      icon = Icons.error_rounded;
      color = theme.colorScheme.error;
      break;
    case 'deleted':
      icon = Icons.delete_rounded;
      color = theme.colorScheme.error;
      break;
    default:
      icon = Icons.history_rounded;
      color = theme.colorScheme.outline;
  }

  return Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      shape: BoxShape.circle,
    ),
    child: Icon(icon, color: color, size: 16),
  );
}

void _showHistoryDetails(
  BuildContext context,
  WidgetRef ref,
  Instance instance,
  RadarrHistoryItem item,
) {
  final theme = Theme.of(context);

  void addRow(List<Widget> rows, String label, String? value) {
    if (value == null || value.isEmpty) return;
    rows.add(
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 140,
              child: Text(
                label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  final date = DateTime.tryParse(item.date ?? '')?.toLocal();
  final formattedDate =
      date != null ? DateFormat.yMMMd().add_jm().format(date) : null;

  final rows = <Widget>[];
  addRow(rows, 'Movie', item.movie?.title);
  addRow(rows, 'Event', item.eventType);
  addRow(rows, 'Source Title', item.sourceTitle);
  addRow(rows, 'Date', formattedDate);
  addRow(rows, 'Download ID', item.downloadId);
  if (item.data != null) {
    item.data!.forEach((k, v) {
      if (v != null && v.isNotEmpty) {
        addRow(rows, k, v);
      }
    });
  }

  final bool canMarkFailed = (item.eventType ?? '').toLowerCase() == 'grabbed';

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'History Details',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.all(20),
              children: [
                ...rows,
                if (canMarkFailed) ...[
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.errorContainer,
                      foregroundColor: theme.colorScheme.onErrorContainer,
                    ),
                    onPressed: () async {
                      final ScaffoldMessengerState messenger =
                          ScaffoldMessenger.of(context);
                      Navigator.of(ctx).pop();
                      try {
                        final api =
                            await ref.read(radarrApiProvider(instance).future);
                        await api.failHistoryItem(item.id);
                        if (!context.mounted) return;
                        ref.invalidate(radarrHistoryProvider(instance));
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Marked release as failed. Radarr will search for replacements.',
                            ),
                          ),
                        );
                      } catch (e) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text('Failed to flag release: $e'),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.report_gmailerrorred_outlined),
                    label: const Text('Mark as Failed'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

Future<void> _confirmDeleteBlocklistItem(
  BuildContext context,
  WidgetRef ref,
  Instance instance,
  RadarrBlocklistItem item,
) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete from Blocklist?'),
      content: const Text(
        'Are you sure you want to remove this entry from your blocklist?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove'),
        ),
      ],
    ),
  );

  if ((ok ?? false) && context.mounted) {
    try {
      final api = await ref.read(radarrApiProvider(instance).future);
      await api.deleteBlocklistItem(item.id);
      ref.invalidate(radarrBlocklistProvider(instance));
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to remove: $e')),
        );
      }
    }
  }
}

// ─── Cards ───────────────────────────────────────────────────────────────────

class _HistoryCard extends ConsumerWidget {
  const _HistoryCard({
    required this.instance,
    required this.item,
  });

  final Instance instance;
  final RadarrHistoryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final api = ref.watch(radarrApiProvider(instance)).value;

    String? posterUrl;
    if (item.movie?.images != null && api != null) {
      final img =
          item.movie!.images.firstWhereOrNull((i) => i.coverType == 'poster');
      if (img != null) {
        posterUrl = api.posterUrl(img);
      }
    }

    final date = DateTime.tryParse(item.date ?? '')?.toLocal();
    final String formattedDate =
        date != null ? DateFormat.yMMMd().add_jm().format(date) : '';

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
        onTap: () => _showHistoryDetails(context, ref, instance, item),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 40,
                  height: 60,
                  child: posterUrl != null
                      ? AtriumNetworkImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.movie_outlined, size: 16),
                          ),
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.movie_outlined, size: 16),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.movie?.title ?? 'Unknown Movie',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.sourceTitle ?? 'No release title',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildEventBadge(context, item.eventType),
                        Text(
                          formattedDate,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
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

  Widget _buildEventBadge(BuildContext context, String? eventType) {
    final theme = Theme.of(context);
    Color bg;
    Color fg;
    final String label = eventType ?? 'unknown';

    switch (label.toLowerCase()) {
      case 'grabbed':
        bg = theme.colorScheme.primaryContainer;
        fg = theme.colorScheme.onPrimaryContainer;
        break;
      case 'downloadfolderimported':
      case 'imported':
        bg = theme.colorScheme.secondaryContainer;
        fg = theme.colorScheme.onSecondaryContainer;
        break;
      case 'failed':
        bg = theme.colorScheme.errorContainer;
        fg = theme.colorScheme.onErrorContainer;
        break;
      default:
        bg = theme.colorScheme.surfaceContainerHighest;
        fg = theme.colorScheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontSize: 8,
          fontWeight: FontWeight.bold,
          color: fg,
        ),
      ),
    );
  }
}

class _GroupedHistoryCard extends ConsumerStatefulWidget {
  const _GroupedHistoryCard({
    required this.instance,
    required this.movie,
    required this.items,
  });

  final Instance instance;
  final RadarrMovie? movie;
  final List<RadarrHistoryItem> items;

  @override
  ConsumerState<_GroupedHistoryCard> createState() =>
      _GroupedHistoryCardState();
}

class _GroupedHistoryCardState extends ConsumerState<_GroupedHistoryCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = ref.watch(radarrApiProvider(widget.instance)).value;

    String? posterUrl;
    if (widget.movie?.images != null && api != null) {
      final img =
          widget.movie!.images.firstWhereOrNull((i) => i.coverType == 'poster');
      if (img != null) {
        posterUrl = api.posterUrl(img);
      }
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
                                child:
                                    const Icon(Icons.movie_outlined, size: 18),
                              ),
                            )
                          : Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.movie_outlined, size: 18),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.movie?.title ?? 'Unknown Movie',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.movie != null)
                          Text(
                            '${widget.movie!.year}',
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
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.items.length,
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  final date = DateTime.tryParse(item.date ?? '')?.toLocal();
                  final String formattedDate = date != null
                      ? DateFormat.yMMMd().add_jm().format(date)
                      : '';
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        _buildHistoryEventIcon(context, item.eventType),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.sourceTitle ?? 'Unknown Release',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formattedDate,
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

class _BlocklistView extends ConsumerWidget {
  const _BlocklistView({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final blocklistAsync = ref.watch(radarrBlocklistProvider(instance));
    final grouped = ref.watch(radarrActivityGroupedProvider(instance));
    final searchQuery =
        ref.watch(radarrActivitySearchQueryProvider(instance)).toLowerCase();

    return blocklistAsync.when(
      data: (List<RadarrBlocklistItem> items) {
        final filteredItems = items.where((item) {
          if (searchQuery.isEmpty) return true;
          final titleMatch =
              item.sourceTitle?.toLowerCase().contains(searchQuery) ?? false;
          final movieMatch =
              item.movie?.title.toLowerCase().contains(searchQuery) ?? false;
          return titleMatch || movieMatch;
        }).toList();

        if (filteredItems.isEmpty) {
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
              ref.invalidate(radarrBlocklistProvider(instance));
              await ref.read(radarrBlocklistProvider(instance).future);
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
                        Icons.block_outlined,
                        size: 48,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No blocklist entries found',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        if (grouped) {
          final groupedMap = groupBy(
            filteredItems,
            (RadarrBlocklistItem item) => item.movie?.id ?? 0,
          );
          final keys = groupedMap.keys.toList();
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
              ref.invalidate(radarrBlocklistProvider(instance));
              await ref.read(radarrBlocklistProvider(instance).future);
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(Insets.md),
              itemCount: keys.length,
              itemBuilder: (context, index) {
                final movieGroup = groupedMap[keys[index]]!;
                final movie = movieGroup.first.movie;
                return _GroupedBlocklistCard(
                  instance: instance,
                  movie: movie,
                  items: movieGroup,
                );
              },
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
            ref.invalidate(radarrBlocklistProvider(instance));
            await ref.read(radarrBlocklistProvider(instance).future);
          },
          child: ListView.builder(
            padding: const EdgeInsets.all(Insets.md),
            itemCount: filteredItems.length,
            itemBuilder: (context, index) {
              final item = filteredItems[index];
              return _BlocklistCard(
                instance: instance,
                item: item,
              );
            },
          ),
        );
      },
      loading: () => const Center(child: ExpressiveProgressIndicator()),
      error: (err, __) => ErrorView(
        title: 'Failed to load blocklist',
        message: err.toString(),
        onRetry: () => ref.invalidate(radarrBlocklistProvider(instance)),
      ),
    );
  }
}

class _BlocklistCard extends ConsumerWidget {
  const _BlocklistCard({
    required this.instance,
    required this.item,
  });

  final Instance instance;
  final RadarrBlocklistItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final api = ref.watch(radarrApiProvider(instance)).value;
    final selection = ref.watch(radarrBlocklistSelectionProvider(instance));
    final isSelected = selection.contains(item.id);

    String? posterUrl;
    if (item.movie?.images != null && api != null) {
      final img =
          item.movie!.images.firstWhereOrNull((i) => i.coverType == 'poster');
      if (img != null) {
        posterUrl = api.posterUrl(img);
      }
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
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
          if (selection.isNotEmpty) {
            final notifier =
                ref.read(radarrBlocklistSelectionProvider(instance).notifier);
            if (isSelected) {
              notifier.state = selection.where((id) => id != item.id).toSet();
            } else {
              notifier.state = {...selection, item.id};
            }
          }
        },
        onLongPress: () {
          final notifier =
              ref.read(radarrBlocklistSelectionProvider(instance).notifier);
          if (isSelected) {
            notifier.state = selection.where((id) => id != item.id).toSet();
          } else {
            notifier.state = {...selection, item.id};
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 40,
                  height: 60,
                  child: posterUrl != null
                      ? AtriumNetworkImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.movie_outlined, size: 16),
                          ),
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.movie_outlined, size: 16),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.movie?.title ?? 'Unknown Movie',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.sourceTitle ?? 'No release title',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (item.message != null && item.message!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.message!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              if (selection.isEmpty) ...[
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(
                    Icons.delete_outline,
                    color: theme.colorScheme.error,
                  ),
                  onPressed: () => _confirmDelete(context, ref),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete from Blocklist?'),
        content: const Text(
          'Are you sure you want to remove this entry from your blocklist?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if ((ok ?? false) && context.mounted) {
      try {
        final api = await ref.read(radarrApiProvider(instance).future);
        await api.deleteBlocklistItem(item.id);
        ref.invalidate(radarrBlocklistProvider(instance));
      } catch (e) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to remove: $e')),
        );
      }
    }
  }
}

class _GroupedBlocklistCard extends ConsumerStatefulWidget {
  const _GroupedBlocklistCard({
    required this.instance,
    required this.movie,
    required this.items,
  });

  final Instance instance;
  final RadarrMovie? movie;
  final List<RadarrBlocklistItem> items;

  @override
  ConsumerState<_GroupedBlocklistCard> createState() =>
      _GroupedBlocklistCardState();
}

class _GroupedBlocklistCardState extends ConsumerState<_GroupedBlocklistCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = ref.watch(radarrApiProvider(widget.instance)).value;
    final selection =
        ref.watch(radarrBlocklistSelectionProvider(widget.instance));
    final isSelecting = selection.isNotEmpty;
    final groupIds = widget.items.map((i) => i.id).toList();
    final isGroupSelected = groupIds.every(selection.contains);

    void toggleGroupSelection() {
      final notifier =
          ref.read(radarrBlocklistSelectionProvider(widget.instance).notifier);
      if (isGroupSelected) {
        notifier.state =
            selection.where((id) => !groupIds.contains(id)).toSet();
      } else {
        notifier.state = {...selection, ...groupIds};
      }
    }

    String? posterUrl;
    if (widget.movie?.images != null && api != null) {
      final img =
          widget.movie!.images.firstWhereOrNull((i) => i.coverType == 'poster');
      if (img != null) {
        posterUrl = api.posterUrl(img);
      }
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
          InkWell(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(_expanded ? 0 : 20),
              bottomRight: Radius.circular(_expanded ? 0 : 20),
            ),
            onTap: () {
              if (isSelecting) {
                toggleGroupSelection();
              } else {
                setState(() => _expanded = !_expanded);
              }
            },
            onLongPress: toggleGroupSelection,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
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
                                    child: const Icon(
                                      Icons.movie_outlined,
                                      size: 18,
                                    ),
                                  ),
                                )
                              : Container(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: const Icon(
                                    Icons.movie_outlined,
                                    size: 18,
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
                      children: [
                        Text(
                          widget.movie?.title ?? 'Unknown Movie',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.movie != null)
                          Text(
                            '${widget.movie!.year}',
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
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.items.length,
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  final isItemSelected = selection.contains(item.id);

                  void toggleItemSelection() {
                    final notifier = ref.read(
                      radarrBlocklistSelectionProvider(widget.instance)
                          .notifier,
                    );
                    if (isItemSelected) {
                      notifier.state =
                          selection.where((id) => id != item.id).toSet();
                    } else {
                      notifier.state = {...selection, item.id};
                    }
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        if (isSelecting) ...[
                          Checkbox(
                            value: isItemSelected,
                            onChanged: (_) => toggleItemSelection(),
                          ),
                          const SizedBox(width: 4),
                        ] else ...[
                          Icon(
                            Icons.block_outlined,
                            color: theme.colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.sourceTitle ?? 'Unknown Release',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (item.message != null &&
                                  item.message!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  item.message!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.error,
                                    fontSize: 11,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (!isSelecting)
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              color: theme.colorScheme.error,
                              size: 20,
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
              onPressed: () => _confirmBulkQueueDelete(context),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancel Downloads'),
            ),
          ] else ...[
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              onPressed: () => _confirmBulkBlocklistDelete(context),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove Entries'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmBulkQueueDelete(BuildContext context) async {
    final container = ProviderScope.containerOf(context);
    bool blocklist = false;

    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Cancel ${selectedIds.length} Downloads?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Are you sure you want to cancel the selected downloads?',
              ),
              CheckboxListTile(
                title: const Text('Add releases to blocklist'),
                value: blocklist,
                contentPadding: EdgeInsets.zero,
                onChanged: (val) => setState(() => blocklist = val ?? false),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes'),
            ),
          ],
        ),
      ),
    );

    if (ok ?? false) {
      try {
        final api = await container.read(radarrApiProvider(instance).future);
        await api.bulkDeleteQueue(selectedIds.toList(), blocklist: blocklist);
        container.invalidate(radarrQueueProvider(instance));
        onClear();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to bulk cancel: $e')),
          );
        }
      }
    }
  }

  Future<void> _confirmBulkBlocklistDelete(BuildContext context) async {
    final container = ProviderScope.containerOf(context);
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${selectedIds.length} Entries?'),
        content: const Text(
          'Are you sure you want to remove the selected entries from the blocklist?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (ok ?? false) {
      try {
        final api = await container.read(radarrApiProvider(instance).future);
        await api.bulkDeleteBlocklist(selectedIds.toList());
        container.invalidate(radarrBlocklistProvider(instance));
        onClear();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to bulk remove: $e')),
          );
        }
      }
    }
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
              final api = await ref.read(radarrApiProvider(instance).future);
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
            ref.invalidate(radarrQueueProvider(instance));
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

String _formatSize(int bytes) {
  if (bytes <= 0) return '0 B';
  const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
  final i = (log(bytes) / log(1024)).floor();
  return '${(bytes / pow(1024, i)).toStringAsFixed(1)} ${suffixes[i]}';
}
