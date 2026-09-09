import 'dart:async';

import 'package:collection/collection.dart';
import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_router/core_router.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../dashboard/dashboard_board.dart';
import '../health_providers.dart';
import 'reorder_sidebar_screen.dart';

/// Home screen. Services live in the navigation drawer (the sidebar); the
/// dashboard body is the at-a-glance widget board. Until a service exists,
/// the body onboards the user to add their first one.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Instance> instances = ref.watch(activeInstancesProvider);
    final Profile? profile = ref.watch(activeProfileProvider);

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (BuildContext context) {
            return IconButton(
              icon: const Icon(Icons.menu),
              onPressed: () {
                openDrawer(context);
              },
            );
          },
        ),
        title: Text(profile == null ? 'Atrium' : profile.name),
        actions: <Widget>[
          if (instances.isNotEmpty)
            Consumer(
              builder: (BuildContext context, WidgetRef ref, Widget? _) {
                final bool editing = ref.watch(dashboardEditModeProvider);
                return IconButton(
                  tooltip: editing ? 'Done' : 'Customize dashboard',
                  icon: Icon(editing ? Icons.check : Icons.tune),
                  onPressed: () => ref
                      .read(dashboardEditModeProvider.notifier)
                      .update((bool v) => !v),
                );
              },
            ),
        ],
      ),
      body: instances.isEmpty
          ? EmptyView(
              icon: Icons.dns_outlined,
              title: 'No services yet',
              message:
                  'Add your first service - a Sonarr, qBittorrent, Jellyfin, '
                  'anything in your stack.',
              action: FilledButton.icon(
                onPressed: () => context.goNamed(AtriumRoutes.addInstanceName),
                icon: const Icon(Icons.add),
                label: const Text('Add service'),
              ),
            )
          : const DashboardBoard(),
    );
  }
}

/// The sidebar: configured services grouped by role (each with a live health
/// dot), with settings, add-service and the active-profile pill along the
/// bottom.
class ServicesDrawer extends ConsumerStatefulWidget {
  const ServicesDrawer({
    required this.instances,
    required this.profile,
    super.key,
  });

  final List<Instance> instances;
  final Profile? profile;

  @override
  ConsumerState<ServicesDrawer> createState() => _ServicesDrawerState();
}

