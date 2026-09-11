import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'jellyfin_client.dart';
import 'jellyfin_deep_link.dart';
import 'jellyfin_providers.dart';
import 'models/jellyfin_item.dart';

class JellyfinAlbumScreen extends ConsumerWidget {
  const JellyfinAlbumScreen({
    required this.instance,
    required this.albumId,
    required this.albumName,
    required this.albumArtist,
    this.albumOverview,
    this.albumGenres,
    this.albumImageUrl,
    super.key,
  });

  final Instance instance;
  final String albumId;
  final String albumName;
  final String albumArtist;
  final String? albumOverview;
  final List<String>? albumGenres;
  final String? albumImageUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<AlbumScreenData> dataAsync = ref.watch(
      jellyfinAlbumDataFutureProvider((instance, albumId, albumArtist)),
    );
    final JellyfinClient? client =
        ref.watch(jellyfinClientProvider(instance)).value;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
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
        onRefresh: () async => ref.invalidate(
          jellyfinAlbumDataFutureProvider((instance, albumId, albumArtist)),
        ),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: <Widget>[
            // Top Section: Album Info
            SliverToBoxAdapter(
              child: albumImageUrl != null
                  ? SizedBox(
                      height: MediaQuery.of(context).size.height * 0.5,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: AtriumNetworkImage(
                              imageUrl: albumImageUrl!,
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
                            child: _buildHeader(context, client),
                          ),
                        ],
                      ),
                    )
                  : SafeArea(
                      bottom: false,
                      child: Padding(
                        // Clear the floating back arrow: the body extends
                        // behind the transparent app bar, so without artwork
                        // the header would sit underneath it.
                        padding: const EdgeInsets.only(
                          top: kToolbarHeight + Insets.lg,
                        ),
                        child: _buildHeader(context, client),
                      ),
                    ),
            ),
            const HeaderLocator.sliver(),

            if (albumGenres != null && albumGenres!.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: Insets.lg,
                    right: Insets.lg,
                    top: Insets.lg,
                  ),
                  child: Wrap(
                    spacing: 6.0,
                    runSpacing: 6.0,
                    children: albumGenres!.map((String g) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(context).colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          g,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSecondaryContainer,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),

            if (albumOverview != null && albumOverview!.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(Insets.lg),
                  child: OverviewBox(overview: albumOverview!),
                ),
              ),

            // Data Section: Bio and Tracks
            SliverToBoxAdapter(
              child: AsyncValueView<AlbumScreenData>(
                value: dataAsync,
                onRetry: () => ref.invalidate(
                  jellyfinAlbumDataFutureProvider(
                    (instance, albumId, albumArtist),
                  ),
                ),
                data: (AlbumScreenData data) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      // Bottom Section: Tracklist
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Insets.lg,
                          vertical: Insets.sm,
                        ),
                        child: Text(
                          'Tracks - ${data.tracks.length}',
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
                        itemCount: data.tracks.length,
                        itemBuilder: (BuildContext context, int index) {
                          final JellyfinItem song = data.tracks[index];

                          String duration = '';
                          if (song.runTimeTicks != null) {
                            final int totalSeconds =
                                (song.runTimeTicks! / 10000000).round();
                            final int minutes = totalSeconds ~/ 60;
                            final int seconds = totalSeconds % 60;
                            duration =
                                '$minutes:${seconds.toString().padLeft(2, '0')}';
                          }

                          final String? imageUrl =
                              client?.imageUrl(song) ?? albumImageUrl;

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: Insets.lg,
                              vertical: Insets.xs,
                            ),
                            onTap: () {
                              if (client != null) {
                                launchJellyfinDeepLink(
                                  context,
                                  client,
                                  song.id,
                                );
                              }
                            },
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                SizedBox(
                                  width: 24,
                                  child: Text(
                                    song.indexNumber?.toString() ??
                                        '${index + 1}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .outline,
                                        ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                const SizedBox(width: Insets.md),
                                if (imageUrl != null)
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: AtriumNetworkImage(
                                      imageUrl: imageUrl,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      errorWidget: (context, url, error) =>
                                          Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Icon(Icons.music_note),
                                      ),
                                    ),
                                  )
                                else
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Icon(Icons.music_note),
                                  ),
                              ],
                            ),
                            title: Text(
                              song.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              song.artists.isNotEmpty
                                  ? '${song.artists.join(', ')} • $duration'
                                  : duration,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
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

  Widget _buildHeader(BuildContext context, JellyfinClient? client) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          if (albumImageUrl != null)
            ClipRRect(
              borderRadius: Radii.card,
              child: AtriumNetworkImage(
                imageUrl: albumImageUrl!,
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
                  albumName,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: Insets.xs),
                Text(
                  albumArtist,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
                const SizedBox(height: Insets.md),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (client != null) {
                        launchJellyfinDeepLink(context, client, albumId);
                      }
                    },
                    icon: const Icon(Icons.play_circle_fill),
                    label: const Text('Play Now'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Theme.of(context).colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(
                  height: Insets.xs,
                ), // Add a small padding at the bottom so it aligns perfectly with the poster's bottom edge
              ],
            ),
          ),
        ],
      ),
    );
  }
}
