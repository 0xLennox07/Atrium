import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/seerr_discover.dart';
import 'seerr_api.dart';
import 'seerr_item_detail.dart';
import 'seerr_providers.dart';
import 'seerr_status_badge.dart';

class SeerrSearchDelegate extends SearchDelegate<void> {
  SeerrSearchDelegate({required this.instance});

  final Instance instance;

  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context);
  }

  @override
  List<Widget>? buildActions(BuildContext context) {
    if (query.isEmpty) {
      return const <Widget>[];
    }
    return <Widget>[
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () => query = '',
      ),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _SearchResults(instance: instance, query: query);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      return const Center(child: Text('Search for movies or shows.'));
    }
    return _SearchResults(instance: instance, query: query);
  }
}

class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.instance, required this.query});

  final Instance instance;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (query.trim().isEmpty) {
      return const Center(child: Text('Search for movies or shows.'));
    }

    final AsyncValue<List<SeerrDiscoverResult>> results = ref.watch(
      seerrSearchProvider((instance: instance, query: query.trim())),
    );

    return AsyncValueView<List<SeerrDiscoverResult>>(
      value: results,
      onRetry: () => ref.invalidate(
        seerrSearchProvider((instance: instance, query: query.trim())),
      ),
      data: (List<SeerrDiscoverResult> list) {
        if (list.isEmpty) {
          return const EmptyView(
            icon: Icons.search_off,
            title: 'No results',
            message: 'No items found matching your search.',
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
            return _SeerrSearchPosterCard(instance: instance, item: item);
          },
        );
      },
    );
  }
}

class _SeerrSearchPosterCard extends ConsumerWidget {
  const _SeerrSearchPosterCard({required this.instance, required this.item});

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