class _ServicesDrawerState extends ConsumerState<ServicesDrawer> {
  Timer? _pollingTimer;
  Future<void>? _activeRefreshFuture;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _checkHealthFreshness();
      _startPolling();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final AppLifecycleState? state =
          SchedulerBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) {
        _refreshHealth();
      }
    });
  }

  void _checkHealthFreshness() {
    final DateTime? lastCheck = ref.read(lastHealthRefreshProvider);
    if (lastCheck == null ||
        DateTime.now().difference(lastCheck) > const Duration(seconds: 60)) {
      _refreshHealth();
    }
  }

  Future<void> _refreshHealth() {
    if (_activeRefreshFuture != null) {
      return _activeRefreshFuture!;
    }
    if (widget.instances.isEmpty || !mounted) {
      return Future<void>.value();
    }
    final AppLifecycleState? state =
        SchedulerBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) {
      return Future<void>.value();
    }

    ref.read(lastHealthRefreshProvider.notifier).markRefreshed();
    final Future<void> future = Future.wait(
      widget.instances.map(
        (Instance i) => ref.refresh(instanceHealthProvider(i.id).future),
      ),
    ).then((_) {}).catchError((_) {}).whenComplete(() {
      _activeRefreshFuture = null;
    });

    _activeRefreshFuture = future;
    return future;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final List<Profile> profiles =
        ref.watch(profileListProvider).value ?? <Profile>[];

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              onTap: () {
                final GoRouter router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.go(AtriumRoutes.dashboard);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Insets.lg,
                  vertical: Insets.md,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.dns_rounded, color: cs.primary, size: 28),
                    const SizedBox(width: Insets.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Atrium',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Dashboard',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.instances.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(Insets.lg),
                        child: Text(
                          'No services yet.\nAdd one with the + below.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : _ServicesList(
                      instances: widget.instances,
                      onRefresh: _refreshHealth,
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(Insets.md),
              child: Row(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Settings',
                    icon: Icon(Icons.settings, color: cs.onSurfaceVariant),
                    onPressed: () => _navTo(context, AtriumRoutes.settingsName),
                  ),
                  IconButton(
                    tooltip: 'Add service',
                    icon: Icon(Icons.add, color: cs.onSurfaceVariant),
                    onPressed: () =>
                        _navTo(context, AtriumRoutes.addInstanceName),
                  ),
                  if (widget.instances.isNotEmpty)
                    IconButton(
                      tooltip: 'Reorder sidebar',
                      icon: Icon(Icons.reorder, color: cs.onSurfaceVariant),
                      onPressed: () {
                        // Capture the navigator before closing the drawer, then
                        // push over the root so the reorder screen covers the
                        // bottom nav bar.
                        final NavigatorState nav = Navigator.of(context);
                        nav.pop();
                        nav.push(MaterialPageRoute<void>(
                          builder: (_) => const ReorderSidebarScreen(),
                        ));
                      },
                    ),
                  const SizedBox(width: Insets.xs),
                  Expanded(
                    child: Builder(
                      builder: (BuildContext pillContext) {
                        return _ProfilePill(
                          label: widget.profile?.name ?? 'Default',
                          onTap: () async {
                            final RenderBox button =
                                pillContext.findRenderObject()! as RenderBox;
                            final RenderBox overlay =
                                Navigator.of(context, rootNavigator: true)
                                    .overlay!
                                    .context
                                    .findRenderObject()! as RenderBox;
                            final RelativeRect position = RelativeRect.fromRect(
                              Rect.fromPoints(
                                button.localToGlobal(const Offset(0, -100),
                                    ancestor: overlay),
                                button.localToGlobal(
                                    button.size.bottomRight(Offset.zero),
                                    ancestor: overlay),
                              ),
                              Offset.zero & overlay.size,
                            );

                            final String? selected = await showMenu<String>(
                              context: context,
                              useRootNavigator: true,
                              position: position,
                              items: <PopupMenuEntry<String>>[
                                for (final Profile p in profiles)
                                  PopupMenuItem<String>(
                                    value: p.id,
                                    child: Row(
                                      children: <Widget>[
                                        Icon(
                                          Icons.smartphone,
                                          size: 16,
                                          color: p.id == widget.profile?.id
                                              ? cs.primary
                                              : cs.outline,
                                        ),
                                        const SizedBox(width: Insets.sm),
                                        Expanded(
                                          child: Text(
                                            p.name,
                                            style: TextStyle(
                                              fontWeight: p.id == widget.profile?.id
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ),
                                        if (p.id == widget.profile?.id)
                                          Icon(
                                            Icons.check,
                                            size: 16,
                                            color: cs.primary,
                                          ),
                                      ],
                                    ),
                                  ),
                                const PopupMenuDivider(),
                                const PopupMenuItem<String>(
                                  value: 'manage',
                                  child: Row(
                                    children: <Widget>[
                                      Icon(Icons.manage_accounts_outlined,
                                          size: 16),
                                      SizedBox(width: Insets.sm),
                                      Text('Manage profiles'),
                                    ],
                                  ),
                                ),
                              ],
                            );

                            if (selected != null && pillContext.mounted) {
                              if (selected == 'manage') {
                                _navTo(pillContext, AtriumRoutes.profilesName);
                              } else {
                                // Capture before the await: switching profiles
                                // rebuilds the tree under this context.
                                final GoRouter router =
                                    GoRouter.of(pillContext);
                                final ScaffoldState? scaffold =
                                    Scaffold.maybeOf(pillContext);
                                await ref
                                    .read(activeProfileIdProvider.notifier)
                                    .select(selected);
                                // Switch succeeded: close the drawer if still
                                // open and land on the dashboard so the user
                                // never sees a NotFound service screen from
                                // the old profile.
                                if (scaffold != null &&
                                    scaffold.mounted &&
                                    scaffold.isDrawerOpen) {
                                  scaffold.closeDrawer();
                                }
                                router.go(AtriumRoutes.dashboard);
                              }
                            }
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Capture the router before closing the drawer (popping invalidates the
  /// drawer's own context for navigation).
  static void _navTo(BuildContext context, String routeName) {
    final GoRouter router = GoRouter.of(context);
    Navigator.of(context).pop();
    router.goNamed(routeName);
  }
}

class _ServicesList extends StatelessWidget {
  const _ServicesList({
    required this.instances,
    required this.onRefresh,
  });

  final List<Instance> instances;
  final RefreshCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    // Group by role, preserving the ServiceRole enum order.
    final Map<ServiceRole, List<Instance>> byRole =
        groupBy<Instance, ServiceRole>(
      instances,
      (Instance i) => i.kind.role,
    );

    final List<_SidebarItem> items = <_SidebarItem>[];
    for (final ServiceRole role in ServiceRole.values) {
      final List<Instance>? group = byRole[role];
      if (group != null && group.isNotEmpty) {
        items.add(_SidebarItem.header(role));
        for (final Instance inst in group) {
          items.add(_SidebarItem.tile(inst));
        }
      }
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(Insets.sm),
        itemCount: items.length,
        itemBuilder: (BuildContext context, int index) {
          final _SidebarItem item = items[index];
          if (item.header != null) {
            return Padding(
              padding: const EdgeInsets.only(
                top: Insets.md,
                bottom: Insets.xs,
                left: Insets.sm,
              ),
              child: Text(
                ServiceVisuals.roleLabel(item.header!),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: Insets.xs),
            child: RepaintBoundary(
              child: _HealthAwareTile(instance: item.tile!),
            ),
          );
        },
      ),
    );
  }
}

class _SidebarItem {
  const _SidebarItem.header(this.header) : tile = null;
  const _SidebarItem.tile(this.tile) : header = null;

  final ServiceRole? header;
  final Instance? tile;
}

/// A [ServiceTile] whose health dot reflects a live probe. Tapping closes the
/// drawer and opens the service.
class _HealthAwareTile extends ConsumerWidget {
  const _HealthAwareTile({required this.instance});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Health> asyncHealth =
        ref.watch(instanceHealthProvider(instance.id));
    final Health health = asyncHealth.value ?? Health.unknown;
    return ServiceTile(
      instance: instance,
      health: health,
      onTap: () {
        final GoRouter router = GoRouter.of(context);
        Navigator.of(context).pop();
        router.go(AtriumRoutes.servicePath(instance.kind.name, instance.id));
      },
      onLongPress: () {
        showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (BuildContext sheetContext) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.open_in_new),
                    title: const Text('Open service'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      final GoRouter router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      router.go(
                        AtriumRoutes.servicePath(
                          instance.kind.name,
                          instance.id,
                        ),
                      );
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit),
                    title: const Text('Edit connection settings'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      final GoRouter router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      router.goNamed(
                        AtriumRoutes.editInstanceName,
                        pathParameters: <String, String>{
                          'instanceId': instance.id,
                        },
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Bottom pill showing the active profile; opens profile management.
class _ProfilePill extends StatelessWidget {
  const _ProfilePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: 8,
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.smartphone, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.unfold_more,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
