import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'emby_client.dart';
import 'emby_home.dart';
import 'emby_item_detail.dart';
import 'emby_providers.dart';
import 'models/emby_item.dart';

class EmbySearchDelegate extends SearchDelegate<void> {
  EmbySearchDelegate({required this.instance});

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
    final EmbyClient? client =
        ref.watch(embyClientProvider(instance)).valueOrNull;

    if (client == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (query.trim().isEmpty) {
      return const Center(child: Text('Search for movies or shows.'));
    }

    return FutureBuilder<List<EmbyItem>>(
      future: client.searchItems(query.trim()),
      builder: (BuildContext context, AsyncSnapshot<List<EmbyItem>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final List<EmbyItem> list = snapshot.data ?? <EmbyItem>[];
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
            final EmbyItem item = list[index];
            return EmbyPosterCard(
              instance: instance,
              item: item,
              imageUrl: client.imageUrl(item),
              onTap: () {
                if (embyContainerTypes.contains(item.type)) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EmbyFolderScreen(
                        instance: instance,
                        item: item,
                      ),
                    ),
                  );
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EmbyItemDetailScreen(
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
