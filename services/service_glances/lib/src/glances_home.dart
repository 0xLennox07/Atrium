import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glances_providers.dart';
import 'models/glances_stats.dart';

class GlancesHome extends ConsumerWidget {
  const GlancesHome({required this.instance, super.key});

  final Instance instance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<GlancesStats> statsAsync = ref.watch(glancesStatsProvider(instance));

    return statsAsync.when(
      data: (GlancesStats stats) => RefreshIndicator(
        onRefresh: () async => ref.refresh(glancesStatsProvider(instance).future),
        child: ListView(
          padding: Insets.page,
          children: <Widget>[
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: Insets.md),
              shape: RoundedRectangleBorder(
                borderRadius: Radii.card,
                side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(Insets.md),
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.schedule_outlined, color: Color(0xFF3B82F6)),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: Text(
                        'System Uptime',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      _formatUptime(stats.uptime),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            _buildGauges(context, stats),
            const SizedBox(height: Insets.md),
            _buildCoresCard(context, stats.cpu),
            const SizedBox(height: Insets.md),
            _buildSectionHeader(context, 'Network', Icons.network_check_outlined),
            ...stats.network.map((GlancesNetwork n) => _buildNetworkCard(context, n)),
            const SizedBox(height: Insets.md),
            _buildSectionHeader(context, 'Disks', Icons.storage_outlined),
            ...stats.disks.map((GlancesDisk d) => _buildDiskCard(context, d)),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace st) => Center(
        child: Padding(
          padding: Insets.page,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: Insets.md),
              Text(
                'Failed to load stats',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: Insets.sm),
              Text(
                e.toString(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatUptime(GlancesUptime uptime) {
    final List<String> parts = <String>[];
    if (uptime.days > 0) parts.add('${uptime.days}d');
    if (uptime.hours > 0) parts.add('${uptime.hours}h');
    if (uptime.minutes > 0) parts.add('${uptime.minutes}m');
    parts.add('${uptime.seconds}s');
    return parts.join(' ');
  }

  Widget _buildSectionHeader(BuildContext context, String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: Insets.sm),
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildGauges(BuildContext context, GlancesStats stats) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: _GaugeCard(
                title: 'CPU',
                percent: stats.cpu.totalUsage / 100.0,
                subtitle: '${stats.cpu.packageTemp.toStringAsFixed(1)}°C',
                subtitleIcon: Icons.thermostat_outlined,
                icon: Icons.speed_outlined,
                color: const Color(0xFF10B981), // Emerald green
              ),
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: _GaugeCard(
                title: 'Memory',
                percent: stats.memory.percentage / 100.0,
                subtitle: '${(stats.memory.used / 1024 / 1024 / 1024).toStringAsFixed(2)} / ${(stats.memory.total / 1024 / 1024 / 1024).toStringAsFixed(2)} GB',
                subtitleIcon: Icons.data_usage_outlined,
                icon: Icons.memory_outlined,
                color: const Color(0xFF6366F1), // Indigo
              ),
            ),
          ],
        ),
        const SizedBox(height: Insets.sm),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: Radii.card,
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(Insets.md),
            child: Row(
              children: <Widget>[
                const Icon(Icons.swap_horiz_outlined, color: Color(0xFFF59E0B)),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Swap', style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: 6),
                      LinearProgressIndicator(
                        value: (stats.swap.percentage / 100.0).clamp(0.0, 1.0),
                        backgroundColor: const Color(0xFFF59E0B).withOpacity(0.15),
                        color: const Color(0xFFF59E0B),
                        minHeight: 6,
                        borderRadius: Radii.card,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: Insets.md),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: <Widget>[
                    Text(
                      '${stats.swap.percentage.toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      '${(stats.swap.used / 1024 / 1024 / 1024).toStringAsFixed(2)} / ${(stats.swap.total / 1024 / 1024 / 1024).toStringAsFixed(2)} GB',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoresCard(BuildContext context, GlancesCpu cpu) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: Insets.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.developer_board, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: Insets.sm),
                Text(
                  'Cores (${cpu.physicalCores} Phys, ${cpu.logicalCores} Log)',
                  style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: Insets.md),
            ...cpu.cores.map((GlancesCpuCore core) {
              return Padding(
                padding: const EdgeInsets.only(bottom: Insets.sm),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 60,
                      child: Text('Core ${core.id}', style: theme.textTheme.labelMedium),
                    ),
                    Expanded(
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(begin: 0.0, end: (core.usage / 100.0).clamp(0.0, 1.0)),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        builder: (BuildContext context, double value, Widget? child) {
                          return LinearProgressIndicator(
                            value: value,
                            backgroundColor: theme.colorScheme.onSurface.withOpacity(0.1),
                            color: theme.colorScheme.primary,
                            minHeight: 6,
                            borderRadius: Radii.card,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    SizedBox(
                      width: 50,
                      child: Text(
                        '${core.usage.toStringAsFixed(1)}%',
                        textAlign: TextAlign.end,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDiskCard(BuildContext context, GlancesDisk disk) {
    final double pct = disk.percentage / 100.0;
    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: Insets.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.dns_outlined, size: 20),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: Text(
                    disk.path,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Text(
                  '${disk.percentage.toStringAsFixed(1)}%',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: Insets.md),
            LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              color: pct > 0.9
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
              minHeight: 6,
              borderRadius: Radii.card,
            ),
            const SizedBox(height: Insets.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  '${(disk.used / 1024 / 1024 / 1024).toStringAsFixed(2)} GB used',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  '${(disk.total / 1024 / 1024 / 1024).toStringAsFixed(2)} GB total',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNetworkCard(BuildContext context, GlancesNetwork net) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: Insets.page,
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.router_outlined,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(net.interface, style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      Icon(Icons.arrow_upward, size: 14, color: theme.colorScheme.tertiary),
                      const SizedBox(width: 4),
                      Text(
                        '${_formatBytes(net.txSpeed)}/s',
                        style: theme.textTheme.labelMedium,
                      ),
                      const SizedBox(width: Insets.lg),
                      Icon(Icons.arrow_downward, size: 14, color: theme.colorScheme.primary),
                      const SizedBox(width: 4),
                      Text(
                        '${_formatBytes(net.rxSpeed)}/s',
                        style: theme.textTheme.labelMedium,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes > 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    } else if (bytes > 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}

class _GaugeCard extends StatelessWidget {
  const _GaugeCard({
    required this.title,
    required this.percent,
    required this.subtitle,
    this.subtitleIcon,
    required this.icon,
    required this.color,
  });

  final String title;
  final double percent;
  final String subtitle;
  final IconData? subtitleIcon;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: Radii.card,
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.lg, horizontal: Insets.md),
        child: Column(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(title, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: Insets.lg),
            Stack(
              alignment: Alignment.center,
              children: <Widget>[
                SizedBox(
                  width: 80,
                  height: 80,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0.0, end: percent.clamp(0.0, 1.0)),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (BuildContext context, double value, Widget? child) {
                      return CircularProgressIndicator(
                        value: value,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: color.withOpacity(0.15),
                        color: color,
                      );
                    },
                  ),
                ),
                Text(
                  '${(percent * 100).toStringAsFixed(0)}%',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: Insets.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (subtitleIcon != null) ...<Widget>[
                  Icon(
                    subtitleIcon,
                    size: 14,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(subtitle, style: Theme.of(context).textTheme.labelMedium),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
