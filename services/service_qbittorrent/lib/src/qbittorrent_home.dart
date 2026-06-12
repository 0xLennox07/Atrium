import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'add_torrent_sheet.dart';
import 'models/qbit_torrent.dart';
import 'models/qbit_transfer_info.dart';
import 'qbittorrent_client.dart';
import 'qbittorrent_providers.dart';
import 'torrent_detail_screen.dart';

/// qBittorrent's per-instance UI: a global up/down header (with pause-all /
/// resume-all), a torrent list with progress / speeds / per-item actions, and
/// a FAB to add new torrents from a magnet, URL, or `.torrent` file.
class QbittorrentHome extends ConsumerWidget {
  const QbittorrentHome({required this.instance, super.key});

  final Instance instance;

  void _refresh(WidgetRef ref) {
    ref.invalidate(qbitTorrentsProvider(instance));
    ref.invalidate(qbitTransferProvider(instance));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<QbitTorrent>> torrents =
        ref.watch(qbitTorrentsProvider(instance));

    return Scaffold(
      body: Column(
        children: <Widget>[
          _TransferHeader(instance: instance),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _refresh(ref),
              child: AsyncValueView<List<QbitTorrent>>(
                value: torrents,
                onRetry: () => ref.invalidate(qbitTorrentsProvider(instance)),
                data: (List<QbitTorrent> list) {
                  if (list.isEmpty) {
                    return const EmptyView(
                      icon: Icons.cloud_download_outlined,
                      title: 'No torrents',
                      message: 'Tap + to add a magnet, URL, or .torrent file.',
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.lg,
                      0,
                      Insets.lg,
                      // leave room so the FAB doesn't cover the last card
                      80,
                    ),
                    itemCount: list.length,
                    itemBuilder: (BuildContext context, int index) =>
                        _TorrentTile(instance: instance, torrent: list[index]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final bool added = await AddTorrentSheet.show(context, instance);
          if (added) {
            _refresh(ref);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
    );
  }
}

class _TransferHeader extends ConsumerWidget {
  const _TransferHeader({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final QbitTransferInfo? info =
        ref.watch(qbitTransferProvider(instance)).value;
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.sm,
        Insets.sm,
        Insets.sm,
      ),
      child: Row(
        children: <Widget>[
          _SpeedBadge(
            icon: Icons.arrow_downward,
            label: info == null ? '-' : '${fmtBytes(info.dlSpeed)}/s',
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: Insets.lg),
          _SpeedBadge(
            icon: Icons.arrow_upward,
            label: info == null ? '-' : '${fmtBytes(info.upSpeed)}/s',
            color: theme.colorScheme.tertiary,
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Pause all',
            icon: const Icon(Icons.pause_circle_outline),
            onPressed: () => _setAll(ref, paused: true),
          ),
          IconButton(
            tooltip: 'Resume all',
            icon: const Icon(Icons.play_circle_outline),
            onPressed: () => _setAll(ref, paused: false),
          ),
        ],
      ),
    );
  }

  Future<void> _setAll(WidgetRef ref, {required bool paused}) async {
    final QbittorrentClient client =
        await ref.read(qbittorrentClientProvider(instance).future);
    await client.setAllPaused(paused: paused);
    ref.invalidate(qbitTorrentsProvider(instance));
    ref.invalidate(qbitTransferProvider(instance));
  }
}

class _SpeedBadge extends StatelessWidget {
  const _SpeedBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 16, color: color),
        const SizedBox(width: Insets.xs),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}

class _TorrentTile extends ConsumerWidget {
  const _TorrentTile({required this.instance, required this.torrent});

  final Instance instance;
  final QbitTorrent torrent;

  bool get _isPaused =>
      torrent.state.toLowerCase().contains('paused') ||
      torrent.state.toLowerCase().contains('stopped');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int pct = (torrent.progress * 100).round();
    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      child: InkWell(
        borderRadius: Radii.card,
        // rootNavigator: pages pushed on the shell navigator get swept on the
        // next GoRouter rebuild (StatefulShellRoute rebuilds its branch
        // navigators declaratively). Same fix as the media-server player.
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => TorrentDetailScreen(
              instance: instance,
              torrent: torrent,
            ),
          ),
        ),
        child: Padding(
          padding: Insets.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                torrent.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: Insets.sm),
              LinearProgressIndicator(value: torrent.progress.clamp(0, 1)),
              const SizedBox(height: Insets.xs),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '$pct% • ${_friendlyState(torrent.state)} • '
                      '↓${fmtBytes(torrent.dlspeed)}/s ↑${fmtBytes(torrent.upspeed)}/s',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause),
                    onPressed: () => _toggle(ref),
                  ),
                  _OverflowMenu(
                    instance: instance,
                    torrent: torrent,
                    onDelete: () => _confirmDelete(context, ref),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(WidgetRef ref) async {
    final QbittorrentClient client =
        await ref.read(qbittorrentClientProvider(instance).future);
    if (_isPaused) {
      await client.resume(torrent.hash);
    } else {
      await client.pause(torrent.hash);
    }
    ref.invalidate(qbitTorrentsProvider(instance));
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    bool deleteFiles = false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => AlertDialog(
          title: const Text('Remove torrent?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(torrent.name, maxLines: 3, overflow: TextOverflow.ellipsis),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Also delete downloaded files'),
                value: deleteFiles,
                onChanged: (bool? v) =>
                    setState(() => deleteFiles = v ?? false),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
    if (ok ?? false) {
      final QbittorrentClient client =
          await ref.read(qbittorrentClientProvider(instance).future);
      await client.delete(torrent.hash, deleteFiles: deleteFiles);
      ref.invalidate(qbitTorrentsProvider(instance));
    }
  }
}

/// Per-torrent overflow: recheck, set category, queue up/down, delete.
class _OverflowMenu extends ConsumerWidget {
  const _OverflowMenu({
    required this.instance,
    required this.torrent,
    required this.onDelete,
  });

  final Instance instance;
  final QbitTorrent torrent;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      onSelected: (String value) async {
        switch (value) {
          case 'recheck':
            await _run(ref, (QbittorrentClient c) => c.recheck(torrent.hash));
          case 'category':
            await _editCategory(context, ref);
          case 'prio_up':
            await _run(
              ref,
              (QbittorrentClient c) =>
                  c.setPriority(torrent.hash, increase: true),
            );
          case 'prio_down':
            await _run(
              ref,
              (QbittorrentClient c) =>
                  c.setPriority(torrent.hash, increase: false),
            );
          case 'delete':
            onDelete();
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'category',
          child: ListTile(
            leading: Icon(Icons.label_outline),
            title: Text('Set category'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'prio_up',
          child: ListTile(
            leading: Icon(Icons.arrow_upward),
            title: Text('Move up in queue'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'prio_down',
          child: ListTile(
            leading: Icon(Icons.arrow_downward),
            title: Text('Move down in queue'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem<String>(
          value: 'recheck',
          child: ListTile(
            leading: Icon(Icons.fact_check_outlined),
            title: Text('Force recheck'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Remove'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _run(
    WidgetRef ref,
    Future<void> Function(QbittorrentClient) action,
  ) async {
    final QbittorrentClient client =
        await ref.read(qbittorrentClientProvider(instance).future);
    await action(client);
    ref.invalidate(qbitTorrentsProvider(instance));
  }

  Future<void> _editCategory(BuildContext context, WidgetRef ref) async {
    final List<String> cats =
        await ref.read(qbitCategoriesProvider(instance).future);
    if (!context.mounted) {
      return;
    }
    final String? chosen = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => SimpleDialog(
        title: const Text('Set category'),
        children: <Widget>[
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(''),
            child: const Text('None'),
          ),
          for (final String c in cats)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(c),
              child: Text(c),
            ),
        ],
      ),
    );
    if (chosen != null) {
      await _run(
        ref,
        (QbittorrentClient c) => c.setCategory(torrent.hash, chosen),
      );
    }
  }
}

/// Maps a raw qBittorrent state to a short friendly label.
String _friendlyState(String state) {
  switch (state) {
    case 'downloading':
    case 'forcedDL':
      return 'Downloading';
    case 'uploading':
    case 'forcedUP':
      return 'Seeding';
    case 'stalledDL':
      return 'Stalled';
    case 'stalledUP':
      return 'Seeding (idle)';
    case 'pausedDL':
    case 'stoppedDL':
      return 'Paused';
    case 'pausedUP':
    case 'stoppedUP':
      return 'Completed';
    case 'queuedDL':
    case 'queuedUP':
      return 'Queued';
    case 'checkingDL':
    case 'checkingUP':
    case 'checkingResumeData':
      return 'Checking';
    case 'metaDL':
      return 'Fetching metadata';
    case 'error':
    case 'missingFiles':
      return 'Error';
    default:
      return state;
  }
}

/// Human-readable byte size (decimal units, matching qBittorrent's display).
String fmtBytes(num bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final String text = value >= 100 || unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}
