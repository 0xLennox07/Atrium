import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/seerr_discover.dart';
import 'models/seerr_issue.dart';
import 'models/seerr_request.dart';
import 'seerr_api.dart';
import 'seerr_providers.dart';

/// Icon for a Seerr issue type (1 video, 2 audio, 3 subtitles, 4 other).
///
/// Shared vocabulary for the issues list, the issue detail screen, and the
/// report-issue sheet.
IconData seerrIssueTypeIcon(int issueType) {
  switch (issueType) {
    case 1:
      return Icons.videocam_outlined;
    case 2:
      return Icons.volume_up_outlined;
    case 3:
      return Icons.subtitles_outlined;
    default:
      return Icons.help_outline;
  }
}

/// Compact relative timestamp ('5m ago', '3d ago') for issue and comment
/// dates, falling back to a plain date once older than a month.
String seerrIssueRelativeTime(String? createdAt) {
  final DateTime? date =
      createdAt == null ? null : DateTime.tryParse(createdAt);
  if (date == null) {
    return '';
  }
  final DateTime local = date.toLocal();
  final Duration diff = DateTime.now().difference(local);
  if (diff.isNegative || diff.inMinutes < 1) {
    return 'just now';
  }
  if (diff.inMinutes < 60) {
    return '${diff.inMinutes}m ago';
  }
  if (diff.inHours < 24) {
    return '${diff.inHours}h ago';
  }
  if (diff.inDays < 30) {
    return '${diff.inDays}d ago';
  }
  final String m = local.month.toString().padLeft(2, '0');
  final String d = local.day.toString().padLeft(2, '0');
  return '${local.year}-$m-$d';
}

/// Display name for the user on an issue or comment.
String seerrIssueUserName(SeerrUser? user) {
  if (user == null) {
    return 'Unknown';
  }
  if (user.displayName.isNotEmpty) {
    return user.displayName;
  }
  return user.username.isNotEmpty ? user.username : 'Unknown';
}

/// Open / Resolved status pill in tonal M3 roles: error container while the
/// issue needs attention, secondary container once resolved.
class SeerrIssueStatusPill extends StatelessWidget {
  const SeerrIssueStatusPill({required this.isOpen, super.key});

  final bool isOpen;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final Color bg = isOpen ? cs.errorContainer : cs.secondaryContainer;
    final Color fg = isOpen ? cs.onErrorContainer : cs.onSecondaryContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            isOpen ? Icons.error_outline : Icons.check_circle_outline,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            isOpen ? 'Open' : 'Resolved',
            style: theme.textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Detail screen for one reported issue: the media header, a Resolve /
/// Reopen action, the comment thread, and an add-comment composer.
///
/// Progressive enhancement - the tapped [issue] renders immediately and is
/// swapped for the fresh copy (with the full comment thread) once
/// `seerrIssueDetailProvider` loads. Every write is try/caught with a
/// snackbar and invalidates both the detail and the issues-list providers.
class SeerrIssueDetailScreen extends ConsumerStatefulWidget {
  const SeerrIssueDetailScreen({
    required this.instance,
    required this.issue,
    super.key,
  });

  final Instance instance;
  final SeerrIssue issue;

  @override
  ConsumerState<SeerrIssueDetailScreen> createState() =>
      _SeerrIssueDetailScreenState();
}

class _SeerrIssueDetailScreenState
    extends ConsumerState<SeerrIssueDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  bool _sendingComment = false;
  bool _updatingStatus = false;

  SeerrIssueDetailArgs get _args =>
      (instance: widget.instance, id: widget.issue.id);

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  void _refreshIssue() {
    ref.invalidate(seerrIssueDetailProvider(_args));
    // The whole family: every filter's list shows the status/comment count.
    ref.invalidate(seerrIssuesProvider);
  }

