import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';

import 'models/seerr_discover.dart';
import 'seerr_api.dart';
import 'seerr_status_badge.dart';

/// The shared tonal poster card used by the Discover rows: a rounded poster
/// with the availability badge and rating overlaid, then the title and date
/// below. Designed to sit inside a fixed-height horizontal row.
class SeerrMediaCard extends StatelessWidget {
  const SeerrMediaCard({
    required this.item,
    required this.api,
    this.onTap,
    this.width = 128,
    super.key,
  });

  final SeerrDiscoverResult item;

  /// Builds the artwork URL. Null while the API is still loading, and the card
  /// shows its placeholder.
  final SeerrApi? api;

  /// Tap handler (usually a push to the item detail screen).
  final VoidCallback? onTap;

  final double width;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Material(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(Radii.lg),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onTap,
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    if (api?.imageUrl(item.posterPath) != null)
                      AtriumNetworkImage(
                        imageUrl: api!.imageUrl(item.posterPath)!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => const _PosterFallback(),
                      )
                    else
                      const _PosterFallback(),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: SeerrStatusBadge(status: item.mediaInfo?.status),
                    ),
                    if (item.voteAverage != null && item.voteAverage! > 0)
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: _RatingBadge(value: item.voteAverage!),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            item.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (item.displayDate != null)
            Text(
              item.displayDate!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.movie_outlined)),
    );
  }
}

/// Small rating pill (star + score) overlaid on a poster; white-on-scrim per
/// the over-imagery rules.
class _RatingBadge extends StatelessWidget {
  const _RatingBadge({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.star, size: 11, color: Colors.amber),
          const SizedBox(width: 3),
          Text(
            value.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A small rounded metadata pill (year, type, status, runtime, genre).
class SeerrInfoPill extends StatelessWidget {
  const SeerrInfoPill({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label, style: theme.textTheme.labelMedium),
    );
  }
}

/// The Requests-tab tile: a tonal card with the poster on the left, the
/// title / requester / color-coded status pills beside it, and an optional
/// inline [actions] row (approve / decline / delete) underneath.
class SeerrRequestCard extends StatelessWidget {
  const SeerrRequestCard({
    required this.item,
    required this.api,
    this.requestedBy,
    this.mediaStatus,
    this.requestStatus,
    this.trailing,
    this.actions,
    super.key,
  });

  final SeerrDiscoverResult item;

  /// Builds the artwork URLs. Null while the API is still loading, and the card
  /// falls back to its placeholders.
  final SeerrApi? api;

  /// Requester display name, shown next to a person icon.
  final String? requestedBy;

  /// Seerr media (download) status: 2 requested, 3 processing, 4 partially
  /// available, 5 available.
  final int? mediaStatus;

  /// Request approval status: 1 pending, 2 approved, 3 declined, 4 failed.
  final int? requestStatus;

  /// Optional top-right widget (the request actions menu).
  final Widget? trailing;

  /// Optional inline actions row rendered below the poster + info.
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<Widget> pills = _statusPills();
    final String? backdrop = item.backdropPath;
    final bool over = backdrop != null;
    // Text sits over the darkened backdrop when present, else over the tonal
    // surface - pick legible colors for each case.
    final Color titleColor = over ? Colors.white : cs.onSurface;
    final Color subColor = over ? Colors.white70 : cs.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: <Widget>[
          if (api?.imageUrl(backdrop, size: 'w780') != null)
            Positioned.fill(
              child: AtriumNetworkImage(
                imageUrl: api!.imageUrl(backdrop, size: 'w780')!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          // Darken left-to-right so the overlaid title/requester stay legible
          // over the backdrop while the poster on the right shows through.
          if (over)
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    stops: <double>[0.0, 0.6, 1.0],
                    colors: <Color>[
                      Color(0xE6000000),
                      Color(0x99000000),
                      Color(0x59000000),
                    ],
                  ),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          if (item.year != null)
                            Text(
                              item.year!,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: subColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          Padding(
                            // keep the title clear of the trailing menu
                            padding: EdgeInsets.only(
                              right: trailing != null ? 32 : 0,
                            ),
                            child: Text(
                              item.displayTitle,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: titleColor,
                                fontWeight: FontWeight.bold,
                                height: 1.15,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (requestedBy != null &&
                              requestedBy!.isNotEmpty) ...<Widget>[
                            const SizedBox(height: Insets.xs),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(
                                  Icons.person_outline,
                                  size: 16,
                                  color: subColor,
                                ),
                                const SizedBox(width: Insets.xs),
                                Flexible(
                                  child: Text(
                                    requestedBy!,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: subColor),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (pills.isNotEmpty) ...<Widget>[
                            const SizedBox(height: Insets.sm),
                            Wrap(spacing: 6, runSpacing: 4, children: pills),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: Insets.md),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.md),
                      child: SizedBox(
                        width: 76,
                        height: 114,
                        child: api?.imageUrl(item.posterPath) != null
                            ? AtriumNetworkImage(
                                imageUrl: api!.imageUrl(item.posterPath)!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) =>
                                    _posterFallback(cs),
                              )
                            : _posterFallback(cs),
                      ),
                    ),
                  ],
                ),
                if (actions != null) ...<Widget>[
                  const SizedBox(height: Insets.sm),
                  actions!,
                ],
              ],
            ),
          ),
          if (trailing != null) Positioned(top: 4, right: 4, child: trailing!),
        ],
      ),
    );
  }

  Widget _posterFallback(ColorScheme cs) => ColoredBox(
        color: cs.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.image_not_supported)),
      );

  List<Widget> _statusPills() {
    final List<Widget> pills = <Widget>[];
    final SeerrStatusStyle? media = seerrMediaStatusStyle(mediaStatus);
    if (media != null) {
      pills.add(SeerrStatusPill(style: media));
    }
    final SeerrStatusStyle? approval = seerrRequestStatusStyle(requestStatus);
    // 'Approved' only adds information when no availability pill is shown.
    if (approval != null && !(requestStatus == 2 && media != null)) {
      pills.add(SeerrStatusPill(style: approval));
    }
    return pills;
  }
}
