import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/plex_models.dart';
import 'plex_api.dart';
import 'plex_home.dart';
import 'plex_providers.dart';

/// Global Plex search, surfaced through the service detail app bar.
class PlexSearchDelegate extends SearchDelegate<void> {
  PlexSearchDelegate({required this.instance});

  final Instance instance;

  @override
  ThemeData appBarTheme(BuildContext context) => Theme.of(context);

  @override
  List<Widget>? buildActions(BuildContext context) {
    if (query.isEmpty) {
      return const <Widget>[];
    }
    return <Widget>[
      IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget? buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) =>
      _SearchResults(instance: instance, query: query);

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
    final PlexApi? api = ref.watch(plexApiProvider(instance)).value;
    if (api == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (query.trim().isEmpty) {
      return const Center(child: Text('Search for movies or shows.'));
    }

    return FutureBuilder<List<PlexMetadata>>(
      future: api.search(query.trim()),
      builder: (
        BuildContext context,
        AsyncSnapshot<List<PlexMetadata>> snapshot,
      ) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorView(
            title: 'Search failed',
            message: '${snapshot.error}',
          );
        }
        final List<PlexMetadata> list = snapshot.data ?? <PlexMetadata>[];
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
            final PlexMetadata item = list[index];
            return PlexPosterCard(
              instance: instance,
              item: item,
              imageUrl: api.imageUrl(item.thumb),
              onTap: () => openPlexItem(context, instance, item),
            );
          },
        );
      },
    );
  }
}
