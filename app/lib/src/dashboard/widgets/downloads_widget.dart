import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_router/core_router.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:service_deluge/service_deluge.dart';
import 'package:service_nzbget/service_nzbget.dart';
import 'package:service_qbittorrent/service_qbittorrent.dart';
import 'package:service_rtorrent/service_rtorrent.dart';
import 'package:service_sabnzbd/service_sabnzbd.dart';
import 'package:service_transmission/service_transmission.dart';

import '../dashboard_widget_card.dart';
import '../dashboard_widget_kind.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';

/// qBittorrent states where data is actually moving, or about to.
const Set<String> _movingDlStates = <String>{
  'downloading',
  'forcedDL',
  'metaDL',
  'checkingDL',
  'allocating',
};

/// States that belong on the card but are not going anywhere yet: queued is
/// waiting its turn, stalled is connected to nobody.
const Set<String> _waitingDlStates = <String>{
  'stalledDL',
  'queuedDL',
};

/// qBittorrent states that count as a download in progress.
///
/// Queued and stalled are included on purpose: they are downloads someone is
/// waiting on, and dropping them would understate the count. They are ranked
/// below moving ones for display, which is a separate matter to being counted.
const Set<String> _activeDlStates = <String>{
  ..._movingDlStates,
  ..._waitingDlStates,
};

/// Live count of active downloads across every qBittorrent + SABnzbd + NZBGet
/// + Deluge instance. Instances still loading or in error contribute 0, so the
/// dashboard only surfaces the downloads widget once real activity is
/// confirmed.
final activeDownloadCountProvider = Provider.autoDispose<int>((Ref ref) {
  final List<Instance> instances = ref.watch(activeInstancesProvider);
  int count = 0;
  for (final Instance i in instances) {
    if (i.kind == ServiceKind.qbittorrent) {
      final List<QbitTorrent> torrents =
          ref.watch(qbitRawTorrentsProvider(i)).value ?? const <QbitTorrent>[];
      for (final QbitTorrent t in torrents) {
        if (_activeDlStates.contains(t.state)) {
          count++;
        }
      }
    } else if (i.kind == ServiceKind.sabnzbd) {
      count += ref.watch(sabQueueProvider(i)).value?.slots.length ?? 0;
    } else if (i.kind == ServiceKind.nzbget) {
      count += ref.watch(nzbgetQueueProvider(i)).value?.length ?? 0;
    } else if (i.kind == ServiceKind.deluge) {
      // A Deluge list keeps finished torrents around as `Seeding`, so only the
      // ones actually pulling data count as active downloads.
      final List<DelugeTorrent> torrents =
          ref.watch(delugeRawTorrentsProvider(i)).value ??
              const <DelugeTorrent>[];
      count += torrents.where((DelugeTorrent t) => t.isDownloading).length;
    } else if (i.kind == ServiceKind.transmission) {
      // Same reasoning: a Transmission list is mostly finished seeds.
      final List<TransmissionTorrent> torrents =
          ref.watch(transmissionRawTorrentsProvider(i)).value ??
              const <TransmissionTorrent>[];
      count += torrents
          .where((TransmissionTorrent t) => t.status.isDownloading)
          .length;
    } else if (i.kind == ServiceKind.rtorrent) {
      // Same reasoning: an rTorrent view is mostly finished seeds.
      final List<RtorrentTorrent> torrents =
          ref.watch(rtorrentRawTorrentsProvider(i)).value ??
              const <RtorrentTorrent>[];
      count += torrents
          .where((RtorrentTorrent t) => t.status.isDownloading)
          .length;
    }
  }
  return count;
});

/// Parses SABnzbd's human speed string ("1.2 M", "512 K") into bytes/s.
int parseSabSpeed(String raw) {
  final RegExpMatch? m =
      RegExp(r'^([\d.]+)\s*([KMGT]?)$').firstMatch(raw.trim());
  if (m == null) {
    return 0;
  }
  final double value = double.tryParse(m.group(1)!) ?? 0;
  const Map<String, int> mult = <String, int>{
    '': 1,
    'K': 1024,
    'M': 1024 * 1024,
    'G': 1024 * 1024 * 1024,
    'T': 1024 * 1024 * 1024 * 1024,
  };
  return (value * mult[m.group(2)]!).round();
}

