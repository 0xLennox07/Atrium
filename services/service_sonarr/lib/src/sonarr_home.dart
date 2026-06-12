import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'add_series_screen.dart';
import 'models/sonarr_calendar.dart';
import 'models/sonarr_queue.dart';
import 'models/sonarr_series.dart';
import 'series_detail_screen.dart';
import 'sonarr_api.dart';
import 'sonarr_providers.dart';

/// Sonarr's per-instance UI: a tabbed Series / Calendar / Queue view.
///
/// Series tab renders a 2:3 poster grid (Jellyfin-style) with title +
/// episode-progress overlay and a small monitored badge in the top-right
/// corner. Queue tab is unchanged.
///
/// This widget is the entry point the app shell dispatches to for a Sonarr
/// instance and remains the reference pattern other *arr modules follow.
class SonarrHome extends StatelessWidget {
  const SonarrHome({required this.instance, super.key});

  final Instance instance;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: Column(
          children: <Widget>[
            const TabBar(
              tabs: <Widget>[
                Tab(text: 'Series'),
                Tab(text: 'Calendar'),
                Tab(text: 'Queue'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _SeriesTab(instance: instance),
                  _CalendarTab(instance: instance),
                  _QueueTab(instance: instance),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          // Root navigator: see qBit detail history.
          onPressed: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute<void>(
              builder: (_) => AddSeriesScreen(instance: instance),
            ),
          ),
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
      ),
    );
  }
}

class _SeriesTab extends ConsumerWidget {
  const _SeriesTab({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SonarrSeries>> series =
        ref.watch(sonarrSeriesProvider(instance));
    final SonarrApi? api =
        ref.watch(sonarrApiProvider(instance)).value;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(sonarrSeriesProvider(instance)),
      child: AsyncValueView<List<SonarrSeries>>(
        value: series,
        onRetry: () => ref.invalidate(sonarrSeriesProvider(instance)),
        data: (List<SonarrSeries> list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.live_tv_outlined,
              title: 'No series',
              message: 'This Sonarr has no series yet.',
            );
          }
          return GridView.builder(
            padding: Insets.page,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              childAspectRatio: 0.52,
              crossAxisSpacing: Insets.md,
              mainAxisSpacing: Insets.md,
            ),
            itemCount: list.length,
            itemBuilder: (BuildContext context, int index) {
              final SonarrSeries s = list[index];
              final SonarrImage? poster = s.images
                  .firstWhereOrNull((SonarrImage i) => i.coverType == 'poster');
              return _SeriesCard(
                series: s,
                imageUrl: poster == null ? null : api?.posterUrl(poster),
                // Root navigator: branch-navigator pushes get swept by
                // GoRouter shell rebuilds (see qBit detail for history).
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SeriesDetailScreen(
                      instance: instance,
                      seriesId: s.id,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Poster card for a single series.
///
/// Visual structure mirrors `service_jellyfin`'s `_PosterCard` so that
/// browsing across services feels consistent.
class _SeriesCard extends StatelessWidget {
  const _SeriesCard({
    required this.series,
    required this.imageUrl,
    required this.onTap,
  });

  final SonarrSeries series;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SonarrSeriesStatistics? stats = series.statistics;
    final double progress = (stats == null || stats.totalEpisodeCount == 0)
        ? 0
        : (stats.episodeFileCount / stats.totalEpisodeCount).clamp(0, 1);

    return InkWell(
      onTap: onTap,
      borderRadius: Radii.card,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: ClipRRect(
            borderRadius: Radii.card,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                _Poster(imageUrl: imageUrl, theme: theme),
                if (series.monitored)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _Badge(
                      color: theme.colorScheme.primary,
                      child: Icon(
                        Icons.bookmark,
                        size: 12,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                if (progress > 0.02 && progress < 0.999)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: LinearProgressIndicator(
                      value: progress.toDouble(),
                      minHeight: 3,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Insets.xs),
        Text(
          series.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelMedium,
        ),
        Text(
          _subtitle(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
      ),
    );
  }

  String _subtitle() {
    final SonarrSeriesStatistics? st = series.statistics;
    final List<String> parts = <String>[
      if (series.year != null) '${series.year}',
      if (st != null)
        '${st.episodeFileCount}/${st.totalEpisodeCount} eps',
    ];
    return parts.join(' • ');
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.imageUrl, required this.theme});

  final String? imageUrl;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.live_tv_outlined,
        color: theme.colorScheme.outline,
      ),
    );
    if (imageUrl == null) {
      return fallback;
    }
    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      placeholder: (BuildContext context, String url) =>
          Container(color: theme.colorScheme.surfaceContainerHighest),
      errorWidget: (BuildContext context, String url, Object error) =>
          fallback,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.child, required this.color});

  final Widget child;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: child,
    );
  }
}

class _QueueTab extends ConsumerWidget {
  const _QueueTab({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<SonarrQueuePage> queue =
        ref.watch(sonarrQueueProvider(instance));
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(sonarrQueueProvider(instance)),
      child: AsyncValueView<SonarrQueuePage>(
        value: queue,
        onRetry: () => ref.invalidate(sonarrQueueProvider(instance)),
        data: (SonarrQueuePage page) {
          if (page.records.isEmpty) {
            return const EmptyView(
              icon: Icons.download_done_outlined,
              title: 'Queue is empty',
              message: 'Nothing downloading right now.',
            );
          }
          return ListView.builder(
            padding: Insets.pageH,
            itemCount: page.records.length,
            itemBuilder: (BuildContext context, int index) {
              final SonarrQueueRecord r = page.records[index];
              final double progress = r.size <= 0
                  ? 0
                  : ((r.size - r.sizeleft) / r.size).clamp(0, 1).toDouble();
              return ListTile(
                title: Text(
                  r.title ?? 'Item ${r.id}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SizedBox(height: Insets.xs),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: Insets.xs),
                    Text(
                      <String?>[
                        r.status,
                        if (r.timeleft != null) r.timeleft,
                      ].whereType<String>().join(' • '),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () async {
                    final SonarrApi api =
                        await ref.read(sonarrApiProvider(instance).future);
                    await api.deleteQueueItem(r.id);
                    ref.invalidate(sonarrQueueProvider(instance));
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CalendarTab extends StatefulWidget {
  const _CalendarTab({required this.instance});

  final Instance instance;

  @override
  State<_CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends State<_CalendarTab> {
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

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? child) {
        final AsyncValue<List<SonarrCalendarEntry>> calendar =
            ref.watch(sonarrCalendarProvider((widget.instance, _visibleMonth)));
        final SonarrApi? api = ref.watch(sonarrApiProvider(widget.instance)).value;

        return RefreshIndicator(
          onRefresh: () async =>
              ref.invalidate(sonarrCalendarProvider((widget.instance, _visibleMonth))),
          child: AsyncValueView<List<SonarrCalendarEntry>>(
            value: calendar,
            onRetry: () =>
                ref.invalidate(sonarrCalendarProvider((widget.instance, _visibleMonth))),
            data: (List<SonarrCalendarEntry> entries) {
              final List<DateTime> gridDays = _generateGridDays(_visibleMonth);

              // Group entries by local date
              final Map<DateTime, List<SonarrCalendarEntry>> entriesMap = {};
              for (final SonarrCalendarEntry entry in entries) {
                if (entry.airDateUtc == null) continue;
                final DateTime local = entry.airDateUtc!.toLocal();
                final DateTime key = DateTime(local.year, local.month, local.day);
                entriesMap.putIfAbsent(key, () => []).add(entry);
              }

              // Selected day entries
              final DateTime selectedDayKey =
                  DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
              final List<SonarrCalendarEntry> selectedDayEntries =
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
                      Text(
                        DateFormat('MMMM yyyy').format(_visibleMonth),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
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
                  // Days Grid
                  GridView.builder(
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

                      final List<SonarrCalendarEntry> dayEntries =
                          entriesMap[dayKey] ?? [];

                      // Dots calculations
                      final bool hasDownloaded = dayEntries.any((SonarrCalendarEntry e) => e.hasFile);
                      final bool hasUpcoming = dayEntries.any(
                        (SonarrCalendarEntry e) =>
                            !e.hasFile &&
                            e.airDateUtc != null &&
                            e.airDateUtc!.isAfter(now),
                      );
                      final bool hasMissing = dayEntries.any(
                        (SonarrCalendarEntry e) =>
                            !e.hasFile &&
                            e.airDateUtc != null &&
                            e.airDateUtc!.isBefore(now),
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
                                color: isSelected
                                    ? theme.colorScheme.primary
                                    : Colors.transparent,
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
                                          : theme.colorScheme.onSurface
                                              .withValues(alpha: 0.35),
                                  fontWeight: isSelected || isToday
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            SizedBox(
                              height: 6,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: <Widget>[
                                  if (hasDownloaded)
                                    const _Dot(color: Colors.green),
                                  if (hasUpcoming)
                                    _Dot(color: theme.colorScheme.primary),
                                  if (hasMissing)
                                    _Dot(color: theme.colorScheme.error),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
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
                              'No airings scheduled',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    for (final SonarrCalendarEntry entry in selectedDayEntries)
                      _CalendarEntryTile(
                        instance: widget.instance,
                        entry: entry,
                        api: api,
                      ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      width: 5,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String title = _getDateHeaderString(date);

    return Padding(
      padding: const EdgeInsets.only(top: Insets.md, bottom: Insets.xs),
      child: Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _getDateHeaderString(DateTime date) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime yesterday = today.subtract(const Duration(days: 1));
    final DateTime tomorrow = today.add(const Duration(days: 1));
    final DateTime compareDate = DateTime(date.year, date.month, date.day);

    if (compareDate == today) {
      return 'Today';
    } else if (compareDate == tomorrow) {
      return 'Tomorrow';
    } else if (compareDate == yesterday) {
      return 'Yesterday';
    } else {
      return DateFormat('EEEE, MMMM d').format(date);
    }
  }
}

class _CalendarEntryTile extends StatelessWidget {
  const _CalendarEntryTile({
    required this.instance,
    required this.entry,
    required this.api,
  });

  final Instance instance;
  final SonarrCalendarEntry entry;
  final SonarrApi? api;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SonarrImage? poster = entry.series?.images
        .firstWhereOrNull((SonarrImage i) => i.coverType == 'poster');
    final String? imageUrl = poster == null ? null : api?.posterUrl(poster);

    final bool isFuture = entry.airDateUtc != null &&
        entry.airDateUtc!.isAfter(DateTime.now());

    final (String label, Color bg, Color fg) = entry.hasFile
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
      onTap: () {
        Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => SeriesDetailScreen(
              instance: instance,
              seriesId: entry.seriesId,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: Insets.sm,
          horizontal: Insets.xs,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: Radii.card,
              child: SizedBox(
                width: 48,
                height: 72,
                child: imageUrl == null
                    ? Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.live_tv_outlined,
                          color: theme.colorScheme.outline,
                          size: 20,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.live_tv_outlined,
                            color: theme.colorScheme.outline,
                            size: 20,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    entry.series?.title ?? 'Unknown Series',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_episodeCode(entry.seasonNumber, entry.episodeNumber)} • ${entry.title ?? "Episode ${entry.episodeNumber}"}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      if (entry.airDateUtc != null) ...[
                        Icon(
                          Icons.access_time,
                          size: 13,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _airTime(entry.airDateUtc),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(width: Insets.md),
                      ],
                      Icon(
                        entry.monitored ? Icons.bookmark : Icons.bookmark_border,
                        size: 13,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        entry.monitored ? 'Monitored' : 'Unmonitored',
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
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.sm,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _episodeCode(int? season, int? episode) {
    if (season == null || episode == null) return '';
    final String s = season.toString().padLeft(2, '0');
    final String e = episode.toString().padLeft(2, '0');
    return 'S${s}E$e';
  }

  String _airTime(DateTime? utcDate) {
    if (utcDate == null) return '';
    return DateFormat.jm().format(utcDate.toLocal());
  }
}
