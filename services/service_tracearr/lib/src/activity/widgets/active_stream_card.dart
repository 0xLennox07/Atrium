import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import '../../media/screens/tracearr_media_detail_screen.dart';
import '../../models/tracearr_models.dart';
import '../../people/screens/tracearr_user_dossier_screen.dart';
import 'stream_diagnostics_sheet.dart';
import 'terminate_stream_dialog.dart';

/// Dense, interactive card for an active playback stream.
class ActiveStreamCard extends StatelessWidget {
  const ActiveStreamCard({
    required this.instance,
    required this.stream,
    super.key,
  });

  final Instance instance;
  final TracearrStream stream;

  String _formatDuration(int? ms) {
    if (ms == null || ms <= 0) return '0:00';
    final duration = Duration(milliseconds: ms);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final double progressPercent = stream.percentComplete != null
        ? (stream.percentComplete! / 100.0).clamp(0.0, 1.0)
        : (stream.progressMs != null &&
                stream.durationMs != null &&
                stream.durationMs! > 0)
            ? (stream.progressMs! / stream.durationMs!).clamp(0.0, 1.0)
            : 0.0;

    final String progressText =
        '${_formatDuration(stream.progressMs)} / ${_formatDuration(stream.durationMs)} • ${(progressPercent * 100).toStringAsFixed(0)}%';

    final bool isHw = stream.isHwTranscode ||
        (stream.hwDecoding != null && stream.hwDecoding!.isNotEmpty) ||
        (stream.hwEncoding != null && stream.hwEncoding!.isNotEmpty);

    final String vDec = stream.videoDecision?.toLowerCase() ?? '';
    final bool isDirectStream = vDec == 'copy' ||
        (stream.isTranscode &&
            stream.audioDecision?.toLowerCase() == 'transcode' &&
            vDec != 'transcode');
    final bool isDirectPlay = (vDec == 'directplay' ||
            (vDec.isEmpty && !stream.isTranscode)) &&
        !isDirectStream;

    final String transcodeLabel = isDirectPlay
        ? 'Direct Play'
        : isDirectStream
            ? 'Direct Stream'
            : isHw
                ? 'HW Transcode'
                : 'CPU Transcode';

    final Color transcodeColor = isDirectPlay
        ? const Color(0xFF4CAF50)
        : isDirectStream
            ? const Color(0xFF00BCD4)
            : isHw
                ? const Color(0xFF2196F3)
                : const Color(0xFFFF9800);

    final int bitrate = stream.bitrate ?? 0;
    final String bitrateText = bitrate >= 1000
        ? '${(bitrate / 1000).toStringAsFixed(1)} Mbps'
        : '$bitrate kbps';

    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(Radii.md),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => StreamDiagnosticsSheet.show(
          context,
          instance: instance,
          stream: stream,
        ),
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Poster + Title + User + Actions
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Poster Thumbnail
                  GestureDetector(
                    onTap: () => TracearrMediaDetailScreen.navigate(
                      context,
                      instance: instance,
                      mediaRef: stream.mediaId ?? stream.ratingKey ?? stream.id,
                      initialTitle: stream.mediaTitle,
                      initialShowTitle: stream.showTitle,
                      initialPosterUrl: stream.posterUrl,
                      initialSeasonNumber: stream.seasonNumber,
                      initialEpisodeNumber: stream.episodeNumber,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.sm),
                      child: SizedBox(
                        width: 48,
                        height: 72,
                        child: stream.posterUrl != null &&
                                stream.posterUrl!.isNotEmpty
                            ? AtriumNetworkImage(
                                imageUrl: stream.posterUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  color: colorScheme.surfaceContainerHighest,
                                  child: Icon(
                                    Icons.movie_outlined,
                                    color: colorScheme.onSurfaceVariant,
                                    size: 24,
                                  ),
                                ),
                                placeholder: (_, __) => Container(
                                  color: colorScheme.surfaceContainerHighest,
                                ),
                              )
                            : Container(
                                color: colorScheme.surfaceContainerHighest,
                                child: Icon(
                                  Icons.movie_outlined,
                                  color: colorScheme.onSurfaceVariant,
                                  size: 24,
                                ),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  // Title and metadata
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (stream.seasonNumber != null &&
                                  stream.episodeNumber != null)
                              ? 'S${stream.seasonNumber}:E${stream.episodeNumber} • ${stream.mediaTitle}'
                              : stream.mediaTitle,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (stream.showTitle != null &&
                            stream.showTitle!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            stream.showTitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ] else if (stream.year != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${stream.year}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () => TracearrUserDossierScreen.navigate(
                                context,
                                instance: instance,
                                userId: stream.userId ?? stream.userUsername,
                                username: stream.userUsername,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 9,
                                    backgroundColor:
                                        colorScheme.primaryContainer,
                                    child: stream.userAvatarUrl != null &&
                                            stream.userAvatarUrl!.isNotEmpty
                                        ? ClipOval(
                                            child: AtriumNetworkImage(
                                              imageUrl: stream.userAvatarUrl!,
                                              width: 18,
                                              height: 18,
                                              fit: BoxFit.cover,
                                              errorWidget: (c, u, e) => Text(
                                                stream.userUsername.isNotEmpty
                                                    ? stream.userUsername[0]
                                                        .toUpperCase()
                                                    : 'U',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: colorScheme
                                                      .onPrimaryContainer,
                                                ),
                                              ),
                                            ),
                                          )
                                        : Text(
                                            stream.userUsername.isNotEmpty
                                                ? stream.userUsername[0]
                                                    .toUpperCase()
                                                : 'U',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme
                                                  .onPrimaryContainer,
                                            ),
                                          ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '@${stream.userUsername}',
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: colorScheme.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (stream.device != null) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '• ${stream.device}',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Action button (Kill Stream)
                  IconButton(
                    icon: Icon(
                      Icons.stop_circle_outlined,
                      color: colorScheme.error,
                      size: 24,
                    ),
                    tooltip: 'Terminate Stream',
                    onPressed: () => TerminateStreamDialog.show(
                      context,
                      instance: instance,
                      stream: stream,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Insets.sm),

              // Progress Bar
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: progressPercent,
                  minHeight: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: Insets.xs),

              // Time and Badges Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    progressText,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: transcodeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: transcodeColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              transcodeLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: transcodeColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (bitrate > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(Radii.sm),
                          ),
                          child: Text(
                            bitrateText,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
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
