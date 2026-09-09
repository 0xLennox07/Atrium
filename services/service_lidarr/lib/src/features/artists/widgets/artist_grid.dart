import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../../core/lidarr_formatters.dart';
import '../../../generated/generated.dart';
import '../../../lidarr_artwork.dart';
import '../artist_detail_screen.dart';

/// Grid view displaying artist cards with 1:1 square artwork, multi-selection support, and status badges.
class ArtistGrid extends StatelessWidget {
  const ArtistGrid({
    required this.instance,
    required this.artists,
    required this.selectedIds,
    required this.inSelectionMode,
    required this.onToggleSelection,
    super.key,
  });

  final Instance instance;
  final List<ArtistResource> artists;
  final Set<int> selectedIds;
  final bool inSelectionMode;
  final void Function(int artistId) onToggleSelection;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 150,
        childAspectRatio: 0.68,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final ArtistResource artist = artists[index];
          final int artistId = artist.id ?? 0;
          final bool isSelected = selectedIds.contains(artistId);
          final String? posterUrl =
              LidarrArtwork.artistPosterUrl(instance, artist.images);

          final int totalTracks = artist.statistics?.totalTrackCount ??
              artist.statistics?.trackCount ??
              0;
          final int trackFiles = artist.statistics?.trackFileCount ?? 0;
          final double progress = totalTracks > 0
              ? (trackFiles / totalTracks).clamp(0.0, 1.0)
              : 0.0;
          final int albumCount = artist.statistics?.albumCount ?? 0;
          final int? sizeOnDisk = artist.statistics?.sizeOnDisk;
          final bool isEnded =
              artist.status == ArtistStatusType.ended || artist.ended == true;

          return Card(
            elevation: isSelected ? 3 : 0,
            color: isSelected
                ? cs.primaryContainer.withValues(alpha: 0.25)
                : cs.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: isSelected
                  ? BorderSide(color: cs.primary, width: 1.5)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onLongPress: () => onToggleSelection(artistId),
              onTap: () {
                if (inSelectionMode) {
                  onToggleSelection(artistId);
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ArtistDetailScreen(
                        instance: instance,
                        artistId: artistId,
                        initialArtist: artist,
                      ),
                    ),
                  );
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1:1 Squircle Artwork Container with Progress Bar
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        posterUrl != null
                            ? AtriumNetworkImage(
                                imageUrl: posterUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: cs.surfaceContainerHighest,
                                  child: const Center(
                                    child: Icon(Icons.music_note, size: 36),
                                  ),
                                ),
                              )
                            : Container(
                                color: cs.surfaceContainerHighest,
                                child: const Center(
                                  child: Icon(Icons.person, size: 40),
                                ),
                              ),
                        // Gradient shadow at bottom of image
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 32,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  cs.scrim.withValues(alpha: 0.5),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Collection progress indicator along bottom of poster
                        if (totalTracks > 0)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 3.5,
                              backgroundColor: cs.scrim.withValues(alpha: 0.3),
                              color: progress >= 1.0 ? cs.tertiary : cs.primary,
                            ),
                          ),
                        // Ended status badge
                        if (isEnded && !inSelectionMode)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4.5,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    cs.errorContainer.withValues(alpha: 0.85),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'ENDED',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onErrorContainer,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ),
                        // Monitored badge
                        if (artist.monitored == true && !inSelectionMode)
                          Positioned(
                            top: 6,
                            right: 6,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: cs.surface.withValues(alpha: 0.85),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.shadow.withValues(alpha: 0.15),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.bookmark,
                                size: 13,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        // Multi-selection check badge
                        if (inSelectionMode)
                          Positioned(
                            top: 6,
                            left: 6,
                            child: Container(
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? cs.primary
                                    : cs.surface.withValues(alpha: 0.85),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.shadow.withValues(alpha: 0.2),
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                              child: Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.circle_outlined,
                                color: isSelected ? cs.onPrimary : cs.onSurface,
                                size: 22,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Metadata Section
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          artist.artistName ?? 'Unknown Artist',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                sizeOnDisk != null && sizeOnDisk > 0
                                    ? '$albumCount • ${LidarrFormatters.formatBytes(sizeOnDisk)}'
                                    : '$albumCount ${albumCount == 1 ? 'album' : 'albums'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            if (totalTracks > 0) ...[
                              Text(
                                ' • ',
                                style: TextStyle(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 10,
                                ),
                              ),
                              Text(
                                '${(progress * 100).toInt()}%',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: progress >= 1.0
                                      ? cs.tertiary
                                      : cs.primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        childCount: artists.length,
      ),
    );
  }
}
