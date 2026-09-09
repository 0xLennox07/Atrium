import 'dart:math' as math;

import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator_plus/palette_generator_plus.dart';

import 'models/seerr_discover.dart';
import 'models/seerr_service.dart';
import 'seerr_api.dart';
import 'seerr_media_card.dart';
import 'seerr_providers.dart';
import 'seerr_report_issue_sheet.dart';
import 'seerr_status_badge.dart';

/// Detail screen for a Seerr movie/show: a backdrop hero fading into the
/// surface with the poster + title + metadata pills at its foot, then the
/// request/report actions, genre pills, overview, a horizontal cast row, and
/// Recommendations / Similar rows that push fresh detail screens.
///
/// Progressive enhancement - the passed [item] (from the browse list) renders
/// immediately and is swapped for the full details (backdrop, status, runtime,
/// genres, credits) once `getMediaDetails` loads. The poster is sampled with
/// palette_generator (bounded, cached by URL, mounted-guarded) and the
/// resulting seed tints the screen's accents through M3 roles.
class SeerrItemDetailScreen extends ConsumerStatefulWidget {
  const SeerrItemDetailScreen({
    required this.instance,
    required this.item,
    super.key,
  });

  final Instance instance;
  final SeerrDiscoverResult item;

  @override
  ConsumerState<SeerrItemDetailScreen> createState() =>
      _SeerrItemDetailScreenState();
}

class _SeerrItemDetailScreenState extends ConsumerState<SeerrItemDetailScreen> {
  PaletteGenerator? _palette;
  String? _lastPosterUrl;

