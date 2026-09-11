import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/lidarr_formatters.dart';
import '../../generated/generated.dart';
import '../../lidarr_api.dart';
import '../../lidarr_artwork.dart';
import '../../lidarr_providers.dart';
import '../search/interactive_search_screen.dart';
import '../track_files/manual_import_dialog.dart';
import '../track_files/rename_dialog.dart';
import '../track_files/retag_dialog.dart';
import '../track_files/track_file_editor_screen.dart';
import '../track_files/unmapped_files_screen.dart';
import 'artist_info_sheet.dart';
import 'edit_artist_sheet.dart';
import 'views/artist_history_view.dart';
import 'widgets/album_bulk_actions_bar.dart';
import 'widgets/album_card.dart';

/// Screen displaying rich artist details, modular cards, categorized discography,
/// server commands, and activity history.
class ArtistDetailScreen extends ConsumerStatefulWidget {
  const ArtistDetailScreen({
    required this.instance,
    required this.artistId,
    this.initialArtist,
    super.key,
  });

  final Instance instance;
  final int artistId;
  final ArtistResource? initialArtist;

  @override
  ConsumerState<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends ConsumerState<ArtistDetailScreen> {
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _showBackToTop = ValueNotifier<bool>(false);
  final GlobalKey _discographyHeaderKey = GlobalKey();
  final Map<String, GlobalKey> _groupKeys = {};

  final Set<int> _selectedAlbumIds = <int>{};
  bool get _isSelectionMode => _selectedAlbumIds.isNotEmpty;

  void _toggleAlbumSelection(int albumId) {
    setState(() {
      if (_selectedAlbumIds.contains(albumId)) {
        _selectedAlbumIds.remove(albumId);
      } else {
        _selectedAlbumIds.add(albumId);
      }
    });
  }

  void _selectAllAlbums(List<AlbumResource> allAlbums) {
    setState(() {
      _selectedAlbumIds.clear();
      _selectedAlbumIds.addAll(
        allAlbums.where((a) => a.id != null).map((a) => a.id!),
      );
    });
  }

  void _invertAlbumSelection(List<AlbumResource> allAlbums) {
    setState(() {
      final Set<int> allIds =
          allAlbums.where((a) => a.id != null).map((a) => a.id!).toSet();
      final Set<int> inverted = allIds.difference(_selectedAlbumIds);
      _selectedAlbumIds.clear();
      _selectedAlbumIds.addAll(inverted);
    });
  }

  void _clearSelection() {
    setState(_selectedAlbumIds.clear);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_scrollListener);
  }

  void _scrollListener() {
    final double threshold = MediaQuery.sizeOf(context).height * 0.4;
    if (_scrollController.hasClients && _scrollController.offset >= threshold) {
      if (!_showBackToTop.value) {
        _showBackToTop.value = true;
      }
    } else {
      if (_showBackToTop.value) {
        _showBackToTop.value = false;
      }
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_scrollListener);
    _scrollController.dispose();
    _showBackToTop.dispose();
    super.dispose();
  }

