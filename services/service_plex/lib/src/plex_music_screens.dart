import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'models/plex_models.dart';
import 'plex_api.dart';
import 'plex_deep_link.dart';
import 'plex_providers.dart';

/// Albums of an artist as a cover grid; tapping an album opens its track
/// list. Browse only: Atrium is a controller, music plays in the Plex app.
class PlexArtistScreen extends ConsumerWidget {
  const PlexArtistScreen({
    required this.instance,
    required this.artist,
    super.key,
  });

  final Instance instance;
  final PlexMetadata artist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PlexMetadata>> albums =
        ref.watch(plexChildrenProvider((instance, artist.ratingKey)));
    final PlexApi? api = ref.watch(plexApiProvider(instance)).value;

    return Scaffold(
      appBar: AppBar(title: Text(artist.title)),
      body: AsyncValueView<List<PlexMetadata>>(
          value: albums,
          onRetry: () => ref
              .invalidate(plexChildrenProvider((instance, artist.ratingKey))),
          data: (List<PlexMetadata> list) {
            
            if (list.isEmpty) {
              return EasyRefresh(
        header: const ClassicHeader(
          dragText: 'Pull to refresh',
          armedText: 'Release ready',
          readyText: 'Refreshing...',
          processingText: 'Refreshing...',
          processedText: 'Succeeded',
          failedText: 'Failed',
          messageText: 'Last updated at %T',
        ),
        onRefresh: () async =>
            ref.invalidate(plexChildrenProvider((instance, artist.ratingKey))),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const <Widget>[
            SizedBox(height: 100),
            EmptyView(
                icon: Icons.album_outlined,
                title: 'No albums',
                message: 'This artist has no albums yet.',
              ),
          ],
        ),
      );
            }
            return EasyRefresh(
      header: const ClassicHeader(
        dragText: 'Pull to refresh',
        armedText: 'Release ready',
        readyText: 'Refreshing...',
        processingText: 'Refreshing...',
        processedText: 'Succeeded',
        failedText: 'Failed',
        messageText: 'Last updated at %T',
      ),
      onRefresh: () async =>
            ref.invalidate(plexChildrenProvider((instance, artist.ratingKey))),
      child: MasonryGridView.extent(
              padding: Insets.page,
              maxCrossAxisExtent: 160,
              crossAxisSpacing: Insets.md,
              mainAxisSpacing: Insets.md,
              itemCount: list.length,
              itemBuilder: (BuildContext context, int index) {
                final PlexMetadata album = list[index];
                return _AlbumCard(
                  album: album,
                  imageUrl: api?.imageUrl(album.thumb),
                  onTap: () => pushScreen<void>(
                    context,
                    PlexAlbumScreen(instance: instance, album: album),
                  ),
                );
              },
            ),
    );
          
          },
        ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({
    required this.album,
    required this.imageUrl,
    required this.onTap,
  });

  final PlexMetadata album;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 1.0,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox.expand(child: _cover(theme)),
              ),
            ),
          ),
          const SizedBox(height: Insets.xs),
          Text(
            album.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (album.year != null)
            Text(
              '${album.year}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
        ],
      ),
    );
  }

  Widget _cover(ThemeData theme) {
    final Widget fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.album_outlined, color: theme.colorScheme.outline),
    );
    if (imageUrl == null) {
      return fallback;
    }
    return AtriumNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      memCacheWidth: 320,
      placeholder: (BuildContext context, String url) =>
          Container(color: theme.colorScheme.surfaceContainerHighest),
      errorWidget: (BuildContext context, String url, Object error) => fallback,
    );
  }
}

class PlexAlbumScreen extends ConsumerWidget {
  const PlexAlbumScreen({
    required this.instance,
    required this.album,
    super.key,
  });

