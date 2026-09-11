import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import '../../../core/lidarr_formatters.dart';
import '../../../generated/generated.dart';
import '../../../lidarr_artwork.dart';
import '../artist_detail_screen.dart';

/// Clean 3-line structured list tile for Lidarr artists.
class ArtistList extends StatelessWidget {
  const ArtistList({
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

    return SliverList.separated(
      itemCount: artists.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final ArtistResource artist = artists[index];
        final int artistId = artist.id ?? 0;
        final bool isSelected = selectedIds.contains(artistId);
        final String? posterUrl =
            LidarrArtwork.artistPosterUrl(instance, artist.images);
        final String? fanartUrl =
            LidarrArtwork.artistFanartUrl(instance, artist.images);

        final int albumCount = artist.statistics?.albumCount ?? 0;
        final int totalTracks = artist.statistics?.totalTrackCount ??
            artist.statistics?.trackCount ??
            0;
        final int tracks = artist.statistics?.trackFileCount ?? 0;
        final double progress =
            totalTracks > 0 ? (tracks / totalTracks).clamp(0.0, 1.0) : 0.0;
        final List<String> genres = artist.genres ?? const <String>[];
        final int? sizeOnDisk = artist.statistics?.sizeOnDisk;
        final bool isEnded =
            artist.status == ArtistStatusType.ended || artist.ended == true;
        final double? ratingVal = artist.ratings?.value;

        final List<String> statsParts = [
          '$albumCount ${albumCount == 1 ? 'album' : 'albums'}',
          if (sizeOnDisk != null && sizeOnDisk > 0)
            LidarrFormatters.formatBytes(sizeOnDisk),
          if (totalTracks > 0)
            '$tracks/$totalTracks trk (${(progress * 100).toInt()}%)'
          else
            '0 tracks',
        ];

        return Card(
          margin: EdgeInsets.zero,
          elevation: isSelected ? 3 : 0,
          color: isSelected
              ? cs.primaryContainer.withValues(alpha: 0.25)
              : cs.surfaceContainerLow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: isSelected
                ? BorderSide(color: cs.primary, width: 1.5)
                : BorderSide.none,
          ),
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
            child: SizedBox(
              height: 86,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 1. Fanart Backdrop
                  if (fanartUrl != null)
                    Positioned.fill(
                      child: AtriumNetworkImage(
                        imageUrl: fanartUrl,
                        fit: BoxFit.cover,
                        alignment: Alignment.centerRight,
                        errorWidget: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  // 2. Surface Fade
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            cs.surface,
                            cs.surface.withValues(alpha: 0.94),
                            cs.surface.withValues(alpha: 0.35),
                          ],
                          stops: const [0.35, 0.72, 0.98],
                        ),
                      ),
                    ),
                  ),
                  // 3. Selection Tint Overlay
                  if (isSelected)
                    Positioned.fill(
                      child: Container(
                        color: cs.primary.withValues(alpha: 0.12),
                      ),
                    ),
                  // 4. Content Row
                  Row(
                    children: [
                      // Square Lead Artwork on Left
                      SizedBox(
                        width: 86,
                        height: 86,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            bottomLeft: Radius.circular(12),
                          ),
                          child: posterUrl != null
                              ? AtriumNetworkImage(
                                  imageUrl: posterUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => Container(
                                    color: cs.surfaceContainerHighest,
                                    child: const Center(
                                      child: Icon(Icons.music_note, size: 28),
                                    ),
                                  ),
                                )
                              : Container(
                                  color: cs.surfaceContainerHighest,
                                  child: const Center(
                                    child: Icon(Icons.person, size: 32),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 3-Line Vertical Column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Line 1: Name + Status Badge + Rating
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    artist.artistName ?? 'Unknown Artist',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (isEnded) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.errorContainer
                                          .withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      'ENDED',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: cs.onErrorContainer,
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                ],
                                if (ratingVal != null && ratingVal > 0) ...[
                                  const SizedBox(width: 6),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.star_rounded,
                                        size: 13,
                                        color: Colors.amber.shade600,
                                      ),
                                      const SizedBox(width: 2),
                                      Text(
                                        ratingVal.toStringAsFixed(1),
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            // Line 2: Disambiguation or Genres
                            Text(
                              artist.disambiguation != null &&
                                      artist.disambiguation!.isNotEmpty
                                  ? artist.disambiguation!
                                  : (genres.isNotEmpty
                                      ? genres.take(2).join(', ')
                                      : 'No description'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontSize: 11.5,
                              ),
                            ),
                            const SizedBox(height: 3),
                            // Line 3: Dedicated Stats Line
                            Text(
                              statsParts.join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color:
                                    cs.onSurfaceVariant.withValues(alpha: 0.85),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Trailing Monitored / Selection Indicator
                      Padding(
                        padding: const EdgeInsets.only(right: 12.0),
                        child: inSelectionMode
                            ? Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? cs.primary
                                      : cs.surface.withValues(alpha: 0.85),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: cs.shadow.withValues(alpha: 0.15),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.circle_outlined,
                                  color:
                                      isSelected ? cs.onPrimary : cs.onSurface,
                                  size: 22,
                                ),
                              )
                            : artist.monitored == true
                                ? Icon(
                                    Icons.bookmark,
                                    size: 16,
                                    color: cs.primary,
                                  )
                                : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  // 5. Bottom Collection Progress Bar
                  if (totalTracks > 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 2.5,
                        backgroundColor:
                            cs.outlineVariant.withValues(alpha: 0.2),
                        color: progress >= 1.0 ? cs.tertiary : cs.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
