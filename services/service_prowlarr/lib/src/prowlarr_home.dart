import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/prowlarr_indexer.dart';
import 'models/prowlarr_indexer_stats.dart';
import 'prowlarr_api.dart';
import 'prowlarr_providers.dart';
import 'prowlarr_search_screen.dart';

/// Prowlarr's per-instance UI: the indexer list with enable status and grab /
/// query counts. Tapping an indexer opens a sheet with full stats, an
/// enable toggle, and a connectivity test. The FAB opens manual search
/// across all indexers.
class ProwlarrHome extends ConsumerWidget {
  const ProwlarrHome({required this.instance, super.key});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<ProwlarrIndexer>> indexers =
        ref.watch(prowlarrIndexersProvider(instance));
    final Map<int, ProwlarrIndexerStat> stats =
        ref.watch(prowlarrStatsByIdProvider(instance)).value ??
            const <int, ProwlarrIndexerStat>{};

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(prowlarrIndexersProvider(instance));
          ref.invalidate(prowlarrStatsByIdProvider(instance));
        },
        child: AsyncValueView<List<ProwlarrIndexer>>(
          value: indexers,
          onRetry: () => ref.invalidate(prowlarrIndexersProvider(instance)),
          data: (List<ProwlarrIndexer> list) {
            if (list.isEmpty) {
              return const EmptyView(
                icon: Icons.travel_explore_outlined,
                title: 'No indexers',
                message: 'This Prowlarr has no indexers configured yet.',
              );
            }
            return ListView.builder(
              padding: Insets.pageH,
              itemCount: list.length,
              itemBuilder: (BuildContext context, int index) {
                final ProwlarrIndexer ix = list[index];
                final ProwlarrIndexerStat? stat = stats[ix.id];
                return ListTile(
                  leading: Icon(
                    ix.enable ? Icons.check_circle : Icons.cancel_outlined,
                    color: ix.enable
                        ? Colors.green
                        : Theme.of(context).colorScheme.outline,
                  ),
                  title: Text(ix.name),
                  subtitle: Text(
                    <String>[
                      if (ix.protocol != null) ix.protocol!,
                      if (stat != null) '${stat.numberOfGrabs} grabs',
                      if (stat != null) '${stat.numberOfQueries} queries',
                    ].join(' • '),
                  ),
                  onTap: () => _showIndexerSheet(context, ix, stat),
                  trailing: IconButton(
                    tooltip: 'Test',
                    icon: const Icon(Icons.network_check),
                    onPressed: () => _test(context, ref, ix),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        // Root navigator: see qBit detail history.
        onPressed: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            builder: (_) => ProwlarrSearchScreen(instance: instance),
          ),
        ),
        icon: const Icon(Icons.search),
        label: const Text('Search'),
      ),
    );
  }

  void _showIndexerSheet(
    BuildContext context,
    ProwlarrIndexer indexer,
    ProwlarrIndexerStat? stat,
  ) {
    // Root navigator: branch-navigator sheets get swept by GoRouter shell
    // rebuilds (see qBit add sheet for history).
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (_) => _IndexerSheet(
        instance: instance,
        indexer: indexer,
        stat: stat,
      ),
    );
  }

  Future<void> _test(
    BuildContext context,
    WidgetRef ref,
    ProwlarrIndexer ix,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final ProwlarrApi api =
          await ref.read(prowlarrApiProvider(instance).future);
      await api.testIndexer(ix.id);
      messenger.showSnackBar(
        SnackBar(content: Text('${ix.name}: test passed')),
      );
    } on Object catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('${ix.name}: ${_errorMessage(e)}')),
      );
    }
  }
}

/// Bottom sheet with an indexer's config summary, full stats, an enable
/// toggle, and a test action.
class _IndexerSheet extends ConsumerStatefulWidget {
  const _IndexerSheet({
    required this.instance,
    required this.indexer,
    required this.stat,
  });

  final Instance instance;
  final ProwlarrIndexer indexer;
  final ProwlarrIndexerStat? stat;

  @override
  ConsumerState<_IndexerSheet> createState() => _IndexerSheetState();
}

class _IndexerSheetState extends ConsumerState<_IndexerSheet> {
  late bool _enabled = widget.indexer.enable;
  bool _busy = false;

  // Inline feedback: snackbars fired from inside a modal sheet render on the
  // scaffold UNDERNEATH it and are invisible while the sheet is up.
  String? _status;
  bool _statusOk = true;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ProwlarrIndexer ix = widget.indexer;
    final ProwlarrIndexerStat? stat = widget.stat;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          0,
          Insets.lg,
          Insets.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(ix.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: Insets.xs),
            Text(
              <String>[
                if (ix.protocol != null) ix.protocol!,
                if (ix.privacy != null) ix.privacy!,
                'priority ${ix.priority}',
              ].join(' • '),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: Insets.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Enabled'),
              value: _enabled,
              onChanged: _busy ? null : _setEnabled,
            ),
            if (stat != null) ...<Widget>[
              const Divider(),
              _StatRow(label: 'Queries', value: '${stat.numberOfQueries}'),
              _StatRow(label: 'Grabs', value: '${stat.numberOfGrabs}'),
              _StatRow(
                label: 'RSS queries',
                value: '${stat.numberOfRssQueries}',
              ),
              _StatRow(
                label: 'Failed queries',
                value: '${stat.numberOfFailedQueries}',
              ),
              _StatRow(
                label: 'Failed grabs',
                value: '${stat.numberOfFailedGrabs}',
              ),
              _StatRow(
                label: 'Avg response',
                value: '${stat.averageResponseTime} ms',
              ),
            ],
            const SizedBox(height: Insets.md),
            OutlinedButton.icon(
              onPressed: _busy ? null : _test,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check),
              label: const Text('Test'),
            ),
            if (_status != null) ...<Widget>[
              const SizedBox(height: Insets.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    _statusOk ? Icons.check_circle : Icons.error_outline,
                    size: 16,
                    color: _statusOk
                        ? Colors.green
                        : theme.colorScheme.error,
                  ),
                  const SizedBox(width: Insets.xs),
                  Flexible(
                    child: Text(_status!, style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _setEnabled(bool value) async {
    setState(() {
      _enabled = value;
      _busy = true;
      _status = null;
    });
    try {
      final ProwlarrApi api =
          await ref.read(prowlarrApiProvider(widget.instance).future);
      await api.setIndexerEnabled(widget.indexer.id, enabled: value);
      ref.invalidate(prowlarrIndexersProvider(widget.instance));
      if (mounted) {
        setState(() {
          _statusOk = true;
          _status = value ? 'Enabled' : 'Disabled';
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _enabled = !value;
          _statusOk = false;
          _status = _errorMessage(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      final ProwlarrApi api =
          await ref.read(prowlarrApiProvider(widget.instance).future);
      await api.testIndexer(widget.indexer.id);
      if (mounted) {
        setState(() {
          _statusOk = true;
          _status = 'Test passed';
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _statusOk = false;
          _status = _errorMessage(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ),
          Text(value, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

String _errorMessage(Object e) {
  if (e is NetworkException && e.message.isNotEmpty) {
    return e.message;
  }
  return 'request failed';
}