  final Instance instance;
  final PlexMetadata album;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PlexMetadata>> tracks =
        ref.watch(plexChildrenProvider((instance, album.ratingKey)));
    final PlexApi? api = ref.watch(plexApiProvider(instance)).value;
    final String? albumImageUrl = api?.imageUrl(album.thumb);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: <Widget>[
          IconButton(
            tooltip: 'Open in Plex',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => launchPlexDeepLink(context),
          ),
        ],
      ),
      body: EasyRefresh(
          header: const ClassicHeader(
            position: IndicatorPosition.locator,
            dragText: 'Pull to refresh',
            armedText: 'Release ready',
            readyText: 'Refreshing...',
            processingText: 'Refreshing...',
            processedText: 'Succeeded',
            failedText: 'Failed',
            messageText: 'Last updated at %T',
          ),
        onRefresh: () async =>
            ref.invalidate(plexChildrenProvider((instance, album.ratingKey))),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: albumImageUrl != null
                  ? SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: AtriumNetworkImage(
                              imageUrl: albumImageUrl,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned.fill(
                            child: ColoredBox(
                              color: Colors.black.withValues(alpha: 0.4),
                            ),
                          ),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: <Color>[
                                    Theme.of(context)
                                        .colorScheme
                                        .surface
                                        .withValues(alpha: 0.0),
                                    Theme.of(context)
                                        .colorScheme
                                        .surface
                                        .withValues(alpha: 0.55),
                                    Theme.of(context).colorScheme.surface,
                                  ],
                                  stops: const <double>[0.35, 0.75, 1.0],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: _buildHeader(context, api),
                          ),
                        ],
                      ),
                    )
                  : SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.only(top: Insets.lg),
                        child: _buildHeader(context, api),
                      ),
                    ),
            ),
            const HeaderLocator.sliver(),
            if (album.summary != null && album.summary!.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(Insets.lg),
                  child: OverviewBox(overview: album.summary!),
                ),
              ),
            SliverToBoxAdapter(
              child: AsyncValueView<List<PlexMetadata>>(
                value: tracks,
                onRetry: () => ref.invalidate(
                  plexChildrenProvider((instance, album.ratingKey)),
                ),
                data: (List<PlexMetadata> list) {
                  if (list.isEmpty) {
                    return const EmptyView(
                      icon: Icons.music_note_outlined,
                      title: 'No tracks',
                      message: 'This album has no tracks yet.',
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Insets.lg,
                          vertical: Insets.sm,
                        ),
                        child: Text(
                          'Tracks - ${list.length}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: list.length,
                        itemBuilder: (BuildContext context, int index) {
                          final PlexMetadata track = list[index];
                          return _TrackRow(track: track);
                        },
                      ),
                      const SizedBox(height: Insets.xl),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, PlexApi? api) {
    final String? albumImageUrl = api?.imageUrl(album.thumb);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (albumImageUrl != null)
            ClipRRect(
              borderRadius: Radii.card,
              child: AtriumNetworkImage(
                imageUrl: albumImageUrl,
                width: 140,
                height: 140,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: Radii.card,
              ),
              child: const Icon(Icons.album, size: 48),
            ),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  album.title,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (album.parentTitle != null) ...<Widget>[
                  const SizedBox(height: Insets.xs),
                  Text(
                    album.parentTitle!,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                ],
                const SizedBox(height: Insets.xs),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track});

  final PlexMetadata track;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String duration = _formatTrackDuration(track.duration);
    return ListTile(
      leading: SizedBox(
        width: 32,
        child: Center(
          child: Text(
            track.index != null ? '${track.index}' : '-',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: duration.isEmpty
          ? null
          : Text(
              duration,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
    );
  }
}

/// Formats a track duration in milliseconds as `m:ss` (284000 -> '4:44').
String _formatTrackDuration(int? durationMs) {
  if (durationMs == null || durationMs <= 0) {
    return '';
  }
  final int totalSeconds = durationMs ~/ 1000;
  final int minutes = totalSeconds ~/ 60;
  final String seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
