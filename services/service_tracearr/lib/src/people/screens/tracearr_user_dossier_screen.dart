import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/tracearr_providers.dart';
import 'widgets/user_genre_breakdown_card.dart';
import 'widgets/user_linked_accounts_card.dart';
import 'widgets/user_recent_history_feed.dart';

/// Deep user dossier and viewing habits screen for Tracearr in Atrium.
class TracearrUserDossierScreen extends ConsumerWidget {
  const TracearrUserDossierScreen({
    required this.instance,
    required this.userId,
    required this.username,
    this.initialAvatarUrl,
    super.key,
  });

  final Instance instance;
  final String userId;
  final String username;
  final String? initialAvatarUrl;

  static Future<void> navigate(
    BuildContext context, {
    required Instance instance,
    required String userId,
    required String username,
    String? initialAvatarUrl,
  }) {
    return pushScreen<void>(
      context,
      TracearrUserDossierScreen(
        instance: instance,
        userId: userId,
        username: username,
        initialAvatarUrl: initialAvatarUrl,
      ),
    );
  }

  String _formatWatchTime(int ms) {
    if (ms <= 0) return '0h';
    final double hours = ms / (1000 * 60 * 60);
    return '${hours.toStringAsFixed(1)}h';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final detailAsync =
        ref.watch(tracearrUserDetailProvider((instance, userId)));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          '@$username',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: ExpressiveProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_off_outlined,
                    size: 48, color: colorScheme.error,),
                const SizedBox(height: Insets.md),
                Text(
                  'Failed to load user profile',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: Insets.sm),
                Text(
                  err.toString(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Insets.md),
                FilledButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  onPressed: () => ref.invalidate(
                    tracearrUserDetailProvider((instance, userId)),
                  ),
                ),
              ],
            ),
          ),
        ),
        data: (detail) {
          final avatar = initialAvatarUrl;

          return ListView(
            padding: const EdgeInsets.symmetric(
              horizontal: Insets.lg,
              vertical: Insets.md,
            ),
            children: [
              // 1. User Header Identity Card
              Container(
                padding: const EdgeInsets.all(Insets.lg),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundColor: colorScheme.primaryContainer,
                      child: avatar != null && avatar.isNotEmpty
                          ? ClipOval(
                              child: AtriumNetworkImage(
                                imageUrl: avatar,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorWidget: (c, u, e) => Text(
                                  detail.username.isNotEmpty
                                      ? detail.username[0].toUpperCase()
                                      : 'U',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              detail.username.isNotEmpty
                                  ? detail.username[0].toUpperCase()
                                  : 'U',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '@${detail.username}',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (detail.email != null &&
                              detail.email!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              detail.email!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                          if (detail.plexAccountId != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Plex Account ID: ${detail.plexAccountId}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.lg),

              // 2. Lifetime Telemetry Stats Grid
              Container(
                padding: const EdgeInsets.all(Insets.md),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    _UserStatTile(
                      label: 'TOTAL PLAYS',
                      value: '${detail.allTimePlays}',
                      color: colorScheme.primary,
                    ),
                    _UserStatTile(
                      label: 'WATCH TIME',
                      value: _formatWatchTime(detail.allTimeWatchTimeMs),
                      color: const Color(0xFF4CAF50),
                    ),
                    _UserStatTile(
                      label: '30D PLAYS',
                      value: '${detail.last30DaysPlays}',
                      color: const Color(0xFF2196F3),
                    ),
                    _UserStatTile(
                      label: '7D PLAYS',
                      value: '${detail.last7DaysPlays}',
                      color: const Color(0xFFFF9800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: Insets.lg),

              // 3. Linked Server Accounts Matrix
              if (detail.accounts.isNotEmpty) ...[
                UserLinkedAccountsCard(
                  accounts: detail.accounts,
                ),
                const SizedBox(height: Insets.lg),
              ],

              // 4. Top Genres & Viewing Habits
              if (detail.topGenres.isNotEmpty) ...[
                UserGenreBreakdownCard(
                  topGenres: detail.topGenres,
                ),
                const SizedBox(height: Insets.lg),
              ],

              // 5. Recent Watch Sessions Feed
              if (detail.recentHistory.isNotEmpty) ...[
                UserRecentHistoryFeed(
                  recentHistory: detail.recentHistory,
                  instance: instance,
                ),
                const SizedBox(height: Insets.xl),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _UserStatTile extends StatelessWidget {
  const _UserStatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 9,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
