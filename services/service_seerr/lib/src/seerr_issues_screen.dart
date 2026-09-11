import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/seerr_discover.dart';
import 'models/seerr_issue.dart';
import 'models/seerr_request.dart';
import 'seerr_api.dart';
import 'seerr_issue_detail_screen.dart';
import 'seerr_providers.dart';

/// The Issues tab body: All / Open / Resolved filter chips over the polled
/// issue list (10s, via `seerrIssuesProvider`). Tapping a card pushes
/// [SeerrIssueDetailScreen].
class SeerrIssuesScreen extends ConsumerStatefulWidget {
  const SeerrIssuesScreen({required this.instance, super.key});

  final Instance instance;

  @override
  ConsumerState<SeerrIssuesScreen> createState() => _SeerrIssuesScreenState();
}

class _SeerrIssuesScreenState extends ConsumerState<SeerrIssuesScreen> {
  static const List<(String, String)> _filters = <(String, String)>[
    ('All', 'all'),
    ('Open', 'open'),
    ('Resolved', 'resolved'),
  ];

  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final SeerrIssuesArgs args = (instance: widget.instance, filter: _filter);
    final AsyncValue<List<SeerrIssue>> issues =
        ref.watch(seerrIssuesProvider(args));

    return Column(
      children: <Widget>[
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: Insets.pageH,
            children: <Widget>[
              for (final (String label, String value) in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: Insets.sm),
                  child: Center(
                    child: FilterChip(
                      label: Text(label),
                      selected: _filter == value,
                      onSelected: (_) => setState(() => _filter = value),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AsyncValueView<List<SeerrIssue>>(
          value: issues,
              onRetry: () => ref.invalidate(seerrIssuesProvider(args)),
          data: (List<SeerrIssue> list) {
            
                if (list.isEmpty) {
                  return EasyRefresh(
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
              ref.invalidate(seerrIssuesProvider(args));
            },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const <Widget>[
            SizedBox(height: 100),
            EmptyView(
                    icon: Icons.report_off_outlined,
                    title: 'No issues',
                    message: 'Nothing has been reported.',
                  ),
          ],
        ),
      );
                }
                return EasyRefresh(
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
              ref.invalidate(seerrIssuesProvider(args));
            },
      child: ListView.separated(
                  padding: Insets.page,
                  itemCount: list.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: Insets.md),
                  itemBuilder: (BuildContext context, int index) => _IssueCard(
                    instance: widget.instance,
                    issue: list[index],
                  ),
                ),
    );
              
          },
        ),
        ),
      ],
    );
  }
}

/// One tonal issue card: poster thumbnail (resolved from TMDB via the
/// media-details provider), title, issue type, reporter + date, and the
/// Open / Resolved status pill.
class _IssueCard extends ConsumerWidget {
  const _IssueCard({required this.instance, required this.issue});

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

    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(Radii.lg),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => pushScreen<void>(
          context,
          SeerrIssueDetailScreen(instance: instance, issue: issue),
        ),
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(Radii.md),
                child: SizedBox(
                  width: 56,
                  height: 84,
                  child: posterUrl != null
                      ? AtriumNetworkImage(
                          imageUrl: posterUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _thumbFallback(cs),
                        )
                      : _thumbFallback(cs),
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: Insets.xs),
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
                      ],
                    ),
                    const SizedBox(height: Insets.xs),
                    Row(
                      children: <Widget>[
                        Icon(
                          Icons.person_outline,
                          size: 14,
                          color: cs.outline,
                        ),
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
              const SizedBox(width: Insets.sm),
              SeerrIssueStatusPill(isOpen: issue.isOpen),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumbFallback(ColorScheme cs) => ColoredBox(
        color: cs.surfaceContainerHighest,
        child: Icon(
          seerrIssueTypeIcon(issue.issueType),
          color: cs.onSurfaceVariant,
        ),
      );
}