  Future<void> _refreshArtist() async {
    try {
      final LidarrApi api =
          await ref.read(lidarrApiProvider(widget.instance).future);
      final ApiResponse<CommandResource> resp = await api.executeCommand(
        'RefreshArtist',
        {'artistId': widget.artistId},
      );
      if (!resp.isSuccess) {
        throw Exception(resp.error?.message ?? 'Failed to trigger refresh');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Refreshing artist and scanning disk...'),
            duration: Duration(seconds: 2),
          ),
        );
        ref.invalidate(
          lidarrArtistByIdProvider((widget.instance, widget.artistId)),
        );
        ref.invalidate(
          lidarrAlbumsForArtistProvider((widget.instance, widget.artistId)),
        );
        ref.invalidate(lidarrArtistsProvider(widget.instance));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _searchMissing() async {
    try {
      final LidarrApi api =
          await ref.read(lidarrApiProvider(widget.instance).future);
      final ApiResponse<CommandResource> resp = await api.executeCommand(
        'ArtistSearch',
        {'artistId': widget.artistId},
      );
      if (!resp.isSuccess) {
        throw Exception(resp.error?.message ?? 'Failed to trigger search');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Searching for monitored missing releases...'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to search missing releases: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleArtistMonitored(ArtistResource artist) async {
    final bool newMonitored = !(artist.monitored ?? false);
    try {
      final LidarrApi api =
          await ref.read(lidarrApiProvider(widget.instance).future);
      final ApiResponse<ArtistResource> resp = await api.artist.putArtistById(
        id: '${artist.id}',
        body: artist.copyWith(monitored: newMonitored),
      );
      if (!resp.isSuccess) {
        throw Exception(resp.error?.message ?? 'Failed to toggle monitoring');
      }

      ref.invalidate(
        lidarrArtistByIdProvider((widget.instance, widget.artistId)),
      );
      ref.invalidate(lidarrArtistsProvider(widget.instance));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newMonitored ? 'Artist monitored' : 'Artist unmonitored',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update monitoring: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _toggleAlbumGroupMonitoring(
    List<AlbumResource> albums,
    bool monitored,
  ) async {
    final List<int> ids = albums.map((a) => a.id).whereType<int>().toList();
    if (ids.isEmpty) return;

    try {
      final LidarrApi api =
          await ref.read(lidarrApiProvider(widget.instance).future);
      final ApiResponse<void> resp = await api.album.putAlbumMonitor(
        body: AlbumsMonitoredResource(
          albumIds: ids,
          monitored: monitored,
        ),
      );
      if (!resp.isSuccess) {
        throw Exception(resp.error?.message ?? 'Failed to update albums');
      }

      ref.invalidate(
        lidarrAlbumsForArtistProvider((widget.instance, widget.artistId)),
      );
      ref.invalidate(
        lidarrArtistByIdProvider((widget.instance, widget.artistId)),
      );
      ref.invalidate(lidarrArtistsProvider(widget.instance));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              monitored
                  ? 'Monitored ${ids.length} albums'
                  : 'Unmonitored ${ids.length} albums',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update album monitoring: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteArtist(ArtistResource artist) async {
    bool deleteFiles = false;
    bool addImportListExclusion = false;

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Delete ${artist.artistName ?? 'Artist'}?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Are you sure you want to remove this artist from Lidarr?',
                  ),
                  const SizedBox(height: Insets.md),
                  CheckboxListTile(
                    title: const Text('Delete Files from Disk'),
                    subtitle:
                        const Text('Remove music directory and audio files'),
                    value: deleteFiles,
                    onChanged: (bool? val) {
                      setDialogState(() {
                        deleteFiles = val ?? false;
                      });
                    },
                  ),
                  CheckboxListTile(
                    title: const Text('Add Import List Exclusion'),
                    subtitle: const Text('Prevent re-adding from auto lists'),
                    value: addImportListExclusion,
                    onChanged: (bool? val) {
                      setDialogState(() {
                        addImportListExclusion = val ?? false;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(ctx).colorScheme.error,
                    foregroundColor: Theme.of(ctx).colorScheme.onError,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm != true) return;

    try {
      final LidarrApi api =
          await ref.read(lidarrApiProvider(widget.instance).future);
      final ApiResponse<void> resp = await api.artist.deleteArtistById(
        id: widget.artistId,
        deleteFiles: deleteFiles,
        addImportListExclusion: addImportListExclusion,
      );
      if (!resp.isSuccess) {
        throw Exception(resp.error?.message ?? 'Failed to delete artist');
      }

      ref.invalidate(lidarrArtistsProvider(widget.instance));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Deleted "${artist.artistName ?? 'Artist'}" successfully',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete artist: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  String _formatGroupTitle(String groupType) {
    return switch (groupType.toLowerCase()) {
      'studio' => 'Studio Albums',
      'album' => 'Albums',
      'ep' => 'EPs',
      'single' => 'Singles',
      'live' => 'Live Albums',
      'broadcast' => 'Broadcasts',
      'compilation' => 'Compilations',
      'soundtrack' => 'Soundtracks',
      _ => '$groupType Releases',
    };
  }

  List<Widget> _buildGroupedAlbumsSlivers(
    BuildContext context,
    List<AlbumResource> albums,
  ) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final Map<String, List<AlbumResource>> grouped = groupBy(
      albums,
      (AlbumResource a) => a.albumType ?? 'Other',
    );

    const List<String> canonicalOrder = [
      'Studio',
      'Album',
      'EP',
      'Single',
      'Live',
      'Broadcast',
      'Compilation',
      'Soundtrack',
      'Other',
    ];

    final List<MapEntry<String, List<AlbumResource>>> sortedEntries =
        grouped.entries.toList()
          ..sort((a, b) {
            final int indexA = canonicalOrder.indexOf(a.key);
            final int indexB = canonicalOrder.indexOf(b.key);
            final int rankA = indexA == -1 ? 999 : indexA;
            final int rankB = indexB == -1 ? 999 : indexB;
            if (rankA != rankB) return rankA.compareTo(rankB);
            return a.key.compareTo(b.key);
          });

    for (final entry in sortedEntries) {
      entry.value.sort((a, b) {
        final String dateA = a.releaseDate ?? '';
        final String dateB = b.releaseDate ?? '';
        return dateB.compareTo(dateA);
      });
      _groupKeys.putIfAbsent(entry.key, GlobalKey.new);
    }

    final List<Widget> slivers = [];

    for (final MapEntry<String, List<AlbumResource>> entry in sortedEntries) {
      final String groupType = entry.key;
      final String groupTitle = _formatGroupTitle(groupType);
      final List<AlbumResource> groupAlbums = entry.value;
      final bool allMonitored = groupAlbums.every((a) => a.monitored == true);
      final GlobalKey groupKey = _groupKeys[groupType]!;

      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            key: groupKey,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '$groupTitle (${groupAlbums.length})',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  icon: Icon(
                    allMonitored ? Icons.bookmark : Icons.bookmark_border,
                    size: 16,
                    color: allMonitored ? cs.primary : cs.onSurfaceVariant,
                  ),
                  label: Text(
                    allMonitored ? 'Monitored' : 'Unmonitored',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: allMonitored ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                  onPressed: () => _toggleAlbumGroupMonitoring(
                    groupAlbums,
                    !allMonitored,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final AlbumResource album = groupAlbums[index];
                final int? albumId = album.id;
                final bool isSelected =
                    albumId != null && _selectedAlbumIds.contains(albumId);
                return AlbumCard(
                  instance: widget.instance,
                  artistId: widget.artistId,
                  album: album,
                  isSelected: isSelected,
                  isSelectionMode: _isSelectionMode,
                  onSelect: albumId != null
                      ? () => _toggleAlbumSelection(albumId)
                      : null,
                  onLongPress: albumId != null
                      ? () => _toggleAlbumSelection(albumId)
                      : null,
                );
              },
              childCount: groupAlbums.length,
            ),
          ),
        ),
      );
    }

    return slivers;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final AsyncValue<ArtistResource> asyncArtist =
        ref.watch(lidarrArtistByIdProvider((widget.instance, widget.artistId)));
    final AsyncValue<List<AlbumResource>> asyncAlbums = ref.watch(
      lidarrAlbumsForArtistProvider((widget.instance, widget.artistId)),
    );

    final ArtistResource? artist = asyncArtist.value ?? widget.initialArtist;
    final List<AlbumResource> albums = asyncAlbums.value ?? [];

    final Map<String, List<AlbumResource>> grouped = groupBy(
      albums,
      (AlbumResource a) => a.albumType ?? 'Other',
    );

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (!didPop && _isSelectionMode) {
          _clearSelection();
        }
      },
      child: Scaffold(
        bottomNavigationBar: _isSelectionMode
            ? AlbumBulkActionsBar(
                instance: widget.instance,
                artistId: widget.artistId,
                selectedIds: _selectedAlbumIds,
                onClear: _clearSelection,
              )
            : null,
        floatingActionButton: !_isSelectionMode
            ? ValueListenableBuilder<bool>(
                valueListenable: _showBackToTop,
                builder: (context, show, child) {
                  return AnimatedScale(
                    scale: show ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: AnimatedOpacity(
                      opacity: show ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: FloatingActionButton.small(
                        onPressed: () {
                          _scrollController.animateTo(
                            0,
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                          );
                        },
                        child: const Icon(Icons.arrow_upward),
                      ),
                    ),
                  );
                },
              )
            : null,
        body: EasyRefresh(
          onRefresh: _isSelectionMode ? () async {} : _refreshArtist,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (_isSelectionMode)
                SliverAppBar(
                  pinned: true,
                  scrolledUnderElevation: 0.0,
                  backgroundColor: cs.surface,
                  surfaceTintColor: Colors.transparent,
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear selection',
                    onPressed: _clearSelection,
                  ),
                  title: Text(
                    '${_selectedAlbumIds.length} selected',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => _selectAllAlbums(albums),
                      child: const Text('Select All'),
                    ),
                    TextButton(
                      onPressed: () => _invertAlbumSelection(albums),
                      child: const Text('Invert'),
                    ),
                    const SizedBox(width: 4),
                  ],
                )
              else
                // 1. SliverAppBar with Pure Fanart Backdrop
                SliverAppBar(
                  expandedHeight: 240.0,
                  pinned: true,
                  backgroundColor: cs.surface,
                  surfaceTintColor: cs.surfaceTint,
                  leading: _AppBarBubbleButton(
                    controller: _scrollController,
                    icon: Icons.arrow_back,
                    onPressed: () => Navigator.maybePop(context),
                  ),
                  actions: [
                    _AppBarBubbleButton(
                      controller: _scrollController,
                      icon: Icons.refresh,
                      tooltip: 'Refresh & Scan',
                      onPressed: _refreshArtist,
                    ),
                    _AppBarBubbleButton(
                      controller: _scrollController,
                      icon: Icons.info_outline,
                      tooltip: 'Artist Info & Links',
                      onPressed: () => showLidarrArtistInfoSheet(
                        context,
                        instance: widget.instance,
                        artist: artist,
                        ref: ref,
                      ),
                    ),
                    _AppBarBubbleButton(
                      controller: _scrollController,
                      icon: Icons.more_vert,
                      tooltip: 'More options',
                      child: PopupMenuButton<String>(
                        tooltip: 'More options',
                        padding: EdgeInsets.zero,
                        icon: _AppBarDynamicIcon(
                          controller: _scrollController,
                          icon: Icons.more_vert,
                        ),
                        onSelected: (String value) {
                          if (value == 'select' && albums.isNotEmpty) {
                            _selectAllAlbums(albums);
                          } else if (value == 'history' && artist != null) {
                            Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (context) => LidarrArtistHistoryScreen(
                                  instance: widget.instance,
                                  artistId: widget.artistId,
                                  artistName: artist.artistName ?? 'Artist',
                                ),
                              ),
                            );
                          } else if (value == 'search' && artist != null) {
                            LidarrInteractiveSearchScreen.show(
                              context,
                              instance: widget.instance,
                              title: artist.artistName ?? 'Artist',
                              artistId: widget.artistId,
                            );
                          } else if (value == 'manual_import' &&
                              artist != null) {
                            showLidarrManualImportFlow(
                              context,
                              ref,
                              widget.instance,
                              artistId: widget.artistId,
                              initialFolder: artist.path,
                            );
                          } else if (value == 'unmapped' && artist != null) {
                            LidarrUnmappedFilesScreen.show(
                              context,
                              instance: widget.instance,
                              artistId: widget.artistId,
                              artistName: artist.artistName,
                            );
                          } else if (value == 'track_files' && artist != null) {
                            LidarrTrackFileEditorScreen.show(
                              context,
                              instance: widget.instance,
                              artistId: widget.artistId,
                              artistName: artist.artistName,
                            );
                          } else if (value == 'rename' && artist != null) {
                            showLidarrRenameDialog(
                              context,
                              instance: widget.instance,
                              artistId: widget.artistId,
                              artistName: artist.artistName,
                            );
                          } else if (value == 'retag' && artist != null) {
                            showLidarrRetagDialog(
                              context,
                              instance: widget.instance,
                              artistId: widget.artistId,
                              artistName: artist.artistName,
                            );
                          } else if (value == 'edit' && artist != null) {
                            LidarrEditArtistSheet.show(
                              context,
                              instance: widget.instance,
                              artist: artist,
                            );
                          } else if (value == 'delete' && artist != null) {
                            _confirmDeleteArtist(artist);
                          }
                        },
                        itemBuilder: (BuildContext context) => [
                          if (albums.isNotEmpty)
                            const PopupMenuItem(
                              value: 'select',
                              child: ListTile(
                                leading: Icon(Icons.checklist_outlined),
                                title: Text('Select Albums'),
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          const PopupMenuItem(
                            value: 'history',
                            child: ListTile(
                              leading: Icon(Icons.history_outlined),
                              title: Text('Activity History'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'search',
                            child: ListTile(
                              leading: Icon(Icons.manage_search_outlined),
                              title: Text('Interactive Search'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'manual_import',
                            child: ListTile(
                              leading: Icon(Icons.drive_folder_upload_outlined),
                              title: Text('Manual Import'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'unmapped',
                            child: ListTile(
                              leading: Icon(Icons.folder_open_outlined),
                              title: Text('Unmapped Files'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'track_files',
                            child: ListTile(
                              leading: Icon(Icons.audio_file_outlined),
                              title: Text('Track Files Editor'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: ListTile(
                              leading: Icon(Icons.drive_file_rename_outline),
                              title: Text('Rename All Files'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'retag',
                            child: ListTile(
                              leading: Icon(Icons.label_outlined),
                              title: Text('Retag All Files'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              leading: Icon(Icons.edit_outlined),
                              title: Text('Edit Artist'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              leading:
                                  Icon(Icons.delete_outline, color: cs.error),
                              title: Text(
                                'Delete Artist',
                                style: TextStyle(color: cs.error),
                              ),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  title: _CollapsedTitle(
                    controller: _scrollController,
                    title: artist?.artistName ?? 'Artist',
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: _Backdrop(
                      instance: widget.instance,
                      images: artist?.images,
                    ),
                  ),
                ),

              // 2. Main Content Header Section
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // A. Unified Hero Artist Identity & Metadata
                      _ArtistHeroHeader(
                        instance: widget.instance,
                        artist: artist,
                        onToggleMonitored: () {
                          if (artist != null) _toggleArtistMonitored(artist);
                        },
                        onSearchMissing: _searchMissing,
                        onInteractiveSearch: () {
                          if (artist != null) {
                            LidarrInteractiveSearchScreen.show(
                              context,
                              instance: widget.instance,
                              title: artist.artistName ?? 'Artist',
                              artistId: widget.artistId,
                            );
                          }
                        },
                      ),

                      // B. Expandable Bio Overview (if available)
                      if (artist?.overview != null &&
                          artist!.overview!.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _OverviewSection(overview: artist.overview!),
                      ],

                      const SizedBox(height: 14),

                      // C. Discography Header & Quick Category Tabs
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Discography',
                            key: _discographyHeaderKey,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (albums.isNotEmpty)
                            Text(
                              '${albums.length} releases',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      if (grouped.length > 1) ...[
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              ActionChip(
                                label: const Text('All'),
                                visualDensity: VisualDensity.compact,
                                onPressed: () {
                                  if (_discographyHeaderKey.currentContext !=
                                      null) {
                                    Scrollable.ensureVisible(
                                      _discographyHeaderKey.currentContext!,
                                      duration:
                                          const Duration(milliseconds: 400),
                                      curve: Curves.easeInOut,
                                    );
                                  }
                                },
                              ),
                              ...grouped.keys.map((groupType) {
                                final String title =
                                    _formatGroupTitle(groupType);
                                return Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: ActionChip(
                                    label: Text(title),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      final key = _groupKeys[groupType];
                                      if (key?.currentContext != null) {
                                        Scrollable.ensureVisible(
                                          key!.currentContext!,
                                          duration:
                                              const Duration(milliseconds: 400),
                                          curve: Curves.easeInOut,
                                        );
                                      }
                                    },
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // 3. Categorized Discography Slivers
              if (asyncAlbums.isLoading && albums.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(48.0),
                    child: Center(
                      child: ExpressiveProgressIndicator(),
                    ),
                  ),
                )
              else if (asyncAlbums.hasError && albums.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Center(
                      child: ErrorView(
                        title: 'Failed to load discography',
                        message: '${asyncAlbums.error}',
                        onRetry: () => ref.invalidate(
                          lidarrAlbumsForArtistProvider(
                            (widget.instance, widget.artistId),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              else if (albums.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: EmptyView(
                        icon: Icons.album_outlined,
                        title: 'No Albums Found',
                        message: 'No albums available for this artist.',
                      ),
                    ),
                  ),
                )
              else
                ..._buildGroupedAlbumsSlivers(context, albums),

              // Bottom safe inset
              const SliverToBoxAdapter(
                child: SizedBox(height: 48),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Atmospheric Backdrop with Dual Scrim
// ---------------------------------------------------------------------------

class _Backdrop extends StatelessWidget {
  const _Backdrop({
    required this.instance,
    required this.images,
  });

  final Instance instance;
  final List<MediaCover>? images;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final String? fanartUrl = LidarrArtwork.artistFanartUrl(
      instance,
      images,
      preferRemote: true,
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        if (fanartUrl != null)
          AtriumNetworkImage(
            imageUrl: fanartUrl,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorWidget: (_, __, ___) =>
                ColoredBox(color: cs.surfaceContainerHigh),
          )
        else
          ColoredBox(color: cs.surfaceContainerHigh),

        // Top dark scrim for status bar and actions legibility
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.0, 0.5],
              colors: [
                cs.scrim.withValues(alpha: 0.5),
                Colors.transparent,
              ],
            ),
          ),
        ),

        // Bottom gradient melting seamlessly into surface
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0.35, 0.8, 1.0],
              colors: [
                cs.surface.withValues(alpha: 0.0),
                cs.surface.withValues(alpha: 0.65),
                cs.surface,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Circular Frosted Action Bubble for SliverAppBar
// ---------------------------------------------------------------------------

class _AppBarBubbleButton extends StatefulWidget {
  const _AppBarBubbleButton({
    required this.controller,
    required this.icon,
    this.tooltip,
    this.onPressed,
    this.child,
  });

  final ScrollController controller;
  final IconData icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final Widget? child;

  @override
  State<_AppBarBubbleButton> createState() => _AppBarBubbleButtonState();
}

class _AppBarBubbleButtonState extends State<_AppBarBubbleButton> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !widget.controller.hasClients) return;
    const double collapseThreshold = 240.0 - kToolbarHeight;
    final double newProgress =
        (widget.controller.offset / collapseThreshold).clamp(0.0, 1.0);
    if (newProgress != _progress) {
      setState(() {
        _progress = newProgress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    final Color iconColor = cs.onSurface;
    final Color bubbleColor =
        cs.surfaceContainerHighest.withValues(alpha: 0.75 * (1.0 - _progress));

    return Center(
      child: Container(
        width: 38,
        height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: bubbleColor,
        ),
        child: widget.child ??
            IconButton(
              tooltip: widget.tooltip,
              icon: Icon(widget.icon, size: 20, color: iconColor),
              onPressed: widget.onPressed,
              padding: EdgeInsets.zero,
            ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dynamic App Bar Icon for PopupMenuButton
// ---------------------------------------------------------------------------

class _AppBarDynamicIcon extends StatefulWidget {
  const _AppBarDynamicIcon({
    required this.controller,
    required this.icon,
  });

  final ScrollController controller;
  final IconData icon;

  @override
  State<_AppBarDynamicIcon> createState() => _AppBarDynamicIconState();
}

class _AppBarDynamicIconState extends State<_AppBarDynamicIcon> {
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !widget.controller.hasClients) return;
    const double collapseThreshold = 240.0 - kToolbarHeight;
    final double newProgress =
        (widget.controller.offset / collapseThreshold).clamp(0.0, 1.0);
    if (newProgress != _progress) {
      setState(() {
        _progress = newProgress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Icon(widget.icon, size: 20, color: cs.onSurface);
  }
}

// ---------------------------------------------------------------------------
// Collapsing App Bar Title
// ---------------------------------------------------------------------------

class _CollapsedTitle extends StatefulWidget {
  const _CollapsedTitle({
    required this.controller,
    required this.title,
  });

  final ScrollController controller;
  final String title;

  @override
  State<_CollapsedTitle> createState() => _CollapsedTitleState();
}

class _CollapsedTitleState extends State<_CollapsedTitle> {
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onScroll());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (!mounted || !widget.controller.hasClients) return;
    const double startFade = 240.0 - kToolbarHeight - 20;
    const double endFade = 240.0 - kToolbarHeight;
    final double offset = widget.controller.offset;
    final double newOpacity =
        ((offset - startFade) / (endFade - startFade)).clamp(0.0, 1.0);
    if (newOpacity != _opacity) {
      setState(() {
        _opacity = newOpacity;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _opacity,
      child: Text(
        widget.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Unified Artist Hero Header
// ---------------------------------------------------------------------------

class _ArtistHeroHeader extends StatelessWidget {
  const _ArtistHeroHeader({
    required this.instance,
    required this.artist,
    required this.onToggleMonitored,
    required this.onSearchMissing,
    required this.onInteractiveSearch,
  });

  final Instance instance;
  final ArtistResource? artist;
  final VoidCallback onToggleMonitored;
  final VoidCallback onSearchMissing;
  final VoidCallback onInteractiveSearch;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final String? posterUrl = LidarrArtwork.artistPosterUrl(
      instance,
      artist?.images,
      preferRemote: true,
    );

    final int totalTracks = artist?.statistics?.totalTrackCount ?? 0;
    final int trackFiles = artist?.statistics?.trackFileCount ?? 0;
    final double percent =
        totalTracks > 0 ? (trackFiles / totalTracks).clamp(0.0, 1.0) : 0.0;
    final String sizeOnDisk =
        LidarrFormatters.formatBytes(artist?.statistics?.sizeOnDisk);
    final bool isMonitored = artist?.monitored ?? false;
    final List<String> genres = artist?.genres ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Main row: Poster + Details
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 76x76 Squircle Poster with subtle border and shadow
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: posterUrl != null
                      ? AtriumNetworkImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          errorWidget: (_, __, ___) => Container(
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                              Icons.person,
                              size: 36,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        )
                      : Container(
                          color: cs.surfaceContainerHighest,
                          child: Icon(
                            Icons.person,
                            size: 36,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Artist Name & Metadata Lines
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    artist?.artistName ?? 'Artist',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (artist?.disambiguation != null &&
                      artist!.disambiguation!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        artist!.disambiguation!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 4),

                  // Inline concise stats: tracks • size • status
                  Text(
                    [
                      '$trackFiles/$totalTracks tracks (${(percent * 100).toInt()}%)',
                      if (sizeOnDisk.isNotEmpty) sizeOnDisk,
                      if (artist?.status?.value case final String status)
                        status,
                    ].join(' • '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Inline subtle genres (at most 3 comma-separated)
                  if (genres.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        genres.take(3).join(', '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w500,
                          fontSize: 11.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Action Bar: [ FilledButton.tonal Monitored ] + [ Search Missing ] + [ Interactive Search ]
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                icon: Icon(
                  isMonitored ? Icons.bookmark : Icons.bookmark_border,
                  size: 18,
                ),
                label: Text(
                  isMonitored ? 'Monitored' : 'Unmonitored',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: isMonitored
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest,
                  foregroundColor:
                      isMonitored ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: onToggleMonitored,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.search, size: 18),
                label: const Text(
                  'Search Missing',
                  style: TextStyle(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: onSearchMissing,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: const Icon(Icons.manage_search, size: 20),
              tooltip: 'Interactive Search',
              style: IconButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onInteractiveSearch,
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Collapsible Overview Section
// ---------------------------------------------------------------------------

class _OverviewSection extends StatefulWidget {
  const _OverviewSection({required this.overview});

  final String overview;

  @override
  State<_OverviewSection> createState() => _OverviewSectionState();
}

class _OverviewSectionState extends State<_OverviewSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return InkWell(
      onTap: () => setState(() => _expanded = !_expanded),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.overview,
              maxLines: _expanded ? 100 : 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _expanded ? 'Show less' : 'Read more',
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
