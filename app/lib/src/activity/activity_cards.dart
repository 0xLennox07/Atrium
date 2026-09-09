import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import 'activity_providers.dart';

/// Backdrop card for one active stream: session art under a bottom-heavy
/// scrim, the watching user top-left, the source service (and transcode
/// decision) top-right, the title bottom-left, and a live progress bar
/// hugging the bottom edge. White/white70/black only over the image scrim.
class ActivityStreamCard extends StatelessWidget {
  const ActivityStreamCard({
    required this.stream,
    required this.onTap,
    this.instanceLabel,
    super.key,
  });

  final ActivityStream stream;
  final VoidCallback onTap;

  /// Set when more than one instance of the source service exists.
  final String? instanceLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? imageUrl = stream.imageUrl;
    final String meta = <String>[
      if ((stream.subtitle ?? '').isNotEmpty) stream.subtitle!,
      if (instanceLabel != null) instanceLabel!,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: Insets.md),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: SizedBox(
        height: 170,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (imageUrl != null && imageUrl.isNotEmpty)
                AtriumNetworkImage(
                  imageUrl: imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (BuildContext context, String _) => ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (BuildContext context, String _, Object __) =>
                      ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                )
              else
                ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
              // Bottom-heavy scrim: keeps the white overlay legible over any
              // backdrop (and over the plain fill when there is no art).
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.45),
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Insets.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(
                          child: Align(
                            alignment: Alignment.topLeft,
                            child: stream.userName == null
                                ? const SizedBox.shrink()
                                : _UserPill(
                                    name: stream.userName!,
                                    avatarUrl: stream.userAvatarUrl,
                                  ),
                          ),
                        ),
                        const SizedBox(width: Insets.sm),
                        _ScrimChip(label: stream.sourceKind.displayName),
                        if (stream.detailChip != null) ...<Widget>[
                          const SizedBox(width: Insets.xs),
                          _ScrimChip(label: stream.detailChip!, subdued: true),
                        ],
                      ],
                    ),
                    const Spacer(),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            stream.paused ? Icons.pause : Icons.play_arrow,
                            size: 18,
                            color: Colors.white70,
                          ),
                        ),
                        const SizedBox(width: Insets.xs),
                        Expanded(
                          child: Text(
                            stream.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (meta.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: Colors.white70),
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: stream.progress.clamp(0.0, 1.0),
                  minHeight: 5,
                  color: stream.paused
                      ? theme.colorScheme.outline
                      : theme.colorScheme.primary,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The watching user, as an avatar-or-initial plus name on a scrim pill.
class _UserPill extends StatelessWidget {
  const _UserPill({required this.name, required this.avatarUrl});

  final String name;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String initial =
        name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CircleAvatar(
            radius: 10,
            backgroundColor: Colors.black.withValues(alpha: 0.4),
            foregroundImage: (avatarUrl == null || avatarUrl!.isEmpty)
                ? null
                : atriumImageProvider(avatarUrl!),
            onForegroundImageError:
                (avatarUrl == null || avatarUrl!.isEmpty) ? null : (_, __) {},
            child: Text(
              initial,
              style: const TextStyle(fontSize: 10, color: Colors.white70),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill over imagery (service name / transcode decision). Black scrim
/// with white (or white70 when [subdued]) text, per the over-imagery rule.
class _ScrimChip extends StatelessWidget {
  const _ScrimChip({required this.label, this.subdued = false});

  final String label;
  final bool subdued;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: subdued ? Colors.white70 : Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Tonal card for one in-flight download: service icon in a tinted circle,
/// title, progress bar, then a status pill with speed / ETA meta.
class ActivityDownloadCard extends StatelessWidget {
  const ActivityDownloadCard({
    required this.download,
    required this.onTap,
    this.instanceLabel,
    super.key,
  });

  final ActivityDownload download;
  final VoidCallback onTap;

  /// Set when more than one instance of the source service exists.
  final String? instanceLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = ServiceVisuals.accent(download.sourceKind);
    final String meta = <String>[
      '${(download.progress * 100).round()}%',
      if (download.speedBps != null) '↓ ${fmtSpeedBps(download.speedBps!)}',
      if (download.upSpeedBps != null) '↑ ${fmtSpeedBps(download.upSpeedBps!)}',
      if (download.eta != null) download.eta!,
      if (instanceLabel != null) instanceLabel!,
    ].join(' · ');

    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  ServiceVisuals.icon(download.sourceKind),
                  size: 22,
                  color: accent,
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      download.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: Insets.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: download.progress.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Insets.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            download.status,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          ),
                        ),
                        const SizedBox(width: Insets.sm),
                        Expanded(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: theme.colorScheme.outline),
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
}

/// Compact error-container pills naming the instances that could not be
/// reached, shown under a section header without hiding healthy sources.
class ActivitySourceErrorChips extends StatelessWidget {
  const ActivitySourceErrorChips({required this.errors, super.key});

  final List<ActivitySourceError> errors;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.sm),
      child: Wrap(
        spacing: Insets.xs,
        runSpacing: Insets.xs,
        children: <Widget>[
          for (final ActivitySourceError error in errors)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${error.instance.name} unreachable',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
