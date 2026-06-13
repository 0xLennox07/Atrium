import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:service_sonarr/service_sonarr.dart';
import 'package:service_radarr/service_radarr.dart';

/// Aggregated calendar event representation.
sealed class CalendarEvent {
  const CalendarEvent(this.instance);
  final Instance instance;

  String get title;
  DateTime get date;
  bool get hasFile;
  bool get monitored;
}

class SonarrCalendarEvent extends CalendarEvent {
  const SonarrCalendarEvent(this.entry, super.instance);
  final SonarrCalendarEntry entry;

  @override
  String get title {
    final String s = (entry.seasonNumber ?? 0).toString().padLeft(2, '0');
    final String e = (entry.episodeNumber ?? 0).toString().padLeft(2, '0');
    return '${entry.series?.title ?? "Unknown Series"} - S${s}E$e';
  }

  @override
  DateTime get date => entry.airDateUtc ?? DateTime.now();

  @override
  bool get hasFile => entry.hasFile;

  @override
  bool get monitored => entry.monitored;
}

class RadarrCalendarEvent extends CalendarEvent {
  RadarrCalendarEvent(this.movie, super.instance, this.month);
  final RadarrMovie movie;
  final DateTime month;

  @override
  String get title => movie.title;

  @override
  DateTime get date {
    final DateTime start = DateTime(month.year, month.month, 1);
    final DateTime end = DateTime(month.year, month.month + 1, 1).subtract(const Duration(seconds: 1));

    final DateTime? digital = _parseDate(movie.digitalRelease);
    if (digital != null && digital.isAfter(start) && digital.isBefore(end)) {
      return digital;
    }
    final DateTime? physical = _parseDate(movie.physicalRelease);
    if (physical != null && physical.isAfter(start) && physical.isBefore(end)) {
      return physical;
    }
    final DateTime? cinemas = _parseDate(movie.inCinemas);
    if (cinemas != null && cinemas.isAfter(start) && cinemas.isBefore(end)) {
      return cinemas;
    }
    final DateTime? general = _parseDate(movie.releaseDate);
    if (general != null && general.isAfter(start) && general.isBefore(end)) {
      return general;
    }
    return cinemas ?? digital ?? physical ?? general ?? DateTime.now();
  }

  @override
  bool get hasFile => movie.hasFile;

  @override
  bool get monitored => movie.monitored;

  static DateTime? _parseDate(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }
}

/// Aggregated calendar provider for all active Sonarr and Radarr instances.
final globalCalendarProvider =
    FutureProvider.autoDispose.family<List<CalendarEvent>, DateTime>((
  Ref ref,
  DateTime month,
) async {
  final List<Instance> instances = ref.watch(activeInstancesProvider);
  final List<Future<List<CalendarEvent>>> futures = [];

  for (final Instance instance in instances) {
    if (instance.kind == ServiceKind.sonarr) {
      futures.add(
        ref.watch(sonarrCalendarProvider((instance, month)).future).then(
              (List<SonarrCalendarEntry> entries) => entries
                  .map((SonarrCalendarEntry e) => SonarrCalendarEvent(e, instance))
                  .toList(),
            ),
      );
    } else if (instance.kind == ServiceKind.radarr) {
      futures.add(
        ref.watch(radarrCalendarProvider((instance, month)).future).then(
              (List<RadarrMovie> movies) => movies
                  .map((RadarrMovie m) => RadarrCalendarEvent(m, instance, month))
                  .toList(),
            ),
      );
    }
  }

  final List<List<CalendarEvent>> results = await Future.wait(futures);
  return results.expand((List<CalendarEvent> list) => list).toList();
});

