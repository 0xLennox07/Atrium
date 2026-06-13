import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/radarr_add_models.dart';
import 'radarr_api.dart';
import 'radarr_providers.dart';

/// Search the metadata provider and add a movie to Radarr.
///
/// Flow: type a title (debounced lookup) -> tap a result -> bottom sheet with
/// quality profile + root folder options -> Add. Results already in the
/// library show a badge and open nothing.
class AddMovieScreen extends ConsumerStatefulWidget {
  const AddMovieScreen({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<AddMovieScreen> createState() => _AddMovieScreenState();
}

class _AddMovieScreenState extends ConsumerState<AddMovieScreen> {
  final TextEditingController _query = TextEditingController();
  Timer? _debounce;
  List<RadarrLookupResult>? _results;
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
      final RadarrApi api =
          await ref.read(radarrApiProvider(widget.instance).future);
      final List<RadarrLookupResult> found =
          await api.lookupMovies(term.trim());
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
      appBar: AppBar(title: const Text('Add movie')),
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
                hintText: 'Search for a movie...',
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
    final List<RadarrLookupResult>? results = _results;
    if (results == null) {
      return const EmptyView(
        icon: Icons.search,
        title: 'Search TMDB',
        message: 'Type at least two characters to look up a movie.',
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
  final RadarrLookupResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      child: InkWell(
        borderRadius: Radii.card,
        onTap: result.inLibrary
            ? null
            : () => _AddMovieSheet.show(context, instance, result),
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
                            Icons.movie_outlined,
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
                              Icons.movie_outlined,
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
                        if (result.runtime > 0) '${result.runtime} min',
                        if (result.studio != null &&
                            result.studio!.isNotEmpty)
                          result.studio!,
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
class _AddMovieSheet extends ConsumerStatefulWidget {
  const _AddMovieSheet({required this.instance, required this.result});

  final Instance instance;
  final RadarrLookupResult result;

  static Future<void> show(
    BuildContext context,
    Instance instance,
    RadarrLookupResult result,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      useRootNavigator: true,
      builder: (_) => _AddMovieSheet(instance: instance, result: result),
    );
  }

  @override
  ConsumerState<_AddMovieSheet> createState() => _AddMovieSheetState();
}

class _AddMovieSheetState extends ConsumerState<_AddMovieSheet> {
  List<RadarrQualityProfile>? _profiles;
  List<RadarrRootFolder>? _folders;
  int? _profileId;
  String? _rootPath;
  bool _monitored = true;
  bool _searchOnAdd = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final RadarrApi api =
          await ref.read(radarrApiProvider(widget.instance).future);
      final List<RadarrQualityProfile> profiles =
          await api.getQualityProfiles();
      final List<RadarrRootFolder> folders = await api.getRootFolders();
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
      final RadarrApi api =
          await ref.read(radarrApiProvider(widget.instance).future);
      await api.addMovie(
        widget.result,
        qualityProfileId: _profileId!,
        rootFolderPath: _rootPath!,
        monitored: _monitored,
        searchOnAdd: _searchOnAdd,
      );
      ref.invalidate(radarrMoviesProvider(widget.instance));
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
                  for (final RadarrQualityProfile p in _profiles!)
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
                  for (final RadarrRootFolder f in _folders!)
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Monitored'),
              value: _monitored,
              onChanged: (bool v) => setState(() => _monitored = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Search for movie after adding'),
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
                  label: const Text('Add movie'),
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
