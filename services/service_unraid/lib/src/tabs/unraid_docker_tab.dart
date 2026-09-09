import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/unraid_models.dart';
import '../unraid_client.dart';
import '../unraid_providers.dart';
import '../widgets/unraid_common.dart';
import '../widgets/unraid_container_sheet.dart';

enum _DockerFilter { all, running, stopped, issues }

class _DockerBody extends StatefulWidget {
  const _DockerBody({required this.containers, required this.instance});

  final List<UnraidContainer> containers;
  final Instance instance;

  @override
  State<_DockerBody> createState() => _DockerBodyState();
}

class _DockerBodyState extends State<_DockerBody> {
  _DockerFilter _filter = _DockerFilter.all;

  List<UnraidContainer> _apply(_DockerFilter filter) {
    return switch (filter) {
      _DockerFilter.all => widget.containers,
      _DockerFilter.running =>
        widget.containers.where((UnraidContainer c) => c.isRunning).toList(),
      _DockerFilter.stopped =>
        widget.containers.where((UnraidContainer c) => c.isStopped).toList(),
      _DockerFilter.issues =>
        widget.containers.where((UnraidContainer c) => c.isUnhealthy).toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final List<UnraidContainer> all = widget.containers;

    if (all.isEmpty) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UnraidSectionHeader(title: 'Docker'),
          SizedBox(height: Insets.sm),
          EmptyView(
            title: 'No containers',
            message: 'This server is not running any Docker containers.',
          ),
        ],
      );
    }

    final int running = _apply(_DockerFilter.running).length;
    final int issues = _apply(_DockerFilter.issues).length;
    // A filter that would show nothing is worse than no filter: keep the chip
    // out of the row rather than offering an empty result.
    final List<_DockerFilter> available = <_DockerFilter>[
      _DockerFilter.all,
      if (running > 0) _DockerFilter.running,
      if (running < all.length) _DockerFilter.stopped,
      if (issues > 0) _DockerFilter.issues,
    ];
    final List<UnraidContainer> shown = _apply(_filter);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        UnraidSectionHeader(
          title: 'Docker',
          trailing: '$running of ${all.length} running',
        ),
        if (available.length > 1) ...<Widget>[
          const SizedBox(height: Insets.md),
          Wrap(
            spacing: Insets.sm,
            runSpacing: Insets.sm,
            children: <Widget>[
              for (final _DockerFilter f in available)
                FilterChip(
                  label: Text(_filterLabel(f, all.length, running, issues)),
                  selected: _filter == f,
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _filter = f),
                ),
            ],
          ),
        ],
        const SizedBox(height: Insets.md),
        _ContainerGroup(containers: shown, instance: widget.instance),
      ],
    );
  }

  String _filterLabel(_DockerFilter f, int total, int running, int issues) =>
      switch (f) {
        _DockerFilter.all => 'All $total',
        _DockerFilter.running => 'Running $running',
        _DockerFilter.stopped => 'Stopped ${total - running}',
        _DockerFilter.issues => 'Issues $issues',
      };
}

class _ContainerGroup extends StatelessWidget {
  const _ContainerGroup({required this.containers, required this.instance});

  final List<UnraidContainer> containers;
  final Instance instance;

  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;

    // Anything failing a healthcheck first, then what is up, then by name, so
    // the thing that needs a person is never buried.
    final List<UnraidContainer> sorted = <UnraidContainer>[...containers]
      ..sort((UnraidContainer a, UnraidContainer b) {
        if (a.isUnhealthy != b.isUnhealthy) return a.isUnhealthy ? -1 : 1;
        if (a.isRunning != b.isRunning) return a.isRunning ? -1 : 1;
        return a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            );
      });

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        children: <Widget>[
          for (int i = 0; i < sorted.length; i++) ...<Widget>[
            if (i > 0)
              Divider(height: 1, indent: Insets.lg, color: cs.outlineVariant),
            _ContainerRow(container: sorted[i], instance: instance),
          ],
        ],
      ),
    );
  }
}

class _ContainerRow extends ConsumerStatefulWidget {
  const _ContainerRow({required this.container, required this.instance});

  final UnraidContainer container;
  final Instance instance;

  @override
  ConsumerState<_ContainerRow> createState() => _ContainerRowState();
}

class _ContainerRowState extends ConsumerState<_ContainerRow> {
  bool _busy = false;

  /// Runs one lifecycle action and refreshes the list.
  ///
  /// The reason a refusal gives is shown as it comes: an API key without the
  /// Docker permission is an ordinary way to have this set up, and "Action
  /// failed" would leave nothing to act on.
  Future<void> _run(
    Future<UnraidContainer> Function(UnraidClient client) action,
  ) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final UnraidClient client =
          await ref.read(unraidClientProvider(widget.instance).future);
      await action(client);
      if (!mounted) return;
      ref.invalidate(unraidContainersProvider(widget.instance));
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e is NetworkException ? e.message : 'Action failed.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final UnraidContainer c = widget.container;