/// Displays a unified schedule and release calendar across all configured
/// Radarr and Sonarr services.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _visibleMonth;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    final DateTime now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  void _prevMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1);
    });
  }

  void _goToToday() {
    final DateTime now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month);
      _selectedDay = DateTime(now.year, now.month, now.day);
    });
  }

  void _onDayTapped(DateTime day) {
    setState(() {
      _selectedDay = day;
      if (day.month != _visibleMonth.month || day.year != _visibleMonth.year) {
        _visibleMonth = DateTime(day.year, day.month);
      }
    });
  }

  List<DateTime> _generateGridDays(DateTime month) {
    final DateTime first = DateTime(month.year, month.month);
    final int offset = first.weekday % 7;
    final DateTime start = first.subtract(Duration(days: offset));
    return List.generate(42, (int index) => start.add(Duration(days: index)));
  }

  void _showMonthYearPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            final ThemeData theme = Theme.of(context);
            return Container(
              padding: const EdgeInsets.all(Insets.md),
              height: 360,
              child: Column(
                children: <Widget>[
                  // Year Selector Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () {
                          setModalState(() {
                            _visibleMonth = DateTime(_visibleMonth.year - 1, _visibleMonth.month);
                          });
                          setState(() {});
                        },
                      ),
                      Text(
                        '${_visibleMonth.year}',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: () {
                          setModalState(() {
                            _visibleMonth = DateTime(_visibleMonth.year + 1, _visibleMonth.month);
                          });
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: Insets.md),
                  // Month Grid (3x4)
                  Expanded(
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 1.5,
                        crossAxisSpacing: Insets.sm,
                        mainAxisSpacing: Insets.sm,
                      ),
                      itemCount: 12,
                      itemBuilder: (BuildContext context, int index) {
                        final int monthNum = index + 1;
                        final bool isCurrent = _visibleMonth.month == monthNum;
                        final String monthName = DateFormat('MMM').format(DateTime(2000, monthNum));
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _visibleMonth = DateTime(_visibleMonth.year, monthNum);
                            });
                            Navigator.pop(context);
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(10),
                              border: isCurrent
                                  ? null
                                  : Border.all(
                                      color: theme.colorScheme.outline
                                          .withValues(alpha: 0.2),
                                    ),
                            ),
                            child: Text(
                              monthName,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: isCurrent
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurface,
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<CalendarEvent>> calendar =
        ref.watch(globalCalendarProvider(_visibleMonth));
    final List<Instance> activeServices = ref.watch(activeInstancesProvider);
    final bool hasCalendarServices = activeServices.any(
      (Instance i) => i.kind == ServiceKind.sonarr || i.kind == ServiceKind.radarr,
    );

    if (!hasCalendarServices) {
      return Scaffold(
        appBar: AppBar(title: const Text('Calendar')),
        body: const EmptyView(
          icon: Icons.calendar_today_outlined,
          title: 'No calendar services',
          message: 'Add a Sonarr or Radarr service to see your release schedule here.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(globalCalendarProvider(_visibleMonth)),
        child: AsyncValueView<List<CalendarEvent>>(
          value: calendar,
          onRetry: () => ref.invalidate(globalCalendarProvider(_visibleMonth)),
          data: (List<CalendarEvent> entries) {
            final List<DateTime> gridDays = _generateGridDays(_visibleMonth);

            // Group entries by local date
            final Map<DateTime, List<CalendarEvent>> entriesMap = {};
            for (final CalendarEvent entry in entries) {
              final DateTime local = entry.date.toLocal();
              final DateTime key = DateTime(local.year, local.month, local.day);
              entriesMap.putIfAbsent(key, () => []).add(entry);
            }

            // Selected day entries
            final DateTime selectedDayKey =
                DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
            final List<CalendarEvent> selectedDayEntries =
                entriesMap[selectedDayKey] ?? [];

            final ThemeData theme = Theme.of(context);
            final DateTime now = DateTime.now();
            final DateTime todayKey = DateTime(now.year, now.month, now.day);

            return ListView(
              padding: Insets.page,
              children: <Widget>[
                // Header Row
                Row(
                  children: <Widget>[
                    InkWell(
                      onTap: () => _showMonthYearPicker(context),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Insets.xs,
                          vertical: 4,
                        ),
                        child: Row(
                          children: <Widget>[
                            Text(
                              DateFormat('MMMM yyyy').format(_visibleMonth),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_drop_down,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _goToToday,
                      child: const Text('Today'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _prevMonth,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: _nextMonth,
                    ),
                  ],
                ),
                const SizedBox(height: Insets.sm),
                // Weekdays header
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: <Widget>[
                    Expanded(child: Center(child: Text('Sun', style: TextStyle(fontWeight: FontWeight.w500)))),
                    Expanded(child: Center(child: Text('Mon', style: TextStyle(fontWeight: FontWeight.w500)))),
                    Expanded(child: Center(child: Text('Tue', style: TextStyle(fontWeight: FontWeight.w500)))),
                    Expanded(child: Center(child: Text('Wed', style: TextStyle(fontWeight: FontWeight.w500)))),
                    Expanded(child: Center(child: Text('Thu', style: TextStyle(fontWeight: FontWeight.w500)))),
                    Expanded(child: Center(child: Text('Fri', style: TextStyle(fontWeight: FontWeight.w500)))),
                    Expanded(child: Center(child: Text('Sat', style: TextStyle(fontWeight: FontWeight.w500)))),
                  ],
                ),
                const SizedBox(height: Insets.xs),
                // Days Grid with horizontal swipe detection
                GestureDetector(
                  onHorizontalDragEnd: (DragEndDetails details) {
                    if (details.primaryVelocity == null) return;
                    if (details.primaryVelocity! < 0) {
                      // Swiped left (next month)
                      _nextMonth();
                    } else if (details.primaryVelocity! > 0) {
                      // Swiped right (prev month)
                      _prevMonth();
                    }
                  },
                  behavior: HitTestBehavior.translucent,
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 7,
                      childAspectRatio: 0.82,
                    ),
                    itemCount: gridDays.length,
                    itemBuilder: (BuildContext context, int index) {
                      final DateTime day = gridDays[index];
                      final bool isCurrentMonth = day.month == _visibleMonth.month;
                      final DateTime dayKey = DateTime(day.year, day.month, day.day);
                      final bool isSelected = dayKey == selectedDayKey;
                      final bool isToday = dayKey == todayKey;

                      final List<CalendarEvent> dayEntries = entriesMap[dayKey] ?? [];

                      // Dots calculations
                      final bool hasDownloaded = dayEntries.any((CalendarEvent e) => e.hasFile);
                      final bool hasUpcoming = dayEntries.any(
                        (CalendarEvent e) => !e.hasFile && e.date.isAfter(now),
                      );
                      final bool hasMissing = dayEntries.any(
                        (CalendarEvent e) => !e.hasFile && e.date.isBefore(now),
                      );

                      return InkWell(
                        onTap: () => _onDayTapped(day),
                        borderRadius: Radii.card,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Container(
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                                shape: BoxShape.circle,
                                border: isToday && !isSelected
                                    ? Border.all(
                                        color: theme.colorScheme.primary,
                                        width: 2,
                                      )
                                    : null,
                              ),
                              child: Text(
                                '${day.day}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: isSelected
                                      ? theme.colorScheme.onPrimary
                                      : isCurrentMonth
                                          ? theme.colorScheme.onSurface
                                          : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                                  fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            SizedBox(
                              height: 6,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  if (hasDownloaded) const _Dot(color: Colors.green),
                                  if (hasUpcoming) _Dot(color: theme.colorScheme.primary),
                                  if (hasMissing) _Dot(color: theme.colorScheme.error),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: Insets.md),
                const Divider(),
                const SizedBox(height: Insets.sm),
                // Airings list header
                _DateHeader(date: _selectedDay),
                const SizedBox(height: Insets.sm),
                // Airings list items
                if (selectedDayEntries.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Insets.xl),
                      child: Column(
                        children: <Widget>[
                          Icon(
                            Icons.calendar_today_outlined,
                            size: 40,
                            color: theme.colorScheme.outline.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: Insets.sm),
                          Text(
                            'No releases scheduled',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (final CalendarEvent event in selectedDayEntries)
                    _EventTile(event: event),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 4,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      _formatDate(date),
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  String _formatDate(DateTime date) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime tomorrow = today.add(const Duration(days: 1));
    final DateTime yesterday = today.subtract(const Duration(days: 1));

    final DateTime compare = DateTime(date.year, date.month, date.day);
    if (compare == today) {
      return 'Today';
    } else if (compare == tomorrow) {
      return 'Tomorrow';
    } else if (compare == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('EEEE, MMMM d').format(date);
    }
  }
}

class _EventTile extends ConsumerWidget {
  const _EventTile({required this.event});
  final CalendarEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final Instance instance = event.instance;

    Widget? posterWidget;
    String releaseType = '';
    VoidCallback? onTap;

    if (event is SonarrCalendarEvent) {
      final SonarrCalendarEntry entry = (event as SonarrCalendarEvent).entry;
      final SonarrApi? api = ref.watch(sonarrApiProvider(instance)).value;
      final SonarrImage? poster =
          entry.series?.images.firstWhereOrNull((SonarrImage i) => i.coverType == 'poster');
      final String? imageUrl = poster == null ? null : api?.posterUrl(poster);

      releaseType = 'TV Episode';
      onTap = () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              builder: (_) => SeriesDetailScreen(
                instance: instance,
                seriesId: entry.seriesId,
              ),
            ),
          );

      posterWidget = _Poster(imageUrl: imageUrl, icon: Icons.live_tv_outlined);
    } else if (event is RadarrCalendarEvent) {
      final RadarrMovie movie = (event as RadarrCalendarEvent).movie;
      final RadarrApi? api = ref.watch(radarrApiProvider(instance)).value;
      final RadarrImage? poster =
          movie.images.firstWhereOrNull((RadarrImage i) => i.coverType == 'poster');
      final String? imageUrl = poster == null ? null : api?.posterUrl(poster);

      final DateTime eventDate = event.date;
      if (movie.digitalRelease != null && DateTime.tryParse(movie.digitalRelease!)?.toLocal().day == eventDate.day) {
        releaseType = 'Digital Release';
      } else if (movie.physicalRelease != null && DateTime.tryParse(movie.physicalRelease!)?.toLocal().day == eventDate.day) {
        releaseType = 'Physical Release';
      } else {
        releaseType = 'Cinema Release';
      }

      onTap = () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              builder: (_) => MovieDetailScreen(
                instance: instance,
                movieId: movie.id,
              ),
            ),
          );

      posterWidget = _Poster(imageUrl: imageUrl, icon: Icons.movie_outlined);
    }

    final bool isFuture = event.date.isAfter(DateTime.now());
    final (String label, Color bg, Color fg) = event.hasFile
        ? (
            'Downloaded',
            theme.colorScheme.primaryContainer,
            theme.colorScheme.onPrimaryContainer,
          )
        : isFuture
            ? (
                'Upcoming',
                theme.colorScheme.secondaryContainer,
                theme.colorScheme.onSecondaryContainer,
              )
            : (
                'Missing',
                theme.colorScheme.errorContainer,
                theme.colorScheme.onErrorContainer,
              );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.sm, horizontal: Insets.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: Radii.card,
              child: SizedBox(
                width: 48,
                height: 72,
                child: posterWidget,
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          releaseType,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                      const SizedBox(width: Insets.sm),
                      Expanded(
                        child: Text(
                          instance.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.access_time,
                        size: 13,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat.jm().format(event.date.toLocal()),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(width: Insets.md),
                      Icon(
                        event.monitored ? Icons.bookmark : Icons.bookmark_border,
                        size: 13,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        event.monitored ? 'Monitored' : 'Unmonitored',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: Insets.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: Insets.sm, vertical: 4),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.imageUrl, required this.icon});
  final String? imageUrl;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(icon, color: theme.colorScheme.outline, size: 20),
    );
    if (imageUrl == null) {
      return fallback;
    }
    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      memCacheWidth: 100,
      memCacheHeight: 150,
      placeholder: (_, __) => Container(color: theme.colorScheme.surfaceContainerHighest),
      errorWidget: (_, __, ___) => fallback,
    );
  }
}
