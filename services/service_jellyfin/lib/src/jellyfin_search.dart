import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'jellyfin_client.dart';
import 'jellyfin_home.dart';
import 'jellyfin_item_detail.dart';
import 'jellyfin_providers.dart';
import 'models/jellyfin_item.dart';

class JellyfinSearchDelegate extends SearchDelegate<void> {
  JellyfinSearchDelegate({required this.instance});

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
    final JellyfinClient? client =
        ref.watch(jellyfinClientProvider(instance)).valueOrNull;

    if (client == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (query.trim().isEmpty) {
      return const Center(child: Text('Search for movies or shows.'));
    }

    return FutureBuilder<List<JellyfinItem>>(
      future: client.searchItems(query.trim()),
      builder: (BuildContext context, AsyncSnapshot<List<JellyfinItem>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final List<JellyfinItem> list = snapshot.data ?? <JellyfinItem>[];
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
            final JellyfinItem item = list[index];
            return JellyfinPosterCard(
              instance: instance,
              item: item,
              imageUrl: client.imageUrl(item),
              onTap: () {
                if (jellyfinContainerTypes.contains(item.type)) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => JellyfinFolderScreen(
                        instance: instance,
                        item: item,
                      ),
                    ),
                  );
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => JellyfinItemDetailScreen(
                        instance: instance,
                        itemId: item.id,
                      ),
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }
}



