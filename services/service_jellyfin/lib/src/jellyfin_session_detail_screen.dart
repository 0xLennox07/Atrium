import 'dart:math';
import 'dart:ui';
import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator_plus/palette_generator_plus.dart';

import 'jellyfin_client.dart';
import 'jellyfin_providers.dart';
import 'models/jellyfin_session.dart';

class JellyfinSessionDetailScreen extends ConsumerStatefulWidget {
  const JellyfinSessionDetailScreen({
    required this.instance,
    required this.initialSession,
    super.key,
  });

  final Instance instance;
  final ActiveSession initialSession;

  @override
  ConsumerState<JellyfinSessionDetailScreen> createState() =>
      _JellyfinSessionDetailScreenState();
}

class _JellyfinSessionDetailScreenState
    extends ConsumerState<JellyfinSessionDetailScreen> {
  bool _isDragging = false;
  double _dragPct = 0.0;
  bool _isVolumeDragging = false;
  double _volumeDragPct = 0.0;
  PaletteGenerator? _palette;
  String? _lastPosterUrl;

  void _updateColorScheme(String? posterUrl, Brightness brightness) {
    if (posterUrl == null || posterUrl == _lastPosterUrl) return;
    _lastPosterUrl = posterUrl;

    PaletteGenerator.fromImageProvider(
      atriumImageProvider(posterUrl, maxWidth: 200, maxHeight: 300),
      size: const Size(200, 300),
    ).then((PaletteGenerator palette) {
      if (mounted) {
        setState(() {
          _palette = palette;
        });
      }
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<ActiveSession>> sessionsAsync =
        ref.watch(jellyfinFastSessionsProvider(widget.instance));
    final ActiveSession session = sessionsAsync.value?.firstWhereOrNull(
          (ActiveSession s) => s.id == widget.initialSession.id,
        ) ??
        widget.initialSession;

    final String? posterUrl = session.posterUrl;

    ThemeData theme = Theme.of(context);
    _updateColorScheme(posterUrl, theme.brightness);
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
          errorContainer: vibrant,
          onErrorContainer: _palette!.vibrantColor?.titleTextColor ??
              theme.colorScheme.onPrimary,
          surface: dominant,
          onSurface: titleText,
          onSurfaceVariant: bodyText,
          surfaceContainer: muted,
          surfaceContainerHighest: muted,
        ),
      );
    }

    final double pct =
        _isDragging ? _dragPct : (session.progressPercent / 100.0);
    final bool playing = session.status == 'Playing';

    return Theme(
      data: theme,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down, size: 32),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Column(
            children: <Widget>[
              Text(
                'STREAMING ON',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70,
                ),
              ),
              Text(
                session.device,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          centerTitle: true,
        ),
        body: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // Background blurred image
            if (session.posterUrl != null)
              Image(
                image: atriumImageProvider(session.posterUrl!),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Container(color: theme.colorScheme.surface),
              ),
            // Blur and gradient overlay
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
            // Content
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    // Volume Control
                    Row(
                      children: <Widget>[
                        IconButton(
                          icon: Icon(
                            session.isMuted || session.volumeLevel == 0
                                ? Icons.volume_off
                                : Icons.volume_up,
                            color: theme.colorScheme.primary,
                          ),
                          onPressed: () async {
                            final ScaffoldMessengerState messenger =
                                ScaffoldMessenger.of(context);
                            try {
                              final JellyfinClient client = await ref.read(
                                jellyfinClientProvider(widget.instance).future,
                              );
                              await client.toggleMute(session.id);
                              if (mounted) {
                                ref.invalidate(
                                  jellyfinFastSessionsProvider(widget.instance),
                                );
                              }
                            } catch (_) {
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Action failed')),
                              );
                            }
                          },
                        ),
                        Expanded(
                          child: SliderTheme(
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
                              value: _isVolumeDragging
                                  ? _volumeDragPct
                                  : (session.volumeLevel / 100.0)
                                      .clamp(0.0, 1.0),
                              onChangeStart: (double val) {
                                setState(() {
                                  _isVolumeDragging = true;
                                  _volumeDragPct = val;
                                });
                              },
                              onChanged: (double val) {
                                setState(() {
                                  _volumeDragPct = val;
                                });
                              },
                              onChangeEnd: (double val) async {
                                setState(() {
                                  _isVolumeDragging = false;
                                });
                                final int targetVol = (val * 100).round();
                                final ScaffoldMessengerState messenger =
                                    ScaffoldMessenger.of(context);
                                try {
                                  final JellyfinClient client = await ref.read(
                                    jellyfinClientProvider(widget.instance)
                                        .future,
                                  );
                                  await client.setVolume(session.id, targetVol);
                                  if (mounted) {
                                    ref.invalidate(
                                      jellyfinFastSessionsProvider(
                                        widget.instance,
                                      ),
                                    );
                                  }
                                } catch (_) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Action failed'),
                                    ),
                                  );
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: Insets.md),
                      ],
                    ),

                    const Spacer(),

                    // Artwork with animated music bars
                    Flexible(
                      flex: 10,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          // Left animated music bars
                          AnimatedMusicBars(
                            color: theme.colorScheme.primary,
                            isPlaying: playing,
                          ),
                          const SizedBox(width: Insets.sm),
                          // Album art
                          Flexible(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 420,
                                maxWidth: 420,
                              ),
                              child: AspectRatio(
                                aspectRatio: session.aspectRatio != null &&
                                        session.aspectRatio! > 0.0
                                    ? session.aspectRatio!
                                    : (2 / 3),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme.surfaceContainerHighest,
                                    borderRadius: Radii.card,
                                    boxShadow: <BoxShadow>[
                                      BoxShadow(
                                        color:
                                            Colors.black.withValues(alpha: 0.4),
                                        blurRadius: 20,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                    image: session.posterUrl != null
                                        ? DecorationImage(
                                            image: atriumImageProvider(
                                              session.posterUrl!,
                                            ),
                                            fit: BoxFit.cover,
                                          )
                                        : null,
                                  ),
                                  child: session.posterUrl == null
                                      ? Icon(
                                          Icons.movie_outlined,
                                          color: theme.colorScheme.outline,
                                          size: 80,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: Insets.sm),
                          // Right animated music bars
                          AnimatedMusicBars(
                            color: theme.colorScheme.primary,
                            isPlaying: playing,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: Insets.lg),

                    // Track Info
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SizedBox(
                            height:
                                (theme.textTheme.titleLarge?.fontSize ?? 22) *
                                    1.5,
                            child: AutoScrollText(
                              text: session.showTitle,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (session.episodeName != null) ...<Widget>[
                            const SizedBox(height: Insets.xs),
                            SizedBox(
                              height: (theme.textTheme.titleMedium?.fontSize ??
                                      16) *
                                  1.5,
                              child: AutoScrollText(
                                text: session.episodeName!,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Progress Bar & Timestamps
                    Column(
                      children: <Widget>[
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 16,
                            activeTrackColor: theme.colorScheme.primary,
                            inactiveTrackColor:
                                theme.colorScheme.surfaceContainerHighest,
                            thumbColor: theme.colorScheme.primary,
                            thumbShape: const ExpressiveSliderThumbShape(),
                            trackShape: const ExpressiveSliderTrackShape(),
                            overlayShape: const RoundSliderOverlayShape(),
                          ),
                          child: Slider(
                            value: pct.clamp(0.0, 1.0),
                            onChangeStart: (_) => setState(() {
                              _isDragging = true;
                              _dragPct = pct;
                            }),
                            onChanged: (double newValue) {
                              setState(() {
                                _dragPct = newValue;
                              });
                            },
                            onChangeEnd: (double newValue) async {
                              setState(() => _isDragging = false);
                              if (session.durationTicks > 0) {
                                final int targetTicks =
                                    (session.durationTicks * newValue).round();
                                final ScaffoldMessengerState messenger =
                                    ScaffoldMessenger.of(context);
                                try {
                                  final JellyfinClient client = await ref.read(
                                    jellyfinClientProvider(widget.instance)
                                        .future,
                                  );
                                  await client.seekSession(
                                    session.id,
                                    targetTicks,
                                  );
                                  if (!mounted) return;
                                  ref.invalidate(
                                    jellyfinFastSessionsProvider(
                                      widget.instance,
                                    ),
                                  );
                                } catch (_) {
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Action failed'),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                          ), // Align with slider track
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Text(
                                session.timePosition,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                session.timeDuration,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: Insets.md),

                    // Row 1: 10s back, Play/Pause, 10s forward
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.15),
                              foregroundColor: theme.colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () async {
                              final ScaffoldMessengerState messenger =
                                  ScaffoldMessenger.of(context);
                              try {
                                final JellyfinClient client = await ref.read(
                                  jellyfinClientProvider(widget.instance)
                                      .future,
                                );
                                final int targetTicks =
                                    session.positionTicks - 10000000;
                                await client.seekSession(
                                  session.id,
                                  targetTicks < 0 ? 0 : targetTicks,
                                );
                                if (!mounted) return;
                                ref.invalidate(
                                  jellyfinFastSessionsProvider(widget.instance),
                                );
                              } catch (_) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Action failed'),
                                  ),
                                );
                              }
                            },
                            child: const Icon(Icons.replay_10, size: 32),
                          ),
                        ),
                        const SizedBox(width: Insets.lg),
                        SizedBox(
                          width: 120,
                          height: 80,
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
                            onPressed: () async {
                              final ScaffoldMessengerState messenger =
                                  ScaffoldMessenger.of(context);
                              try {
                                final JellyfinClient client = await ref.read(
                                  jellyfinClientProvider(widget.instance)
                                      .future,
                                );
                                await client.playPauseSession(session.id);
                                if (!mounted) return;
                                ref.invalidate(
                                  jellyfinFastSessionsProvider(widget.instance),
                                );
                              } catch (_) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Action failed'),
                                  ),
                                );
                              }
                            },
                            child: Icon(
                              playing ? Icons.pause : Icons.play_arrow,
                              size: 40,
                            ),
                          ),
                        ),
                        const SizedBox(width: Insets.lg),
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.15),
                              foregroundColor: theme.colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () async {
                              final ScaffoldMessengerState messenger =
                                  ScaffoldMessenger.of(context);
                              try {
                                final JellyfinClient client = await ref.read(
                                  jellyfinClientProvider(widget.instance)
                                      .future,
                                );
                                final int targetTicks =
                                    session.positionTicks + 10000000;
                                if (targetTicks < session.durationTicks) {
                                  await client.seekSession(
                                    session.id,
                                    targetTicks,
                                  );
                                }
                                if (!mounted) return;
                                ref.invalidate(
                                  jellyfinFastSessionsProvider(widget.instance),
                                );
                              } catch (_) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Action failed'),
                                  ),
                                );
                              }
                            },
                            child: const Icon(Icons.forward_10, size: 32),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: Insets.md),

                    // Row 2: Skip Previous, Stop, Skip Next
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.15),
                              foregroundColor: theme.colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () async {
                              final ScaffoldMessengerState messenger =
                                  ScaffoldMessenger.of(context);
                              try {
                                final JellyfinClient client = await ref.read(
                                  jellyfinClientProvider(widget.instance)
                                      .future,
                                );
                                if (session.positionTicks > 50000000) {
                                  await client.seekSession(session.id, 0);
                                } else {
                                  await client.previousTrack(session.id);
                                }
                                if (!mounted) return;
                                ref.invalidate(
                                  jellyfinFastSessionsProvider(widget.instance),
                                );
                              } catch (_) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Action failed'),
                                  ),
                                );
                              }
                            },
                            child: const Icon(Icons.skip_previous, size: 32),
                          ),
                        ),
                        const SizedBox(width: Insets.lg),
                        SizedBox(
                          width: 120,
                          height: 80,
                          child: FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              foregroundColor: theme.colorScheme.errorContainer,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(32),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () async {
                              final ScaffoldMessengerState messenger =
                                  ScaffoldMessenger.of(context);
                              final NavigatorState navigator =
                                  Navigator.of(context);
                              try {
                                final JellyfinClient client = await ref.read(
                                  jellyfinClientProvider(widget.instance)
                                      .future,
                                );
                                await client.stopSession(session.id);
                                if (!mounted) return;
                                ref.invalidate(
                                  jellyfinFastSessionsProvider(widget.instance),
                                );
                                navigator.pop();
                              } catch (_) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Action failed'),
                                  ),
                                );
                              }
                            },
                            child: const Icon(Icons.stop, size: 28),
                          ),
                        ),
                        const SizedBox(width: Insets.lg),
                        SizedBox(
                          width: 80,
                          height: 80,
                          child: FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.15),
                              foregroundColor: theme.colorScheme.primary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () async {
                              final ScaffoldMessengerState messenger =
                                  ScaffoldMessenger.of(context);
                              try {
                                final JellyfinClient client = await ref.read(
                                  jellyfinClientProvider(widget.instance)
                                      .future,
                                );
                                await client.nextTrack(session.id);
                                if (!mounted) return;
                                ref.invalidate(
                                  jellyfinFastSessionsProvider(widget.instance),
                                );
                              } catch (_) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('Action failed'),
                                  ),
                                );
                              }
                            },
                            child: const Icon(Icons.skip_next, size: 32),
                          ),
                        ),
                      ],
                    ),

                    const Spacer(),
                    const SizedBox(height: Insets.lg),

                    // Footer
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        // Device Chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                Icons.speaker,
                                size: 16,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                session.device,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // User Chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(
                                Icons.person,
                                size: 16,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                session.user,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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