  Future<void> _sendComment() async {
    final String message = _commentController.text.trim();
    if (message.isEmpty) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _sendingComment = true);
    try {
      final SeerrApi api =
          await ref.read(seerrApiProvider(widget.instance).future);
      await api.addIssueComment(widget.issue.id, message);
      if (!mounted) {
        return;
      }
      _commentController.clear();
      _refreshIssue();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not add comment: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _sendingComment = false);
      }
    }
  }

  Future<void> _setStatus({required bool resolved}) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() => _updatingStatus = true);
    try {
      final SeerrApi api =
          await ref.read(seerrApiProvider(widget.instance).future);
      await api.setIssueStatus(widget.issue.id, resolved: resolved);
      if (!mounted) {
        return;
      }
      _refreshIssue();
      messenger.showSnackBar(
        SnackBar(
          content: Text(resolved ? 'Issue resolved' : 'Issue reopened'),
        ),
      );
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not update issue: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _updatingStatus = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final SeerrIssue issue =
        ref.watch(seerrIssueDetailProvider(_args)).value ?? widget.issue;
    final List<SeerrIssueComment> comments = issue.comments;

    return Scaffold(
      appBar: AppBar(title: Text('Issue #${issue.id}')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: EasyRefresh(
          header: const ClassicHeader(
            dragText: 'Pull to refresh',
            armedText: 'Release ready',
            readyText: 'Refreshing...',
            processingText: 'Refreshing...',
            processedText: 'Succeeded',
            failedText: 'Failed',
            messageText: 'Last updated at %T',
          ),
                onRefresh: () async {
                  _refreshIssue();
                },
                child: ListView(
                  padding: Insets.page,
                  children: <Widget>[
                    _IssueHeader(instance: widget.instance, issue: issue),
                    const SizedBox(height: Insets.md),
                    SizedBox(
                      width: double.infinity,
                      child: issue.isOpen
                          ? FilledButton.tonalIcon(
                              onPressed: _updatingStatus
                                  ? null
                                  : () => _setStatus(resolved: true),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Resolve'),
                            )
                          : OutlinedButton.icon(
                              onPressed: _updatingStatus
                                  ? null
                                  : () => _setStatus(resolved: false),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Reopen'),
                            ),
                    ),
                    const SizedBox(height: Insets.lg),
                    Text(
                      'Comments',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: Insets.sm),
                    if (comments.isEmpty)
                      Text(
                        'No comments yet.',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.outline),
                      )
                    else
                      for (final SeerrIssueComment comment
                          in comments) ...<Widget>[
                        _CommentTile(comment: comment),
                        const SizedBox(height: Insets.sm),
                      ],
                  ],
                ),
              ),
            ),
            _buildComposer(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.sm,
        Insets.lg,
        Insets.lg,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _commentController,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Add a comment',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Insets.lg,
                  vertical: Insets.md,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Radii.xl),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: Insets.sm),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: _sendingComment ? null : _sendComment,
            icon: _sendingComment
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: ExpressiveProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
          ),
        ],
      ),
    );
  }
}

/// Tonal media header: poster (resolved from TMDB via the media-details
/// provider), title, status pill, issue type, reporter, and date.
class _IssueHeader extends ConsumerWidget {
  const _IssueHeader({required this.instance, required this.issue});

  final Instance instance;
  final SeerrIssue issue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    final SeerrMedia? media = issue.media;
    SeerrDiscoverResult? details;
    if (media != null && media.tmdbId != null && media.mediaType.isNotEmpty) {
      details = ref
          .watch(
            seerrMediaDetailsProvider(
              (
                instance: instance,
                mediaType: media.mediaType,
                tmdbId: media.tmdbId!,
              ),
            ),
          )
          .value;
    }
    final String title = details?.displayTitle ?? 'Issue #${issue.id}';
    final SeerrApi? api = ref.watch(seerrApiProvider(instance)).value;
    final String? posterUrl = api?.imageUrl(details?.posterPath);
    final String time = seerrIssueRelativeTime(issue.createdAt);

    return Container(
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.md),
            child: SizedBox(
              width: 72,
              height: 108,
              child: posterUrl != null
                  ? AtriumNetworkImage(
                      imageUrl: posterUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _posterFallback(cs),
                    )
                  : _posterFallback(cs),
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    SeerrIssueStatusPill(isOpen: issue.isOpen),
                  ],
                ),
                const SizedBox(height: Insets.sm),
                Row(
                  children: <Widget>[
                    Icon(
                      seerrIssueTypeIcon(issue.issueType),
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: Insets.xs),
                    Text(
                      issue.typeLabel,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (issue.problemSeason != null &&
                        issue.problemSeason! > 0) ...<Widget>[
                      const SizedBox(width: Insets.sm),
                      Text(
                        'Season ${issue.problemSeason}',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: Insets.xs),
                Row(
                  children: <Widget>[
                    Icon(Icons.person_outline, size: 16, color: cs.outline),
                    const SizedBox(width: Insets.xs),
                    Flexible(
                      child: Text(
                        seerrIssueUserName(issue.createdBy),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.outline),
                      ),
                    ),
                    if (time.isNotEmpty) ...<Widget>[
                      const SizedBox(width: Insets.sm),
                      Text(
                        time,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.outline),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _posterFallback(ColorScheme cs) => ColoredBox(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.movie_outlined, color: cs.onSurfaceVariant),
      );
}

/// One comment: author + relative date on top, the message below.
class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});

  final SeerrIssueComment comment;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme cs = theme.colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Insets.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(Radii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              CircleAvatar(
                radius: 12,
                backgroundColor: cs.secondaryContainer,
                child: Icon(
                  Icons.person,
                  size: 14,
                  color: cs.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(
                  seerrIssueUserName(comment.user),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                seerrIssueRelativeTime(comment.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(color: cs.outline),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          Text(comment.message, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
