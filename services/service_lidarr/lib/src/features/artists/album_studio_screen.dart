import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../generated/generated.dart';
import '../../lidarr_api.dart';
import '../../lidarr_artwork.dart';
import '../../lidarr_providers.dart';

/// Full-screen mass album monitoring manager for Lidarr.
class LidarrAlbumStudioScreen extends ConsumerStatefulWidget {
  const LidarrAlbumStudioScreen({
    required this.instance,
    this.initialArtistIds,
    super.key,
  });

  final Instance instance;
  final Set<int>? initialArtistIds;

  @override
  ConsumerState<LidarrAlbumStudioScreen> createState() =>
      _LidarrAlbumStudioScreenState();
}

class _LidarrAlbumStudioScreenState
    extends ConsumerState<LidarrAlbumStudioScreen> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final ScrollController _scrollController;
  double _lastBottomInset = 0.0;
  String _searchQuery = '';
  Set<int>? _filteredArtistIds;

  /// Global map of album monitoring states across all artists
  final Set<int> _selectedAlbumIds = <int>{};
  final Set<int> _initializedArtistIds = <int>{};
  final Set<int> _expandedArtistIds = <int>{};

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController = ScrollController()..addListener(_onScroll);
    if (widget.initialArtistIds != null &&
        widget.initialArtistIds!.isNotEmpty) {
      _filteredArtistIds = Set<int>.from(widget.initialArtistIds!);
      // Automatically expand initial artists if only a few are selected
      if (_filteredArtistIds!.length <= 5) {
        _expandedArtistIds.addAll(_filteredArtistIds!);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
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

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.userScrollDirection !=
            ScrollDirection.idle) {
      if (_searchFocusNode.hasFocus) {
        _searchFocusNode.unfocus();
      }
    }
  }

  Future<void> _saveChanges(List<ArtistResource> allArtists) async {
    setState(() => _isSaving = true);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    try {
      final LidarrApi api =
          await ref.read(lidarrApiProvider(widget.instance).future);

      final List<AlbumStudioArtistResource> studioPayload = [];

      for (final ArtistResource a in allArtists) {
        final int? aId = a.id;
        if (aId == null) continue;

        // If this artist's albums were fetched/initialized, build their album payload
        final AsyncValue<List<AlbumResource>> albumsAsync = ref.read(
          lidarrAlbumsForArtistProvider((widget.instance, aId)),
        );

        final List<AlbumResource>? albums = albumsAsync.value;
        if (albums != null && albums.isNotEmpty) {
          final List<AlbumResource> updatedAlbums = albums.map((alb) {
            final bool isMon =
                alb.id != null && _selectedAlbumIds.contains(alb.id);
            return alb.copyWith(monitored: isMon);
          }).toList();

          studioPayload.add(
            AlbumStudioArtistResource(
              id: aId,
              monitored: a.monitored,
              albums: updatedAlbums,
            ),
          );
        }
      }

      if (studioPayload.isEmpty) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('No changes to save.')),
          );
        }
        return;
      }

      final ApiResponse<void> resp = await api.albumStudio.postAlbumstudio(
        body: AlbumStudioResource(artist: studioPayload),
      );

      if (!resp.isSuccess) {
        throw Exception(
          resp.error?.message ?? 'Failed to update Album Studio',
        );
      }

      ref.invalidate(lidarrArtistsProvider(widget.instance));
      for (final AlbumStudioArtistResource p in studioPayload) {
        if (p.id != null) {
          ref.invalidate(
            lidarrAlbumsForArtistProvider((widget.instance, p.id!)),
          );
        }
      }

      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Successfully updated monitoring for ${studioPayload.length} ${studioPayload.length == 1 ? 'artist' : 'artists'}!',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Save error: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _onToggleArtistExpanded(int artistId) {
    setState(() {
      if (_expandedArtistIds.contains(artistId)) {
        _expandedArtistIds.remove(artistId);
      } else {
        _expandedArtistIds.add(artistId);
      }
    });
  }

  void _onToggleSingleAlbum(int albumId, bool monitored) {
    setState(() {
      if (monitored) {
        _selectedAlbumIds.add(albumId);
      } else {
        _selectedAlbumIds.remove(albumId);
      }
    });
  }

  void _onToggleAllAlbumsForArtist(List<AlbumResource> albums, bool monitor) {
    setState(() {
      for (final AlbumResource alb in albums) {
        if (alb.id != null) {
          if (monitor) {
            _selectedAlbumIds.add(alb.id!);
          } else {
            _selectedAlbumIds.remove(alb.id!);
          }
        }
      }
    });
  }

  void _onMonitorStudioAlbumsOnly(List<AlbumResource> albums) {
    setState(() {
      for (final AlbumResource alb in albums) {
        if (alb.id != null) {
          final String type = (alb.albumType ?? '').toLowerCase();
          final bool isStudio =
              type == 'album' || type == 'studio' || type == 'studio album';
          if (isStudio) {
            _selectedAlbumIds.add(alb.id!);
          } else {
            _selectedAlbumIds.remove(alb.id!);
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final AsyncValue<List<ArtistResource>> asyncArtists =
        ref.watch(lidarrArtistsProvider(widget.instance));

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Album Studio',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            asyncArtists.when(
              data: (artists) => Text(
                '${artists.length} artists in library',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              onPressed: _isSaving
                  ? null
                  : () {
                      final List<ArtistResource> artists =
                          asyncArtists.value ?? <ArtistResource>[];
                      _saveChanges(artists);
                    },
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save'),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: Column(
          children: [
            // M3 Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(Icons.search, color: cs.onSurfaceVariant, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        decoration: InputDecoration(
                          hintText: 'Filter artists by name...',
                          hintStyle: TextStyle(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                            fontSize: 14,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (String val) => setState(
                          () => _searchQuery = val.trim().toLowerCase(),
                        ),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        tooltip: 'Clear search',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          _searchController.clear();
                          _searchFocusNode.unfocus();
                          setState(() => _searchQuery = '');
                        },
                      ),
                  ],
                ),
              ),
            ),

            // Optional active filter pills (e.g. Scoped to selected artists)
            if (_filteredArtistIds != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    FilterChip(
                      selected: true,
                      label: Text(
                        'Showing ${_filteredArtistIds!.length} selected artists',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onSelected: (_) {},
                      onDeleted: () {
                        setState(() => _filteredArtistIds = null);
                      },
                    ),
                  ],
                ),
              ),

            // Main Artist Album Grid/List
            Expanded(
              child: AsyncValueView<List<ArtistResource>>(
                value: asyncArtists,
                data: (List<ArtistResource> artists) {
                  final List<ArtistResource> filtered = artists.where((
                    ArtistResource a,
                  ) {
                    if (_filteredArtistIds != null &&
                        !_filteredArtistIds!.contains(a.id)) {
                      return false;
                    }
                    if (_searchQuery.isEmpty) return true;
                    return (a.artistName ?? '')
                        .toLowerCase()
                        .contains(_searchQuery);
                  }).toList();

                  if (filtered.isEmpty) {
                    return const Center(
                      child: EmptyView(
                        icon: Icons.search_off_outlined,
                        title: 'No Artists Found',
                        message:
                            'No artists in your library match the current filter.',
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                    itemCount: filtered.length,
                    itemBuilder: (BuildContext context, int index) {
                      final ArtistResource artist = filtered[index];
                      final int artistId = artist.id ?? 0;
                      final bool isExpanded =
                          _expandedArtistIds.contains(artistId);

                      return _ArtistMatrixCard(
                        key: ValueKey('studio_artist_$artistId'),
                        instance: widget.instance,
                        artist: artist,
                        isExpanded: isExpanded,
                        selectedAlbumIds: _selectedAlbumIds,
                        isInitialized: _initializedArtistIds.contains(artistId),
                        onInitializeAlbums: (List<AlbumResource> albums) {
                          if (!_initializedArtistIds.contains(artistId)) {
                            for (final AlbumResource alb in albums) {
                              if (alb.id != null && alb.monitored == true) {
                                _selectedAlbumIds.add(alb.id!);
                              }
                            }
                            _initializedArtistIds.add(artistId);
                          }
                        },
                        onToggleExpand: () => _onToggleArtistExpanded(artistId),
                        onToggleAlbum: _onToggleSingleAlbum,
                        onToggleAllAlbums: _onToggleAllAlbumsForArtist,
                        onMonitorStudioOnly: _onMonitorStudioAlbumsOnly,
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArtistMatrixCard extends ConsumerWidget {
  const _ArtistMatrixCard({
    required this.instance,
    required this.artist,
    required this.isExpanded,
    required this.selectedAlbumIds,
    required this.isInitialized,
    required this.onInitializeAlbums,
    required this.onToggleExpand,
    required this.onToggleAlbum,
    required this.onToggleAllAlbums,
    required this.onMonitorStudioOnly,
    super.key,
  });

  final Instance instance;
  final ArtistResource artist;
  final bool isExpanded;
  final Set<int> selectedAlbumIds;
  final bool isInitialized;
  final void Function(List<AlbumResource> albums) onInitializeAlbums;
  final VoidCallback onToggleExpand;
  final void Function(int albumId, bool monitored) onToggleAlbum;
  final void Function(List<AlbumResource> albums, bool monitor)
      onToggleAllAlbums;
  final void Function(List<AlbumResource> albums) onMonitorStudioOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final int artistId = artist.id ?? 0;
    final String? posterUrl =
        LidarrArtwork.artistPosterUrl(instance, artist.images);

    // Watch albums only when expanded or already initialized
    final AsyncValue<List<AlbumResource>>? asyncAlbums =
        isExpanded || isInitialized
            ? ref.watch(lidarrAlbumsForArtistProvider((instance, artistId)))
            : null;

    if (asyncAlbums != null && asyncAlbums.hasValue) {
      onInitializeAlbums(asyncAlbums.value!);
    }

    final bool isContinuing = artist.status != ArtistStatusType.ended;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isExpanded
              ? cs.primary.withValues(alpha: 0.5)
              : cs.outlineVariant.withValues(alpha: 0.35),
          width: isExpanded ? 1.5 : 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Artist Header Tile
          InkWell(
            onTap: onToggleExpand,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  // Artist Avatar Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 44,
                      height: 44,
                      color: cs.surfaceContainerHighest,
                      child: posterUrl != null
                          ? AtriumNetworkImage(
                              imageUrl: posterUrl,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Icon(
                                Icons.person,
                                color: cs.onSurfaceVariant,
                              ),
                            )
                          : Icon(Icons.person, color: cs.onSurfaceVariant),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Artist Name & Badges
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          artist.artistName ?? 'Artist',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            // Status badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isContinuing
                                    ? Colors.green.withValues(alpha: 0.15)
                                    : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isContinuing ? 'Continuing' : 'Ended',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: isContinuing
                                      ? Colors.greenAccent.shade400
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),

                            // Monitored badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: (artist.monitored == true)
                                    ? cs.primaryContainer.withValues(alpha: 0.4)
                                    : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                artist.monitored == true
                                    ? 'Monitored'
                                    : 'Unmonitored',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: artist.monitored == true
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                ),
                              ),
                            ),

                            if (artist.disambiguation != null &&
                                artist.disambiguation!.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '(${artist.disambiguation})',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Animated Expansion Chevron
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Discography Expansion Content
          if (isExpanded) ...[
            const Divider(height: 1),
            if (asyncAlbums == null || asyncAlbums.isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              )
            else if (asyncAlbums.hasError)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Failed to load albums: ${asyncAlbums.error}',
                  style: TextStyle(color: cs.error, fontSize: 13),
                ),
              )
            else ...[
              _DiscographyMatrix(
                instance: instance,
                artist: artist,
                albums: asyncAlbums.value ?? <AlbumResource>[],
                selectedAlbumIds: selectedAlbumIds,
                onToggleAlbum: onToggleAlbum,
                onToggleAllAlbums: onToggleAllAlbums,
                onMonitorStudioOnly: onMonitorStudioOnly,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _DiscographyMatrix extends StatelessWidget {
  const _DiscographyMatrix({
    required this.instance,
    required this.artist,
    required this.albums,
    required this.selectedAlbumIds,
    required this.onToggleAlbum,
    required this.onToggleAllAlbums,
    required this.onMonitorStudioOnly,
  });

  final Instance instance;
  final ArtistResource artist;
  final List<AlbumResource> albums;
  final Set<int> selectedAlbumIds;
  final void Function(int albumId, bool monitored) onToggleAlbum;
  final void Function(List<AlbumResource> albums, bool monitor)
      onToggleAllAlbums;
  final void Function(List<AlbumResource> albums) onMonitorStudioOnly;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    if (albums.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Center(
          child: Text(
            'No albums found for this artist.',
            style: TextStyle(fontSize: 13),
          ),
        ),
      );
    }

    final int monitoredCount = albums
        .where((a) => a.id != null && selectedAlbumIds.contains(a.id))
        .length;
    final bool allMonitored =
        albums.isNotEmpty && monitoredCount == albums.length;

    final bool hasNonStudioAlbums = albums.any((a) {
      final String type = (a.albumType ?? '').toLowerCase();
      return type != 'album' && type != 'studio' && type != 'studio album';
    });

    return Column(
      children: [
        // Quick Action Bar
        Container(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              // Summary Count
              Text(
                '$monitoredCount of ${albums.length} ${albums.length == 1 ? 'Album' : 'Albums'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const Spacer(),

              // "Studio Only" preset button if applicable
              if (hasNonStudioAlbums) ...[
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () => onMonitorStudioOnly(albums),
                  child: const Text(
                    'Studio Only',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 4),
              ],

              // Monitor All / Unmonitor All Button
              FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                ),
                onPressed: () => onToggleAllAlbums(albums, !allMonitored),
                child: Text(
                  allMonitored ? 'Unmonitor All' : 'Monitor All',
                  style: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Album Rows
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: albums.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.2),
          ),
          itemBuilder: (BuildContext context, int index) {
            final AlbumResource album = albums[index];
            final int? albumId = album.id;
            if (albumId == null) return const SizedBox.shrink();

            final bool isMonitored = selectedAlbumIds.contains(albumId);
            final String? coverUrl =
                LidarrArtwork.albumCoverUrl(instance, album.images);

            final int trackFiles = album.statistics?.trackFileCount ?? 0;
            final int totalTracks = album.statistics?.totalTrackCount ??
                album.statistics?.trackCount ??
                0;
            final bool hasTracks = totalTracks > 0;
            final bool isComplete = hasTracks && trackFiles >= totalTracks;

            final String releaseYear =
                album.releaseDate != null && album.releaseDate!.length >= 4
                    ? album.releaseDate!.substring(0, 4)
                    : '--';

            return InkWell(
              onTap: () => onToggleAlbum(albumId, !isMonitored),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    // Album Cover Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        width: 38,
                        height: 38,
                        color: cs.surfaceContainerHighest,
                        child: coverUrl != null
                            ? AtriumNetworkImage(
                                imageUrl: coverUrl,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Icon(
                                  Icons.album_outlined,
                                  color: cs.onSurfaceVariant,
                                  size: 20,
                                ),
                              )
                            : Icon(
                                Icons.album_outlined,
                                color: cs.onSurfaceVariant,
                                size: 20,
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Title & Metadata
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            album.title ?? 'Album',
                            style: TextStyle(
                              fontWeight: isMonitored
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              fontSize: 13.5,
                              color: isMonitored
                                  ? cs.onSurface
                                  : cs.onSurface.withValues(alpha: 0.7),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              // Type Badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  album.albumType ?? 'Album',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                releaseYear,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              if (hasTracks) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '•',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$trackFiles/$totalTracks tracks',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isComplete
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isComplete
                                        ? Colors.greenAccent.shade400
                                        : isMonitored
                                            ? cs.primary
                                            : cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Checkbox
                    Checkbox(
                      value: isMonitored,
                      visualDensity: VisualDensity.compact,
                      onChanged: (bool? val) {
                        if (val != null) {
                          onToggleAlbum(albumId, val);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
