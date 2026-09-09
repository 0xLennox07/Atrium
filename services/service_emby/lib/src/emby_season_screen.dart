import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'emby_client.dart';
import 'emby_deep_link.dart';
import 'emby_item_detail.dart';
import 'emby_providers.dart';
import 'models/emby_item.dart';

class EmbySeasonScreen extends ConsumerWidget {
  const EmbySeasonScreen({
    required this.instance,
    required this.seasonId,
    required this.seasonName,
    this.seasonImageUrl,
    super.key,
  });

  final Instance instance;
  final String seasonId;
  final String seasonName;
  final String? seasonImageUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<EmbyItem>> episodesAsync =
        ref.watch(embyEpisodesProvider((instance, seasonId)));
    final EmbyClient? client = ref.watch(embyClientProvider(instance)).value;

    return Scaffold(
      appBar: AppBar(
        title: Text(seasonName),
      ),
      body: AsyncValueView<List<EmbyItem>>(
        value: episodesAsync,
        onRetry: () =>
            ref.invalidate(embyEpisodesProvider((instance, seasonId))),
        data: (List<EmbyItem> episodes) {
          if (episodes.isEmpty) {
            return const EmptyView(
              icon: Icons.tv,
              title: 'No Episodes',
              message: 'This season has no episodes.',
            );
          }
          return ListView.separated(
            padding: Insets.page,
            itemCount: episodes.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (BuildContext context, int index) {
              final EmbyItem episode = episodes[index];

              final int sIndex = episode.parentIndexNumber ?? 1;
              final int eIndex = episode.indexNumber ?? (index + 1);

              return InkWell(
                onTap: () {
                  pushScreen<void>(
                    context,
                    EmbyItemDetailScreen(
                      instance: instance,
                      itemId: episode.id,
                    ),
                  );
                },
                borderRadius: Radii.card,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Insets.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (seasonImageUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AtriumNetworkImage(
                            imageUrl: seasonImageUrl!,
                            width: 120,
                            height: 180,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _FallbackImage(),
                          ),
                        )
                      else
                        _FallbackImage(),
                      const SizedBox(width: Insets.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              episode.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'S$sIndex:E$eIndex',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            if (episode.overview != null &&
                                episode.overview!.isNotEmpty) ...<Widget>[
                              const SizedBox(height: Insets.sm),
                              Text(
                                episode.overview!,
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 5,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (client != null)
                        IconButton(
                          icon: const Icon(Icons.play_arrow),
                          onPressed: () {
                            launchEmbyDeepLink(context, client, episode.id);
                          },
                          color: Theme.of(context).colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _FallbackImage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 180,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.tv),
    );
  }
}
