import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import '../../models/tracearr_models.dart';
import '../screens/tracearr_media_detail_screen.dart';

/// 2:3 aspect ratio poster tile for recently added media in grid view.
class RecentlyAddedPosterTile extends StatelessWidget {
  const RecentlyAddedPosterTile({
    required this.instance,
    required this.item,
    super.key,
  });

  final Instance instance;
  final TracearrRecentlyAddedItem item;

  String _formatRelativeTime(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays > 365) {
      return '${(diff.inDays / 365).floor()}y ago';
    } else if (diff.inDays > 30) {
      return '${(diff.inDays / 30).floor()}mo ago';
    } else if (diff.inDays > 0) {
      return '${diff.inDays}d ago';
    } else if (diff.inHours > 0) {
      return '${diff.inHours}h ago';
    } else if (diff.inMinutes > 0) {
      return '${diff.inMinutes}m ago';
    }
    return 'just now';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final posterUrl = item.resolvedPosterUrl;
    final timeStr = _formatRelativeTime(item.addedAt);
    final isTv = item.mediaType == 'show' || item.mediaType == 'episode';

    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () {
        final mediaRef = item.mediaId ?? item.ratingKey ?? item.id;
        TracearrMediaDetailScreen.navigate(
          context,
          instance: instance,
          mediaRef: mediaRef,
          initialTitle: item.title,
          initialPosterUrl: posterUrl,
          initialSeasonNumber: item.seasonNumber,
          initialEpisodeNumber: item.episodeNumber,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poster Artwork Container (2:3 Aspect Ratio)
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.md),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (posterUrl != null && posterUrl.isNotEmpty)
                    AtriumNetworkImage(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      errorWidget: (context, url, error) => Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: Center(
                          child: Icon(
                            isTv ? Icons.tv : Icons.movie_outlined,
                            color: colorScheme.onSurfaceVariant,
                            size: 32,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Icon(
                          isTv ? Icons.tv : Icons.movie_outlined,
                          color: colorScheme.onSurfaceVariant,
                          size: 32,
                        ),
                      ),
                    ),
                  // Media Type & Year Badges
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child: Text(
                        item.mediaType.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  if (item.year != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        child: Text(
                          '${item.year}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Insets.xs),

          // Title
          Text(
            (item.seasonNumber != null && item.episodeNumber != null)
                ? 'S${item.seasonNumber}:E${item.episodeNumber} • ${item.title}'
                : item.title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (timeStr.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              'Added $timeStr',
              style: theme.textTheme.labelSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
