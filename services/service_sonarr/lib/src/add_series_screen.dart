import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/sonarr_add_models.dart';
import 'sonarr_api.dart';
import 'sonarr_providers.dart';

/// Search the metadata provider and add a series to Sonarr.
///
/// Flow: type a title (debounced lookup) -> tap a result -> bottom sheet with
/// quality profile + root folder + monitor options -> Add. Results already in
/// the library show a badge and open nothing.
class AddSeriesScreen extends ConsumerStatefulWidget {
  const AddSeriesScreen({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<AddSeriesScreen> createState() => _AddSeriesScreenState();
}

class _AddSeriesScreenState extends ConsumerState<AddSeriesScreen> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<SonarrLookupResult>? _results;
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    if (text.trim().length < 2) {
      setState(() {
        _results = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () => _search(text));
  }

  Future<void> _search(String term) async {
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final SonarrApi api =
          await ref.read(sonarrApiProvider(widget.instance).future);
      final List<SonarrLookupResult> found = await api.lookupSeries(term.trim());
      if (mounted) {
        setState(() {
          _results = found;
          _searching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searching = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add series')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: Insets.page,
            child: TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _onChanged,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: 'Search for a show...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _query.clear();
                          _onChanged('');
                        },
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          if (_searching) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: Insets.page,
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          Expanded(child: _resultsList()),
        ],
      ),
    );
  }

  Widget _resultsList() {
    final List<SonarrLookupResult>? results = _results;
    if (results == null) {
      return const EmptyView(
        icon: Icons.search,
        title: 'Search TheTVDB',
        message: 'Type at least two characters to look up a show.',
      );
    }
    if (results.isEmpty) {
      return const EmptyView(
        icon: Icons.search_off,
        title: 'No matches',
        message: 'Try a different title.',
      );
    }
    return ListView.builder(
      padding: Insets.pageH,
      itemCount: results.length,
      itemBuilder: (BuildContext context, int index) => _ResultCard(
        instance: widget.instance,
        result: results[index],
      ),
    );
  }
}

class _ResultCard extends ConsumerWidget {
  const _ResultCard({required this.instance, required this.result});

  final Instance instance;
  final SonarrLookupResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      child: InkWell(
        borderRadius: Radii.card,
        onTap: result.inLibrary
            ? null
            : () => _AddSeriesSheet.show(context, instance, result),
        child: Padding(
          padding: const EdgeInsets.all(Insets.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 56,
                  height: 84,
                  child: result.remotePoster == null
                      ? Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.live_tv_outlined,
                            color: theme.colorScheme.outline,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: result.remotePoster!,
                          fit: BoxFit.cover,
                          memCacheWidth: 120,
                          errorWidget: (_, __, ___) => Container(
                            color:
                                theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.live_tv_outlined,
                              color: theme.colorScheme.outline,
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
                    Text(result.title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      <String>[
                        if (result.year != null && result.year! > 0)
                          '${result.year}',
                        if (result.network != null &&
                            result.network!.isNotEmpty)
                          result.network!,
                        if (result.seasonCount > 0)
                          '${result.seasonCount} season'
                              '${result.seasonCount == 1 ? '' : 's'}',
                      ].join(' • '),
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    if (result.overview != null &&
                        result.overview!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: Insets.xs),
                      Text(
                        result.overview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              if (result.inLibrary)
                Padding(
                  padding: const EdgeInsets.only(left: Insets.sm),
                  child: Chip(
                    label: const Text('In library'),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    labelStyle: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(left: Insets.sm),
                  child: Icon(Icons.add_circle_outline),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Options sheet shown when a result is tapped.
class _AddSeriesSheet extends ConsumerStatefulWidget {
  const _AddSeriesSheet({required this.instance, required this.result});

  final Instance instance;
  final SonarrLookupResult result;

  static Future<void> show(
    BuildContext context,
    Instance instance,
    SonarrLookupResult result,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => _AddSeriesSheet(instance: instance, result: result),
    );
  }

  @override
  ConsumerState<_AddSeriesSheet> createState() => _AddSeriesSheetState();
}

class _AddSeriesSheetState extends ConsumerState<_AddSeriesSheet> {
  List<SonarrQualityProfile>? _profiles;
  List<SonarrRootFolder>? _folders;
  int? _profileId;
  String? _rootPath;
  String _monitor = 'all';
  bool _searchOnAdd = true;
  bool _busy = false;
  String? _error;

  static const Map<String, String> _monitorChoices = <String, String>{
    'all': 'All episodes',
    'future': 'Future episodes',
    'missing': 'Missing episodes',
    'firstSeason': 'First season',
    'latestSeason': 'Latest season',
    'none': 'None',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final SonarrApi api =
          await ref.read(sonarrApiProvider(widget.instance).future);
      final List<SonarrQualityProfile> profiles =
          await api.getQualityProfiles();
      final List<SonarrRootFolder> folders = await api.getRootFolders();
      if (mounted) {
        setState(() {
          _profiles = profiles;
          _folders = folders;
          _profileId = profiles.isEmpty ? null : profiles.first.id;
          _rootPath = folders.isEmpty ? null : folders.first.path;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    }
  }

  Future<void> _add() async {
    if (_profileId == null || _rootPath == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final SonarrApi api =
          await ref.read(sonarrApiProvider(widget.instance).future);
      await api.addSeries(
        widget.result,
        qualityProfileId: _profileId!,
        rootFolderPath: _rootPath!,
        monitor: _monitor,
        searchForMissing: _searchOnAdd,
      );
      ref.invalidate(sonarrSeriesProvider(widget.instance));
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added "${widget.result.title}"')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not add: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final EdgeInsets viewInsets = MediaQuery.of(context).viewInsets;
    final bool loading = _profiles == null || _folders == null;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SingleChildScrollView(
        padding: Insets.page,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(widget.result.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: Insets.md),
            if (loading && _error == null) const LinearProgressIndicator(),
            if (_profiles != null)
              DropdownButtonFormField<int>(
                initialValue: _profileId,
                decoration: const InputDecoration(
                  labelText: 'Quality profile',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<int>>[
                  for (final SonarrQualityProfile p in _profiles!)
                    DropdownMenuItem<int>(value: p.id, child: Text(p.name)),
                ],
                onChanged: (int? v) => setState(() => _profileId = v),
              ),
            const SizedBox(height: Insets.sm),
            if (_folders != null)
              DropdownButtonFormField<String>(
                initialValue: _rootPath,
                decoration: const InputDecoration(
                  labelText: 'Root folder',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final SonarrRootFolder f in _folders!)
                    DropdownMenuItem<String>(
                      value: f.path,
                      child: Text(
                        '${f.path} (${_fmtSize(f.freeSpace)} free)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (String? v) => setState(() => _rootPath = v),
              ),
            const SizedBox(height: Insets.sm),
            DropdownButtonFormField<String>(
              initialValue: _monitor,
              decoration: const InputDecoration(
                labelText: 'Monitor',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final MapEntry<String, String> e
                    in _monitorChoices.entries)
                  DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
              ],
              onChanged: (String? v) =>
                  setState(() => _monitor = v ?? 'all'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Search for episodes after adding'),
              value: _searchOnAdd,
              onChanged: (bool v) => setState(() => _searchOnAdd = v),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const SizedBox(height: Insets.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed:
                      _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: Insets.sm),
                FilledButton.icon(
                  onPressed:
                      _busy || loading || _profileId == null || _rootPath == null
                          ? null
                          : _add,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Add series'),
                ),
              ],
            ),
          ],
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
