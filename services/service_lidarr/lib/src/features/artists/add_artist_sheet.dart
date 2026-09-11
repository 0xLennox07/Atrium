import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lidarr_formatters.dart';
import '../../generated/models/add_artist_options.dart';
import '../../generated/models/artist_resource.dart';
import '../../generated/models/metadata_profile_resource.dart';
import '../../generated/models/monitor_types.dart';
import '../../generated/models/new_item_monitor_types.dart';
import '../../generated/models/quality_profile_resource.dart';
import '../../generated/models/root_folder_resource.dart';
import '../../generated/models/tag_resource.dart';
import '../../generated/responses/api_response.dart';
import '../../lidarr_api.dart';
import '../../lidarr_artwork.dart';
import '../../lidarr_providers.dart';
import 'artist_detail_screen.dart';

/// Modal bottom sheet for configuring options before adding an artist to Lidarr.
class LidarrAddArtistSheet extends ConsumerStatefulWidget {
  const LidarrAddArtistSheet({
    required this.instance,
    required this.artist,
    super.key,
  });

  final Instance instance;
  final ArtistResource artist;

  @override
  ConsumerState<LidarrAddArtistSheet> createState() =>
      _LidarrAddArtistSheetState();
}

class _LidarrAddArtistSheetState extends ConsumerState<LidarrAddArtistSheet> {
  String? _selectedRootFolder;
  int? _selectedQualityProfileId;
  int? _selectedMetadataProfileId;
  MonitorTypes _selectedMonitor = MonitorTypes.all;
  NewItemMonitorTypes _selectedMonitorNewItems = NewItemMonitorTypes.all;
  bool _monitored = true;
  bool _searchForMissingAlbums = false;
  final List<int> _selectedTagIds = [];
  bool _submitting = false;

  String _formatFreeSpace(int? bytes) =>
      '${LidarrFormatters.formatBytes(bytes)} free';

  String _monitorLabel(MonitorTypes type) {
    return switch (type) {
      MonitorTypes.all => 'All Albums',
      MonitorTypes.future => 'Future Albums',
      MonitorTypes.missing => 'Missing Albums',
      MonitorTypes.existing => 'Existing Albums',
      MonitorTypes.first => 'First Album',
      MonitorTypes.latest => 'Latest Album',
      MonitorTypes.none => 'None',
      _ => type.value,
    };
  }

