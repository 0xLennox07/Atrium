import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';

import 'models/sonarr_episode.dart';
import 'models/sonarr_release.dart';
import 'sonarr_api.dart';
import 'sonarr_providers.dart';

class SonarrReleaseSearchScreen extends ConsumerWidget {
  const SonarrReleaseSearchScreen({
    required this.instance,
    required this.episode,
    super.key,
  });

  final Instance instance;
  final SonarrEpisode episode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String epCode = 'S${episode.seasonNumber.toString().padLeft(2, '0')}E${episode.episodeNumber.toString().padLeft(2, '0')}';
    final AsyncValue<List<SonarrRelease>> releasesValue =
        ref.watch(sonarrReleasesProvider((instance, episode.id)));

    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Search Releases'),
            Text(
              '$epCode • ${episode.title ?? "Episode ${episode.episodeNumber}"}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(sonarrReleasesProvider((instance, episode.id))),
        child: AsyncValueView<List<SonarrRelease>>(
          value: releasesValue,
          onRetry: () =>
              ref.invalidate(sonarrReleasesProvider((instance, episode.id))),
          loading: Center(
            child: Padding(
              padding: const EdgeInsets.all(Insets.xl),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const CircularProgressIndicator(),
                  const SizedBox(height: Insets.lg),
                  Text(
                    'Querying Indexers...',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: Insets.sm),
                  Text(
                    'Contacting your configured indexers in real time. This can take up to a minute depending on indexer response times.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ),
          data: (List<SonarrRelease> list) {
            if (list.isEmpty) {
              return const EmptyView(
                icon: Icons.search_off,
                title: 'No releases found',
                message: 'No matching releases were found on your indexers.',
              );
            }

            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: Insets.sm),
              itemCount: list.length,
              itemBuilder: (BuildContext context, int index) {
                final SonarrRelease release = list[index];
                return _ReleaseTile(
                  instance: instance,
                  release: release,
                  onGrabbed: () {
                    // Refreshes the episodes list to reflect the downloaded status
                    ref.invalidate(sonarrEpisodesProvider((instance, episode.seriesId)));
                    Navigator.pop(context);
                  },
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ReleaseTile extends ConsumerStatefulWidget {
  const _ReleaseTile({
    required this.instance,
    required this.release,
    required this.onGrabbed,
  });

  final Instance instance;
  final SonarrRelease release;
  final VoidCallback onGrabbed;

  @override
  ConsumerState<_ReleaseTile> createState() => _ReleaseTileState();
}

class _ReleaseTileState extends ConsumerState<_ReleaseTile> {
  bool _grabbing = false;

  Future<void> _grab() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Grab release?'),
        content: Text(widget.release.title),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Grab'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _grabbing = true);
    try {
      final SonarrApi api = await ref.read(sonarrApiProvider(widget.instance).future);
      await api.grabRelease(widget.release);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Release grabbed successfully!')),
        );
        widget.onGrabbed();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to grab release: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _grabbing = false);
      }
    }
  }

  void _showRejections() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Rejection Reasons'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.release.rejections
                .map(
                  (String r) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(child: Text(r)),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SonarrRelease r = widget.release;

    final String sizeStr = _fmtSize(r.size);
    final String peersStr = r.isTorrent
        ? 'S:${r.seeders ?? 0} L:${r.leechers ?? 0}'
        : '';

    final List<String> details = <String>[
      if (r.indexer != null) r.indexer!,
      sizeStr,
      r.ageLabel,
      if (peersStr.isNotEmpty) peersStr,
    ];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4.0, horizontal: Insets.md),
      child: ListTile(
        leading: Icon(
          r.isTorrent ? Icons.swap_vert : Icons.newspaper_outlined,
          color: theme.colorScheme.primary,
        ),
        title: Text(
          r.title,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 4),
            Text(
              details.join(' • '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if (!r.approved && r.rejections.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: _showRejections,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 14,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Rejected (view reasons)',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        trailing: _grabbing
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : IconButton(
                icon: Icon(
                  Icons.cloud_download_outlined,
                  color: r.downloadAllowed ? theme.colorScheme.primary : theme.colorScheme.outline,
                ),
                tooltip: r.downloadAllowed ? 'Grab release' : 'Download not allowed',
                onPressed: r.downloadAllowed ? _grab : null,
              ),
      ),
    );
  }
}

String _fmtSize(int bytes) {
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
  final String text =
      value >= 100 || unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}
