import 'package:cached_network_image/cached_network_image.dart';
import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/radarr_movie.dart';
import 'radarr_api.dart';
import 'radarr_providers.dart';

/// Detail view for one Radarr movie: poster header, status/file info,
/// ratings, and actions (monitor toggle, search, delete).
class MovieDetailScreen extends ConsumerWidget {
  const MovieDetailScreen({
    required this.instance,
    required this.movieId,
    super.key,
  });

  final Instance instance;
  final int movieId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<RadarrMovie> movie =
        ref.watch(radarrMovieByIdProvider((instance, movieId)));

    return Scaffold(
      appBar: AppBar(
        title: Text(movie.value?.title ?? 'Movie'),
        actions: <Widget>[
          if (movie.hasValue)
            _MovieMenu(instance: instance, movie: movie.requireValue),
        ],
      ),
      body: AsyncValueView<RadarrMovie>(
        value: movie,
        onRetry: () =>
            ref.invalidate(radarrMovieByIdProvider((instance, movieId))),
        data: (RadarrMovie m) => _Body(instance: instance, movie: m),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.instance, required this.movie});

  final Instance instance;
  final RadarrMovie movie;

  void _refresh(WidgetRef ref) {
    ref.invalidate(radarrMovieByIdProvider((instance, movie.id)));
    ref.invalidate(radarrMoviesProvider(instance));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final RadarrApi? api = ref.watch(radarrApiProvider(instance)).value;
    final RadarrImage? poster = movie.images
        .firstWhereOrNull((RadarrImage i) => i.coverType == 'poster');
    final String? imageUrl = poster == null ? null : api?.posterUrl(poster);

    return RefreshIndicator(
      onRefresh: () async => _refresh(ref),
      child: ListView(
        padding: Insets.page,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: Radii.card,
                child: SizedBox(
                  width: 110,
                  height: 165,
                  child: imageUrl == null
                      ? Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(
                            Icons.movie_outlined,
                            color: theme.colorScheme.outline,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.movie_outlined,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(movie.title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: Insets.xs),
                    Text(
                      <String>[
                        if (movie.year != null) '${movie.year}',
                        if (movie.runtime != null && movie.runtime! > 0)
                          '${movie.runtime} min',
                        if (movie.studio != null && movie.studio!.isNotEmpty)
                          movie.studio!,
                      ].join(' • '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: Insets.sm),
                    _StatusChip(movie: movie),
                    if (movie.ratings?.tmdb != null &&
                        movie.ratings!.tmdb!.value > 0) ...<Widget>[
                      const SizedBox(height: Insets.sm),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.star,
                            size: 16,
                            color: theme.colorScheme.tertiary,
                          ),
                          const SizedBox(width: Insets.xs),
                          Text(
                            movie.ratings!.tmdb!.value.toStringAsFixed(1),
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.tonalIcon(
                  icon: Icon(
                    movie.monitored ? Icons.bookmark : Icons.bookmark_border,
                  ),
                  label:
                      Text(movie.monitored ? 'Monitored' : 'Unmonitored'),
                  onPressed: () async {
                    final RadarrApi api =
                        await ref.read(radarrApiProvider(instance).future);
                    final Map<String, dynamic> raw =
                        await api.getMovieRaw(movie.id);
                    raw['monitored'] = !movie.monitored;
                    await api.updateMovieRaw(raw);
                    _refresh(ref);
                  },
                ),
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.search),
                  label: const Text('Search'),
                  onPressed: () async {
                    final RadarrApi api =
                        await ref.read(radarrApiProvider(instance).future);
                    await api.searchMovie(movie.id);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Search started'),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
          if (movie.overview != null && movie.overview!.isNotEmpty) ...<
              Widget>[
            const SizedBox(height: Insets.md),
            Text(movie.overview!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: Insets.xl),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.movie});

  final RadarrMovie movie;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (String label, Color bg, Color fg) = movie.hasFile
        ? (
            'Downloaded${movie.sizeOnDisk > 0 ? ' • ${_fmtSize(movie.sizeOnDisk)}' : ''}',
            theme.colorScheme.primaryContainer,
            theme.colorScheme.onPrimaryContainer,
          )
        : (
            'Missing',
            theme.colorScheme.errorContainer,
            theme.colorScheme.onErrorContainer,
          );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.sm,
        vertical: Insets.xs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(color: fg),
      ),
    );
  }
}

class _MovieMenu extends ConsumerWidget {
  const _MovieMenu({required this.instance, required this.movie});

  final Instance instance;
  final RadarrMovie movie;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      onSelected: (String v) async {
        if (v == 'delete') {
          await _confirmDelete(context, ref);
        }
      },
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          value: 'delete',
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Delete movie'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    bool deleteFiles = false;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => AlertDialog(
          title: const Text('Delete movie?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(movie.title),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Also delete file on disk'),
                value: deleteFiles,
                onChanged: (bool? v) =>
                    setState(() => deleteFiles = v ?? false),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
    );
    if (ok ?? false) {
      final RadarrApi api = await ref.read(radarrApiProvider(instance).future);
      await api.deleteMovie(movie.id, deleteFiles: deleteFiles);
      ref.invalidate(radarrMoviesProvider(instance));
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    }
  }
}

String _fmtSize(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final String text =
      value >= 100 || unit == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}