class AutoScrollText extends StatefulWidget {
  const AutoScrollText({
    super.key,
    required this.text,
    this.style,
  });

  final String text;
  final TextStyle? style;

  @override
  State<AutoScrollText> createState() => _AutoScrollTextState();
}

class _AutoScrollTextState extends State<AutoScrollText> {
  late ScrollController _scrollController;
  bool _isScrolling = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndScroll());
  }

  @override
  void didUpdateWidget(AutoScrollText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _isScrolling = false;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      _checkAndScroll();
    }
  }

  void _checkAndScroll() async {
    if (!mounted) return;
    if (_scrollController.hasClients &&
        _scrollController.position.maxScrollExtent > 0) {
      if (_isScrolling) return;
      _isScrolling = true;
      _loopScroll();
    } else {
      // Keep checking if layout changes (e.g. text updates or bounds change)
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (mounted && !_isScrolling) _checkAndScroll();
    }
  }

  void _loopScroll() async {
    while (mounted && _isScrolling) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || !_scrollController.hasClients) break;

      final double maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent > 0) {
        final int durationMs = (maxExtent * 40).toInt().clamp(1000, 15000);
        await _scrollController.animateTo(
          maxExtent,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.linear,
        );
      }

      if (!mounted || !_scrollController.hasClients) break;
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted || !_scrollController.hasClients) break;

      final double currentExtent = _scrollController.position.maxScrollExtent;
      final int durationMs = (currentExtent * 40).toInt().clamp(1000, 15000);
      await _scrollController.animateTo(
        0,
        duration: Duration(milliseconds: durationMs),
        curve: Curves.linear,
      );
    }
  }

  @override
  void dispose() {
    _isScrolling = false;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      child: Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
      ),
    );
  }
}

