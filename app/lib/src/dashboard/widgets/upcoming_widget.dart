import 'package:core_router/core_router.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../screens/calendar_screen.dart';
import '../dashboard_widget_card.dart';
import '../dashboard_widget_kind.dart';

/// First-of-month keys for every month the [now, now+7d] window touches.
List<DateTime> upcomingWindowMonths(DateTime now) {
  final DateTime start = DateTime(now.year, now.month, 1);
  final DateTime end =
      DateTime(now.year, now.month, now.day).add(const Duration(days: 8));
  final DateTime endMonth = DateTime(end.year, end.month, 1);
  return <DateTime>[start, if (endMonth != start) endMonth];
}

/// The next 7 days of Sonarr/Radarr releases as day-grouped artwork banners:
/// poster thumb, backdrop background, and a downloaded/pending status icon.
class DashboardUpcomingWidget extends ConsumerWidget {
  const DashboardUpcomingWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final DateTime now = DateTime.now();
    final DateTime windowStart = DateTime(now.year, now.month, now.day);
    final DateTime windowEnd = windowStart.add(const Duration(days: 8));
    final List<DateTime> months = upcomingWindowMonths(now);

    final List<CalendarEvent> events = <CalendarEvent>[];
    final Set<CalendarEvent> seen = <CalendarEvent>{};
    bool anyLoading = false;
    bool anyError = false;
    for (final DateTime month in months) {
      final AsyncValue<List<CalendarEvent>> value =
          ref.watch(globalCalendarProvider((month, false)));
      anyLoading |= value.isLoading && !value.hasValue;
      anyError |= value.hasError;
      for (final CalendarEvent e in value.value ?? const <CalendarEvent>[]) {
        if (seen.add(e)) {
          events.add(e);
        }
      }
    }

    final List<CalendarEvent> upcoming = events.where((CalendarEvent e) {
      final DateTime d = e.date.toLocal();
      return !d.isBefore(windowStart) && d.isBefore(windowEnd);
    }).toList()
      ..sort((CalendarEvent a, CalendarEvent b) => a.date.compareTo(b.date));
    final List<CalendarEvent> top = upcoming.take(5).toList();

    Widget body;
    if (upcoming.isEmpty && anyLoading) {
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
    } else if (upcoming.isEmpty && anyError) {
      body = DashboardErrorRow(
        onRetry: () {
          for (final DateTime m in months) {
            ref.invalidate(globalCalendarProvider((m, false)));
          }
        },
      );
    } else if (upcoming.isEmpty) {
      body = const DashboardIdleRow(text: 'Nothing airing in the next 7 days');
    } else {
      final List<Widget> rows = <Widget>[];
      DateTime? lastDay;
      for (final CalendarEvent e in top) {
        final DateTime d = e.date.toLocal();
        final DateTime day = DateTime(d.year, d.month, d.day);
        if (lastDay == null || day != lastDay) {
          lastDay = day;
          final bool isToday = day == windowStart;
          rows.add(Padding(
            padding: EdgeInsets.only(
              top: rows.isEmpty ? 2 : Insets.md,
              bottom: Insets.sm,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: isToday ? cs.primary : cs.outline,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: Insets.sm),
                Text(
                  _dayLabel(day, windowStart),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isToday ? cs.primary : cs.onSurface,
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(child: Container(height: 1, color: cs.outlineVariant)),
              ],
            ),
          ));
        } else {
          rows.add(const SizedBox(height: Insets.sm));
        }
        rows.add(_ReleaseBanner(event: e));
      }
      if (upcoming.length > top.length) {
        rows.add(Padding(
          padding: const EdgeInsets.only(top: Insets.sm),
          child:
              DashboardIdleRow(text: '+${upcoming.length - top.length} more'),
        ));
      }
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      );
    }

    return DashboardWidgetCard(
      kind: DashboardWidgetKind.upcoming,
      accent: cs.secondary,
      onTap: () => context.goNamed(AtriumRoutes.calendarName),
      trailing: upcoming.isNotEmpty
          ? DashboardPill(
              icon: Icons.calendar_today_outlined,
              label:
                  '${upcoming.length} release${upcoming.length == 1 ? '' : 's'}',
              color: cs.primary,
            )
          : null,
      child: body,
    );
  }

  static String _dayLabel(DateTime day, DateTime today) {
    if (day == today) {
      return 'Today';
    }
    if (day == today.add(const Duration(days: 1))) {
      return 'Tomorrow';
    }
    return DateFormat('EEE, MMM d').format(day);
  }
}