  String _monitorNewItemsLabel(NewItemMonitorTypes type) {
    return switch (type) {
      NewItemMonitorTypes.all => 'All',
      NewItemMonitorTypes.none => 'None',
      NewItemMonitorTypes.newVal => 'New',
    };
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    ref.listen(lidarrRootFoldersProvider(widget.instance), (previous, next) {
      if (next.hasValue && next.value != null && next.value!.isNotEmpty) {
        if (_selectedRootFolder == null) {
          final first = next.value!.first;
          setState(() {
            _selectedRootFolder = first.path;
            if (first.defaultQualityProfileId != null &&
                first.defaultQualityProfileId! > 0) {
              _selectedQualityProfileId = first.defaultQualityProfileId;
            }
            if (first.defaultMetadataProfileId != null &&
                first.defaultMetadataProfileId! > 0) {
              _selectedMetadataProfileId = first.defaultMetadataProfileId;
            }
            if (first.defaultMonitorOption != null) {
              _selectedMonitor = first.defaultMonitorOption!;
            }
            if (first.defaultNewItemMonitorOption != null) {
              _selectedMonitorNewItems = first.defaultNewItemMonitorOption!;
            }
            if (first.defaultTags != null &&
                first.defaultTags!.isNotEmpty &&
                _selectedTagIds.isEmpty) {
              _selectedTagIds.addAll(first.defaultTags!);
            }
          });
        }
      }
    });

    final AsyncValue<List<RootFolderResource>> rootFoldersAsync =
        ref.watch(lidarrRootFoldersProvider(widget.instance));
    final AsyncValue<List<QualityProfileResource>> qualityProfilesAsync =
        ref.watch(lidarrQualityProfilesProvider(widget.instance));
    final AsyncValue<List<MetadataProfileResource>> metadataProfilesAsync =
        ref.watch(lidarrMetadataProfilesProvider(widget.instance));
    final AsyncValue<List<TagResource>> tagsAsync =
        ref.watch(lidarrTagsProvider(widget.instance));

    final List<ArtistResource> localArtists =
        ref.watch(lidarrArtistsProvider(widget.instance)).value ?? [];

    final ArtistResource? localMatch = localArtists.firstWhereOrNull(
      (local) =>
          (local.foreignArtistId != null &&
              widget.artist.foreignArtistId != null &&
              local.foreignArtistId!.trim().toLowerCase() ==
                  widget.artist.foreignArtistId!.trim().toLowerCase()) ||
          (local.mbId != null &&
              widget.artist.mbId != null &&
              local.mbId!.trim().toLowerCase() ==
                  widget.artist.mbId!.trim().toLowerCase()) ||
          (local.artistName != null &&
              widget.artist.artistName != null &&
              local.artistName!.trim().toLowerCase() ==
                  widget.artist.artistName!.trim().toLowerCase()) ||
          (local.id != null &&
              local.id! > 0 &&
              widget.artist.id != null &&
              widget.artist.id! > 0 &&
              local.id == widget.artist.id),
    );
    final bool isAlreadyInLibrary = localMatch != null ||
        (widget.artist.id != null && widget.artist.id! > 0);

    rootFoldersAsync.whenData((List<RootFolderResource> folders) {
      if (_selectedRootFolder == null && folders.isNotEmpty) {
        final first = folders.first;
        _selectedRootFolder = first.path;
        if (first.defaultQualityProfileId != null &&
            first.defaultQualityProfileId! > 0) {
          _selectedQualityProfileId ??= first.defaultQualityProfileId;
        }
        if (first.defaultMetadataProfileId != null &&
            first.defaultMetadataProfileId! > 0) {
          _selectedMetadataProfileId ??= first.defaultMetadataProfileId;
        }
        if (first.defaultMonitorOption != null) {
          _selectedMonitor = first.defaultMonitorOption!;
        }
        if (first.defaultNewItemMonitorOption != null) {
          _selectedMonitorNewItems = first.defaultNewItemMonitorOption!;
        }
        if (first.defaultTags != null &&
            first.defaultTags!.isNotEmpty &&
            _selectedTagIds.isEmpty) {
          _selectedTagIds.addAll(first.defaultTags!);
        }
      }
    });
    qualityProfilesAsync.whenData((List<QualityProfileResource> profiles) {
      if (_selectedQualityProfileId == null && profiles.isNotEmpty) {
        _selectedQualityProfileId = profiles.first.id;
      }
    });
    metadataProfilesAsync.whenData((List<MetadataProfileResource> profiles) {
      if (_selectedMetadataProfileId == null && profiles.isNotEmpty) {
        _selectedMetadataProfileId = profiles.first.id;
      }
    });

    final String? posterUrl = LidarrArtwork.artistPosterUrl(
          widget.instance,
          widget.artist.images,
          preferRemote: true,
        ) ??
        (widget.artist.remotePoster != null &&
                widget.artist.remotePoster!.isNotEmpty
            ? widget.artist.remotePoster
            : null);

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
            title: const Text('Add Artist Options'),
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
                    // Hero card representing the selected artist
                    Card(
                      elevation: 0,
                      color: cs.primaryContainer.withValues(alpha: 0.15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(Insets.md),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: SizedBox(
                                width: 70,
                                height: 105,
                                child: posterUrl != null
                                    ? AtriumNetworkImage(
                                        imageUrl: posterUrl,
                                        fit: BoxFit.cover,
                                        alignment: Alignment.topCenter,
                                        errorWidget: (_, __, ___) =>
                                            const Icon(Icons.person, size: 40),
                                      )
                                    : const Icon(Icons.person, size: 40),
                              ),
                            ),
                            const SizedBox(width: Insets.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.artist.artistName ??
                                        'Unknown Artist',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (widget.artist.disambiguation != null &&
                                      widget.artist.disambiguation!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(
                                        '(${widget.artist.disambiguation!})',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: cs.onSurfaceVariant,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  if (widget.artist.genres != null &&
                                      widget.artist.genres!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      widget.artist.genres!.join(', '),
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: cs.primary),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    if (widget.artist.overview != null &&
                        widget.artist.overview!.isNotEmpty) ...[
                      const SizedBox(height: Insets.md),
                      OverviewBox(overview: widget.artist.overview!),
                    ],

                    const SizedBox(height: Insets.md),

                    // Paths & Profiles Card
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(Insets.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Paths & Profiles',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(height: Insets.md),
                            // Root folder selector
                            rootFoldersAsync.when(
                              data: (List<RootFolderResource> folders) {
                                if (folders.isEmpty) {
                                  return const Text(
                                    'No root folders configured in Lidarr.',
                                  );
                                }
                                final String selectedVal =
                                    _selectedRootFolder != null &&
                                            folders.any(
                                              (f) =>
                                                  f.path == _selectedRootFolder,
                                            )
                                        ? _selectedRootFolder!
                                        : folders.first.path ?? '';
                                return DropdownButtonFormField<String>(
                                  key: ValueKey<String?>(
                                    'root_$_selectedRootFolder',
                                  ),
                                  initialValue: selectedVal,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Root Folder',
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  items: folders.map((RootFolderResource f) {
                                    final String path = f.path ?? '';
                                    final String free =
                                        _formatFreeSpace(f.freeSpace);
                                    return DropdownMenuItem<String>(
                                      value: path,
                                      child: Text(
                                        '$path ($free)',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (String? val) {
                                    if (val != null) {
                                      setState(() {
                                        _selectedRootFolder = val;
                                        final RootFolderResource? folder =
                                            folders.firstWhereOrNull(
                                          (f) => f.path == val,
                                        );
                                        if (folder != null) {
                                          if (folder.defaultQualityProfileId !=
                                                  null &&
                                              folder.defaultQualityProfileId! >
                                                  0) {
                                            _selectedQualityProfileId =
                                                folder.defaultQualityProfileId;
                                          }
                                          if (folder.defaultMetadataProfileId !=
                                                  null &&
                                              folder.defaultMetadataProfileId! >
                                                  0) {
                                            _selectedMetadataProfileId =
                                                folder.defaultMetadataProfileId;
                                          }
                                          if (folder.defaultMonitorOption !=
                                              null) {
                                            _selectedMonitor =
                                                folder.defaultMonitorOption!;
                                          }
                                          if (folder
                                                  .defaultNewItemMonitorOption !=
                                              null) {
                                            _selectedMonitorNewItems = folder
                                                .defaultNewItemMonitorOption!;
                                          }
                                        }
                                      });
                                    }
                                  },
                                );
                              },
                              loading: () =>
                                  const ExpressiveProgressIndicator(),
                              error: (e, _) =>
                                  Text('Failed to load root folders: $e'),
                            ),
                            const SizedBox(height: Insets.md),
                            // Quality profile selector
                            qualityProfilesAsync.when(
                              data: (List<QualityProfileResource> profiles) {
                                if (profiles.isEmpty) {
                                  return const Text(
                                    'No quality profiles found.',
                                  );
                                }
                                final int selectedVal =
                                    _selectedQualityProfileId != null &&
                                            profiles.any(
                                              (p) =>
                                                  p.id ==
                                                  _selectedQualityProfileId,
                                            )
                                        ? _selectedQualityProfileId!
                                        : profiles.first.id ?? 1;
                                return DropdownButtonFormField<int>(
                                  key: ValueKey<String>(
                                    'quality_$_selectedQualityProfileId',
                                  ),
                                  initialValue: selectedVal,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Quality Profile',
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  items:
                                      profiles.map((QualityProfileResource p) {
                                    return DropdownMenuItem<int>(
                                      value: p.id,
                                      child: Text(
                                        p.name ?? 'Quality Profile ${p.id}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (int? val) {
                                    setState(() {
                                      _selectedQualityProfileId = val;
                                    });
                                  },
                                );
                              },
                              loading: () =>
                                  const ExpressiveProgressIndicator(),
                              error: (e, _) =>
                                  Text('Failed to load quality profiles: $e'),
                            ),
                            const SizedBox(height: Insets.md),
                            // Metadata profile selector (Lidarr-specific)
                            metadataProfilesAsync.when(
                              data: (List<MetadataProfileResource> profiles) {
                                if (profiles.isEmpty) {
                                  return const Text(
                                    'No metadata profiles found.',
                                  );
                                }
                                final int selectedVal =
                                    _selectedMetadataProfileId != null &&
                                            profiles.any(
                                              (p) =>
                                                  p.id ==
                                                  _selectedMetadataProfileId,
                                            )
                                        ? _selectedMetadataProfileId!
                                        : profiles.first.id ?? 1;
                                return DropdownButtonFormField<int>(
                                  key: ValueKey<String>(
                                    'meta_$_selectedMetadataProfileId',
                                  ),
                                  initialValue: selectedVal,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Metadata Profile',
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  items:
                                      profiles.map((MetadataProfileResource p) {
                                    return DropdownMenuItem<int>(
                                      value: p.id,
                                      child: Text(
                                        p.name ?? 'Metadata Profile ${p.id}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (int? val) {
                                    setState(() {
                                      _selectedMetadataProfileId = val;
                                    });
                                  },
                                );
                              },
                              loading: () =>
                                  const ExpressiveProgressIndicator(),
                              error: (e, _) =>
                                  Text('Failed to load metadata profiles: $e'),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: Insets.md),

                    // Monitoring Options Card
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(Insets.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Monitoring Options',
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: cs.primary,
                              ),
                            ),
                            const SizedBox(height: Insets.md),
                            // Monitor Albums Dropdown
                            DropdownButtonFormField<MonitorTypes>(
                              key: ValueKey<String>(
                                'monitor_${_selectedMonitor.name}',
                              ),
                              initialValue: _selectedMonitor,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Monitor Albums',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: const [
                                MonitorTypes.all,
                                MonitorTypes.future,
                                MonitorTypes.missing,
                                MonitorTypes.existing,
                                MonitorTypes.first,
                                MonitorTypes.latest,
                                MonitorTypes.none,
                              ].map((MonitorTypes type) {
                                return DropdownMenuItem<MonitorTypes>(
                                  value: type,
                                  child: Text(_monitorLabel(type)),
                                );
                              }).toList(),
                              onChanged: (MonitorTypes? val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedMonitor = val;
                                  });
                                }
                              },
                            ),
                            const SizedBox(height: Insets.md),
                            // Monitor New Items Dropdown
                            DropdownButtonFormField<NewItemMonitorTypes>(
                              key: ValueKey<String>(
                                'new_items_${_selectedMonitorNewItems.name}',
                              ),
                              initialValue: _selectedMonitorNewItems,
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: 'Monitor New Items',
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              items: const [
                                NewItemMonitorTypes.all,
                                NewItemMonitorTypes.none,
                                NewItemMonitorTypes.newVal,
                              ].map((NewItemMonitorTypes type) {
                                return DropdownMenuItem<NewItemMonitorTypes>(
                                  value: type,
                                  child: Text(_monitorNewItemsLabel(type)),
                                );
                              }).toList(),
                              onChanged: (NewItemMonitorTypes? val) {
                                if (val != null) {
                                  setState(() {
                                    _selectedMonitorNewItems = val;
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: Insets.md),

                    // Switches Card
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('Monitored'),
                            subtitle: const Text(
                              'Monitor this artist for new and missing releases',
                            ),
                            value: _monitored,
                            onChanged: (bool val) {
                              setState(() {
                                _monitored = val;
                              });
                            },
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            title: const Text('Search for Missing Albums'),
                            subtitle: const Text(
                              'Start searching indexers immediately after adding',
                            ),
                            value: _searchForMissingAlbums,
                            onChanged: (bool val) {
                              setState(() {
                                _searchForMissingAlbums = val;
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    // Tags Card (if tags are configured)
                    tagsAsync.maybeWhen(
                      data: (List<TagResource> tags) {
                        if (tags.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: Insets.md),
                          child: Card(
                            elevation: 0,
                            color: cs.surfaceContainerLow,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: cs.outlineVariant.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(Insets.md),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Tags',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: cs.primary,
                                    ),
                                  ),
                                  const SizedBox(height: Insets.sm),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: tags.map((TagResource tag) {
                                      final int id = tag.id ?? 0;
                                      final String label =
                                          tag.label ?? 'Tag $id';
                                      final bool isSelected =
                                          _selectedTagIds.contains(id);
                                      return FilterChip(
                                        label: Text(label),
                                        selected: isSelected,
                                        onSelected: (bool selected) {
                                          setState(() {
                                            if (selected) {
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
                          ),
                        );
                      },
                      orElse: () => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),

              // Bottom Submit Capsule Button / Already Added Navigation Button
              Padding(
                padding: const EdgeInsets.all(Insets.md),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: isAlreadyInLibrary
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(
                            shape: const StadiumBorder(),
                            backgroundColor: cs.primaryContainer,
                            foregroundColor: cs.onPrimaryContainer,
                          ),
                          icon: const Icon(Icons.library_music_outlined),
                          label: const Text(
                            'Already in Library — View Artist',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: () {
                            Navigator.of(context).pop();
                            final targetArtist = localMatch ?? widget.artist;
                            final int targetId =
                                targetArtist.id ?? localMatch?.id ?? 0;
                            if (targetId > 0) {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => ArtistDetailScreen(
                                    instance: widget.instance,
                                    artistId: targetId,
                                    initialArtist: targetArtist,
                                  ),
                                ),
                              );
                            }
                          },
                        )
                      : FilledButton(
                          style: FilledButton.styleFrom(
                            shape: const StadiumBorder(),
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                          ),
                          onPressed: _submitting ? null : _submit,
                          child: _submitting
                              ? ExpressiveProgressIndicator(color: cs.onPrimary)
                              : const Text(
                                  'Add Artist',
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
    final List<ArtistResource> localArtists =
        ref.read(lidarrArtistsProvider(widget.instance)).value ?? [];

    final ArtistResource? localMatch = localArtists.firstWhereOrNull(
      (local) =>
          (local.foreignArtistId != null &&
              widget.artist.foreignArtistId != null &&
              local.foreignArtistId!.trim().toLowerCase() ==
                  widget.artist.foreignArtistId!.trim().toLowerCase()) ||
          (local.mbId != null &&
              widget.artist.mbId != null &&
              local.mbId!.trim().toLowerCase() ==
                  widget.artist.mbId!.trim().toLowerCase()) ||
          (local.artistName != null &&
              widget.artist.artistName != null &&
              local.artistName!.trim().toLowerCase() ==
                  widget.artist.artistName!.trim().toLowerCase()) ||
          (local.id != null &&
              local.id! > 0 &&
              widget.artist.id != null &&
              widget.artist.id! > 0 &&
              local.id == widget.artist.id),
    );
    if (localMatch != null ||
        (widget.artist.id != null && widget.artist.id! > 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '"${widget.artist.artistName ?? 'Artist'}" is already in your library.',
          ),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ),
      );
      return;
    }

    final List<RootFolderResource>? folders =
        ref.read(lidarrRootFoldersProvider(widget.instance)).value;
    final List<QualityProfileResource>? qualityProfiles =
        ref.read(lidarrQualityProfilesProvider(widget.instance)).value;
    final List<MetadataProfileResource>? metadataProfiles =
        ref.read(lidarrMetadataProfilesProvider(widget.instance)).value;

    final String? rootFolder = _selectedRootFolder ??
        folders?.firstOrNull?.path ??
        widget.artist.rootFolderPath;

    final int? qualityProfileId = _selectedQualityProfileId ??
        qualityProfiles?.firstOrNull?.id ??
        (widget.artist.qualityProfileId != null &&
                widget.artist.qualityProfileId! > 0
            ? widget.artist.qualityProfileId
            : 1);

    final int? metadataProfileId = _selectedMetadataProfileId ??
        metadataProfiles?.firstOrNull?.id ??
        (widget.artist.metadataProfileId != null &&
                widget.artist.metadataProfileId! > 0
            ? widget.artist.metadataProfileId
            : 1);

    if (rootFolder == null || rootFolder.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a root folder.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final LidarrApi api =
          await ref.read(lidarrApiProvider(widget.instance).future);

      final ArtistResource payload = widget.artist.copyWith(
        id: 0,
        rootFolderPath: rootFolder,
        qualityProfileId: qualityProfileId,
        metadataProfileId: metadataProfileId,
        monitored: _monitored,
        monitorNewItems: _selectedMonitorNewItems,
        tags: _selectedTagIds,
        addOptions: AddArtistOptions(
          monitor: _selectedMonitor,
          monitored: _monitored,
          searchForMissingAlbums: _searchForMissingAlbums,
        ),
      );

      final ApiResponse<ArtistResource> resp =
          await api.artist.postArtist(body: payload);

      if (!resp.isSuccess) {
        final String errorMsg = resp.error?.message ??
            (resp.error?.errors.isNotEmpty == true
                ? resp.error!.errors.join('\n')
                : 'Unknown server error');
        throw Exception(errorMsg);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added "${widget.artist.artistName ?? 'Artist'}" successfully!',
            ),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );

        // Invalidate local library provider so library refreshes
        ref.invalidate(lidarrArtistsProvider(widget.instance));

        // Close sheet and the search screen if present
        final NavigatorState nav = Navigator.of(context);
        if (nav.canPop()) {
          nav.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        final String cleanMsg = e.toString().replaceFirst('Exception: ', '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to add artist: $cleanMsg'),
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