/// Animated equalizer-style music bars that bounce while playing.
class AnimatedMusicBars extends StatefulWidget {
  const AnimatedMusicBars({
    super.key,
    required this.color,
    this.barCount = 4,
    this.barWidth = 5,
    this.height = 60,
    this.isPlaying = true,
  });

  final Color color;
  final int barCount;
  final double barWidth;
  final double height;
  final bool isPlaying;

  @override
  State<AnimatedMusicBars> createState() => _AnimatedMusicBarsState();
}

class _AnimatedMusicBarsState extends State<AnimatedMusicBars>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _controllers = List<AnimationController>.generate(
      widget.barCount,
      (int i) {
        final int durationMs = 400 + _random.nextInt(400);
        return AnimationController(
          vsync: this,
          duration: Duration(milliseconds: durationMs),
        );
      },
    );

    _animations = _controllers.map((AnimationController controller) {
      return Tween<double>(begin: 0.2, end: 1.0).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    if (widget.isPlaying) {
      _startAnimations();
    }
  }

  void _startAnimations() {
    for (int i = 0; i < _controllers.length; i++) {
      Future<void>.delayed(Duration(milliseconds: _random.nextInt(300)), () {
        if (mounted && widget.isPlaying) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  void _stopAnimations() {
    for (final AnimationController controller in _controllers) {
      controller.animateTo(0.3, duration: const Duration(milliseconds: 300));
    }
  }

  @override
  void didUpdateWidget(AnimatedMusicBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying != oldWidget.isPlaying) {
      if (widget.isPlaying) {
        _startAnimations();
      } else {
        _stopAnimations();
      }
    }
  }

  @override
  void dispose() {
    for (final AnimationController controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: (widget.barWidth + 3) * widget.barCount,
      height: widget.height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List<Widget>.generate(widget.barCount, (int i) {
          return AnimatedBuilder(
            animation: _animations[i],
            builder: (BuildContext context, Widget? child) {
              return Container(
                width: widget.barWidth,
                height: widget.height * _animations[i].value,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(widget.barWidth / 2),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
