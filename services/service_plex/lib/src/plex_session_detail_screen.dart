import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator_plus/palette_generator_plus.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';

import 'models/plex_session.dart';
import 'plex_api.dart';
import 'plex_deep_link.dart';
import 'plex_providers.dart';

/// Full-screen now-playing controller for one Plex stream.
///
/// Follows [plexSessionsProvider]'s 3s poll, resolving the live session by id
/// and falling back to [initialSession] when the stream has ended. Transport
/// controls (play/pause, stop, skip, seek) are only shown for players that
/// advertise Plex Companion control; everything else is view-only. The
/// app-bar terminate action degrades to a "needs Plex Pass" message when the
/// server refuses.
class PlexSessionDetailScreen extends ConsumerStatefulWidget {
  const PlexSessionDetailScreen({
    required this.instance,
    required this.initialSession,
    super.key,
  });

  final Instance instance;
  final PlexSession initialSession;

  @override
  ConsumerState<PlexSessionDetailScreen> createState() =>
      _PlexSessionDetailScreenState();
}

class _PlexSessionDetailScreenState
    extends ConsumerState<PlexSessionDetailScreen> {
  bool _isDragging = false;
  double _dragPct = 0.0;
  PaletteGenerator? _palette;
  String? _lastPosterUrl;

  /// Samples the poster for a color scheme, once per poster URL.
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

    // maximumColorCount is left at its default of 16.
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

  /// Sends a Plex Companion transport command to the session's player and
  /// refreshes the sessions poll so the UI reflects the new state.
  Future<void> _cmd(
    PlexSession session,
    String command, {
    int? offsetMs,
  }) async {
    final PlexSessionPlayer? player = session.player;
    if (player == null) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final PlexApi api =
          await ref.read(plexApiProvider(widget.instance).future);
      await api.sendPlayerCommand(
        command,
        machineIdentifier: player.machineIdentifier,
        offsetMs: offsetMs,
      );
      if (!mounted) {
        return;
      }
      ref.invalidate(plexSessionsProvider(widget.instance));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Command failed - the player may not be controllable'),
        ),
      );
    }
  }

  /// Confirms, then asks the server to end the stream. Termination is a Plex
  /// Pass feature server-side, so an auth refusal (401/403) degrades to an
  /// explanatory snackbar; any other failure gets a generic error message.
  Future<void> _confirmTerminate(PlexSession session) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    final String? userTitle = session.user?.title;
    final String viewer =
        (userTitle == null || userTitle.isEmpty) ? 'this viewer' : userTitle;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Stop this stream?'),
          content: Text('This ends playback for $viewer.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Stop stream'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      final PlexApi api =
          await ref.read(plexApiProvider(widget.instance).future);
      await api.terminateSession(session.sessionId);
      if (!mounted) {
        return;
      }
      ref.invalidate(plexSessionsProvider(widget.instance));
      navigator.pop();
    } catch (e) {
      // Only a 401/403 means the server refused the Plex Pass feature;
      // anything else (timeout, DNS, bad session id) is a plain failure.
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is NetworkAuthException
                ? 'Terminating a stream requires Plex Pass'
                : 'Could not stop the stream',
          ),
        ),
      );
    }
  }

  String _fmtMs(int? ms) {
    final Duration d = Duration(milliseconds: ms ?? 0);
    final String m = d.inMinutes.remainder(60).toString();
    final String s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:${m.padLeft(2, '0')}:$s';
    }
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<PlexSession>> sessionsAsync =
        ref.watch(plexSessionsProvider(widget.instance));
    final PlexSession session = sessionsAsync.value?.firstWhereOrNull(
          // An empty id must never match: sessions without a session block
          // all share '' and would re-bind this screen to the wrong stream.
          (PlexSession s) =>
              s.sessionId.isNotEmpty &&
              s.sessionId == widget.initialSession.sessionId,
        ) ??
        widget.initialSession;

    final PlexApi? api = ref.watch(plexApiProvider(widget.instance)).value;
    final String? posterUrl = api?.imageUrl(session.thumb);
    final String? backdropUrl = api?.imageUrl(session.art) ?? posterUrl;

    ThemeData theme = Theme.of(context);
    _updatePalette(posterUrl);
    if (_palette != null) {
      final Color dominant =
          _palette!.dominantColor?.color ?? theme.colorScheme.surface;
      final Color vibrant = _palette!.vibrantColor?.color ??
          _palette!.lightVibrantColor?.color ??
          dominant;
      final Color muted = _palette!.mutedColor?.color ??
          theme.colorScheme.surfaceContainerHighest;
      final Color darkMuted = _palette!.darkMutedColor?.color ?? dominant;
      final Color titleText = _palette!.lightVibrantColor?.color ??
          _palette!.vibrantColor?.color ??
          _palette!.lightMutedColor?.color ??
          theme.colorScheme.onSurface;
      final Color bodyText = _palette!.lightMutedColor?.color ??
          _palette!.mutedColor?.color ??
          theme.colorScheme.onSurfaceVariant;

      theme = theme.copyWith(
        scaffoldBackgroundColor: darkMuted,
        colorScheme: theme.colorScheme.copyWith(
          primary: vibrant,
          onPrimary: _palette!.vibrantColor?.titleTextColor ??
              theme.colorScheme.onPrimary,
          secondaryContainer: vibrant.withValues(alpha: 0.25),
          onSecondaryContainer: vibrant,
          surface: dominant,
          onSurface: titleText,
          onSurfaceVariant: bodyText,
          surfaceContainer: muted,
          surfaceContainerHighest: muted,
        ),
      );
    }

    final PlexSessionPlayer? player = session.player;
    final bool controllable = player?.controllable ?? false;
    final bool playing = player?.state == 'playing';
    final double pct = _isDragging ? _dragPct : session.progress;

    return Theme(
      data: theme,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(
              Icons.keyboard_arrow_down,
              size: 32,
              color: Colors.white,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            'NOW PLAYING',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          centerTitle: true,
          actions: <Widget>[
            IconButton(
              tooltip: 'Open in Plex',
              icon: const Icon(Icons.open_in_new, color: Colors.white),
              onPressed: () => launchPlexDeepLink(context),
            ),
            IconButton(
              tooltip: 'Stop stream',
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
              onPressed: () => _confirmTerminate(session),
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Blurred backdrop behind everything.
            if (backdropUrl != null)
              Image(
                image: atriumImageProvider(backdropUrl),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: theme.colorScheme.surface),
              ),
            // Blur and gradient scrim; text over it is forced white.
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Colors.black.withValues(alpha: 0.5),
                      theme.colorScheme.surface.withValues(alpha: 0.8),
                      Colors.black.withValues(alpha: 0.95),
                    ],
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const SizedBox(height: Insets.md),
                    if (session.user != null)
                      _UserRow(
                        user: session.user!,
                        avatarUrl: api?.imageUrl(session.user!.thumb),
                      ),
                    const Spacer(),
                    // Poster artwork.
                    Flexible(
                      flex: 10,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            maxHeight: 420,
                            maxWidth: 280,
                          ),
                          child: AspectRatio(
                            aspectRatio: 2 / 3,
                            child: Container(
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: Radii.card,
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 20,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              child: posterUrl == null
                                  ? Icon(
                                      Icons.movie_outlined,
                                      color: theme.colorScheme.outline,
                                      size: 80,
                                    )
                                  : Image(
                                      image:
                                          atriumImageProvider(posterUrl),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.movie_outlined,
                                        color: theme.colorScheme.outline,
                                        size: 80,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: Insets.lg),
                    // Title block: show title for episodes, then the episode
                    // name; movies just show their title.
                    Text(
                      session.grandparentTitle ?? session.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        height: 1.2,
                      ),
                    ),
                    if (session.grandparentTitle != null) ...<Widget>[
                      const SizedBox(height: Insets.xs),
                      Text(
                        session.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white70,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (player != null) ...<Widget>[
                      const SizedBox(height: Insets.xs),
                      Text(
                        player.product == null || player.product!.isEmpty
                            ? player.title
                            : '${player.title} · ${player.product}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    ],
                    const SizedBox(height: Insets.md),
                    Wrap(
                      spacing: Insets.sm,
                      runSpacing: Insets.xs,
                      children: <Widget>[
                        _InfoChip(label: session.decisionLabel),
                        if (session.bandwidth != null)
                          _InfoChip(label: '${session.bandwidth} kbps'),
                        if (session.location != null)
                          _InfoChip(label: session.location!.toUpperCase()),
                      ],
                    ),
                    const SizedBox(height: Insets.lg),
                    // Progress: a seek slider for controllable players, a
                    // read-only bar otherwise.
                    if (controllable)
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 16,
                          thumbShape: const ExpressiveSliderThumbShape(),
                          trackShape: const ExpressiveSliderTrackShape(),
                          overlayShape: const RoundSliderOverlayShape(),
                          activeTrackColor: theme.colorScheme.primary,
                          inactiveTrackColor:
                              Colors.white.withValues(alpha: 0.2),
                          thumbColor: theme.colorScheme.primary,
                        ),
                        child: Slider(
                          value: pct.clamp(0.0, 1.0),
                          onChangeStart: (double v) => setState(() {
                            _isDragging = true;
                            _dragPct = v;
                          }),
                          onChanged: (double v) => setState(() => _dragPct = v),
                          onChangeEnd: (double v) {
                            setState(() => _isDragging = false);
                            final int? duration = session.duration;
                            if (duration != null && duration > 0) {
                              _cmd(
                                session,
                                'seekTo',
                                offsetMs: (v * duration).round(),
                              );
                            }
                          },
                        ),
                      )
                    else
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: Insets.md),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicatorM3E(
                            shape: ProgressM3EShape.flat,
                            value: session.progress,
                            activeColor: theme.colorScheme.primary,
                            trackColor: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Insets.lg,
                        vertical: Insets.xs,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            _fmtMs(session.viewOffset),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _fmtMs(session.duration),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: Colors.white70,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Insets.md),
                    if (controllable)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          _TransportButton(
                            icon: Icons.skip_previous,
                            onPressed: () => _cmd(session, 'skipPrevious'),
                          ),
                          const SizedBox(width: Insets.md),
                          SizedBox(
                            width: 112,
                            height: 72,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: theme.colorScheme.primary
                                    .withValues(alpha: 0.85),
                                foregroundColor: theme.colorScheme.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(32),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: () => _cmd(session, 'playPause'),
                              child: Icon(
                                playing ? Icons.pause : Icons.play_arrow,
                                size: 40,
                              ),
                            ),
                          ),
                          const SizedBox(width: Insets.md),
                          _TransportButton(
                            icon: Icons.stop,
                            onPressed: () => _cmd(session, 'stop'),
                          ),
                          const SizedBox(width: Insets.md),
                          _TransportButton(
                            icon: Icons.skip_next,
                            onPressed: () => _cmd(session, 'skipNext'),
                          ),
                        ],
                      )
                    else
                      Text(
                        "This player can't be controlled from here",
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                    const Spacer(),
                    const SizedBox(height: Insets.xl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar plus user name, top-left over the scrim.
class _UserRow extends StatelessWidget {
  const _UserRow({required this.user, required this.avatarUrl});

  final PlexSessionUser user;
  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String initial =
        user.title.isEmpty ? '?' : user.title[0].toUpperCase();
    return Row(
      children: <Widget>[
        CircleAvatar(
          radius: 16,
          backgroundColor: Colors.white.withValues(alpha: 0.2),
          foregroundImage:
              avatarUrl == null ? null : atriumImageProvider(avatarUrl!),
          onForegroundImageError: avatarUrl == null ? null : (_, __) {},
          child: Text(
            initial,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: Insets.sm),
        Expanded(
          child: Text(
            user.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelLarge?.copyWith(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Small translucent pill for stream facts (decision, bandwidth, LAN/WAN).
class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Square tonal transport button (previous / stop / next).
class _TransportButton extends StatelessWidget {
  const _TransportButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      width: 72,
      height: 72,
      child: FilledButton.tonal(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white.withValues(alpha: 0.15),
          foregroundColor: theme.colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: EdgeInsets.zero,
        ),
        onPressed: onPressed,
        child: Icon(icon, size: 32),
      ),
    );
  }
}