    // A failing healthcheck still reports RUNNING, so state alone would show
    // it as fine. It gets its own icon rather than only its own colour, which
    // a red-green colour blind eye would miss.
    final (IconData icon, Color color) = c.isUnhealthy
        ? (Icons.warning_amber_rounded, cs.error)
        : c.isPaused
            ? (Icons.pause_rounded, cs.tertiary)
            : c.isRunning
                ? (Icons.play_arrow_rounded, unraidOkGreen(cs))
                : (Icons.stop_rounded, cs.outline);

    final String? ports = c.publishedPortsLabel;
    final String subtitle =
        c.status ?? (c.isRunning ? 'Running' : 'Stopped');

    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.lg,
        vertical: Insets.md,
      ),
      child: Row(
        children: <Widget>[
          _ContainerAvatar(container: c, icon: icon, color: color),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        c.displayName,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (c.isUpdateAvailable == true) ...<Widget>[
                      const SizedBox(width: Insets.xs),
                      Tooltip(
                        message: 'Update available',
                        child: Icon(
                          Icons.arrow_circle_up_rounded,
                          size: 16,
                          color: cs.primary,
                        ),
                      ),
                    ],
                    // Says the row goes somewhere. Without it, tapping to open
                    // the container's web interface is not discoverable at all.
                    if ((c.webUiUrl ?? '').isNotEmpty) ...<Widget>[
                      const SizedBox(width: Insets.xs),
                      Icon(
                        Icons.open_in_new_rounded,
                        size: 13,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Insets.xxs),
                Text(
                  ports == null ? subtitle : '$subtitle  -  $ports',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: c.isUnhealthy ? cs.error : cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (c.autoStart) ...<Widget>[
            const SizedBox(width: Insets.sm),
            Tooltip(
              message: 'Starts with the array',
              child: Icon(Icons.bolt, size: 18, color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(width: Insets.xs),
          _busy
              ? const SizedBox(
                  width: 40,
                  height: 40,
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              : IconButton(
                  // A paused container is offered a resume rather than a
                  // stop: stopping it would throw away the state pausing it
                  // was meant to keep.
                  icon: Icon(
                    c.isRunning
                        ? Icons.stop_rounded
                        : Icons.play_arrow_rounded,
                  ),
                  tooltip: c.isRunning
                      ? 'Stop'
                      : c.isPaused
                          ? 'Resume'
                          : 'Start',
                  onPressed: () => _run(
                    (UnraidClient client) => switch (c.state) {
                      'RUNNING' => client.stopContainer(c.id),
                      'PAUSED' => client.unpauseContainer(c.id),
                      _ => client.startContainer(c.id),
                    },
                  ),
                ),
        ],
      ),
    );

    // Every row opens now, not just the ones with a web interface: the sheet
    // carries the rest of what a container has to say, and the quick action
    // stays on the row so the common case needs no detour.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => showUnraidContainerSheet(
          context,
          instance: widget.instance,
          container: c,
        ),
        child: row,
      ),
    );
  }
}

/// The container's own icon when its Unraid template names one, and the state
/// glyph when it does not.
///
/// A container created outside the web UI has no template and so no icon,
/// which is common enough that it cannot be treated as an error.
class _ContainerAvatar extends StatelessWidget {
  const _ContainerAvatar({
    required this.container,
    required this.icon,
    required this.color,
  });

  final UnraidContainer container;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final String? url = container.iconUrl;

    final Widget fallback = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: 20, color: color),
    );

    if (url == null || url.isEmpty) return fallback;

    return Stack(
      alignment: Alignment.bottomRight,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(Radii.sm),
          child: Image.network(
            url,
            headers: ArtworkHeaders.forUrl(url),
            width: 36,
            height: 36,
            fit: BoxFit.cover,
            // A broken or unreachable icon is not worth an error state; the
            // glyph says everything the row actually needs to.
            errorBuilder: (_, __, ___) => fallback,
            frameBuilder: (
              BuildContext context,
              Widget child,
              int? frame,
              bool wasSynchronouslyLoaded,
            ) =>
                wasSynchronouslyLoaded || frame != null ? child : fallback,
          ),
        ),
        // The state still has to be readable at a glance once the icon takes
        // the place the state glyph used to hold.
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              width: 2,
            ),
          ),
        ),
      ],
    );
  }
}

/// Every container the server knows about.
class UnraidDockerTab extends ConsumerWidget {
  const UnraidDockerTab({required this.instance, super.key});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<UnraidContainer>> containers =
        ref.watch(unraidContainersProvider(instance));

    return UnraidTabScaffold(
      onRefresh: () => ref.invalidate(unraidContainersProvider(instance)),
      children: <Widget>[
        AsyncValueView<List<UnraidContainer>>(
          value: containers,
          onRetry: () => ref.invalidate(unraidContainersProvider(instance)),
          loading: const UnraidCardPlaceholder(height: 160),
          data: (List<UnraidContainer> value) =>
              _DockerBody(containers: value, instance: instance),
        ),
      ],
    );
  }
}
