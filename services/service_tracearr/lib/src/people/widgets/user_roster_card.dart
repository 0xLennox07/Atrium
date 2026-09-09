import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/tracearr_models.dart';
import '../../providers/tracearr_providers.dart';
import '../screens/tracearr_user_dossier_screen.dart';

/// Interactive card in the People fleet directory representing a user with live streaming indicator.
class UserRosterCard extends ConsumerWidget {
  const UserRosterCard({
    required this.instance,
    required this.user,
    super.key,
  });

  final Instance instance;
  final TracearrUserSummary user;

  String _formatWatchTime(int ms) {
    if (ms <= 0) return '0h';
    final double hours = ms / (1000 * 60 * 60);
    return '${hours.toStringAsFixed(1)}h';
  }

  String _formatLastActive(DateTime? dt) {
    if (dt == null) return 'Never active';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final avatarUrl = user.avatarUrl;
    final lastActiveStr = _formatLastActive(user.lastActiveAt);

    final streamsAsync = ref.watch(tracearrStreamsProvider(instance));
    final bool isWatching = streamsAsync.value?.any(
          (s) => s.userUsername.toLowerCase() == user.username.toLowerCase(),
        ) ??
        false;

    return InkWell(
      borderRadius: BorderRadius.circular(Radii.md),
      onTap: () {
        TracearrUserDossierScreen.navigate(
          context,
          instance: instance,
          userId: user.id,
          username: user.username,
          initialAvatarUrl: avatarUrl,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(Insets.md),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: isWatching
                ? const Color(0xFF4CAF50).withValues(alpha: 0.5)
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: isWatching ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            // User Avatar Thumbnail
            CircleAvatar(
              radius: 22,
              backgroundColor: colorScheme.primaryContainer,
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? ClipOval(
                      child: AtriumNetworkImage(
                        imageUrl: avatarUrl,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorWidget: (c, u, e) => Text(
                          user.username.isNotEmpty
                              ? user.username[0].toUpperCase()
                              : 'U',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    )
                  : Text(
                      user.username.isNotEmpty
                          ? user.username[0].toUpperCase()
                          : 'U',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
            ),
            const SizedBox(width: Insets.md),

            // User Identity & Accounts
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '@${user.username}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isWatching) ...[
                        const SizedBox(width: Insets.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF4CAF50).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(Radii.sm),
                            border: Border.all(
                              color: const Color(0xFF4CAF50)
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.play_circle_fill,
                                size: 9,
                                color: Color(0xFF4CAF50),
                              ),
                              SizedBox(width: 2),
                              Text(
                                'WATCHING',
                                style: TextStyle(
                                  color: Color(0xFF4CAF50),
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (user.accounts.isNotEmpty) ...[
                        const SizedBox(width: Insets.xs),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(Radii.sm),
                          ),
                          child: Text(
                            '${user.accounts.length} ${user.accounts.length == 1 ? 'acct' : 'accts'}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (user.email != null && user.email!.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      user.email!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: Insets.xs),

                  // Telemetry Stats Row
                  Row(
                    children: [
                      Text(
                        '${user.allTimePlays} ${user.allTimePlays == 1 ? 'play' : 'plays'}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary,
                        ),
                      ),
                      Text(
                        ' • ${_formatWatchTime(user.allTimeWatchTimeMs)}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        ' • $lastActiveStr',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 20,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
