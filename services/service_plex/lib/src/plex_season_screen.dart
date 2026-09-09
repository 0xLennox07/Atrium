import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';

import 'models/plex_models.dart';
import 'plex_api.dart';
import 'plex_item_detail.dart';
import 'plex_providers.dart';

/// Season and episode browsing for a Plex show. Browse/manage only: episodes
/// carry a watched toggle; playback stays with the official Plex app. Seasons
/// are shown inline on the show's detail screen ([PlexSeasonCard]); tapping one
/// opens its [PlexEpisodeList].

/// Tonal card for one season: poster, title, and watched progress from
/// `viewedLeafCount / leafCount`. Tapping opens the episode list.
class PlexSeasonCard extends StatelessWidget {
  const PlexSeasonCard({
    required this.instance,
    required this.season,
    required this.imageUrl,
    super.key,
  });

  final Instance instance;
  final PlexMetadata season;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int leafCount = season.leafCount ?? 0;
    final int viewed = season.viewedLeafCount ?? 0;
    final double? progress =
        leafCount > 0 ? (viewed / leafCount).clamp(0, 1).toDouble() : null;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(24)),
      ),
      child: InkWell(
        onTap: () => pushScreen<void>(
          context,
          PlexEpisodeList(instance: instance, season: season),
        ),
        child: SizedBox(
          height: 96,
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 64,
                height: double.infinity,
                child: _poster(theme),
              ),
              const SizedBox(width: Insets.lg),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      season.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (leafCount > 0) ...<Widget>[
                      const SizedBox(height: Insets.xs),
                      Text(
                        '$viewed of $leafCount watched',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                      const SizedBox(height: Insets.sm),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicatorM3E(
                          shape: ProgressM3EShape.flat,
                          value: progress,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: Insets.md),
              Icon(Icons.chevron_right, color: theme.colorScheme.outline),
              const SizedBox(width: Insets.md),
            ],
          ),
        ),
      ),
    );
  }

  Widget _poster(ThemeData theme) {
    final Widget fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.tv_outlined, color: theme.colorScheme.outline),
    );
    if (imageUrl == null) {
      return fallback;
    }
    return AtriumNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      memCacheWidth: 128,
      placeholder: (BuildContext context, String url) =>
          Container(color: theme.colorScheme.surfaceContainerHighest),
      errorWidget: (BuildContext context, String url, Object error) => fallback,
    );
  }
}

/// Episodes of one season. Each row shows the SxEx label, watched state, and
/// a trailing toggle that scrobbles/unscrobbles the episode on the server.
/// Tapping a row opens the episode detail screen.
class PlexEpisodeList extends ConsumerWidget {
  const PlexEpisodeList({
    required this.instance,
    required this.season,
    super.key,
  });

  final Instance instance;
  final PlexMetadata season;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PlexMetadata>> episodes =
        ref.watch(plexChildrenProvider((instance, season.ratingKey)));
    final PlexApi? api = ref.watch(plexApiProvider(instance)).value;

    return Scaffold(
      appBar: AppBar(title: Text(season.title)),
      body: AsyncValueView<List<PlexMetadata>>(
          value: episodes,
          onRetry: () => ref
              .invalidate(plexChildrenProvider((instance, season.ratingKey))),
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
            ref.invalidate(plexChildrenProvider((instance, season.ratingKey))),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const <Widget>[
            SizedBox(height: 100),
            EmptyView(
                icon: Icons.tv_outlined,
                title: 'No episodes',
                message: 'This season has no episodes yet.',
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
            ref.invalidate(plexChildrenProvider((instance, season.ratingKey))),
      child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: Insets.sm),
              itemCount: list.length,
              itemBuilder: (BuildContext context, int index) {
                final PlexMetadata episode = list[index];
                return _EpisodeTile(
                  instance: instance,
                  episode: episode,
                  api: api,
                );
              },
            ),
    );
          
          },
        ),
    );
  }
}

class _EpisodeTile extends ConsumerWidget {
  const _EpisodeTile({
    required this.instance,
    required this.episode,
    required this.api,
  });

  final Instance instance;
  final PlexMetadata episode;
  final PlexApi? api;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final bool watched = episode.viewCount > 0;
    final String label = (episode.parentIndex != null && episode.index != null)
        ? 'S${episode.parentIndex}E${episode.index} - ${episode.title}'
        : episode.title;
    final int minutes =
        episode.duration != null ? episode.duration! ~/ 60000 : 0;

    return ListTile(
      title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: minutes > 0 ? Text('$minutes min') : null,
      trailing: IconButton(
        tooltip: watched ? 'Mark as unwatched' : 'Mark as watched',
        icon: Icon(
          watched ? Icons.check_circle : Icons.check_circle_outline,
          color: watched ? theme.colorScheme.primary : null,
        ),
        onPressed: api == null
            ? null
            : () async {
                final ScaffoldMessengerState messenger =
                    ScaffoldMessenger.of(context);
                try {
                  await api!.setWatched(episode.ratingKey, watched: !watched);
                } catch (_) {
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Could not update watched state'),
                    ),
                  );
                  return;
                }
                if (!context.mounted) {
                  return;
                }
                // Whole-family invalidation refreshes both this episode list
                // and the season progress behind it; on deck moves too.
                ref.invalidate(plexChildrenProvider);
                ref.invalidate(plexOnDeckProvider(instance));
                ref.invalidate(plexItemsProvider);
              },
      ),
      onTap: () => pushScreen<void>(
        context,
        PlexItemDetailScreen(instance: instance, ratingKey: episode.ratingKey),
      ),
    );
  }
}
