import 'dart:async';

import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../generated/models/artist_resource.dart';
import '../../lidarr_artwork.dart';
import '../../lidarr_providers.dart';
import 'add_artist_sheet.dart';
import 'artist_detail_screen.dart';

/// Screen allowing online search and lookup of music artists to add to Lidarr.
class LidarrAddArtistSearchScreen extends ConsumerStatefulWidget {
  const LidarrAddArtistSearchScreen({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<LidarrAddArtistSearchScreen> createState() =>
      _LidarrAddArtistSearchScreenState();
}

class _LidarrAddArtistSearchScreenState
    extends ConsumerState<LidarrAddArtistSearchScreen>
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

    final AsyncValue<List<ArtistResource>> lookupResults = ref.watch(
      lidarrArtistLookupProvider((widget.instance, _debouncedQuery)),
    );

    // Watch local artists library to check if already added
    final List<ArtistResource> localArtists =
        ref.watch(lidarrArtistsProvider(widget.instance)).value ?? [];

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
              hintText: 'Search online artist catalog...',
              textInputAction: TextInputAction.search,
              onSubmitted: (_) {
                if (_searchFocusNode.hasFocus) {
                  _searchFocusNode.unfocus();
                }
              },
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
                      'Search for an artist to add',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            : AsyncValueView<List<ArtistResource>>(
                value: lookupResults,
                onRetry: () {
                  ref.invalidate(
                    lidarrArtistLookupProvider(
                      (widget.instance, _debouncedQuery),
                    ),
                  );
                },
                data: (List<ArtistResource> results) {
                  if (results.isEmpty) {
                    return const EmptyView(
                      icon: Icons.search_off_outlined,
                      title: 'No artists found',
                      message:
                          'We couldn\'t find any artists matching your query.',
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(Insets.md),
                    itemCount: results.length,
                    itemBuilder: (BuildContext context, int index) {
                      final ArtistResource artist = results[index];

                      // Robust match against local library by foreignArtistId, mbId, artistName, or id
                      final ArtistResource? localMatch =
                          localArtists.firstWhereOrNull(
                        (local) =>
                            (local.foreignArtistId != null &&
                                artist.foreignArtistId != null &&
                                local.foreignArtistId!.trim().toLowerCase() ==
                                    artist.foreignArtistId!
                                        .trim()
                                        .toLowerCase()) ||
                            (local.mbId != null &&
                                artist.mbId != null &&
                                local.mbId!.trim().toLowerCase() ==
                                    artist.mbId!.trim().toLowerCase()) ||
                            (local.artistName != null &&
                                artist.artistName != null &&
                                local.artistName!.trim().toLowerCase() ==
                                    artist.artistName!.trim().toLowerCase()) ||
                            (local.id != null &&
                                local.id! > 0 &&
                                artist.id != null &&
                                artist.id! > 0 &&
                                local.id == artist.id),
                      );
                      final bool isAdded = localMatch != null;

                      final String subtitle = [
                        if (artist.disambiguation != null &&
                            artist.disambiguation!.isNotEmpty)
                          artist.disambiguation!,
                        if (artist.genres != null && artist.genres!.isNotEmpty)
                          artist.genres!.take(2).join(', '),
                      ].join(' • ');

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
                                  builder: (_) => ArtistDetailScreen(
                                    instance: widget.instance,
                                    artistId: localMatch.id ?? 0,
                                    initialArtist: localMatch,
                                  ),
                                ),
                              );
                            } else {
                              // Tapping unadded artist opens configuration sheet (Step 3)
                              _openAddArtistSheet(context, artist);
                            }
                          },
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 1:1 Square Artist Artwork
                                SizedBox(
                                  width: 100,
                                  child: AspectRatio(
                                    aspectRatio: 1.0,
                                    child: _PosterImage(
                                      instance: widget.instance,
                                      artist: artist,
                                    ),
                                  ),
                                ),
                                // Metadata info
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
                                              artist.artistName ??
                                                  'Unknown Artist',
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (subtitle.isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(
                                                subtitle,
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: Insets.sm),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          alignment: WrapAlignment.spaceBetween,
                                          children: [
                                            if (artist.artistType != null &&
                                                artist.artistType!.isNotEmpty)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: cs
                                                      .surfaceContainerHighest,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  artist.artistType!,
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    color: cs.onSurfaceVariant,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 10.5,
                                                  ),
                                                ),
                                              ),
                                            // Status Chip
                                            if (artist.status != null)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 7,
                                                  vertical: 2,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _statusColor(
                                                    artist.status!.value,
                                                    theme,
                                                  ).withValues(alpha: 0.15),
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                child: Text(
                                                  _capitalise(
                                                    artist.status!.value,
                                                  ),
                                                  style: theme
                                                      .textTheme.bodySmall
                                                      ?.copyWith(
                                                    color: _statusColor(
                                                      artist.status!.value,
                                                      theme,
                                                    ),
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 10.5,
                                                  ),
                                                ),
                                              ),
                                            // Added / Not Added indicator
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

  void _openAddArtistSheet(BuildContext context, ArtistResource artist) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => LidarrAddArtistSheet(
        instance: widget.instance,
        artist: artist,
      ),
    );
  }

  Color _statusColor(String status, ThemeData theme) {
    return switch (status.toLowerCase()) {
      'continuing' => theme.colorScheme.primary,
      'ended' => theme.colorScheme.outline,
      _ => theme.colorScheme.secondary,
    };
  }

  String _capitalise(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}

class _PosterImage extends ConsumerWidget {
  const _PosterImage({required this.instance, required this.artist});

  final Instance instance;
  final ArtistResource artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? url = LidarrArtwork.artistPosterUrl(
          instance,
          artist.images,
          preferRemote: true,
        ) ??
        (artist.remotePoster != null && artist.remotePoster!.isNotEmpty
            ? artist.remotePoster
            : null);

    if (url == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Center(
          child: Icon(Icons.person, size: 36),
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
