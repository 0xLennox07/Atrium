import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'bazarr_providers.dart';
import 'models/bazarr_models.dart';

/// Bazarr's per-instance UI: a badges header (wanted episodes / movies,
/// provider count) above a unified list of items still missing subtitles.
class BazarrHome extends ConsumerWidget {
  const BazarrHome({required this.instance, super.key});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<BazarrWantedRow>> wanted =
        ref.watch(bazarrWantedProvider(instance));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(bazarrBadgesProvider(instance));
        ref.invalidate(bazarrWantedProvider(instance));
      },
      child: Column(
        children: <Widget>[
          _BadgesHeader(instance: instance),
          Expanded(
            child: AsyncValueView<List<BazarrWantedRow>>(
              value: wanted,
              onRetry: () => ref.invalidate(bazarrWantedProvider(instance)),
              data: (List<BazarrWantedRow> rows) {
                if (rows.isEmpty) {
                  return const EmptyView(
                    icon: Icons.subtitles_outlined,
                    title: 'All subtitled',
                    message: 'Nothing is waiting on subtitles.',
                  );
                }
                return ListView.builder(
                  padding: Insets.pageH,
                  itemCount: rows.length,
                  itemBuilder: (BuildContext context, int index) =>
                      _WantedTile(row: rows[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BadgesHeader extends ConsumerWidget {
  const _BadgesHeader({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BazarrBadges? b = ref.watch(bazarrBadgesProvider(instance)).value;
    if (b == null) {
      return const SizedBox(height: Insets.sm);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.lg,
        vertical: Insets.sm,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          _Badge(label: 'Episodes', value: b.episodes),
          _Badge(label: 'Movies', value: b.movies),
          _Badge(label: 'Providers', value: b.providers),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Text('$value', style: theme.textTheme.titleMedium),
        Text(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }
}

class _WantedTile extends StatelessWidget {
  const _WantedTile({required this.row});

  final BazarrWantedRow row;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      child: ListTile(
        leading: Icon(
          row.isMovie ? Icons.movie_outlined : Icons.live_tv_outlined,
        ),
        title: Text(row.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(row.subtitle),
        trailing: Wrap(
          spacing: Insets.xs,
          children: <Widget>[
            for (final BazarrSubtitle s in row.missing.take(3))
              Chip(
                label: Text(
                  s.code2.isNotEmpty ? s.code2.toUpperCase() : s.name,
                ),
                labelStyle: Theme.of(context).textTheme.labelSmall,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
          ],
        ),
      ),
    );
  }
}
