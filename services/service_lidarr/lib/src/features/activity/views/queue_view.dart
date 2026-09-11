import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/lidarr_formatters.dart';
import '../../../generated/generated.dart';
import '../../../lidarr_api.dart';
import '../../../lidarr_artwork.dart';
import '../../../lidarr_providers.dart';
import '../../search/interactive_search_screen.dart';
import '../../track_files/manual_import_dialog.dart';

/// Active download queue view with grouped and plain-list display modes and deep item inspection.
class QueueView extends ConsumerStatefulWidget {
  const QueueView({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends ConsumerState<QueueView> {
  bool _showAllStatusMessages = false;

  Future<void> _removeQueueItem(QueueResource item) async {
    final int? id = item.id;
    if (id == null) return;

    bool removeFromClient = true;
    bool blocklist = false;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setDialogState) {
          return AlertDialog(
            title: const Text('Remove from Queue'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Remove "${item.title ?? 'Download'}" from download queue?',
                ),
                const SizedBox(height: Insets.md),
                CheckboxListTile(
                  title: const Text('Remove from Download Client'),
                  subtitle: const Text('Delete from client and discard files'),
                  value: removeFromClient,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onChanged: (bool? val) {
                    setDialogState(() {
                      removeFromClient = val ?? true;
                    });
                  },
                ),
                CheckboxListTile(
                  title: const Text('Blocklist Release'),
                  subtitle: const Text(
                    'Prevent Lidarr from grabbing this release again',
                  ),
                  value: blocklist,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  onChanged: (bool? val) {
                    setDialogState(() {
                      blocklist = val ?? false;
                    });
                  },
                ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Remove'),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final LidarrApi api =
          await ref.read(lidarrApiProvider(widget.instance).future);
      final ApiResponse<void> resp = await api.queue.deleteQueueById(
        id: id,
        removeFromClient: removeFromClient,
        blocklist: blocklist,
      );

      if (!resp.isSuccess) {
        throw Exception(resp.error?.message ?? 'Failed to remove queue item');
      }

      ref.invalidate(lidarrQueueProvider(widget.instance));
      ref.invalidate(lidarrBlocklistProvider(widget.instance));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Removed "${item.title ?? 'Item'}" from queue'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to remove item: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showQueueItemDetails(QueueResource item) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.95,
        expand: false,
        builder: (BuildContext context, ScrollController scrollController) {
          final ThemeData theme = Theme.of(context);
          final ColorScheme cs = theme.colorScheme;
          final String? coverUrl =
              LidarrArtwork.albumCoverUrl(widget.instance, item.album?.images);
          final double size = item.size ?? 0.0;
          final double sizeLeft = item.sizeleft ?? 0.0;
          final double progress =
              size > 0 ? ((size - sizeLeft) / size).clamp(0.0, 1.0) : 0.0;

          final String status = item.status?.toLowerCase() ?? 'queued';
          final String trackedState =
              item.trackedDownloadState?.name ?? 'unknown';
          final bool isImportBlocked =
              item.trackedDownloadState == TrackedDownloadState.importBlocked ||
                  item.trackedDownloadStatus == TrackedDownloadStatus.warning;
          final bool hasError =
              item.trackedDownloadStatus == TrackedDownloadStatus.error ||
                  item.trackedDownloadState ==
                      TrackedDownloadState.downloadFailed ||
                  status == 'failed' ||
                  (item.errorMessage != null && item.errorMessage!.isNotEmpty);

          String statusDescription;
          if (isImportBlocked) {
            statusDescription =
                'One or more tracks expected in this release were not imported automatically. Use Manual Import below to match files.';
          } else if (item.trackedDownloadState ==
              TrackedDownloadState.importPending) {
            statusDescription =
                'Download finished. Waiting for Lidarr import scanner to process tracks.';
          } else if (item.trackedDownloadState ==
              TrackedDownloadState.importing) {
            statusDescription =
                'Currently importing and organizing audio files into your library.';
          } else if (status == 'downloading') {
            statusDescription =
                'Currently downloading via ${item.downloadClient ?? 'download client'}.';
          } else if (status == 'completed') {
            statusDescription = 'Download completed in client.';
          } else if (status == 'paused') {
            statusDescription = 'Download paused in download client.';
          } else {
            statusDescription = 'Release is currently queued for download.';
          }

          return Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(
              title: const Text('Download Details'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
              actions: <Widget>[
                IconButton(
                  icon: Icon(Icons.delete_outline, color: cs.error),
                  tooltip: 'Remove from Queue',
                  onPressed: () {
                    Navigator.of(context).pop();
                    _removeQueueItem(item);
                  },
                ),
              ],
            ),
            body: ListView(
              controller: scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: <Widget>[
                // Header card with Artwork & Titles
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: coverUrl != null
                            ? AtriumNetworkImage(
                                imageUrl: coverUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: cs.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.album_outlined,
                                    size: 36,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : Container(
                                color: cs.surfaceContainerHighest,
                                child: Icon(
                                  Icons.album_outlined,
                                  size: 36,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            item.title ??
                                item.album?.title ??
                                'Unknown Release',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (item.artist?.artistName != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              item.artist!.artistName!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (item.album?.title != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Album: ${item.album!.title!}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Status & Diagnostics Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasError
                        ? cs.errorContainer.withValues(alpha: 0.5)
                        : isImportBlocked
                            ? cs.tertiaryContainer.withValues(alpha: 0.4)
                            : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasError
                          ? cs.error
                          : isImportBlocked
                              ? cs.tertiary
                              : cs.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            hasError
                                ? Icons.error_outline
                                : isImportBlocked
                                    ? Icons.warning_amber_rounded
                                    : Icons.info_outline,
                            size: 20,
                            color: hasError
                                ? cs.error
                                : isImportBlocked
                                    ? cs.tertiary
                                    : cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            (item.status ?? trackedState).toUpperCase(),
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: hasError
                                  ? cs.error
                                  : isImportBlocked
                                      ? cs.tertiary
                                      : cs.primary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${(progress * 100).toStringAsFixed(0)}%',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        statusDescription,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurface,
                        ),
                      ),
                      if (item.errorMessage != null &&
                          item.errorMessage!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Error: ${item.errorMessage!}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Progress Bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: cs.surfaceContainerHighest,
                    color: hasError
                        ? cs.error
                        : isImportBlocked
                            ? cs.tertiary
                            : cs.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      '${LidarrFormatters.formatBytes(size - sizeLeft)} / ${LidarrFormatters.formatBytes(size)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    if (item.timeleft != null && item.timeleft!.isNotEmpty)
                      Text(
                        'ETA: ${item.timeleft}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Quick Action Buttons
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      icon: const Icon(
                        Icons.drive_folder_upload_outlined,
                        size: 18,
                      ),
                      label: const Text('Manual Import'),
                      onPressed: () {
                        Navigator.of(context).pop();
                        showLidarrManualImportFlow(
                          context,
                          ref,
                          widget.instance,
                          downloadId: item.downloadId,
                          artistId: item.artistId,
                        );
                      },
                    ),
                    if (item.albumId != null)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.search, size: 18),
                        label: const Text('Interactive Search'),
                        onPressed: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => LidarrInteractiveSearchScreen(
                                instance: widget.instance,
                                title: item.album?.title ?? 'Album',
                                albumId: item.albumId,
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),

                // Download & Technical Details
                Text(
                  'Technical Details',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    child: Column(
                      children: <Widget>[
                        _buildDetailRow(
                          'Download Client',
                          item.downloadClient ?? '--',
                          context,
                        ),
                        const Divider(height: 12),
                        _buildDetailRow(
                          'Indexer',
                          item.indexer ?? '--',
                          context,
                        ),
                        const Divider(height: 12),
                        _buildDetailRow(
                          'Protocol',
                          LidarrFormatters.formatWireEnum(item.protocol?.value),
                          context,
                        ),
                        const Divider(height: 12),
                        _buildDetailRow(
                          'Quality',
                          item.quality?.quality?.name ?? '--',
                          context,
                        ),
                        if (item.customFormatScore != null &&
                            item.customFormatScore != 0) ...[
                          const Divider(height: 12),
                          _buildDetailRow(
                            'Custom Format Score',
                            '${item.customFormatScore}',
                            context,
                          ),
                        ],
                        if (item.trackFileCount != null &&
                            item.trackFileCount! > 0) ...[
                          const Divider(height: 12),
                          _buildDetailRow(
                            'Album Tracks Imported',
                            '${item.trackHasFileCount ?? 0} of ${item.trackFileCount} tracks',
                            context,
                          ),
                        ],
                        if (item.outputPath != null &&
                            item.outputPath!.isNotEmpty) ...[
                          const Divider(height: 12),
                          _buildDetailRow(
                            'Output Path',
                            item.outputPath!,
                            context,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                // Status Messages Section
                if (item.statusMessages != null &&
                    item.statusMessages!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Status Messages',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isImportBlocked ? cs.tertiary : cs.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  StatefulBuilder(
                    builder: (BuildContext context, StateSetter setCardState) {
                      final List<TrackedDownloadStatusMessage> messages =
                          item.statusMessages!;
                      final bool canExpand = messages.length > 3;
                      final List<TrackedDownloadStatusMessage> visible =
                          (!canExpand || _showAllStatusMessages)
                              ? messages
                              : messages.take(3).toList();

                      return Card(
                        elevation: 0,
                        color: cs.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              for (final msg in visible) ...[
                                Text(
                                  msg.title ?? 'Message',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                if (msg.messages != null)
                                  for (final m in msg.messages!)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        top: 4,
                                        left: 8,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          const Text('• '),
                                          Expanded(
                                            child: Text(
                                              m,
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                const SizedBox(height: 8),
                              ],
                              if (canExpand)
                                Center(
                                  child: TextButton(
                                    onPressed: () {
                                      setCardState(() {
                                        _showAllStatusMessages =
                                            !_showAllStatusMessages;
                                      });
                                    },
                                    child: Text(
                                      _showAllStatusMessages
                                          ? 'Show less'
                                          : 'Show all ${messages.length} messages',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<QueueResource>> asyncQueue =
        ref.watch(lidarrQueueProvider(widget.instance));
    final String filterQuery =
        ref.watch(lidarrActivitySearchQueryProvider(widget.instance));
    final bool grouped =
        ref.watch(lidarrActivityGroupedProvider(widget.instance));
    final Set<int> selection =
        ref.watch(lidarrQueueSelectionProvider(widget.instance));

    return asyncQueue.when(
      data: (List<QueueResource> rawQueue) {
        List<QueueResource> queue = rawQueue;
        if (filterQuery.trim().isNotEmpty) {
          final String q = filterQuery.trim().toLowerCase();
          queue = queue.where((QueueResource item) {
            final String title = (item.title ?? '').toLowerCase();
            final String artist = (item.artist?.artistName ?? '').toLowerCase();
            final String album = (item.album?.title ?? '').toLowerCase();
            final String client = (item.downloadClient ?? '').toLowerCase();
            final String indexer = (item.indexer ?? '').toLowerCase();
            return title.contains(q) ||
                artist.contains(q) ||
                album.contains(q) ||
                client.contains(q) ||
                indexer.contains(q);
          }).toList();
        }

        if (queue.isEmpty) {
          return EasyRefresh(
            onRefresh: () async {
              ref.invalidate(lidarrQueueProvider(widget.instance));
            },
            child: Center(
              child: EmptyView(
                icon: Icons.cloud_done_outlined,
                title: rawQueue.isEmpty ? 'Queue Empty' : 'No matches found',
                message: rawQueue.isEmpty
                    ? 'No active music downloads in progress.'
                    : 'No downloads matching your search query.',
              ),
            ),
          );
        }

        if (grouped) {
          // Group by Artist
          final Map<String, List<QueueResource>> groups =
              <String, List<QueueResource>>{};
          for (final QueueResource item in queue) {
            final String artistKey = item.artist?.artistName ??
                item.album?.title ??
                'Other Downloads';
            groups.putIfAbsent(artistKey, () => <QueueResource>[]).add(item);
          }

          final List<MapEntry<String, List<QueueResource>>> groupEntries =
              groups.entries.toList();

          return EasyRefresh(
            onRefresh: () async {
              ref.invalidate(lidarrQueueProvider(widget.instance));
            },
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: groupEntries.length,
              itemBuilder: (BuildContext context, int index) {
                final MapEntry<String, List<QueueResource>> entry =
                    groupEntries[index];
                return _QueueArtistGroupCard(
                  instance: widget.instance,
                  artistName: entry.key,
                  items: entry.value,
                  selection: selection,
                  onSelect: (int id) {
                    final notifier = ref.read(
                      lidarrQueueSelectionProvider(widget.instance).notifier,
                    );
                    if (selection.contains(id)) {
                      notifier.state = selection.difference(<int>{id});
                    } else {
                      notifier.state = <int>{...selection, id};
                    }
                  },
                  onTapItem: _showQueueItemDetails,
                  onRemoveItem: _removeQueueItem,
                );
              },
            ),
          );
        }

        return EasyRefresh(
          onRefresh: () async {
            ref.invalidate(lidarrQueueProvider(widget.instance));
          },
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 6),
            itemCount: queue.length,
            itemBuilder: (BuildContext context, int index) {
              final QueueResource item = queue[index];
              final bool isSelected =
                  item.id != null && selection.contains(item.id!);
              return _QueueCard(
                instance: widget.instance,
                item: item,
                isSelected: isSelected,
                isSelecting: selection.isNotEmpty,
                onTap: () {
                  if (selection.isNotEmpty && item.id != null) {
                    final notifier = ref.read(
                      lidarrQueueSelectionProvider(widget.instance).notifier,
                    );
                    if (isSelected) {
                      notifier.state = selection.difference(<int>{item.id!});
                    } else {
                      notifier.state = <int>{...selection, item.id!};
                    }
                  } else {
                    _showQueueItemDetails(item);
                  }
                },
                onLongPress: () {
                  if (item.id != null) {
                    final notifier = ref.read(
                      lidarrQueueSelectionProvider(widget.instance).notifier,
                    );
                    notifier.state = <int>{...selection, item.id!};
                  }
                },
                onRemove: () => _removeQueueItem(item),
              );
            },
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stack) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              size: 48,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text('Failed to load queue: $error'),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () =>
                  ref.invalidate(lidarrQueueProvider(widget.instance)),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grouped card presenting all queued downloads for a single artist.
class _QueueArtistGroupCard extends StatelessWidget {
  const _QueueArtistGroupCard({
    required this.instance,
    required this.artistName,
    required this.items,
    required this.selection,
    required this.onSelect,
    required this.onTapItem,
    required this.onRemoveItem,
  });

  final Instance instance;
  final String artistName;
  final List<QueueResource> items;
  final Set<int> selection;
  final ValueChanged<int> onSelect;
  final ValueChanged<QueueResource> onTapItem;
  final ValueChanged<QueueResource> onRemoveItem;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final QueueResource first = items.first;
    final String? coverUrl =
        LidarrArtwork.albumCoverUrl(instance, first.album?.images) ??
            LidarrArtwork.artistPosterUrl(instance, first.artist?.images);

    double totalSize = 0.0;
    double totalSizeLeft = 0.0;
    for (final QueueResource item in items) {
      totalSize += item.size ?? 0.0;
      totalSizeLeft += item.sizeleft ?? 0.0;
    }
    final double aggregateProgress = totalSize > 0
        ? ((totalSize - totalSizeLeft) / totalSize).clamp(0.0, 1.0)
        : 0.0;

    final bool hasAnyError = items.any(
      (QueueResource item) =>
          item.trackedDownloadStatus == TrackedDownloadStatus.warning ||
          item.trackedDownloadStatus == TrackedDownloadStatus.error ||
          item.trackedDownloadState == TrackedDownloadState.importBlocked ||
          item.status == 'warning' ||
          (item.errorMessage != null && item.errorMessage!.isNotEmpty),
    );

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Artist Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: coverUrl != null
                        ? AtriumNetworkImage(
                            imageUrl: coverUrl,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(
                                Icons.person,
                                size: 24,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Container(
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              Icons.person,
                              size: 24,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        artistName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${items.length} ${items.length == 1 ? 'release' : 'releases'} • ${LidarrFormatters.formatBytes(totalSize - totalSizeLeft)} of ${LidarrFormatters.formatBytes(totalSize)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${(aggregateProgress * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: hasAnyError ? cs.error : cs.primary,
                  ),
                ),
              ],
            ),
          ),

          // Aggregate progress bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: aggregateProgress,
                minHeight: 4,
                backgroundColor: cs.surfaceContainerHighest,
                color: hasAnyError ? cs.error : cs.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),

          const Divider(height: 1),

          // Releases list inside group
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16),
            itemBuilder: (BuildContext context, int idx) {
              final QueueResource item = items[idx];
              final bool isSelected =
                  item.id != null && selection.contains(item.id!);
              return _QueueItemRow(
                instance: instance,
                item: item,
                isSelected: isSelected,
                isSelecting: selection.isNotEmpty,
                onTap: () {
                  if (selection.isNotEmpty && item.id != null) {
                    onSelect(item.id!);
                  } else {
                    onTapItem(item);
                  }
                },
                onLongPress: () {
                  if (item.id != null) {
                    onSelect(item.id!);
                  }
                },
                onRemove: () => onRemoveItem(item),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// Compact row representation of a release item inside a grouped artist card.
class _QueueItemRow extends StatelessWidget {
  const _QueueItemRow({
    required this.instance,
    required this.item,
    required this.isSelected,
    required this.isSelecting,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
  });

  final Instance instance;
  final QueueResource item;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final double size = item.size ?? 0.0;
    final double sizeLeft = item.sizeleft ?? 0.0;
    final double progress =
        size > 0 ? ((size - sizeLeft) / size).clamp(0.0, 1.0) : 0.0;

    final String protocolStr = LidarrFormatters.formatWireEnum(
      item.protocol?.value ?? item.protocol?.name,
    );
    final String qualityName = item.quality?.quality?.name ?? 'Unknown';
    final bool hasError =
        item.trackedDownloadStatus == TrackedDownloadStatus.warning ||
            item.trackedDownloadStatus == TrackedDownloadStatus.error ||
            item.trackedDownloadState == TrackedDownloadState.importBlocked ||
            item.status == 'warning' ||
            (item.errorMessage != null && item.errorMessage!.isNotEmpty);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: <Widget>[
            if (isSelecting) ...[
              Checkbox(
                value: isSelected,
                onChanged: (_) => onTap(),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    item.album?.title ?? item.title ?? 'Download Item',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: cs.secondaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          protocolStr,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          qualityName,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        '${LidarrFormatters.formatBytes(size - sizeLeft)} / ${LidarrFormatters.formatBytes(size)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      minHeight: 3,
                      backgroundColor: cs.surfaceContainerHighest,
                      color: hasError ? cs.error : cs.primary,
                    ),
                  ),
                  if (hasError) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.errorMessage ??
                          item.statusMessages?.firstOrNull?.messages
                              ?.firstOrNull ??
                          item.statusMessages?.firstOrNull?.title ??
                          'Import warning',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.error,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (!isSelecting) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.close, size: 18, color: cs.onSurfaceVariant),
                tooltip: 'Remove from Queue',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                onPressed: onRemove,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Standalone Card for Plain List mode.
class _QueueCard extends StatelessWidget {
  const _QueueCard({
    required this.instance,
    required this.item,
    required this.isSelected,
    required this.isSelecting,
    required this.onTap,
    required this.onLongPress,
    required this.onRemove,
  });

  final Instance instance;
  final QueueResource item;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final String? coverUrl =
        LidarrArtwork.albumCoverUrl(instance, item.album?.images);
    final double size = item.size ?? 0.0;
    final double sizeLeft = item.sizeleft ?? 0.0;
    final double progress =
        size > 0 ? ((size - sizeLeft) / size).clamp(0.0, 1.0) : 0.0;

    final String protocolStr =
        (item.protocol?.name ?? 'download').toUpperCase();
    final String qualityName = item.quality?.quality?.name ?? 'Unknown';
    final String statusStr =
        item.status ?? item.trackedDownloadStatus?.name ?? 'Queued';
    final bool hasError =
        item.trackedDownloadStatus == TrackedDownloadStatus.warning ||
            item.trackedDownloadStatus == TrackedDownloadStatus.error ||
            item.trackedDownloadState == TrackedDownloadState.importBlocked ||
            item.trackedDownloadState == TrackedDownloadState.downloadFailed ||
            item.status == 'warning' ||
            (item.errorMessage != null && item.errorMessage!.isNotEmpty);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Header row: Cover + Artist / Album + Delete
              Row(
                children: <Widget>[
                  if (isSelecting) ...[
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => onTap(),
                    ),
                    const SizedBox(width: 4),
                  ],
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: coverUrl != null
                          ? AtriumNetworkImage(
                              imageUrl: coverUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Container(
                                color: cs.surfaceContainerHighest,
                                child: Icon(
                                  Icons.album_outlined,
                                  size: 24,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            )
                          : Container(
                              color: cs.surfaceContainerHighest,
                              child: Icon(
                                Icons.album_outlined,
                                size: 24,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.album?.title ?? item.title ?? 'Download Item',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 1),
                        Text(
                          <String>[
                            if (item.artist?.artistName != null)
                              item.artist!.artistName!,
                            protocolStr,
                            qualityName,
                          ].join(' • '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!isSelecting)
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 18,
                        color: cs.onSurfaceVariant,
                      ),
                      tooltip: 'Remove from Queue',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: onRemove,
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Progress bar
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 3.5,
                  backgroundColor: cs.surfaceContainerHighest,
                  color: hasError ? cs.error : cs.primary,
                ),
              ),
              const SizedBox(height: 4),

              // Progress stats & ETA
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    '${LidarrFormatters.formatBytes(size - sizeLeft)} / ${LidarrFormatters.formatBytes(size)} • $statusStr',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: hasError ? cs.error : cs.onSurfaceVariant,
                      fontWeight:
                          hasError ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  Text(
                    item.timeleft != null && item.timeleft!.isNotEmpty
                        ? 'ETA: ${item.timeleft}'
                        : '${(progress * 100).toStringAsFixed(0)}%',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),

              if (hasError) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.errorContainer.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: cs.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.errorMessage ??
                              item.statusMessages?.firstOrNull?.messages
                                  ?.firstOrNull ??
                              item.statusMessages?.firstOrNull?.title ??
                              'Download warning',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onErrorContainer,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
