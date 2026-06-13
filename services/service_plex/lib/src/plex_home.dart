import 'package:cached_network_image/cached_network_image.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/plex_models.dart';
import 'plex_api.dart';
import 'plex_providers.dart';

/// Plex item types that play directly; the rest are containers we drill into.
const Set<String> _playableTypes = <String>{'movie', 'episode', 'clip'};

/// Plex's per-instance UI: library chips + poster grid. Tapping a movie or
/// episode resolves its file part and plays it; tapping a show or season
/// drills into its children.
class PlexHome extends ConsumerStatefulWidget {
  const PlexHome({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<PlexHome> createState() => _PlexHomeState();
}

class _PlexHomeState extends ConsumerState<PlexHome> {
  String? _selectedKey;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<PlexLibrary>> libraries =
        ref.watch(plexLibrariesProvider(widget.instance));

    return AsyncValueView<List<PlexLibrary>>(
      value: libraries,
      onRetry: () => ref.invalidate(plexLibrariesProvider(widget.instance)),
      data: (List<PlexLibrary> libs) {
        if (libs.isEmpty) {
          return const EmptyView(
            icon: Icons.play_circle_outline,
            title: 'No libraries',
            message: 'This Plex server has no libraries to show.',
          );
        }
        final String selected = _selectedKey ?? libs.first.key;
        return Column(
          children: <Widget>[
            _LibraryChips(
              libraries: libs,
              selectedKey: selected,
              onSelect: (String k) => setState(() => _selectedKey = k),
            ),
            Expanded(
              child: _ItemsGrid(
                instance: widget.instance,
                id: selected,
                isSection: true,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LibraryChips extends StatelessWidget {
  const _LibraryChips({
    required this.libraries,
    required this.selectedKey,
    required this.onSelect,
  });

  final List<PlexLibrary> libraries;
  final String selectedKey;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
        itemCount: libraries.length,
        separatorBuilder: (_, __) => const SizedBox(width: Insets.sm),
        itemBuilder: (BuildContext context, int index) {
          final PlexLibrary lib = libraries[index];
          return Center(
            child: ChoiceChip(
              label: Text(lib.title),
              selected: lib.key == selectedKey,
              onSelected: (_) => onSelect(lib.key),
            ),
          );
        },
      ),
    );
  }
}

/// Grid of items, sourced either from a library section ([isSection] true,
/// [id] = sectionKey) or from a parent's children ([isSection] false, [id] =
/// ratingKey).
class _ItemsGrid extends ConsumerWidget {
  const _ItemsGrid({
    required this.instance,
    required this.id,
    required this.isSection,
  });

  final Instance instance;
  final String id;
  final bool isSection;

  FutureProvider<List<PlexMetadata>> get _provider => isSection
      ? plexItemsProvider((instance, id))
      : plexChildrenProvider((instance, id));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<PlexMetadata>> items = ref.watch(_provider);
    final PlexApi? api = ref.watch(plexApiProvider(instance)).value;

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(_provider),
      child: AsyncValueView<List<PlexMetadata>>(
        value: items,
        onRetry: () => ref.invalidate(_provider),
        data: (List<PlexMetadata> list) {
          if (list.isEmpty) {
            return const EmptyView(
              icon: Icons.movie_outlined,
              title: 'Empty',
              message: 'Nothing here yet.',
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
              return _PosterCard(
                item: item,
                imageUrl: api?.imageUrl(item.thumb),
                onTap: api == null ? null : () => _openItem(context, api, item),
              );
            },
          );
        },
      ),
    );
  }

  void _openItem(
    BuildContext context,
    PlexApi api,
    PlexMetadata item,
  ) {
    if (!_playableTypes.contains(item.type)) {
      // pushScreen = root navigator; branch-navigator pushes get swept by
      // GoRouter shell rebuilds.
      pushScreen<void>(
        context,
        _FolderScreen(instance: instance, item: item),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Playback is handled by the official app.')),
    );
  }
}

class _FolderScreen extends StatelessWidget {
  const _FolderScreen({required this.instance, required this.item});

  final Instance instance;
  final PlexMetadata item;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(item.title)),
      body: _ItemsGrid(
        instance: instance,
        id: item.ratingKey,
        isSection: false,
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.item,
    required this.imageUrl,
    required this.onTap,
  });

  final PlexMetadata item;
  final String? imageUrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool watched = item.viewCount > 0;
    final double progress = (item.viewOffset != null &&
            item.duration != null &&
            item.duration! > 0)
        ? item.viewOffset! / item.duration!
        : 0;

    return InkWell(
      onTap: onTap,
      borderRadius: Radii.card,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: ClipRRect(
              borderRadius: Radii.card,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _poster(theme),
                  if (watched)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check,
                          size: 14,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  if (!watched && progress > 0.02)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: LinearProgressIndicator(
                        value: progress.clamp(0, 1),
                        minHeight: 3,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: Insets.xs),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium,
          ),
          if (item.year != null)
            Text(
              '${item.year}',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
        ],
      ),
    );
  }

  Widget _poster(ThemeData theme) {
    final Widget fallback = Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(Icons.movie_outlined, color: theme.colorScheme.outline),
    );
    if (imageUrl == null) {
      return fallback;
    }
    return CachedNetworkImage(
      imageUrl: imageUrl!,
      fit: BoxFit.cover,
      memCacheWidth: 200,
      placeholder: (BuildContext context, String url) =>
          Container(color: theme.colorScheme.surfaceContainerHighest),
      errorWidget: (BuildContext context, String url, Object error) => fallback,
    );
  }
}
