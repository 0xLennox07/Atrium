import 'dart:async';

import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'jellyfin_client.dart';
import 'jellyfin_deep_link.dart';
import 'jellyfin_identify_screen.dart';
import 'jellyfin_providers.dart';
import 'jellyfin_remote_images_screen.dart';
import 'jellyfin_season_screen.dart';
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: <Widget>[
          if (itemAsync.hasValue && client != null) ...<Widget>[
            IconButton(
              icon: Icon(
                itemAsync.value!.userData?.played == true
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
              ),
              onPressed: () async {
                final toggle =
                    ref.read(jellyfinToggleWatchedProvider(instance));
                await toggle(
                  itemId,
                  !(itemAsync.value!.userData?.played == true),
                );
              },
            ),
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
            if (itemAsync.value!.type != 'Episode')
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (String choice) async {
                  if (choice == 'identify') {
                    final bool? changed = await pushScreen<bool>(
                      context,
                      JellyfinIdentifyScreen(
                        instance: instance,
                        item: itemAsync.value!,
                      ),
                    );
                    if (changed == true && context.mounted) {
                      ref.invalidate(
                        jellyfinItemDetailsProvider((instance, itemId)),
                      );
                    }
                  } else if (choice == 'refresh') {
                    try {
                      await ref
                          .read(jellyfinClientProvider(instance))
                          .value
                          ?.refreshMetadata(itemId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Refresh queued')),
                        );
                        ref.invalidate(
                          jellyfinItemDetailsProvider((instance, itemId)),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Failed to refresh: $e')),
                        );
                      }
                    }
                  } else if (choice == 'backdrop') {
                    unawaited(
                      pushScreen<void>(
                        context,
                        JellyfinRemoteImagesScreen(
                          instance: instance,
                          itemId: itemId,
                          imageType: 'Backdrop',
                        ),
                      ),
                    );
                  }
                },
                itemBuilder: (BuildContext context) {
                  return const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'identify',
                      child: Text('Identify'),
                    ),
                    PopupMenuItem<String>(
                      value: 'refresh',
                      child: Text('Refresh Metadata'),
                    ),
                    PopupMenuItem<String>(
                      value: 'backdrop',
                      child: Text('Change Backdrop'),
                    ),
                  ];
                },
              ),
          ],
        ],
      ),
      body: AsyncValueView<JellyfinItem>(
        value: itemAsync,
        onRetry: () =>
            ref.invalidate(jellyfinItemDetailsProvider((instance, itemId))),
        data: (JellyfinItem item) {
          final String? backdropUrl = client?.backdropImageUrl(item);

          return CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: backdropUrl != null
                    ? SizedBox(
                        height: MediaQuery.of(context).size.height * 0.5,
                        child: Stack(
                          children: <Widget>[
                            Positioned.fill(
                              child: AtriumNetworkImage(
                                key: ValueKey<String>(backdropUrl),
                                imageUrl: backdropUrl,
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
                              child: _Header(
                                instance: instance,
                                item: item,
                                client: client,
                              ),
                            ),
                          ],
                        ),
                      )
                    : SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.only(top: Insets.lg),
                          child: _Header(
                            instance: instance,
                            item: item,
                            client: client,
                          ),
                        ),
                      ),
              ),
              if (item.genres.isNotEmpty)
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
                      children: item.genres.map((String g) {
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondaryContainer,
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
              if (item.overview != null && item.overview!.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(Insets.lg),
                    child: OverviewBox(overview: item.overview!),
                  ),
                ),
              if (_InfoSection.canShow(item))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: Insets.lg,
                      right: Insets.lg,
                      bottom: Insets.lg,
                      top: (item.overview != null && item.overview!.isNotEmpty)
                          ? 0
                          : Insets.lg,
                    ),
                    child: _InfoSection(item: item),
                  ),
                ),
              if (item.people.isNotEmpty)
                SliverToBoxAdapter(
                  child: _PeopleRow(item: item, client: client),
                ),
              if (item.type == 'Series') ...<Widget>[
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: Insets.lg),
                    child: Divider(),
                  ),
                ),
                _SeasonsGrid(instance: instance, seriesId: item.id),
              ],
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
  const _Header({
    required this.instance,
    required this.item,
    required this.client,
  });

  final Instance instance;
  final JellyfinItem item;
  final JellyfinClient? client;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? posterUrl = client?.imageUrl(item, maxHeight: 600);

    // Runtime is in ticks (1 tick = 100ns = 0.0001 ms = 0.0000001 s).
    final int minutes =
        item.runTimeTicks != null ? (item.runTimeTicks! ~/ 10000000) ~/ 60 : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          InkWell(
            onTap: item.type == 'Episode'
                ? null
                : () {
                    pushScreen<void>(
                      context,
                      JellyfinRemoteImagesScreen(
                        instance: instance,
                        itemId: item.id,
                      ),
                    );
                  },
            borderRadius: Radii.card,
            child: Stack(
              children: <Widget>[
                if (posterUrl != null)
                  ClipRRect(
                    borderRadius: Radii.card,
                    child: AtriumNetworkImage(
                      key: ValueKey<String>(posterUrl),
                      imageUrl: posterUrl,
                      width: 140,
                      height: 210,
                      fit: BoxFit.cover,
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
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (item.seriesName != null)
                  Tooltip(
                    message: item.seriesName!,
                    triggerMode: TooltipTriggerMode.tap,
                    child: Text(
                      item.seriesName!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (item.seriesName != null) const SizedBox(height: 4),
                Tooltip(
                  message: (item.seriesName != null && item.indexNumber != null)
                      ? 'Episode ${item.indexNumber} - ${item.name}'
                      : item.name,
                  triggerMode: TooltipTriggerMode.tap,
                  child: Text(
                    (item.seriesName != null && item.indexNumber != null)
                        ? 'Episode ${item.indexNumber} - ${item.name}'
                        : item.name,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(height: Insets.xs),
                Wrap(
                  spacing: Insets.sm,
                  children: <Widget>[
                    if (item.productionYear != null)
                      Text(
                        '${item.productionYear}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (minutes > 0)
                      Text('$minutes min', style: theme.textTheme.bodyMedium),
                    if (item.officialRating != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: theme.colorScheme.outline),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.officialRating!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    if (item.communityRating != null)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            item.communityRating!.toStringAsFixed(1),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: Insets.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      if (client != null) {
                        launchJellyfinDeepLink(context, client!, item.id);
                      }
                    },
                    icon: SvgPicture.asset(
                      'assets/glyphs/jellyfin-vector.svg',
                      width: 24,
                      height: 24,
                      colorFilter: ColorFilter.mode(
                        theme.colorScheme.onPrimary,
                        BlendMode.srcIn,
                      ),
                    ),
                    label: const Text('Play'),
                  ),
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
              final String b =
                  client?.baseUrl.toString().replaceAll(RegExp(r'/+$'), '') ??
                      '';
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
                          ? atriumImageProvider(personImageUrl)
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

class _SeasonsGrid extends ConsumerWidget {
  const _SeasonsGrid({required this.instance, required this.seriesId});

  final Instance instance;
  final String seriesId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<JellyfinItem>> seasonsAsync =
        ref.watch(jellyfinSeasonsProvider((instance, seriesId)));
    final JellyfinClient? client =
        ref.watch(jellyfinClientProvider(instance)).value;
    final ThemeData theme = Theme.of(context);

    return SliverToBoxAdapter(
      child: AsyncValueView<List<JellyfinItem>>(
        value: seasonsAsync,
        onRetry: () =>
            ref.invalidate(jellyfinSeasonsProvider((instance, seriesId))),
        data: (List<JellyfinItem> seasons) {
          if (seasons.isEmpty) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg,
              vertical: Insets.lg,
            ),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.65,
                crossAxisSpacing: Insets.md,
                mainAxisSpacing: Insets.md,
              ),
              itemCount: seasons.length,
              itemBuilder: (BuildContext context, int index) {
                final JellyfinItem season = seasons[index];
                final String? posterUrl =
                    client?.imageUrl(season, maxHeight: 300);

                return InkWell(
                  borderRadius: Radii.card,
                  onTap: () {
                    pushScreen<void>(
                      context,
                      JellyfinSeasonScreen(
                        instance: instance,
                        seriesId: seriesId,
                        seasonId: season.id,
                        seasonName: season.name,
                        seasonImageUrl: posterUrl,
                      ),
                    );
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: ClipRRect(
                          borderRadius: Radii.card,
                          child: posterUrl != null
                              ? AtriumNetworkImage(
                                  imageUrl: posterUrl,
                                  fit: BoxFit.cover,
                                )
                              : Container(
                                  color:
                                      theme.colorScheme.surfaceContainerHighest,
                                  child: const Icon(Icons.tv),
                                ),
                        ),
                      ),
                      const SizedBox(height: Insets.xs),
                      Text(
                        season.name,
                        style: theme.textTheme.labelMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Series / episode facts for an item, shown as a tonal card on the detail
/// screen when the item carries a series name or a season+episode number.
class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.item});

  final JellyfinItem item;

  static bool canShow(JellyfinItem item) {
    return (item.seriesName != null && item.seriesName!.isNotEmpty) ||
        (item.parentIndexNumber != null && item.indexNumber != null);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Insets.lg),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (item.seriesName != null && item.seriesName!.isNotEmpty)
            _InfoRow(
              icon: Icons.tv,
              label: 'Series',
              value: item.seriesName!,
            ),
          if (item.parentIndexNumber != null &&
              item.indexNumber != null) ...<Widget>[
            if (item.seriesName != null && item.seriesName!.isNotEmpty)
              const SizedBox(height: Insets.sm),
            _InfoRow(
              icon: Icons.tag,
              label: 'Episode',
              value:
                  'Season ${item.parentIndexNumber} Episode ${item.indexNumber}',
            ),
          ],
        ],
      ),
    );
  }
}

/// One labelled fact row (icon, label, value) inside [_InfoSection].
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: Insets.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
