import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import '../../models/tracearr_models.dart';
import '../screens/tracearr_media_detail_screen.dart';

/// Dense horizontal card for recently added media in list view.
class RecentlyAddedCard extends StatelessWidget {
  const RecentlyAddedCard({
    required this.instance,
    required this.item,
    super.key,
  });

  final Instance instance;
  final TracearrRecentlyAddedItem item;

  String _formatAddedTime(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final posterUrl = item.resolvedPosterUrl;
    final timeStr = _formatAddedTime(item.addedAt);
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
      child: Container(
        padding: const EdgeInsets.all(Insets.sm),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            // Poster Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.sm),
              child: SizedBox(
                width: 48,
                height: 72,
                child: posterUrl != null && posterUrl.isNotEmpty
                    ? AtriumNetworkImage(
                        imageUrl: posterUrl,
                        fit: BoxFit.cover,
                        errorWidget: (c, u, e) => Container(
                          color: colorScheme.surfaceContainerHighest,
                          child: Icon(
                            isTv ? Icons.tv : Icons.movie_outlined,
                            size: 24,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(
                          isTv ? Icons.tv : Icons.movie_outlined,
                          size: 24,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: Insets.md),

            // Metadata
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (item.seasonNumber != null && item.episodeNumber != null)
                        ? 'S${item.seasonNumber}:E${item.episodeNumber} • ${item.title}'
                        : item.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        child: Text(
                          item.mediaType.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 9,
                          ),
                        ),
                      ),
                      if (item.year != null) ...[
                        const SizedBox(width: Insets.xs),
                        Text(
                          '${item.year}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (timeStr.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      'Added $timeStr',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