class _DownloadRow {
  const _DownloadRow({
    required this.name,
    required this.progress,
    required this.instance,
    this.moving = true,
  });

  final String name;
  final double progress;
  final Instance instance;

  /// Whether data is actually moving for this one.
  ///
  /// The card only has room for a few rows, and sorting purely on progress put
  /// a torrent queued at 90% above one downloading at 10%, so a busy queue
  /// hid the very thing the card exists to show. Only qBittorrent reports a
  /// state fine-grained enough to tell; every other client is already filtered
  /// to what is downloading, so they default to moving.
  final bool moving;
}

/// Combined qBittorrent + SABnzbd + NZBGet + Deluge activity: total speed,
/// count, top items.
class DashboardDownloadsWidget extends ConsumerWidget {
  const DashboardDownloadsWidget({
    required this.qbitInstances,
    required this.sabInstances,
    required this.nzbgetInstances,
    required this.delugeInstances,
    required this.transmissionInstances,
    required this.rtorrentInstances,
    super.key,
  });

  final List<Instance> qbitInstances;
  final List<Instance> sabInstances;
  final List<Instance> nzbgetInstances;
  final List<Instance> delugeInstances;
  final List<Instance> transmissionInstances;
  final List<Instance> rtorrentInstances;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final List<_DownloadRow> rows = <_DownloadRow>[];
    int totalSpeed = 0;
    bool anyLoading = false;
    bool anyError = false;

    for (final Instance i in qbitInstances) {
      final AsyncValue<List<QbitTorrent>> torrents =
          ref.watch(qbitRawTorrentsProvider(i));
      anyLoading |= torrents.isLoading && !torrents.hasValue;
      anyError |= torrents.hasError;
      for (final QbitTorrent t in torrents.value ?? const <QbitTorrent>[]) {
        if (_activeDlStates.contains(t.state)) {
          rows.add(_DownloadRow(
            name: t.name,
            progress: t.progress.clamp(0, 1).toDouble(),
            instance: i,
            moving: _movingDlStates.contains(t.state),
          ));
        }
      }
      totalSpeed += ref.watch(qbitTransferProvider(i)).value?.dlSpeed ?? 0;
    }
    for (final Instance i in sabInstances) {
      final AsyncValue<SabQueue> queue = ref.watch(sabQueueProvider(i));
      anyLoading |= queue.isLoading && !queue.hasValue;
      anyError |= queue.hasError;
      final SabQueue? q = queue.value;
      if (q != null) {
        totalSpeed += parseSabSpeed(q.speed);
        for (final SabSlot s in q.slots) {
          rows.add(_DownloadRow(
            name: s.filename,
            progress: ((double.tryParse(s.percentage) ?? 0) / 100)
                .clamp(0, 1)
                .toDouble(),
            instance: i,
          ));
        }
      }
    }
    for (final Instance i in nzbgetInstances) {
      final AsyncValue<List<NzbgetGroup>> groups =
          ref.watch(nzbgetQueueProvider(i));
      anyLoading |= groups.isLoading && !groups.hasValue;
      anyError |= groups.hasError;
      for (final NzbgetGroup g in groups.value ?? const <NzbgetGroup>[]) {
        rows.add(_DownloadRow(name: g.name, progress: g.progress, instance: i));
      }
      totalSpeed += ref.watch(nzbgetStatusProvider(i)).value?.downloadRate ?? 0;
    }
    for (final Instance i in delugeInstances) {
      final AsyncValue<List<DelugeTorrent>> torrents =
          ref.watch(delugeRawTorrentsProvider(i));
      anyLoading |= torrents.isLoading && !torrents.hasValue;
      anyError |= torrents.hasError;
      for (final DelugeTorrent t
          in torrents.value ?? const <DelugeTorrent>[]) {
        // Seeding torrents are not downloads; listing them here would make a
        // finished library look like live activity.
        if (t.isDownloading) {
          rows.add(_DownloadRow(
            name: t.name,
            progress: t.progressFraction,
            instance: i,
          ));
        }
      }
      totalSpeed += ref
              .watch(delugeSessionStatusProvider(i))
              .value
              ?.downloadRate
              .round() ??
          0;
    }
    for (final Instance i in transmissionInstances) {
      final AsyncValue<List<TransmissionTorrent>> torrents =
          ref.watch(transmissionRawTorrentsProvider(i));
      anyLoading |= torrents.isLoading && !torrents.hasValue;
      anyError |= torrents.hasError;
      for (final TransmissionTorrent t
          in torrents.value ?? const <TransmissionTorrent>[]) {
        // Finished seeds are not downloads.
        if (t.status.isDownloading) {
          rows.add(_DownloadRow(
            name: t.name,
            progress: t.percentDone.clamp(0, 1).toDouble(),
            instance: i,
          ));
        }
      }
      totalSpeed +=
          ref.watch(transmissionSessionStatsProvider(i)).value?.downloadSpeed ??
              0;
    }
    for (final Instance i in rtorrentInstances) {
      final AsyncValue<List<RtorrentTorrent>> torrents =
          ref.watch(rtorrentRawTorrentsProvider(i));
      anyLoading |= torrents.isLoading && !torrents.hasValue;
      anyError |= torrents.hasError;
      for (final RtorrentTorrent t
          in torrents.value ?? const <RtorrentTorrent>[]) {
        // Finished seeds are not downloads.
        if (t.status.isDownloading) {
          rows.add(_DownloadRow(
            name: t.name,
            progress: t.progress,
            instance: i,
          ));
        }
      }
      totalSpeed += ref.watch(rtorrentGlobalProvider(i)).value?.downRate ?? 0;
    }

