import 'dart:async';
import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../service_radarr.dart';

class AddMovieScreen extends ConsumerStatefulWidget {
  const AddMovieScreen({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<AddMovieScreen> createState() => _AddMovieScreenState();
}

class _AddMovieScreenState extends ConsumerState<AddMovieScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _debouncedQuery = '';
  Timer? _debounceTimer;
  final ScrollController _scrollController = ScrollController();
  double _lastBottomInset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchFocusNode.requestFocus();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    _searchFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final double bottomInset = WidgetsBinding
        .instance.platformDispatcher.views.first.viewInsets.bottom;
    if (bottomInset == 0 && _lastBottomInset > 0) {
      if (_searchFocusNode.hasFocus) {
        _searchFocusNode.unfocus();
      }
    }
    _lastBottomInset = bottomInset;
  }

  void _onFocusChange() {
    setState(() {});
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.userScrollDirection !=
            ScrollDirection.idle) {
      if (_searchFocusNode.hasFocus) {
        _searchFocusNode.unfocus();
      }
    }
  }

  void _onSearchChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _debouncedQuery = _searchController.text.trim();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final AsyncValue<List<RadarrMovie>> lookupResults = ref.watch(
      radarrLookupMovieProvider((widget.instance, _debouncedQuery)),
    );

    final List<RadarrMovie> localMovies =
        ref.watch(radarrMoviesProvider(widget.instance)).value ?? [];

    return PopScope<Object?>(
      canPop: !_searchFocusNode.hasFocus,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
        }
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          scrolledUnderElevation: 0.0,
          backgroundColor: cs.surface,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Padding(
            padding: const EdgeInsets.only(right: Insets.md),
            child: SearchBar(
              focusNode: _searchFocusNode,
              controller: _searchController,
              hintText: 'Search online catalog...',
              onTapOutside: (event) {
                if (_searchFocusNode.hasFocus) {
                  _searchFocusNode.unfocus();
                }
              },
              elevation: const WidgetStatePropertyAll<double>(0),
              backgroundColor: WidgetStatePropertyAll<Color>(
                cs.surfaceContainerHigh,
              ),
              shape: WidgetStatePropertyAll<OutlinedBorder>(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _debouncedQuery = '';
                      });
                    },
                  ),
              ],
            ),
          ),
        ),
        body: _debouncedQuery.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search,
                      size: 64,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: Insets.md),
                    Text(
                      'Search for a movie to add',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            : AsyncValueView<List<RadarrMovie>>(
                value: lookupResults,
                onRetry: () {
                  ref.invalidate(
                    radarrLookupMovieProvider(
                      (widget.instance, _debouncedQuery),
                    ),
                  );
                },
                data: (List<RadarrMovie> results) {
                  if (results.isEmpty) {
                    return const EmptyView(
                      icon: Icons.search_off_outlined,
                      title: 'No movies found',
                      message:
                          'We couldn\'t find any movies matching your query.',
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(Insets.md),
                    itemCount: results.length,
                    itemBuilder: (BuildContext context, int index) {
                      final RadarrMovie m = results[index];
                      final RadarrMovie? localMatch =
                          localMovies.firstWhereOrNull(
                        (local) => local.tmdbId == m.tmdbId,
                      );
                      final bool isAdded = localMatch != null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: Insets.md),
                        clipBehavior: Clip.antiAlias,
                        color: cs.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: InkWell(
                          onTap: () {
                            if (_searchFocusNode.hasFocus) {
                              _searchFocusNode.unfocus();
                            }
                            if (isAdded) {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => MovieDetailScreen(
                                    instance: widget.instance,
                                    movieId: localMatch.id,
                                    movie: localMatch,
                                  ),
                                ),
                              );
                            } else {
                              showModalBottomSheet<void>(
                                context: context,
                                useRootNavigator: true,
                                isScrollControlled: true,
                                useSafeArea: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(28),
                                  ),
                                ),
                                builder: (BuildContext context) =>
                                    RadarrAddMovieSheet(
                                  instance: widget.instance,
                                  movie: m,
                                ),
                              );
                            }
                          },
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: 100,
                                  child: AspectRatio(
                                    aspectRatio: 2 / 3,
                                    child: _PosterImage(
                                      instance: widget.instance,
                                      movie: m,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(Insets.md),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              m.title,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${m.year ?? "Unknown Year"} • ${m.studio ?? "Unknown Studio"}',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: Insets.sm),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            if (isAdded)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: cs.primaryContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.check,
                                                      size: 14,
                                                      color:
                                                          cs.onPrimaryContainer,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Added',
                                                      style: theme
                                                          .textTheme.labelSmall
                                                          ?.copyWith(
                                                        color: cs
                                                            .onPrimaryContainer,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else
                                              Icon(
                                                Icons.add_circle_outline,
                                                color: cs.primary,
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }
}

class RadarrAddMovieSheet extends ConsumerStatefulWidget {
  const RadarrAddMovieSheet({
    required this.instance,
    required this.movie,
    super.key,
  });

  final Instance instance;
  final RadarrMovie movie;

  @override
  ConsumerState<RadarrAddMovieSheet> createState() =>
      _RadarrAddMovieSheetState();
}

class _RadarrAddMovieSheetState extends ConsumerState<RadarrAddMovieSheet> {
  String? _selectedRootFolder;
  int? _selectedQualityProfileId;
  bool _monitored = true;
  String _minimumAvailability = 'announced';
  bool _searchForMovie = false;
  final List<int> _selectedTagIds = [];
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final AsyncValue<List<Map<String, dynamic>>> rootFoldersAsync =
        ref.watch(radarrRootFoldersProvider(widget.instance));
    final AsyncValue<List<Map<String, dynamic>>> qualityProfilesAsync =
        ref.watch(radarrQualityProfilesProvider(widget.instance));
    final AsyncValue<List<Map<String, dynamic>>> tagsAsync =
        ref.watch(radarrTagsProvider(widget.instance));

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            scrolledUnderElevation: 0.0,
            backgroundColor: cs.surface,
            automaticallyImplyLeading: false,
            title: const Text('Add Movie Options'),
            centerTitle: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(Insets.md),
                  children: [
                    Card(
                      elevation: 0,
                      color: cs.primaryContainer.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(Insets.md),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: SizedBox(
                                width: 70,
                                height: 105,
                                child: _PosterImage(
                                  instance: widget.instance,
                                  movie: widget.movie,
                                ),
                              ),
                            ),
                            const SizedBox(width: Insets.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.movie.title,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${widget.movie.year ?? "Unknown Year"} • ${widget.movie.studio ?? "Unknown Studio"}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.movie.overview ??
                                        'No overview available.',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: Insets.lg),
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(Insets.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Configuration',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: Insets.md),
                            rootFoldersAsync.when(
                              data: (folders) {
                                if (_selectedRootFolder == null &&
                                    folders.isNotEmpty) {
                                  _selectedRootFolder =
                                      folders.first['path'] as String;
                                }
                                return DropdownButtonFormField<String>(
                                  initialValue: _selectedRootFolder,
                                  decoration: const InputDecoration(
                                    labelText: 'Root Folder',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: folders
                                      .map(
                                        (f) => DropdownMenuItem(
                                          value: f['path'] as String,
                                          child: Text(f['path'] as String),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) => setState(
                                    () => _selectedRootFolder = val,
                                  ),
                                );
                              },
                              loading: () => const SizedBox(
                                height: 50,
                                child: Center(
                                  child: ExpressiveProgressIndicator(),
                                ),
                              ),
                              error: (_, __) =>
                                  const Text('Error loading folders'),
                            ),
                            const SizedBox(height: Insets.md),
                            qualityProfilesAsync.when(
                              data: (profiles) {
                                if (_selectedQualityProfileId == null &&
                                    profiles.isNotEmpty) {
                                  _selectedQualityProfileId =
                                      profiles.first['id'] as int;
                                }
                                return DropdownButtonFormField<int>(
                                  initialValue: _selectedQualityProfileId,
                                  decoration: const InputDecoration(
                                    labelText: 'Quality Profile',
                                    border: OutlineInputBorder(),
                                  ),
                                  items: profiles
                                      .map(
                                        (p) => DropdownMenuItem(
                                          value: p['id'] as int,
                                          child: Text(p['name'] as String),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (val) => setState(
                                    () => _selectedQualityProfileId = val,
                                  ),
                                );
                              },
                              loading: () => const SizedBox(
                                height: 50,
                                child: Center(
                                  child: ExpressiveProgressIndicator(),
                                ),
                              ),
                              error: (_, __) =>
                                  const Text('Error loading profiles'),
                            ),
                            const SizedBox(height: Insets.md),
                            DropdownButtonFormField<String>(
                              initialValue: _minimumAvailability,
                              decoration: const InputDecoration(
                                labelText: 'Minimum Availability',
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'announced',
                                  child: Text('Announced'),
                                ),
                                DropdownMenuItem(
                                  value: 'inCinemas',
                                  child: Text('In Cinemas'),
                                ),
                                DropdownMenuItem(
                                  value: 'released',
                                  child: Text('Released'),
                                ),
                              ],
                              onChanged: (val) => setState(
                                () => _minimumAvailability = val ?? 'announced',
                              ),
                            ),
                            const SizedBox(height: Insets.md),
                            SwitchListTile(
                              title: const Text('Monitored'),
                              value: _monitored,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (val) =>
                                  setState(() => _monitored = val),
                            ),
                            SwitchListTile(
                              title: const Text('Start search for movie'),
                              value: _searchForMovie,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (val) =>
                                  setState(() => _searchForMovie = val),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: Insets.lg),
                    tagsAsync.maybeWhen(
                      data: (tags) {
                        if (tags.isEmpty) return const SizedBox.shrink();
                        return Card(
                          elevation: 0,
                          color: cs.surfaceContainerHigh,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(Insets.md),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Tags',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: Insets.md),
                                Wrap(
                                  spacing: Insets.sm,
                                  runSpacing: Insets.sm,
                                  children: tags.map((t) {
                                    final int id = t['id'] as int;
                                    final String label = t['label'] as String;
                                    final bool selected =
                                        _selectedTagIds.contains(id);
                                    return FilterChip(
                                      label: Text(label),
                                      selected: selected,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      onSelected: (val) {
                                        setState(() {
                                          if (val) {
                                            _selectedTagIds.add(id);
                                          } else {
                                            _selectedTagIds.remove(id);
                                          }
                                        });
                                      },
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Insets.md),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                    ),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? ExpressiveProgressIndicator(color: cs.onPrimary)
                        : const Text(
                            'Add Movie',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    if (_selectedRootFolder == null || _selectedQualityProfileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('Please select a root folder and quality profile.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final RadarrApi api =
          await ref.read(radarrApiProvider(widget.instance).future);

      final Map<String, dynamic> payload = {
        'title': widget.movie.title,
        'tmdbId': widget.movie.tmdbId,
        'qualityProfileId': _selectedQualityProfileId,
        'titleSlug': widget.movie.titleSlug ??
            widget.movie.title
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]'), '-'),
        'images': widget.movie.images.map((i) => i.toJson()).toList(),
        'monitored': _monitored,
        'minimumAvailability': _minimumAvailability,
        'rootFolderPath': _selectedRootFolder,
        'tags': _selectedTagIds,
        'addOptions': {
          'searchForMovie': _searchForMovie,
        },
      };

      await api.addMovie(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${widget.movie.title}" successfully!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        ref.invalidate(radarrMoviesProvider(widget.instance));
        Navigator.of(context).pop(); // Pops the sheet
        Navigator.of(context).pop(); // Pops the search screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add movie: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }
}

class _PosterImage extends ConsumerWidget {
  const _PosterImage({required this.instance, required this.movie});

  final Instance instance;
  final RadarrMovie movie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RadarrApi? api = ref.watch(radarrApiProvider(instance)).value;
    final RadarrImage? poster = movie.images.firstWhereOrNull(
      (RadarrImage i) => i.coverType == 'poster',
    );
    final String? url =
        poster == null ? null : api?.posterUrl(poster, preferRemote: true);

    if (url == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Center(
          child: Icon(Icons.movie_outlined),
        ),
      );
    }

    return AtriumNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Center(
          child: ExpressiveProgressIndicator(),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Center(
          child: Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}
