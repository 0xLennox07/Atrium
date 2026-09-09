import 'package:core_models/core_models.dart';
import 'package:core_router/core_router.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:service_seerr/service_seerr.dart';

import '../dashboard_widget_card.dart';
import '../dashboard_widget_kind.dart';

class _Request {
  const _Request({required this.request, required this.instance});

  final SeerrRequest request;
  final Instance instance;
}

/// Recent Seerr requests across every instance, newest first, each with its
/// poster and live availability status - not just the approval queue.
class DashboardRequestsWidget extends ConsumerWidget {
  const DashboardRequestsWidget({required this.instances, super.key});

  final List<Instance> instances;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    int totalRequested = 0;
    final List<_Request> requests = <_Request>[];
    bool anyLoading = false;
    bool anyError = false;

    for (final Instance i in instances) {
      final AsyncValue<SeerrCounts> counts =
          ref.watch(seerrRequestCountsProvider(i));
      totalRequested += counts.value?.total ?? 0;

      final AsyncValue<List<SeerrRequest>> list =
          ref.watch(seerrRequestsProvider(i));
      anyLoading |= list.isLoading && !list.hasValue;
      anyError |= list.hasError;
      for (final SeerrRequest r in list.value ?? const <SeerrRequest>[]) {
        requests.add(_Request(request: r, instance: i));
      }
    }

    requests.sort((_Request a, _Request b) {
      final DateTime da =
          DateTime.tryParse(a.request.createdAt ?? '') ?? DateTime(1970);
      final DateTime db =
          DateTime.tryParse(b.request.createdAt ?? '') ?? DateTime(1970);
      return db.compareTo(da);
    });
    final List<_Request> top = requests.take(3).toList();

    Widget body;
    if (requests.isEmpty && anyLoading) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(Insets.sm),
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    } else if (requests.isEmpty && anyError) {
      body = DashboardErrorRow(
        onRetry: () {
          for (final Instance i in instances) {
            ref.invalidate(seerrRequestCountsProvider(i));
            ref.invalidate(seerrRequestsProvider(i));
          }
        },
      );
    } else if (requests.isEmpty) {
      body = const DashboardIdleRow(text: 'No requests yet');
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (int j = 0; j < top.length; j++) ...<Widget>[
            if (j > 0) const SizedBox(height: Insets.sm),
            _RequestRow(request: top[j]),
          ],
          if (requests.length > top.length)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: DashboardIdleRow(
                  text: '+${requests.length - top.length} more'),
            ),
        ],
      );
    }

    return DashboardWidgetCard(
      kind: DashboardWidgetKind.requests,
      accent: cs.secondary,
      onTap: instances.length == 1
          ? () => context.go(
                AtriumRoutes.servicePath(
                  instances.first.kind.name,
                  instances.first.id,
                ),
              )
          : null,
      trailing: totalRequested > 0
          ? DashboardPill(
              icon: Icons.bookmark_added_outlined,
              label: '$totalRequested requested',
              color: cs.secondary,
            )
          : null,
      child: body,
    );
  }
}

/// A single request as a poster banner: artwork thumb, resolved title, the
/// requester, and an availability chip.
class _RequestRow extends ConsumerWidget {
  const _RequestRow({required this.request});

  final _Request request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final SeerrRequest r = request.request;

    // Resolve the title + poster like the Seerr requests tab does; fall back
    // to the request type while it loads or when there is no tmdb id.
    final int? tmdbId = r.media?.tmdbId;
    String title = r.type == 'movie' ? 'Movie request' : 'Series request';
    String? posterPath;
    if (tmdbId != null) {
      final String mediaType =
          (r.media?.mediaType ?? '').isNotEmpty ? r.media!.mediaType : r.type;
      final SeerrDiscoverResult? details = ref
          .watch(seerrMediaDetailsProvider(
            (instance: request.instance, mediaType: mediaType, tmdbId: tmdbId),
          ))
          .value;
      if (details != null) {
        title = details.displayTitle;
        posterPath = details.posterPath;
      }
    }
    final SeerrApi? api = ref.watch(seerrApiProvider(request.instance)).value;
    final String? posterUrl = api?.imageUrl(posterPath, size: 'w185');
    final String by = r.requestedBy?.displayName ?? '';
    final (String statusLabel, Color statusColor) = _status(r, cs);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => context.go(
        AtriumRoutes.servicePath(
          request.instance.kind.name,
          request.instance.id,
        ),
      ),
      child: Row(
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 40,
              height: 56,
              child: posterUrl == null
                  ? _posterFallback(cs, r.type)
                  : AtriumNetworkImage(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 120,
                      errorWidget: (_, __, ___) => _posterFallback(cs, r.type),
                    ),
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Row(
                  children: <Widget>[
                    _StatusChip(label: statusLabel, color: statusColor),
                    if (by.isNotEmpty) ...<Widget>[
                      const SizedBox(width: Insets.sm),
                      Flexible(
                        child: Text(
                          by,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
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
    );
  }

  Widget _posterFallback(ColorScheme cs, String type) => Container(
        color: cs.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          type == 'movie' ? Icons.movie_outlined : Icons.live_tv_outlined,
          size: 18,
          color: cs.onSurfaceVariant,
        ),
      );

  /// Request state -> (label, colour). Approval status wins; otherwise the
  /// media availability status (1 unknown, 2 pending, 3 processing, 4 partial,
  /// 5 available) is surfaced.
  (String, Color) _status(SeerrRequest r, ColorScheme cs) {
    if (r.status == 3) {
      return ('Declined', cs.onSurfaceVariant);
    }
    if (r.status == 1) {
      return ('Needs approval', cs.primary);
    }
    return switch (r.media?.status ?? 1) {
      5 => ('Available', cs.tertiary),
      4 => ('Partial', cs.tertiary),
      3 => ('Processing', cs.secondary),
      _ => ('Requested', cs.onSurfaceVariant),
    };
  }
}

/// A compact filled status chip for a request row.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
