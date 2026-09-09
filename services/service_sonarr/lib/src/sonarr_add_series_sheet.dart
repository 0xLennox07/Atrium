import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';

import 'models/sonarr_series.dart';
import 'sonarr_api.dart';
import 'sonarr_providers.dart';

class SonarrAddSeriesSheet extends ConsumerStatefulWidget {
  const SonarrAddSeriesSheet({
    required this.instance,
    required this.series,
    super.key,
  });

  final Instance instance;
  final SonarrSeries series;

  @override
  ConsumerState<SonarrAddSeriesSheet> createState() =>
      _SonarrAddSeriesSheetState();
}

class _SonarrAddSeriesSheetState extends ConsumerState<SonarrAddSeriesSheet> {
  String? _selectedRootFolder;
  int? _selectedQualityProfileId;
  String _selectedMonitorType = 'all';
  String _selectedSeriesType = 'standard';
  bool _seasonFolder = true;
  bool _searchForMissing = false;
  bool _searchForCutoffUnmet = false;
  final List<int> _selectedTagIds = [];
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final AsyncValue<List<Map<String, dynamic>>> rootFoldersAsync =
        ref.watch(sonarrRootFoldersProvider(widget.instance));
    final AsyncValue<List<Map<String, dynamic>>> qualityProfilesAsync =
        ref.watch(sonarrQualityProfilesProvider(widget.instance));
    final AsyncValue<List<Map<String, dynamic>>> tagsAsync =
        ref.watch(sonarrTagsProvider(widget.instance));

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
            title: const Text('Add Series Options'),
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
                    // Hero card representing the selected series (28dp corners)
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
                                  series: widget.series,
                                ),
                              ),
                            ),
                            const SizedBox(width: Insets.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.series.title,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${widget.series.year} • ${widget.series.network ?? "Unknown Network"}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.series.overview ??
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

                    // Configuration Options card (16dp corners)
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
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: Insets.md),

                            // Root folder selection
                            rootFoldersAsync.when(
                              data: (List<Map<String, dynamic>> folders) {
                                if (folders.isEmpty) {
                                  return Text(
                                    'No root folder configured in Sonarr.',
                                    style: TextStyle(color: cs.error),
                                  );
                                }
                                _selectedRootFolder ??=
                                    folders.first['path'] as String;

                                return DropdownButtonFormField<String>(
                                  initialValue: _selectedRootFolder,
                                  decoration: InputDecoration(
                                    labelText: 'Root Folder',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  items: folders.map((f) {
                                    final String path = f['path'] as String;
                                    final int freeBytes =
                                        f['freeSpace'] as int? ?? 0;
                                    final double freeGb =
                                        freeBytes / (1024 * 1024 * 1024);
                                    return DropdownMenuItem<String>(
                                      value: path,
                                      child: Text(
                                        '$path (${freeGb.toStringAsFixed(1)} GB free)',
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedRootFolder = val;
                                    });
                                  },
                                );
                              },
                              loading: () => const LinearProgressIndicatorM3E(
                                shape: ProgressM3EShape.flat,
                              ),
                              error: (e, s) =>
                                  Text('Error loading folders: $e'),
                            ),
                            const SizedBox(height: Insets.md),

                            // Quality Profile selection
                            qualityProfilesAsync.when(
                              data: (List<Map<String, dynamic>> profiles) {
                                if (profiles.isEmpty) {
                                  return Text(
                                    'No quality profiles found.',
                                    style: TextStyle(color: cs.error),
                                  );
                                }
                                _selectedQualityProfileId ??=
                                    profiles.first['id'] as int;

                                return DropdownButtonFormField<int>(
                                  initialValue: _selectedQualityProfileId,
                                  decoration: InputDecoration(
                                    labelText: 'Quality Profile',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  items: profiles.map((p) {
                                    return DropdownMenuItem<int>(
                                      value: p['id'] as int,
                                      child: Text(p['name'] as String),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    setState(() {
                                      _selectedQualityProfileId = val;
                                    });
                                  },
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (e, s) =>
                                  Text('Error loading profiles: $e'),
                            ),
                            const SizedBox(height: Insets.md),

                            // Monitor options dropdown
                            DropdownButtonFormField<String>(
                              initialValue: _selectedMonitorType,
                              decoration: InputDecoration(
                                labelText: 'Monitor',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'all',
                                  child: Text('All Episodes'),
                                ),
                                DropdownMenuItem(
                                  value: 'future',
                                  child: Text('Future Episodes'),
                                ),
                                DropdownMenuItem(
                                  value: 'missing',
                                  child: Text('Missing Episodes'),
                                ),
                                DropdownMenuItem(
                                  value: 'existing',
                                  child: Text('Existing Episodes'),
                                ),
                                DropdownMenuItem(
                                  value: 'firstSeason',
                                  child: Text('First Season'),
                                ),
                                DropdownMenuItem(
                                  value: 'latestSeason',
                                  child: Text('Latest Season'),
                                ),
                                DropdownMenuItem(
                                  value: 'none',
                                  child: Text('None'),
                                ),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedMonitorType = val ?? 'all';
                                });
                              },
                            ),
                            const SizedBox(height: Insets.md),

                            // Series Type dropdown
                            DropdownButtonFormField<String>(
                              initialValue: _selectedSeriesType,
                              decoration: InputDecoration(
                                labelText: 'Series Type',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'standard',
                                  child: Text('Standard'),
                                ),
                                DropdownMenuItem(
                                  value: 'daily',
                                  child: Text('Daily'),
                                ),
                                DropdownMenuItem(
                                  value: 'anime',
                                  child: Text('Anime'),
                                ),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedSeriesType = val ?? 'standard';
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: Insets.md),

                    // Switches card (16dp corners)
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerHigh,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Season Folder'),
                            subtitle:
                                const Text('Store files in season folders'),
                            value: _seasonFolder,
                            onChanged: (val) {
                              setState(() {
                                _seasonFolder = val;
                              });
                            },
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            title: const Text('Search missing episodes'),
                            subtitle:
                                const Text('Search indexers for missing files'),
                            value: _searchForMissing,
                            onChanged: (val) {
                              setState(() {
                                _searchForMissing = val;
                              });
                            },
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            title: const Text('Search cutoff unmet'),
                            subtitle: const Text('Upgrade lower quality files'),
                            value: _searchForCutoffUnmet,
                            onChanged: (val) {
                              setState(() {
                                _searchForCutoffUnmet = val;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Insets.md),

                    // Tags card (16dp corners)
                    tagsAsync.maybeWhen(
                      data: (List<Map<String, dynamic>> tags) {
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
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    color: cs.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: Insets.sm),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
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

              // Add Action Button Panel (Capsule stadium button)
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
                            'Add Series',
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
      final SonarrApi api =
          await ref.read(sonarrApiProvider(widget.instance).future);

      // Construct payload matching SeriesResource and AddSeriesOptions in v3.yaml
      final Map<String, dynamic> payload = {
        'title': widget.series.title,
        'tvdbId': widget.series.tvdbId,
        'qualityProfileId': _selectedQualityProfileId,
        'titleSlug': widget.series.titleSlug ??
            widget.series.title
                .toLowerCase()
                .replaceAll(RegExp(r'[^a-z0-9]'), '-'),
        'images': widget.series.images.map((i) => i.toJson()).toList(),
        'seasons': widget.series.seasons.map((s) => s.toJson()).toList(),
        'monitored': true,
        'seasonFolder': _seasonFolder,
        'seriesType': _selectedSeriesType,
        'rootFolderPath': _selectedRootFolder,
        'tags': _selectedTagIds,
        'addOptions': {
          'monitor': _selectedMonitorType,
          'searchForMissingEpisodes': _searchForMissing,
          'searchForCutoffUnmetEpisodes': _searchForCutoffUnmet,
        },
      };

      await api.addSeries(payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added "${widget.series.title}" successfully!'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
        // Refresh local series list provider
        ref.invalidate(sonarrSeriesProvider(widget.instance));
        // Close sheet and the search screen
        Navigator.of(context).pop(); // Pops the sheet
        Navigator.of(context).pop(); // Pops the search screen
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add series: $e'),
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
  const _PosterImage({required this.instance, required this.series});

  final Instance instance;
  final SonarrSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SonarrApi? api = ref.watch(sonarrApiProvider(instance)).value;
    final SonarrImage? poster = series.images.firstWhereOrNull(
      (SonarrImage i) => i.coverType == 'poster',
    );
    final String? url =
        poster == null ? null : api?.posterUrl(poster, preferRemote: true);

    if (url == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Center(
          child: Icon(Icons.tv),
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
