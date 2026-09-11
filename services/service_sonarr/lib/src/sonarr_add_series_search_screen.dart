import 'dart:async';

import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/sonarr_series.dart';
import 'series_detail_screen.dart';
import 'sonarr_add_series_sheet.dart';
import 'sonarr_api.dart';
import 'sonarr_providers.dart';

class SonarrAddSeriesSearchScreen extends ConsumerStatefulWidget {
  const SonarrAddSeriesSearchScreen({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<SonarrAddSeriesSearchScreen> createState() =>
      _SonarrAddSeriesSearchScreenState();
}

class _SonarrAddSeriesSearchScreenState
    extends ConsumerState<SonarrAddSeriesSearchScreen>
    with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _debouncedQuery = '';
  Timer? _debounceTimer;
  final ScrollController _scrollController = ScrollController();
  double _lastBottomInset = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchFocusNode.requestFocus();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
    _searchFocusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final double bottomInset = WidgetsBinding
        .instance.platformDispatcher.views.first.viewInsets.bottom;
    if (bottomInset == 0 && _lastBottomInset > 0) {
      if (_searchFocusNode.hasFocus) {
        _searchFocusNode.unfocus();
      }
    }
    _lastBottomInset = bottomInset;
  }

  void _onFocusChange() {
    setState(() {});
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.userScrollDirection !=
            ScrollDirection.idle) {
      if (_searchFocusNode.hasFocus) {
        _searchFocusNode.unfocus();
      }
    }
  }

  void _onSearchChanged() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _debouncedQuery = _searchController.text.trim();
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;

    final AsyncValue<List<SonarrSeries>> lookupResults = ref.watch(
      sonarrLookupSeriesProvider((widget.instance, _debouncedQuery)),
    );

    // Watch local series to check if already added
    final List<SonarrSeries> localSeries =
        ref.watch(sonarrSeriesProvider(widget.instance)).value ?? [];

    return PopScope<Object?>(
      canPop: !_searchFocusNode.hasFocus,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_searchFocusNode.hasFocus) {
          _searchFocusNode.unfocus();
        }
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        appBar: AppBar(
          scrolledUnderElevation: 0.0,
          backgroundColor: cs.surface,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Padding(
            padding: const EdgeInsets.only(right: Insets.md),
            child: SearchBar(
              focusNode: _searchFocusNode,
              controller: _searchController,
              hintText: 'Search online catalog...',
              onTapOutside: (event) {
                if (_searchFocusNode.hasFocus) {
                  _searchFocusNode.unfocus();
                }
              },
              elevation: const WidgetStatePropertyAll<double>(0),
              backgroundColor: WidgetStatePropertyAll<Color>(
                cs.surfaceContainerHigh,
              ),
              shape: WidgetStatePropertyAll<OutlinedBorder>(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _debouncedQuery = '';
                      });
                    },
                  ),
              ],
            ),
          ),
        ),
        body: _debouncedQuery.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.search,
                      size: 64,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: Insets.md),
                    Text(
                      'Search for a TV show to add',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            : AsyncValueView<List<SonarrSeries>>(
                value: lookupResults,
                onRetry: () {
                  ref.invalidate(
                    sonarrLookupSeriesProvider(
                      (widget.instance, _debouncedQuery),
                    ),
                  );
                },
                data: (List<SonarrSeries> results) {
                  if (results.isEmpty) {
                    return const EmptyView(
                      icon: Icons.search_off_outlined,
                      title: 'No series found',
                      message:
                          'We couldn\'t find any series matching your query.',
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(Insets.md),
                    itemCount: results.length,
                    itemBuilder: (BuildContext context, int index) {
                      final SonarrSeries s = results[index];
                      // Check if already in the local library by tvdbId
                      final SonarrSeries? localMatch =
                          localSeries.firstWhereOrNull(
                        (local) => local.tvdbId == s.tvdbId,
                      );
                      final bool isAdded = localMatch != null;

                      return Card(
                        margin: const EdgeInsets.only(bottom: Insets.md),
                        clipBehavior: Clip.antiAlias,
                        color: cs.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: InkWell(
                          onTap: () {
                            if (_searchFocusNode.hasFocus) {
                              _searchFocusNode.unfocus();
                            }
                            if (isAdded) {
                              // Already added: go to details screen
                              pushScreen<void>(
                                context,
                                SeriesDetailScreen(
                                  instance: widget.instance,
                                  series: localMatch,
                                ),
                              );
                            } else {
                              // Not added: open configuration sheet
                              showModalBottomSheet<void>(
                                context: context,
                                useRootNavigator: true,
                                isScrollControlled: true,
                                useSafeArea: true,
                                shape: const RoundedRectangleBorder(
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(28),
                                  ),
                                ),
                                builder: (BuildContext context) =>
                                    SonarrAddSeriesSheet(
                                  instance: widget.instance,
                                  series: s,
                                ),
                              );
                            }
                          },
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // Poster image
                                SizedBox(
                                  width: 100,
                                  child: AspectRatio(
                                    aspectRatio: 2 / 3,
                                    child: _PosterImage(
                                      instance: widget.instance,
                                      series: s,
                                    ),
                                  ),
                                ),
                                // Metadata info
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(Insets.md),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              s.title,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                fontWeight: FontWeight.bold,
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${s.year} • ${s.network ?? "Unknown Network"}',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: Insets.sm),
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            // Status Chip
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: _statusColor(
                                                  s.status ?? '',
                                                  theme,
                                                ).withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                _capitalise(s.status ?? ''),
                                                style: theme.textTheme.bodySmall
                                                    ?.copyWith(
                                                  color: _statusColor(
                                                    s.status ?? '',
                                                    theme,
                                                  ),
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                            // Added/Not Added Status Indicator
                                            if (isAdded)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: cs.primaryContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.check,
                                                      size: 14,
                                                      color:
                                                          cs.onPrimaryContainer,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Added',
                                                      style: theme
                                                          .textTheme.labelSmall
                                                          ?.copyWith(
                                                        color: cs
                                                            .onPrimaryContainer,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            else
                                              Icon(
                                                Icons.add_circle_outline,
                                                color: cs.primary,
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
      ),
    );
  }

  Color _statusColor(String status, ThemeData theme) {
    return switch (status.toLowerCase()) {
      'continuing' => theme.colorScheme.primary,
      'upcoming' => theme.colorScheme.secondary,
      _ => theme.colorScheme.outline,
    };
  }

  String _capitalise(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}

class _PosterImage extends ConsumerWidget {
  const _PosterImage({required this.instance, required this.series});

  final Instance instance;
  final SonarrSeries series;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final SonarrApi? api = ref.watch(sonarrApiProvider(instance)).value;
    final SonarrImage? poster = series.images.firstWhereOrNull(
      (SonarrImage i) => i.coverType == 'poster',
    );
    final String? url =
        poster == null ? null : api?.posterUrl(poster, preferRemote: true);

    if (url == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Center(
          child: Icon(Icons.tv),
        ),
      );
    }

    return AtriumNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (context, url) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Center(
          child: ExpressiveProgressIndicator(),
        ),
      ),
      errorWidget: (context, url, error) => Container(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: const Center(
          child: Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}
