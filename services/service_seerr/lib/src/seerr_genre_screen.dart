import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/seerr_discover.dart';
import 'seerr_api.dart';
import 'seerr_item_detail.dart';
import 'seerr_providers.dart';
import 'seerr_status_badge.dart';

class SeerrGenreScreen extends ConsumerWidget {
  const SeerrGenreScreen({
    required this.instance,
    required this.genre,
    required this.isMovie,
    super.key,
  });

  final Instance instance;
  final SeerrGenre genre;
  final bool isMovie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<SeerrDiscoverResult>> items = ref.watch(
      seerrItemsByGenreProvider(
        (instance: instance, genreId: genre.id, isMovie: isMovie),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('${genre.name} ${isMovie ? 'Movies' : 'TV Shows'}'),
      ),
      body: AsyncValueView<List<SeerrDiscoverResult>>(
        value: items,
        onRetry: () => ref.invalidate(
          seerrItemsByGenreProvider(
            (instance: instance, genreId: genre.id, isMovie: isMovie),
          ),
        ),
        data: (List<SeerrDiscoverResult> list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.movie_filter_outlined,
              title: 'No results',
              message: 'No items found for this genre.',
            );
          }

          return GridView.builder(
            padding: Insets.page,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 140,
              childAspectRatio: 0.52,
              crossAxisSpacing: Insets.md,
              mainAxisSpacing: Insets.md,
            ),
            itemCount: list.length,
            itemBuilder: (BuildContext context, int index) {
              final SeerrDiscoverResult item = list[index];
              return _SeerrGenrePosterCard(instance: instance, item: item);
            },
          );
        },
      ),
    );
  }
}

class _SeerrGenrePosterCard extends ConsumerWidget {
  const _SeerrGenrePosterCard({required this.instance, required this.item});

  final Instance instance;
  final SeerrDiscoverResult item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SeerrApi? api = ref.watch(seerrApiProvider(instance)).value;
    final String? posterUrl = api?.imageUrl(item.posterPath, size: 'w500');
    return GestureDetector(
      onTap: () {
        pushScreen<void>(
          context,
          SeerrItemDetailScreen(instance: instance, item: item),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  child: posterUrl != null
                      ? Image.network(
                          posterUrl,
                          headers: ArtworkHeaders.forUrl(posterUrl),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const _Placeholder(),
                        )
                      : const _Placeholder(),
                ),
                Positioned(
                  top: 6,
                  right: 6,
                  child: SeerrStatusBadge(status: item.mediaInfo?.status),
                ),
              ],
            ),
          ),
          const SizedBox(height: Insets.xs),
          Text(
            item.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (item.displayDate != null)
            Text(
              item.displayDate!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.movie_outlined)),
    );
  }
}