/// One release as an artwork banner: fanart backdrop with a legibility scrim,
/// poster thumb, title + meta line, and a trailing badge - a check for a
/// grabbed release, an airtime chip for an episode still to air.
class _ReleaseBanner extends StatelessWidget {
  const _ReleaseBanner({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String? backdrop = event.backdropUrl;
    final String? poster = event.posterUrl;
    final bool hasArt = backdrop != null;
    // Over a backdrop the scrim + text follow the theme: light mode gets a
    // light scrim with dark text (not a heavy black band), dark mode keeps the
    // classic dark scrim with white text. Either way the text stays legible.
    final bool isLight = theme.brightness == Brightness.light;
    final Color scrim = isLight ? Colors.white : Colors.black;
    final Color onArt = isLight ? const Color(0xFF141414) : Colors.white;
    final Color titleColor = hasArt ? onArt : cs.onSurface;
    final Color subColor =
        hasArt ? onArt.withValues(alpha: 0.78) : cs.onSurfaceVariant;
    // Episodes carry a real airtime; movie release dates do not.
    final String? airTime = event is SonarrCalendarEvent
        ? DateFormat.jm().format(event.date.toLocal())
        : null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 78,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (hasArt)
              AtriumNetworkImage(
                imageUrl: backdrop,
                fit: BoxFit.cover,
                memCacheWidth: 600,
                errorWidget: (_, __, ___) =>
                    Container(color: cs.surfaceContainerHighest),
              )
            else
              Container(color: cs.surfaceContainerHighest),
            if (hasArt)
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      scrim.withValues(alpha: 0.88),
                      scrim.withValues(alpha: 0.60),
                      scrim.withValues(alpha: 0.20),
                    ],
                    stops: const <double>[0.0, 0.55, 1.0],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: <Widget>[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 44,
                      height: 66,
                      child: poster == null
                          ? _posterFallback(cs)
                          : AtriumNetworkImage(
                              imageUrl: poster,
                              fit: BoxFit.cover,
                              memCacheWidth: 132,
                              errorWidget: (_, __, ___) => _posterFallback(cs),
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
                          event.primaryTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          event.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: subColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  _StatusBadge(
                    hasArt: hasArt,
                    hasFile: event.hasFile,
                    airTime: airTime,
                    onArt: onArt,
                    scrim: scrim,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _posterFallback(ColorScheme cs) => Container(
        color: cs.surfaceContainerHigh,
        alignment: Alignment.center,
        child: Icon(Icons.movie_outlined, size: 18, color: cs.onSurfaceVariant),
      );
}

/// Trailing status on a release banner: a check for a grabbed release, an
/// airtime chip for an episode still to air, nothing otherwise.
class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.hasArt,
    required this.hasFile,
    required this.airTime,
    required this.onArt,
    required this.scrim,
  });

  final bool hasArt;
  final bool hasFile;
  final String? airTime;

  /// Legible foreground over the scrim for the current theme (white in dark
  /// mode, near-black in light mode).
  final Color onArt;

  /// The scrim base tone (opposite of [onArt]): black in dark mode, white in
  /// light mode. Used as the inverted, low-opacity airtime-box fill.
  final Color scrim;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    if (hasFile) {
      // A frosted plate (theme-aware) so the green check reads on the weak
      // right side of the scrim in either mode.
      final Color plate = hasArt ? onArt : cs.tertiary;
      return Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: plate.withValues(alpha: hasArt ? 0.22 : 0.16),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.check_rounded, size: 18, color: cs.tertiary),
      );
    }
    if (airTime != null) {
      // Inverted, low-opacity plate: the box takes the scrim tone (opposite of
      // the text) at a light alpha, keeping the on-art tone for icon + label.
      final Color fg = hasArt ? onArt : cs.onSurfaceVariant;
      final Color box = hasArt ? scrim : cs.surface;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: box.withValues(alpha: hasArt ? 0.14 : 0.55),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.schedule_rounded, size: 12, color: fg),
            const SizedBox(width: 3),
            Text(
              airTime!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
