import 'package:cached_network_image/cached_network_image.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'jellyfin_client.dart';
import 'jellyfin_providers.dart';
import 'models/jellyfin_item.dart';

class JellyfinItemDetailScreen extends ConsumerWidget {
  const JellyfinItemDetailScreen({
    required this.instance,
    required this.itemId,
    super.key,
  });

  final Instance instance;
  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<JellyfinItem> itemAsync =
        ref.watch(jellyfinItemDetailsProvider((instance, itemId)));
    final JellyfinClient? client =
        ref.watch(jellyfinClientProvider(instance)).value;

    return Scaffold(
      appBar: AppBar(
        actions: <Widget>[
          if (itemAsync.hasValue && client != null)
            IconButton(
              icon: Icon(
                itemAsync.value!.userData?.isFavorite == true
                    ? Icons.favorite
                    : Icons.favorite_border,
                color: itemAsync.value!.userData?.isFavorite == true
                    ? Colors.red
                    : null,
              ),
              onPressed: () async {
                final bool isFav =
                    itemAsync.value!.userData?.isFavorite == true;
                await client.markFavorite(itemId, !isFav);
                ref.invalidate(jellyfinItemDetailsProvider((instance, itemId)));
                ref.invalidate(jellyfinFavoritesProvider(instance));
              },
            ),
        ],
      ),
      body: AsyncValueView<JellyfinItem>(
        value: itemAsync,
        onRetry: () =>
            ref.invalidate(jellyfinItemDetailsProvider((instance, itemId))),
        data: (JellyfinItem item) {
          return CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: _Header(item: item, client: client),
              ),
              if (item.overview != null && item.overview!.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(Insets.lg),
                    child: Text(
                      item.overview!,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),
                ),
              if (item.people.isNotEmpty)
                SliverToBoxAdapter(
                  child: _PeopleRow(item: item, client: client),
                ),
              const SliverToBoxAdapter(
                child: SizedBox(height: Insets.xl),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.item, required this.client});

  final JellyfinItem item;
  final JellyfinClient? client;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? posterUrl = client?.imageUrl(item, maxHeight: 600);

    // Runtime is in ticks (1 tick = 100ns = 0.0001 ms = 0.0000001 s).
    final int minutes = item.runTimeTicks != null
        ? (item.runTimeTicks! ~/ 10000000) ~/ 60
        : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (posterUrl != null)
            ClipRRect(
              borderRadius: Radii.card,
              child: CachedNetworkImage(
                imageUrl: posterUrl,
                width: 140,
                height: 210,
                fit: BoxFit.cover,
                memCacheWidth: 200,
                memCacheHeight: 300,
              ),
            )
          else
            Container(
              width: 140,
              height: 210,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: Radii.card,
              ),
              child: const Icon(Icons.movie, size: 48),
            ),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.name,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: Insets.xs),
                Wrap(
                  spacing: Insets.sm,
                  children: <Widget>[
                    if (item.productionYear != null)
                      Text('${item.productionYear}',
                          style: theme.textTheme.bodyMedium,),
                    if (minutes > 0)
                      Text('$minutes min', style: theme.textTheme.bodyMedium),
                    if (item.officialRating != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2,),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outline),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.officialRating!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PeopleRow extends StatelessWidget {
  const _PeopleRow({required this.item, required this.client});

  final JellyfinItem item;
  final JellyfinClient? client;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
          child: Text(
            'Cast & Crew',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: Insets.sm),
        SizedBox(
          height: 180,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
            itemCount: item.people.length,
            separatorBuilder: (_, __) => const SizedBox(width: Insets.md),
            itemBuilder: (BuildContext context, int index) {
              final JellyfinPerson person = item.people[index];
              final String b = client?.baseUrl.toString().replaceAll(RegExp(r'/+$'), '') ?? '';
              final String? personImageUrl = person.primaryImageTag != null
                  ? '$b/Items/${person.id}/Images/Primary?tag=${person.primaryImageTag}&quality=90&maxWidth=200'
                  : null;

              return SizedBox(
                width: 100,
                child: Column(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 50,
                      backgroundImage: personImageUrl != null
                          ? CachedNetworkImageProvider(personImageUrl)
                          : null,
                      child: personImageUrl == null
                          ? const Icon(Icons.person, size: 40)
                          : null,
                    ),
                    const SizedBox(height: Insets.xs),
                    Text(
                      person.name,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    if (person.role != null)
                      Text(
                        person.role!,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}



