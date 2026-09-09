import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../../generated/generated.dart';
import '../../../lidarr_artwork.dart';

/// Clean, high-density media tile representing a wanted album with monitoring toggle,
/// quick search actions, and batch selection.
class WantedAlbumCard extends StatelessWidget {
  const WantedAlbumCard({
    required this.instance,
    required this.album,
    required this.onToggleMonitored,
    required this.onSearch,
    required this.onInteractiveSearch,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.onToggleSelected,
    this.onTap,
    super.key,
  });

  final Instance instance;
  final AlbumResource album;
  final VoidCallback onToggleMonitored;
  final VoidCallback onSearch;
  final VoidCallback onInteractiveSearch;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onToggleSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final String? coverUrl =
        LidarrArtwork.albumCoverUrl(instance, album.images);
    final bool isMonitored = album.monitored ?? true;
    final String releaseYear =
        album.releaseDate != null ? album.releaseDate!.split('-').first : '';
    final String albumType = album.albumType ?? 'Album';
    final String artistName = album.artist?.artistName ?? '';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      color: isSelected
          ? cs.primaryContainer.withValues(alpha: 0.3)
          : cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: cs.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isSelectionMode ? onToggleSelected : onTap,
        onLongPress: onToggleSelected,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              if (isSelectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: Checkbox(
                      value: isSelected,
                      visualDensity: VisualDensity.compact,
                      onChanged: (_) => onToggleSelected?.call(),
                    ),
                  ),
                ),

              // 52x52 Squircle Album Artwork
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: coverUrl != null
                      ? AtriumNetworkImage(
                          imageUrl: coverUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              Icons.album_outlined,
                              size: 26,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.album_outlined,
                            size: 26,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),

              // Title, Artist Name & Metadata
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      album.title ?? 'Unknown Album',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (artistName.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        artistName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                          fontSize: 12.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (releaseYear.isNotEmpty) releaseYear,
                        if (albumType.isNotEmpty) albumType,
                      ].join(' • '),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                        fontSize: 11,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              // Trailing Controls (when not selecting)
              if (!isSelectionMode) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: isMonitored ? 'Monitored' : 'Unmonitored',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: Icon(
                    isMonitored
                        ? Icons.bookmark
                        : Icons.bookmark_border_outlined,
                    color: isMonitored ? cs.primary : cs.outline,
                    size: 20,
                  ),
                  onPressed: onToggleMonitored,
                ),
                IconButton(
                  tooltip: 'Interactive Search',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: Icon(
                    Icons.manage_search,
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                  onPressed: onInteractiveSearch,
                ),
                IconButton(
                  tooltip: 'Auto Search',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  icon: Icon(
                    Icons.search,
                    color: cs.onSurfaceVariant,
                    size: 20,
                  ),
                  onPressed: onSearch,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