    // What is moving comes first, then furthest along. Progress alone let a
    // queue full of nearly-complete torrents push the live download off a card
    // that only shows three.
    rows.sort((_DownloadRow a, _DownloadRow b) {
      if (a.moving != b.moving) {
        return a.moving ? -1 : 1;
      }
      return b.progress.compareTo(a.progress);
    });
    final List<_DownloadRow> top = rows.take(3).toList();

    Widget body;
    if (rows.isEmpty && anyLoading) {
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
    } else if (rows.isEmpty && anyError) {
      body = DashboardErrorRow(onRetry: () => _refresh(ref));
    } else if (rows.isEmpty) {
      body = const DashboardIdleRow(text: 'Nothing downloading');
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final _DownloadRow row in top) _ItemRow(row: row),
          if (rows.length > top.length)
            DashboardIdleRow(text: '+${rows.length - top.length} more'),
        ],
      );
    }

    return DashboardWidgetCard(
      kind: DashboardWidgetKind.downloads,
      accent: cs.primary,
      trailing: totalSpeed > 0
          ? DashboardPill(
              icon: Icons.arrow_downward_rounded,
              label: '${fmtBytes(totalSpeed)}/s',
              color: cs.primary,
            )
          : null,
      child: body,
    );
  }

  void _refresh(WidgetRef ref) {
    for (final Instance i in qbitInstances) {
      ref.invalidate(qbitRawTorrentsProvider(i));
      ref.invalidate(qbitTransferProvider(i));
    }
    for (final Instance i in sabInstances) {
      ref.invalidate(sabQueueProvider(i));
    }
    for (final Instance i in nzbgetInstances) {
      ref.invalidate(nzbgetQueueProvider(i));
      ref.invalidate(nzbgetStatusProvider(i));
    }
    for (final Instance i in delugeInstances) {
      ref.invalidate(delugeRawTorrentsProvider(i));
      ref.invalidate(delugeSessionStatusProvider(i));
    }
    for (final Instance i in transmissionInstances) {
      ref.invalidate(transmissionRawTorrentsProvider(i));
      ref.invalidate(transmissionSessionStatsProvider(i));
    }
    for (final Instance i in rtorrentInstances) {
      ref.invalidate(rtorrentRawTorrentsProvider(i));
      ref.invalidate(rtorrentGlobalProvider(i));
    }
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.row});

  final _DownloadRow row;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => context.go(
        AtriumRoutes.servicePath(row.instance.kind.name, row.instance.id),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    row.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: Insets.sm),
                Text(
                  '${(row.progress * 100).toStringAsFixed(0)}%',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicatorM3E(
                size: LinearProgressM3ESize.s,
                shape: ProgressM3EShape.flat,
                value: row.progress,
                activeColor: cs.primary,
                trackColor: cs.surfaceContainerHighest,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
