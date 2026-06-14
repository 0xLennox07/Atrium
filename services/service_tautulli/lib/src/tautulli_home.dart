import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'models/tautulli_activity.dart';
import 'models/tautulli_models.dart';
import 'tautulli_api.dart';
import 'tautulli_providers.dart';

/// Tautulli's per-instance UI: Activity (live streams w/ detail + terminate),
/// History, Stats, and Users tabs - all poster-rich via Tautulli's image proxy.
class TautulliHome extends StatelessWidget {
  const TautulliHome({required this.instance, super.key});

  final Instance instance;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(
        children: <Widget>[
          const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: <Widget>[
              Tab(icon: Icon(Icons.play_circle_outline), text: 'Activity'),
              Tab(icon: Icon(Icons.history), text: 'History'),
              Tab(icon: Icon(Icons.bar_chart_outlined), text: 'Stats'),
              Tab(icon: Icon(Icons.people_alt_outlined), text: 'Users'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                _ActivityTab(instance: instance),
                _HistoryTab(instance: instance),
                _StatsTab(instance: instance),
                _UsersTab(instance: instance),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity

class _ActivityTab extends ConsumerWidget {
  const _ActivityTab({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TautulliActivity> activity =
        ref.watch(tautulliActivityProvider(instance));
    final TautulliApi? api = ref.watch(tautulliApiProvider(instance)).valueOrNull;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(tautulliActivityProvider(instance)),
      child: AsyncValueView<TautulliActivity>(
        value: activity,
        onRetry: () => ref.invalidate(tautulliActivityProvider(instance)),
        data: (TautulliActivity a) {
          if (a.sessions.isEmpty) {
            return const EmptyView(
              icon: Icons.podcasts_outlined,
              title: 'Nothing playing',
              message: 'No active streams right now.',
            );
          }
          return ListView.builder(
            padding: Insets.page,
            itemCount: a.sessions.length + 1,
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) {
                return _ActivitySummary(activity: a);
              }
              final TautulliSession s = a.sessions[index - 1];
              return _SessionCard(
                session: s,
                posterUrl: api?.imageUrl(s.posterThumb),
                avatarUrl: api?.imageUrl(s.userThumb, fallback: 'art'),
                onTap: () => _showSession(context, s),
              );
            },
          );
        },
      ),
    );
  }

  void _showSession(BuildContext context, TautulliSession session) {
    // Root navigator: branch-navigator sheets get swept by GoRouter shell
    // rebuilds (see qBit add sheet for history).
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _SessionSheet(instance: instance, session: session),
    );
  }
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({required this.activity});

  final TautulliActivity activity;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Wrap(
        spacing: Insets.sm,
        runSpacing: Insets.xs,
        children: <Widget>[
          _MetricChip(
            icon: Icons.sensors,
            label: '${activity.streamCount} '
                'stream${activity.streamCount == 1 ? '' : 's'}',
          ),
          _MetricChip(
            icon: Icons.speed,
            label: fmtTautulliKbps(activity.totalBandwidth),
          ),
          if (activity.transcodeCount > 0)
            _MetricChip(
              icon: Icons.transform,
              label: '${activity.transcodeCount} transcoding',
            ),
        ],
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(label, style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.session,
    required this.posterUrl,
    required this.avatarUrl,
    required this.onTap,
  });

  final TautulliSession session;
  final String? posterUrl;
  final String? avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double pct = session.progressPercent / 100.0;
    final bool playing = session.state.toLowerCase() == 'playing';
    final String meta = <String>[
      session.friendlyName,
      if (session.player.isNotEmpty) session.player,
      if (session.qualityProfile.isNotEmpty) session.qualityProfile,
      if (session.bandwidth > 0) fmtTautulliKbps(session.bandwidth),
    ].join(' • ');

    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.card,
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Poster(url: posterUrl, width: 58, height: 87),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(
                          playing ? Icons.play_arrow : Icons.pause,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            session.fullTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 4),
                        _DecisionChip(decision: session.transcodeDecision),
                      ],
                    ),
                    if (session.episodeLabel.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          session.episodeLabel,
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ),
                    const SizedBox(height: Insets.sm),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct.clamp(0, 1),
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: Insets.sm),
                    Row(
                      children: <Widget>[
                        _Avatar(
                          url: avatarUrl,
                          initial: _initial(session.friendlyName),
                          radius: 9,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall,
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

class _DecisionChip extends StatelessWidget {
  const _DecisionChip({required this.decision});

  final String decision;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (decision.isEmpty) {
      return const SizedBox.shrink();
    }
    final (Color bg, Color fg) = switch (decision.toLowerCase()) {
      'direct play' => (
          theme.colorScheme.primaryContainer,
          theme.colorScheme.onPrimaryContainer,
        ),
      'copy' || 'direct stream' => (
          theme.colorScheme.secondaryContainer,
          theme.colorScheme.onSecondaryContainer,
        ),
      _ => (
          theme.colorScheme.tertiaryContainer,
          theme.colorScheme.onTertiaryContainer,
        ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _label(),
        style: theme.textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }

  String _label() => switch (decision.toLowerCase()) {
        'direct play' => 'Direct Play',
        'copy' || 'direct stream' => 'Direct Stream',
        'transcode' => 'Transcode',
        _ => decision,
      };
}

/// Bottom sheet with full stream details and a terminate action.
class _SessionSheet extends ConsumerStatefulWidget {
  const _SessionSheet({required this.instance, required this.session});

  final Instance instance;
  final TautulliSession session;

  @override
  ConsumerState<_SessionSheet> createState() => _SessionSheetState();
}

class _SessionSheetState extends ConsumerState<_SessionSheet> {
  bool _busy = false;

  // Inline feedback: snackbars fired from inside a modal sheet render on the
  // scaffold UNDERNEATH it and are invisible while the sheet is up.
  String? _error;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final TautulliSession s = widget.session;
    final TautulliApi? api =
        ref.watch(tautulliApiProvider(widget.instance)).valueOrNull;
    final String video = _streamLine(
      s.videoDecision,
      s.videoCodec,
      s.streamVideoCodec,
      s.videoResolution,
    );
    final String audio =
        _streamLine(s.audioDecision, s.audioCodec, s.streamAudioCodec, '');
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Insets.lg,
          right: Insets.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + Insets.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                _Poster(url: api?.imageUrl(s.posterThumb), width: 64, height: 96),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(s.fullTitle, style: theme.textTheme.titleMedium),
                      if (s.episodeLabel.isNotEmpty || s.year.isNotEmpty) ...<Widget>[
                        const SizedBox(height: Insets.xs),
                        Text(
                          <String>[
                            if (s.episodeLabel.isNotEmpty) s.episodeLabel,
                            if (s.year.isNotEmpty) s.year,
                          ].join(' • '),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: theme.colorScheme.outline),
                        ),
                      ],
                      const SizedBox(height: Insets.sm),
                      _DecisionChip(decision: s.transcodeDecision),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.md),
            _DetailRow(label: 'User', value: s.friendlyName),
            _DetailRow(label: 'State', value: _capitalize(s.state)),
            _DetailRow(
              label: 'Player',
              value: <String>[
                if (s.player.isNotEmpty) s.player,
                if (s.product.isNotEmpty) s.product,
                if (s.platform.isNotEmpty) s.platform,
              ].join(' • '),
            ),
            if (s.qualityProfile.isNotEmpty)
              _DetailRow(label: 'Quality', value: s.qualityProfile),
            _DetailRow(
              label: 'Decision',
              value: _capitalize(s.transcodeDecision),
            ),
            if (video.isNotEmpty) _DetailRow(label: 'Video', value: video),
            if (audio.isNotEmpty) _DetailRow(label: 'Audio', value: audio),
            if (s.container.isNotEmpty)
              _DetailRow(label: 'Container', value: s.container),
            if (s.bandwidth > 0)
              _DetailRow(
                label: 'Bandwidth',
                value: fmtTautulliKbps(s.bandwidth),
              ),
            if (s.location.isNotEmpty)
              _DetailRow(label: 'Location', value: s.location.toUpperCase()),
            _DetailRow(label: 'Progress', value: '${s.progressPercent}%'),
            const SizedBox(height: Insets.lg),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.errorContainer,
                foregroundColor: theme.colorScheme.onErrorContainer,
              ),
              onPressed: _busy ? null : _confirmTerminate,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.stop_circle_outlined),
              label: const Text('Terminate stream'),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: Insets.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    Icons.error_outline,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: Insets.xs),
                  Flexible(
                    child: Text(_error!, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "Transcode (h264 -> hevc, 1080p)" / "Direct play (h264)".
  String _streamLine(
    String decision,
    String codec,
    String streamCodec,
    String resolution,
  ) {
    if (decision.isEmpty && codec.isEmpty) {
      return '';
    }
    final bool changed = streamCodec.isNotEmpty &&
        streamCodec.toLowerCase() != codec.toLowerCase();
    final String codecs = changed ? '$codec -> $streamCodec' : codec;
    final String detail = <String>[
      if (codecs.isNotEmpty) codecs,
      if (resolution.isNotEmpty) resolution,
    ].join(', ');
    final String head = _capitalize(decision);
    return detail.isEmpty ? head : '$head ($detail)';
  }

  Future<void> _confirmTerminate() async {
    final bool? confirmed = await showDialog<bool>(
      // Root navigator is showDialog's default, satisfying the hard rule.
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Terminate stream?'),
        content: Text(
          '${widget.session.friendlyName} will be stopped with a message. '
          'Requires Plex Pass.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Terminate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final TautulliApi api =
          await ref.read(tautulliApiProvider(widget.instance).future);
      await api.terminateSession(widget.session);
      ref.invalidate(tautulliActivityProvider(widget.instance));
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e is NetworkException ? e.message : 'Terminate failed';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

// ---------------------------------------------------------------------------
// History

class _HistoryTab extends ConsumerWidget {
  const _HistoryTab({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<TautulliHistoryPage> history =
        ref.watch(tautulliHistoryProvider(instance));
    final TautulliApi? api = ref.watch(tautulliApiProvider(instance)).valueOrNull;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(tautulliHistoryProvider(instance)),
      child: AsyncValueView<TautulliHistoryPage>(
        value: history,
        onRetry: () => ref.invalidate(tautulliHistoryProvider(instance)),
        data: (TautulliHistoryPage page) {
          if (page.records.isEmpty) {
            return const EmptyView(
              icon: Icons.history,
              title: 'No history',
              message: 'Nothing has been watched yet.',
            );
          }
          return ListView.separated(
            padding: Insets.page,
            itemCount: page.records.length + 1,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 56),
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: Insets.sm),
                  child: Text(
                    '${page.recordsTotal} plays total • showing latest '
                    '${page.records.length}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                );
              }
              final TautulliHistoryRecord r = page.records[index - 1];
              return _HistoryTile(
                record: r,
                posterUrl: api?.imageUrl(r.posterThumb),
                avatarUrl: api?.imageUrl(r.userThumb, fallback: 'art'),
              );
            },
          );
        },
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.record,
    required this.posterUrl,
    required this.avatarUrl,
  });

  final TautulliHistoryRecord record;
  final String? posterUrl;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (IconData icon, Color color) = switch (record.watchedStatus) {
      >= 1 => (Icons.check_circle, theme.colorScheme.primary),
      >= 0.5 => (Icons.timelapse, theme.colorScheme.secondary),
      _ => (Icons.radio_button_unchecked, theme.colorScheme.outline),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Row(
        children: <Widget>[
          _Poster(url: posterUrl, width: 40, height: 60),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  record.fullTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 3),
                Row(
                  children: <Widget>[
                    _Avatar(
                      url: avatarUrl,
                      initial: _initial(record.friendlyName),
                      radius: 8,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        <String>[
                          record.friendlyName,
                          relativeEpoch(record.date),
                          if (record.playDuration > 0)
                            fmtSeconds(record.playDuration),
                        ].join(' • '),
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
          const SizedBox(width: Insets.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 2),
              Text(
                '${record.percentComplete}%',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stats

class _StatsTab extends ConsumerWidget {
  const _StatsTab({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<TautulliHomeStat>> stats =
        ref.watch(tautulliHomeStatsProvider(instance));
    final TautulliApi? api = ref.watch(tautulliApiProvider(instance)).valueOrNull;
    return RefreshIndicator(
      onRefresh: () async =>
          ref.invalidate(tautulliHomeStatsProvider(instance)),
      child: AsyncValueView<List<TautulliHomeStat>>(
        value: stats,
        onRetry: () => ref.invalidate(tautulliHomeStatsProvider(instance)),
        data: (List<TautulliHomeStat> all) {
          final List<TautulliHomeStat> sections = all
              .where((TautulliHomeStat s) => s.rows.isNotEmpty)
              .toList();
          if (sections.isEmpty) {
            return const EmptyView(
              icon: Icons.bar_chart,
              title: 'No statistics',
              message: 'No plays in the last 30 days.',
            );
          }
          return ListView.builder(
            padding: Insets.page,
            itemCount: sections.length,
            itemBuilder: (BuildContext context, int index) =>
                _StatSection(stat: sections[index], api: api),
          );
        },
      ),
    );
  }
}

class _StatSection extends StatelessWidget {
  const _StatSection({required this.stat, required this.api});

  final TautulliHomeStat stat;
  final TautulliApi? api;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isUsers = stat.statId == 'top_users';
    final bool isPlatforms = stat.statId == 'top_platforms';
    final bool isConcurrent = stat.statId == 'most_concurrent';
    final bool isLastWatched = stat.statId == 'last_watched';

    int metric(TautulliStatRow r) => isConcurrent ? r.count : r.totalPlays;
    final int maxMetric = stat.rows
        .fold<int>(0, (int m, TautulliStatRow r) => math.max(m, metric(r)));
    final bool showBar = !isLastWatched && maxMetric > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: Insets.md),
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(_statIcon(stat.statId),
                    size: 18, color: theme.colorScheme.primary,),
                const SizedBox(width: Insets.sm),
                Text(
                  stat.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.sm),
            for (final (int i, TautulliStatRow row) in stat.rows.indexed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 18,
                      child: Text(
                        '${i + 1}',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ),
                    const SizedBox(width: Insets.xs),
                    _StatLeading(
                      row: row,
                      api: api,
                      isUsers: isUsers,
                      isPlatforms: isPlatforms,
                    ),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            row.labelFor(stat.statId),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                          if (showBar) ...<Widget>[
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: (metric(row) / maxMetric).clamp(0, 1),
                                minHeight: 5,
                                backgroundColor:
                                    theme.colorScheme.surfaceContainerHighest,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    Text(
                      _trailing(row, isConcurrent, isLastWatched),
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _trailing(TautulliStatRow row, bool isConcurrent, bool isLastWatched) {
    if (isConcurrent) {
      return '${row.count} streams';
    }
    if (isLastWatched) {
      return row.user;
    }
    return '${row.totalPlays} plays';
  }
}

/// The leading thumbnail for a stat row: poster, user avatar, or platform icon.
class _StatLeading extends StatelessWidget {
  const _StatLeading({
    required this.row,
    required this.api,
    required this.isUsers,
    required this.isPlatforms,
  });

  final TautulliStatRow row;
  final TautulliApi? api;
  final bool isUsers;
  final bool isPlatforms;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (isUsers) {
      return _Avatar(
        url: api?.imageUrl(row.userThumb, fallback: 'art'),
        initial: _initial(row.labelFor('top_users')),
        radius: 17,
      );
    }
    if (isPlatforms) {
      return CircleAvatar(
        radius: 17,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(Icons.devices_outlined,
            size: 18, color: theme.colorScheme.onSurfaceVariant,),
      );
    }
    return _Poster(url: api?.imageUrl(row.posterThumb), width: 34, height: 51);
  }
}

// ---------------------------------------------------------------------------
// Users

class _UsersTab extends ConsumerWidget {
  const _UsersTab({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<TautulliUser>> users =
        ref.watch(tautulliUsersProvider(instance));
    final TautulliApi? api = ref.watch(tautulliApiProvider(instance)).valueOrNull;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(tautulliUsersProvider(instance)),
      child: AsyncValueView<List<TautulliUser>>(
        value: users,
        onRetry: () => ref.invalidate(tautulliUsersProvider(instance)),
        data: (List<TautulliUser> list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.people_outline,
              title: 'No users',
              message: 'Tautulli has not seen any users yet.',
            );
          }
          return ListView.separated(
            padding: Insets.page,
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
            itemBuilder: (BuildContext context, int index) {
              final TautulliUser u = list[index];
              return _UserTile(
                user: u,
                avatarUrl: api?.imageUrl(u.userThumb, fallback: 'art'),
              );
            },
          );
        },
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({required this.user, required this.avatarUrl});

  final TautulliUser user;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Row(
        children: <Widget>[
          _Avatar(
            url: avatarUrl,
            initial: _initial(user.friendlyName),
            radius: 20,
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  user.friendlyName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  <String>[
                    '${user.plays} plays',
                    if (user.duration > 0) fmtSeconds(user.duration),
                    if (user.lastSeen > 0) 'seen ${relativeEpoch(user.lastSeen)}',
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
            ),
          ),
          if (user.lastPlayed.isNotEmpty) ...<Widget>[
            const SizedBox(width: Insets.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                user.lastPlayed,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets

/// A rounded poster image (2:3) with a graceful fallback.
class _Poster extends StatelessWidget {
  const _Poster({required this.url, this.width = 48, this.height = 72});

  final String? url;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget fallback = Container(
      width: width,
      height: height,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.movie_outlined,
        size: width * 0.5,
        color: theme.colorScheme.outline,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: (url == null || url!.isEmpty)
          ? fallback
          : CachedNetworkImage(
              imageUrl: url!,
              width: width,
              height: height,
              fit: BoxFit.cover,
              memCacheWidth: (width * 3).round(),
              placeholder: (BuildContext context, String _) => Container(
                width: width,
                height: height,
                color: theme.colorScheme.surfaceContainerHighest,
              ),
              errorWidget: (BuildContext context, String _, Object __) =>
                  fallback,
            ),
    );
  }
}

/// A circular avatar that loads a Plex user image, falling back to an initial.
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.initial,
    this.radius = 18,
  });

  final String? url;
  final String initial;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        foregroundImage: CachedNetworkImageProvider(url!),
        // If the image fails, the initial below shows through.
        child: Text(
          initial,
          style: TextStyle(
            fontSize: radius * 0.8,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: radius * 0.8,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Expanded(
            child: Text(value, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

IconData _statIcon(String statId) => switch (statId) {
      'top_movies' || 'popular_movies' => Icons.movie_outlined,
      'top_tv' || 'popular_tv' => Icons.tv_outlined,
      'top_music' || 'popular_music' => Icons.music_note_outlined,
      'top_libraries' => Icons.video_library_outlined,
      'top_users' => Icons.people_alt_outlined,
      'top_platforms' => Icons.devices_outlined,
      'last_watched' => Icons.history,
      'most_concurrent' => Icons.timeline_outlined,
      _ => Icons.bar_chart,
    };

String _initial(String name) =>
    name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Tautulli reports bandwidth in kbps.
String fmtTautulliKbps(int kbps) {
  if (kbps >= 1000) {
    return '${(kbps / 1000).toStringAsFixed(1)} Mbps';
  }
  return '$kbps kbps';
}

/// Seconds to "2h 14m" / "45m" / "30s".
String fmtSeconds(int seconds) {
  if (seconds >= 3600) {
    final int h = seconds ~/ 3600;
    final int m = (seconds % 3600) ~/ 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }
  if (seconds >= 60) {
    return '${seconds ~/ 60}m';
  }
  return '${seconds}s';
}

/// Epoch seconds to a compact relative label.
String relativeEpoch(int epochSeconds) {
  if (epochSeconds <= 0) {
    return 'never';
  }
  final DateTime then =
      DateTime.fromMillisecondsSinceEpoch(epochSeconds * 1000);
  final Duration diff = DateTime.now().difference(then);
  if (diff.inMinutes < 1) {
    return 'just now';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes}m ago';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours}h ago';
  }
  if (diff.inDays < 7) {
    return '${diff.inDays}d ago';
  }
  return DateFormat('d MMM yyyy').format(then);
}