  /// Samples the poster for accent colors, once per poster URL.
  ///
  /// `timeout: Duration.zero` disables palette_generator's load-failure
  /// timer: a poster that never resolves simply keeps the default colors
  /// instead of erroring after 15s (and leaves no pending timer behind in
  /// widget tests, where network images always fail).
  void _updatePalette(String? posterUrl) {
    if (posterUrl == null || posterUrl == _lastPosterUrl) {
      return;
    }
    _lastPosterUrl = posterUrl;

    PaletteGenerator.fromImageProvider(
      atriumImageProvider(posterUrl, maxWidth: 200, maxHeight: 300),
      size: const Size(200, 300),
      timeout: Duration.zero,
    ).then((PaletteGenerator palette) {
      if (mounted) {
        setState(() => _palette = palette);
      }
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final SeerrMediaDetailsArgs args = (
      instance: widget.instance,
      mediaType: widget.item.mediaType,
      tmdbId: widget.item.id,
    );
    final SeerrDiscoverResult full =
        ref.watch(seerrMediaDetailsProvider(args)).value ?? widget.item;

    final SeerrApi? api = ref.watch(seerrApiProvider(widget.instance)).value;
    final String? backdropPath = full.backdropPath ?? widget.item.backdropPath;
    final String? posterPath = full.posterPath ?? widget.item.posterPath;
    final String? posterUrl = api?.imageUrl(posterPath);
    final String? backdropUrl = api?.imageUrl(backdropPath, size: 'w780');
    _updatePalette(posterUrl);

    // Poster-palette accent: reseed a full M3 scheme from the poster's
    // vibrant color so every accent pairing keeps guaranteed contrast in
    // both brightnesses. Surfaces stay on the ambient theme.
    final Color? seed = _palette?.vibrantColor?.color ??
        _palette?.lightVibrantColor?.color ??
        _palette?.dominantColor?.color;
    final ColorScheme accent = seed == null
        ? cs
        : (cs.brightness == Brightness.dark
            ? FlexColorScheme.dark(
                colors: FlexSchemeColor.from(primary: seed),
                keyColors: const FlexKeyColors(
                  keepPrimary: true,
                ),
              ).toScheme
            : FlexColorScheme.light(
                colors: FlexSchemeColor.from(primary: seed),
                keyColors: const FlexKeyColors(
                  keepPrimary: true,
                ),
              ).toScheme);

    final List<String> genreNames = full.genres
        .map((SeerrGenre g) => g.name)
        .where((String n) => n.isNotEmpty)
        .toList();
    final List<SeerrCastMember> cast =
        full.credits?.cast ?? const <SeerrCastMember>[];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        // The hero is not pinned, so the back button can end up floating
        // over pale scrolled content as well as the backdrop: sit the white
        // arrow on a translucent circular scrim so it stays legible over
        // both, and force light status-bar icons to match the dark hero
        // scrim. Without a hero the button sits on plain surface and keeps
        // the M3 role color and the ambient overlay style.
        systemOverlayStyle:
            backdropPath != null ? SystemUiOverlayStyle.light : null,
        leading: backdropPath != null
            ? IconButton(
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.maybePop(context),
                icon: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.black.withValues(alpha: 0.4),
                  child: const Icon(Icons.arrow_back, color: Colors.white),
                ),
              )
            : null,
      ),
      body: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: backdropPath != null
                ? SizedBox(
                    // Half the screen, but never below the 180dp poster plus
                    // title block: on a landscape phone 50% of the height
                    // would hard-clip the header.
                    height: math.max(
                      MediaQuery.sizeOf(context).height * 0.5,
                      340,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: <Widget>[
                        Positioned.fill(
                          child: backdropUrl != null
                              ? AtriumNetworkImage(
                                  key: ValueKey<String>(backdropUrl),
                                  imageUrl: backdropUrl,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => ColoredBox(
                                    color: cs.surfaceContainerHighest,
                                  ),
                                )
                              : ColoredBox(color: cs.surfaceContainerHighest),
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
                                  cs.surface.withValues(alpha: 0.0),
                                  cs.surface.withValues(alpha: 0.55),
                                  cs.surface,
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
                          child: _DetailHeader(
                            item: full,
                            posterUrl: posterUrl,
                            accent: accent,
                          ),
                        ),
                      ],
                    ),
                  )
                : SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: kToolbarHeight + Insets.lg,
                      ),
                      child: _DetailHeader(
                        item: full,
                        posterUrl: posterUrl,
                        accent: accent,
                      ),
                    ),
                  ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(Insets.lg, Insets.lg, Insets.lg, 0),
              child: _ActionRow(
                instance: widget.instance,
                item: full,
                accent: accent,
              ),
            ),
          ),
          if (genreNames.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.lg,
                  Insets.lg,
                  Insets.lg,
                  0,
                ),
                child: Wrap(
                  spacing: 6.0,
                  runSpacing: 6.0,
                  children: <Widget>[
                    for (final String g in genreNames)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: accent.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          g,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: accent.onSecondaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          if (full.overview != null && full.overview!.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.lg,
                  Insets.lg,
                  Insets.lg,
                  0,
                ),
                child: OverviewBox(overview: full.overview!),
              ),
            ),
          if (cast.isNotEmpty)
            SliverToBoxAdapter(child: _CastRow(cast: cast, api: api)),
          SliverToBoxAdapter(
            child: _MediaRow(
              title: 'Recommendations',
              instance: widget.instance,
              provider: seerrRecommendationsProvider(args),
            ),
          ),
          SliverToBoxAdapter(
            child: _MediaRow(
              title: 'Similar',
              instance: widget.instance,
              provider: seerrSimilarProvider(args),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: Insets.xl)),
        ],
      ),
    );
  }
}

/// Poster + title + metadata pills, shown at the foot of the backdrop hero
/// (or standalone when the item has no backdrop).
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.item,
    required this.posterUrl,
    required this.accent,
  });

  final SeerrDiscoverResult item;
  final String? posterUrl;
  final ColorScheme accent;

  String _fmtRuntime(int minutes) {
    final int h = minutes ~/ 60;
    final int m = minutes % 60;
    if (h > 0) {
      return m == 0 ? '${h}h' : '${h}h ${m}m';
    }
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? runtimeLabel = item.isMovie
        ? (item.runtime != null && item.runtime! > 0
            ? _fmtRuntime(item.runtime!)
            : null)
        : (item.numberOfEpisodes != null && item.numberOfEpisodes! > 0
            ? '${item.numberOfEpisodes} episodes'
            : null);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.lg),
            child: posterUrl != null
                ? AtriumNetworkImage(
                    key: ValueKey<String>(posterUrl!),
                    imageUrl: posterUrl!,
                    width: 120,
                    height: 180,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _posterFallback(theme),
                  )
                : _posterFallback(theme),
          ),
          const SizedBox(width: Insets.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.displayTitle,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: Insets.sm),
                Wrap(
                  spacing: Insets.sm,
                  runSpacing: Insets.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    if (item.year != null) SeerrInfoPill(label: item.year!),
                    if (item.voteAverage != null && item.voteAverage! > 0)
                      _RatingPill(value: item.voteAverage!, accent: accent),
                    if (runtimeLabel != null)
                      SeerrInfoPill(label: runtimeLabel),
                    if (item.status != null && item.status!.isNotEmpty)
                      SeerrInfoPill(label: item.status!),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _posterFallback(ThemeData theme) => Container(
        width: 120,
        height: 180,
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.movie_outlined, size: 40)),
      );
}

