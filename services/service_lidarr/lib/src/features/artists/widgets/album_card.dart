import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/lidarr_formatters.dart';
import '../../../generated/generated.dart';
import '../../../lidarr_api.dart';
import '../../../lidarr_artwork.dart';
import '../../../lidarr_providers.dart';
import '../../albums/album_detail_screen.dart';
import '../../search/interactive_search_screen.dart';
import '../../track_files/rename_dialog.dart';
import '../../track_files/retag_dialog.dart';
import '../../track_files/track_file_editor_screen.dart';
import '../edit_album_sheet.dart';

/// Opens the M3 modal action sheet for a Lidarr album.
void showLidarrAlbumActionSheet(
  BuildContext context, {
  required Instance instance,
  required int artistId,
  required AlbumResource album,
  required WidgetRef ref,
}) {
  final ThemeData theme = Theme.of(context);
  final ColorScheme cs = theme.colorScheme;

  final String? coverUrl = LidarrArtwork.albumCoverUrl(instance, album.images);
  final String year =
      album.releaseDate != null ? album.releaseDate!.split('-').first : '';
  final int trackFiles = album.statistics?.trackFileCount ?? 0;
  final int totalTracks = album.statistics?.totalTrackCount ?? 0;
  final String sizeStr =
      LidarrFormatters.formatBytes(album.statistics?.sizeOnDisk);

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (BuildContext ctx) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row: Cover Art + Title + Category / Year / Progress
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 56,
                      height: 56,
                      child: coverUrl != null
                          ? AtriumNetworkImage(
                              imageUrl: coverUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  const Icon(Icons.album_outlined, size: 28),
                            )
                          : Container(
                              color: cs.surfaceContainerHighest,
                              child: const Icon(Icons.album_outlined, size: 28),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          album.title ?? 'Album',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (album.albumType != null) album.albumType!,
                            if (year.isNotEmpty) year,
                            if (sizeStr.isNotEmpty) sizeStr,
                          ].join(' • '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$trackFiles / $totalTracks tracks (${totalTracks > 0 ? ((trackFiles / totalTracks) * 100).toInt() : 0}%)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Primary Actions Bar: [ Auto Search ] & [ Interactive Search ]
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Auto Search'),
                      onPressed: () async {
                        Navigator.pop(ctx);
                        final int? albumId = album.id;
                        if (albumId == null) return;
                        try {
                          final LidarrApi api = await ref
                              .read(lidarrApiProvider(instance).future);
                          final resp = await api.executeCommand(
                            'AlbumSearch',
                            {
                              'albumIds': [albumId],
                            },
                          );
                          if (!resp.isSuccess) {
                            throw Exception(
                              resp.error?.message ?? 'Failed to search album',
                            );
                          }
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content:
                                    Text('Searching for "${album.title}"...'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Failed to search album: $e'),
                                backgroundColor: cs.error,
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      icon: const Icon(Icons.manage_search_outlined, size: 18),
                      label: const Text('Interactive'),
                      onPressed: () {
                        Navigator.pop(ctx);
                        LidarrInteractiveSearchScreen.show(
                          context,
                          instance: instance,
                          title: album.title ?? 'Album',
                          albumId: album.id,
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 4),

              // Secondary Actions List
              ListTile(
                dense: true,
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit Album'),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(ctx);
                  showLidarrEditAlbumSheet(
                    context,
                    instance: instance,
                    artistId: artistId,
                    album: album,
                    artistName: album.artist?.artistName,
                  );
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.audio_file_outlined),
                title: const Text('Track Files Editor'),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(ctx);
                  LidarrTrackFileEditorScreen.show(
                    context,
                    instance: instance,
                    artistId: artistId,
                    albumId: album.id,
                    albumTitle: album.title,
                  );
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Rename Files'),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(ctx);
                  showLidarrRenameDialog(
                    context,
                    instance: instance,
                    artistId: artistId,
                    albumId: album.id,
                    albumTitle: album.title,
                  );
                },
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.label_outlined),
                title: const Text('Retag Files'),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(ctx);
                  showLidarrRetagDialog(
                    context,
                    instance: instance,
                    artistId: artistId,
                    albumId: album.id,
                    albumTitle: album.title,
                  );
                },
              ),
              ListTile(
                dense: true,
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text(
                  'Delete Album',
                  style: TextStyle(color: cs.error),
                ),
                contentPadding: EdgeInsets.zero,
                onTap: () {
                  Navigator.pop(ctx);
                  showLidarrDeleteAlbumDialog(
                    context,
                    instance: instance,
                    artistId: artistId,
                    album: album,
                    ref: ref,
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Expandable album card featuring monitoring toggles, track progress, and contextual actions.
class AlbumCard extends ConsumerStatefulWidget {
  const AlbumCard({
    required this.instance,
    required this.artistId,
    required this.album,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onSelect,
    this.onLongPress,
    super.key,
  });

  final Instance instance;
  final int artistId;
  final AlbumResource album;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onSelect;
  final VoidCallback? onLongPress;

  @override
  ConsumerState<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends ConsumerState<AlbumCard> {
  Future<void> _toggleMonitored() async {
    final bool newMonitored = !(widget.album.monitored ?? false);
    final int? albumId = widget.album.id;
    if (albumId == null) return;

    try {
      final LidarrApi api =
          await ref.read(lidarrApiProvider(widget.instance).future);
      final ApiResponse<void> resp = await api.album.putAlbumMonitor(
        body: AlbumsMonitoredResource(
          albumIds: [albumId],
          monitored: newMonitored,
        ),
      );
      if (!resp.isSuccess) {
        throw Exception(resp.error?.message ?? 'Failed to toggle album');
      }

      ref.invalidate(
        lidarrAlbumsForArtistProvider((widget.instance, widget.artistId)),
      );
      ref.invalidate(
        lidarrArtistByIdProvider((widget.instance, widget.artistId)),
      );
      ref.invalidate(lidarrArtistsProvider(widget.instance));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to toggle album: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _navigateToAlbum() {
    final int? albumId = widget.album.id;
    if (albumId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => AlbumDetailScreen(
          instance: widget.instance,
          artistId: widget.artistId,
          albumId: albumId,
          initialAlbum: widget.album,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final String? coverUrl =
        LidarrArtwork.albumCoverUrl(widget.instance, widget.album.images);
    final String year = widget.album.releaseDate != null
        ? widget.album.releaseDate!.split('-').first
        : '';

    final bool isMonitored = widget.album.monitored ?? false;
    final int trackFiles = widget.album.statistics?.trackFileCount ?? 0;
    final int totalTracks = widget.album.statistics?.totalTrackCount ?? 0;
    final double progress =
        totalTracks > 0 ? (trackFiles / totalTracks).clamp(0.0, 1.0) : 0.0;
    final bool isMultiDisc =
        widget.album.mediumCount != null && widget.album.mediumCount! > 1;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      color: widget.isSelected
          ? cs.primaryContainer.withValues(alpha: 0.25)
          : cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: widget.isSelected
            ? BorderSide(color: cs.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.isSelectionMode ? widget.onSelect : _navigateToAlbum,
        onLongPress: widget.isSelectionMode
            ? widget.onSelect
            : (widget.onLongPress ??
                () => showLidarrAlbumActionSheet(
                      context,
                      instance: widget.instance,
                      artistId: widget.artistId,
                      album: widget.album,
                      ref: ref,
                    )),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // 54x54 Squircle Album Cover Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: coverUrl != null
                      ? AtriumNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              Icons.album_outlined,
                              size: 28,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.album_outlined,
                            size: 28,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),

              // Title, Metadata, Status Chip
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.album.title ?? 'Unknown Album',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            [
                              if (year.isNotEmpty) year,
                              '$trackFiles/$totalTracks tracks',
                              if (isMultiDisc)
                                '${widget.album.mediumCount} discs',
                            ].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (totalTracks > 0 && progress >= 1.0)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: cs.tertiaryContainer.withValues(
                                alpha: 0.35,
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '100%',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: cs.tertiary,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (totalTracks > 0 && progress < 1.0) ...[
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 2.5,
                          backgroundColor: cs.surfaceContainerHighest,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),

              // Trailing Controls: [ Selection Checkbox ] or [ 🔖 Monitor ] [ ⋮ Options ]
              if (widget.isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(
                    widget.isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: widget.isSelected ? cs.primary : cs.outline,
                    size: 24,
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: isMonitored ? 'Monitored' : 'Unmonitored',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: Icon(
                        isMonitored ? Icons.bookmark : Icons.bookmark_border,
                        color: isMonitored ? cs.primary : cs.outline,
                        size: 20,
                      ),
                      onPressed: _toggleMonitored,
                    ),
                    IconButton(
                      tooltip: 'Album options',
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      icon: const Icon(Icons.more_vert, size: 18),
                      onPressed: () => showLidarrAlbumActionSheet(
                        context,
                        instance: widget.instance,
                        artistId: widget.artistId,
                        album: widget.album,
                        ref: ref,
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
}