/// Star + score pill tinted with the poster-palette accent.
class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.value, required this.accent});

  final double value;
  final ColorScheme accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: accent.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.star, size: 14, color: accent.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            value.toStringAsFixed(1),
            style: theme.textTheme.labelMedium?.copyWith(
              color: accent.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The request action/status plus (when the item exists in Seerr's media
/// table) the report-issue button.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.instance,
    required this.item,
    required this.accent,
  });

  final Instance instance;
  final SeerrDiscoverResult item;
  final ColorScheme accent;

  @override
  Widget build(BuildContext context) {
    final bool canReport = item.mediaInfo?.id != null;
    return Row(
      children: <Widget>[
        Expanded(
          child: _RequestButton(instance: instance, item: item, accent: accent),
        ),
        if (canReport) ...<Widget>[
          const SizedBox(width: Insets.sm),
          Expanded(
            child: _ReportIssueButton(
              instance: instance,
              item: item,
              accent: accent,
            ),
          ),
        ],
      ],
    );
  }
}

/// Outline button for reporting a playback/quality issue on this item;
/// opens the report-issue sheet over the root navigator. Only rendered when
/// the item exists in Seerr's media table (`mediaInfo.id` is the internal
/// media DB id the issue endpoints key on).
class _ReportIssueButton extends StatelessWidget {
  const _ReportIssueButton({
    required this.instance,
    required this.item,
    required this.accent,
  });

  final Instance instance;
  final SeerrDiscoverResult item;
  final ColorScheme accent;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(foregroundColor: accent.primary),
      onPressed: () => showSeerrReportIssueSheet(
        context,
        instance: instance,
        mediaId: item.mediaInfo!.id!,
        title: item.displayTitle,
      ),
      icon: const Icon(Icons.flag_outlined),
      label: const Text('Report issue'),
    );
  }
}

/// Horizontal cast row: circular profile avatars with name + character.
class _CastRow extends StatelessWidget {
  const _CastRow({required this.cast, required this.api});

  final List<SeerrCastMember> cast;

  /// Builds the profile URLs. Null while the API is still loading, and the
  /// avatars show their person icon.
  final SeerrApi? api;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: Insets.lg),
        Padding(
          padding: Insets.pageH,
          child: Text(
            'Cast',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: Insets.sm),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: Insets.pageH,
            itemCount: cast.length,
            separatorBuilder: (_, __) => const SizedBox(width: Insets.md),
            itemBuilder: (BuildContext context, int index) {
              final SeerrCastMember member = cast[index];
              final String? profileUrl =
                  api?.imageUrl(member.profilePath, size: 'w185');
              return SizedBox(
                width: 92,
                child: Column(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 40,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      backgroundImage: profileUrl != null
                          ? atriumImageProvider(profileUrl)
                          : null,
                      onBackgroundImageError:
                          profileUrl != null ? (_, __) {} : null,
                      child: profileUrl == null
                          ? const Icon(Icons.person, size: 32)
                          : null,
                    ),
                    const SizedBox(height: Insets.xs),
                    Text(
                      member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (member.character != null &&
                        member.character!.isNotEmpty)
                      Text(
                        member.character!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
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

/// One horizontal row of poster cards (Recommendations / Similar). Hidden
/// while loading, on error, and when the list is empty - these rows are an
/// enhancement and must never block the detail screen.
class _MediaRow extends ConsumerWidget {
  const _MediaRow({
    required this.title,
    required this.instance,
    required this.provider,
  });

  final String title;
  final Instance instance;
  final FutureProvider<List<SeerrDiscoverResult>> provider;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<SeerrDiscoverResult> items =
        ref.watch(provider).value ?? const <SeerrDiscoverResult>[];
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final SeerrApi? api = ref.watch(seerrApiProvider(instance)).value;
    final ThemeData theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: Insets.lg),
        Padding(
          padding: Insets.pageH,
          child: Text(
            title,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: Insets.sm),
        SizedBox(
          height: 250,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: Insets.pageH,
            itemCount: items.length,
            itemBuilder: (BuildContext context, int index) =>
                _PosterCard(instance: instance, item: items[index], api: api),
          ),
        ),
      ],
    );
  }
}

/// Tappable poster card used in the Recommendations / Similar rows; pushes a
/// fresh detail screen for the tapped item.
class _PosterCard extends StatelessWidget {
  const _PosterCard({
    required this.instance,
    required this.item,
    required this.api,
  });

  final Instance instance;
  final SeerrDiscoverResult item;

  /// Builds the poster URL. Null while the API is still loading, and the card
  /// shows its placeholder.
  final SeerrApi? api;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: 128,
      margin: const EdgeInsets.only(right: Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Material(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => pushScreen<void>(
                  context,
                  SeerrItemDetailScreen(instance: instance, item: item),
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    api?.imageUrl(item.posterPath) != null
                        ? AtriumNetworkImage(
                            imageUrl: api!.imageUrl(item.posterPath)!,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _posterFallback(theme),
                          )
                        : _posterFallback(theme),
                    Positioned(
                      top: 6,
                      right: 6,
                      child: SeerrStatusBadge(status: item.mediaInfo?.status),
                    ),
                    if (item.voteAverage != null && item.voteAverage! > 0)
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: _PosterRatingBadge(value: item.voteAverage!),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: Insets.sm),
          Text(
            item.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          if (item.year != null)
            Text(
              item.year!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _posterFallback(ThemeData theme) => Container(
        color: theme.colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.movie_outlined)),
      );
}

/// Small rating pill (star + score) overlaid on a poster; white-on-scrim per
/// the over-imagery rules.
class _PosterRatingBadge extends StatelessWidget {
  const _PosterRatingBadge({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.star, size: 11, color: Colors.amber),
          const SizedBox(width: 3),
          Text(
            value.toStringAsFixed(1),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The request action: a full-width tonal status panel when the item is
/// already requested / processing / available, otherwise the accent-tinted
/// Request button that opens the options sheet.
class _RequestButton extends ConsumerStatefulWidget {
  const _RequestButton({
    required this.instance,
    required this.item,
    required this.accent,
  });

  final Instance instance;
  final SeerrDiscoverResult item;
  final ColorScheme accent;

  @override
  ConsumerState<_RequestButton> createState() => _RequestButtonState();
}

class _RequestButtonState extends ConsumerState<_RequestButton> {
  bool _requestedLocal = false;

  Future<void> _openRequestSheet() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool? requested = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _RequestOptionsSheet(instance: widget.instance, item: widget.item),
    );
    if (requested == true && mounted) {
      setState(() => _requestedLocal = true);
      messenger.showSnackBar(
        const SnackBar(content: Text('Request submitted successfully!')),
      );
      ref.invalidate(seerrRequestCountsProvider(widget.instance));
      ref.invalidate(seerrRequestsProvider(widget.instance));
    }
  }

  @override
  Widget build(BuildContext context) {
    final int status = widget.item.mediaInfo?.status ?? 1;
    // 1 = unknown, 2 = pending, 3 = processing, 4 = partial, 5 = available.
    if (_requestedLocal || status == 2 || status == 3) {
      return _StatusPanel(
        icon: status == 3 ? Icons.downloading : Icons.hourglass_top,
        label: status == 3 ? 'Processing' : 'Requested',
        accent: widget.accent,
      );
    } else if (status == 4 || status == 5) {
      return _StatusPanel(
        icon: Icons.check_circle,
        label: status == 4 ? 'Partially available' : 'Available',
        accent: widget.accent,
      );
    }

    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: widget.accent.primary,
        foregroundColor: widget.accent.onPrimary,
      ),
      onPressed: _openRequestSheet,
      icon: const Icon(Icons.add_to_queue),
      label: const Text('Request'),
    );
  }
}

/// Non-interactive tonal panel showing the request/availability state, sized
/// to line up with the buttons beside it.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.icon,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final ColorScheme accent;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: accent.secondaryContainer,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 18, color: accent.onSecondaryContainer),
          const SizedBox(width: Insets.sm),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: accent.onSecondaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sheet to pick the quality profile / root folder / server (and 4K when the
/// instance has 4K servers) before submitting a request. Falls back to a
/// defaults-only request when the service options can't be loaded (e.g. the
/// user lacks the advanced-request permission).
class _RequestOptionsSheet extends ConsumerStatefulWidget {
  const _RequestOptionsSheet({required this.instance, required this.item});

  final Instance instance;
  final SeerrDiscoverResult item;

  @override
  ConsumerState<_RequestOptionsSheet> createState() =>
      _RequestOptionsSheetState();
}

class _RequestOptionsSheetState extends ConsumerState<_RequestOptionsSheet> {
  int? _serverId;
  int? _profileId;
  String? _rootFolder;
  bool _is4k = false;
  bool _submitting = false;
  String? _error;

  String get _mediaType => widget.item.mediaType;

  Future<void> _submit({
    int? serverId,
    int? profileId,
    String? rootFolder,
    bool is4k = false,
  }) async {
    final NavigatorState navigator = Navigator.of(context);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = await ref.read(seerrApiProvider(widget.instance).future);
      await api.createRequest(
        mediaType: widget.item.mediaType,
        mediaId: widget.item.id,
        is4k: is4k,
        serverId: serverId,
        profileId: profileId,
        rootFolder: rootFolder,
      );
      if (mounted) {
        navigator.pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Request failed: $e';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<List<SeerrServer>> serversAsync = ref.watch(
      seerrServersProvider((instance: widget.instance, mediaType: _mediaType)),
    );

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: Insets.lg,
          right: Insets.lg,
          bottom: MediaQuery.of(context).viewInsets.bottom + Insets.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Request',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 2),
            Text(widget.item.displayTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: Insets.lg),
            serversAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(Insets.lg),
                child: Center(child: ExpressiveProgressIndicator()),
              ),
              error: (Object e, _) => _fallback(
                'Advanced options are unavailable. You can still request using '
                'the server defaults.',
              ),
              data: (List<SeerrServer> servers) => servers.isEmpty
                  ? _fallback(
                      'No ${_mediaType == 'tv' ? 'Sonarr' : 'Radarr'} server is '
                      'configured; requesting will use Seerr defaults.',
                    )
                  : _options(servers),
            ),
          ],
        ),
      ),
    );
  }

  Widget _options(List<SeerrServer> servers) {
    final bool has4k = servers.any((SeerrServer s) => s.is4k);
    final bool hasStandard = servers.any((SeerrServer s) => !s.is4k);
    // Only offer/force 4K when a 4K server exists; when nothing but 4K
    // servers are configured the request has to be 4K.
    final bool is4k = has4k && (_is4k || !hasStandard);
    final List<SeerrServer> pool =
        servers.where((SeerrServer s) => s.is4k == is4k).toList();

    final SeerrServer defaultServer = pool.firstWhere(
      (SeerrServer s) => s.isDefault,
      orElse: () => pool.first,
    );
    final SeerrServer server = pool.firstWhere(
      (SeerrServer s) => s.id == _serverId,
      orElse: () => defaultServer,
    );
    final int serverId = server.id;

    final AsyncValue<SeerrServerDetails> detailsAsync = ref.watch(
      seerrServerDetailsProvider(
        (instance: widget.instance, mediaType: _mediaType, serverId: serverId),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (has4k && hasStandard) ...<Widget>[
          SwitchListTile(
            value: is4k,
            contentPadding: EdgeInsets.zero,
            title: const Text('Request in 4K'),
            onChanged: (bool v) => setState(() {
              _is4k = v;
              _serverId = null;
              _profileId = null;
              _rootFolder = null;
            }),
          ),
          const SizedBox(height: Insets.xs),
        ],
        if (pool.length > 1) ...<Widget>[
          DropdownButtonFormField<int>(
            // Re-key per pool so the 4K toggle reseeds the initial value.
            key: ValueKey<String>('server-$is4k'),
            initialValue: serverId,
            decoration: const InputDecoration(
              labelText: 'Server',
              border: OutlineInputBorder(),
            ),
            items: pool
                .map(
                  (SeerrServer s) => DropdownMenuItem<int>(
                    value: s.id,
                    child: Text(s.name.isEmpty ? 'Server ${s.id}' : s.name),
                  ),
                )
                .toList(),
            onChanged: (int? v) => setState(() {
              _serverId = v;
              _profileId = null;
              _rootFolder = null;
            }),
          ),
          const SizedBox(height: Insets.md),
        ],
        detailsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(Insets.lg),
            child: Center(child: ExpressiveProgressIndicator()),
          ),
          error: (Object e, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'Could not load quality profiles for this server.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: Insets.md),
              _submitButton(
                'Request with defaults',
                () => _submit(serverId: serverId, is4k: is4k),
              ),
            ],
          ),
          data: (SeerrServerDetails details) =>
              _form(server, details, serverId, is4k),
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: Insets.sm),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _form(
    SeerrServer server,
    SeerrServerDetails details,
    int serverId,
    bool is4k,
  ) {
    final List<SeerrProfile> profiles = details.profiles;
    final List<SeerrRootFolder> roots = details.rootFolders;

    // Resolve the effective selections, guarding against a default that isn't
    // in the list so the dropdown never asserts on an unknown value.
    int? profileId = _profileId ?? server.activeProfileId;
    if (!profiles.any((SeerrProfile p) => p.id == profileId)) {
      profileId = profiles.isNotEmpty ? profiles.first.id : null;
    }
    String? rootFolder = _rootFolder ?? server.activeDirectory;
    if (!roots.any((SeerrRootFolder r) => r.path == rootFolder)) {
      rootFolder = roots.isNotEmpty ? roots.first.path : null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (profiles.isNotEmpty)
          DropdownButtonFormField<int>(
            // Re-key per server so a server switch reseeds the initial value.
            key: ValueKey<String>('profile-$serverId'),
            initialValue: profileId,
            decoration: const InputDecoration(
              labelText: 'Quality profile',
              border: OutlineInputBorder(),
            ),
            items: profiles
                .map(
                  (SeerrProfile p) => DropdownMenuItem<int>(
                    value: p.id,
                    child: Text(p.name),
                  ),
                )
                .toList(),
            onChanged: (int? v) => setState(() => _profileId = v),
          ),
        if (roots.isNotEmpty) ...<Widget>[
          const SizedBox(height: Insets.md),
          DropdownButtonFormField<String>(
            key: ValueKey<String>('root-$serverId'),
            initialValue: rootFolder,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Root folder',
              border: OutlineInputBorder(),
            ),
            items: roots
                .map(
                  (SeerrRootFolder r) => DropdownMenuItem<String>(
                    value: r.path,
                    child: Text(r.path, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (String? v) => setState(() => _rootFolder = v),
          ),
        ],
        const SizedBox(height: Insets.lg),
        _submitButton(
          'Request',
          () => _submit(
            serverId: serverId,
            profileId: profileId,
            rootFolder: rootFolder,
            is4k: is4k,
          ),
        ),
      ],
    );
  }

  Widget _fallback(String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(message, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: Insets.lg),
        _submitButton('Request', _submit),
        if (_error != null) ...<Widget>[
          const SizedBox(height: Insets.sm),
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }

  Widget _submitButton(String label, VoidCallback onPressed) {
    return FilledButton.icon(
      onPressed: _submitting ? null : onPressed,
      icon: _submitting
          ? const SizedBox(
              width: 16,
              height: 16,
              child: ExpressiveProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add_to_queue),
      label: Text(label),
    );
  }
}
