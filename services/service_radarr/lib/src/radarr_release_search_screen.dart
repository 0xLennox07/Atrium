import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';

import 'models/radarr_movie.dart';
import 'models/radarr_release.dart';
import 'radarr_api.dart';
import 'radarr_providers.dart';

class RadarrReleaseSearchScreen extends ConsumerStatefulWidget {
  const RadarrReleaseSearchScreen({
    required this.instance,
    required this.movie,
    super.key,
  });

  final Instance instance;
  final RadarrMovie movie;

  @override
  ConsumerState<RadarrReleaseSearchScreen> createState() =>
      _RadarrReleaseSearchScreenState();
}

class _RadarrReleaseSearchScreenState
    extends ConsumerState<RadarrReleaseSearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedProtocol = 'All'; // 'All', 'Torrent', 'Usenet'
  bool _approvedOnly = false;
  String _sortBy = 'Age'; // 'Age', 'Size', 'Seeders', 'Score'
  bool _sortAscending = true; // For Age, true means smaller age (newest) first

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  double _getAgeMinutes(RadarrRelease r) {
    if (r.ageMinutes != null) return r.ageMinutes!;
    if (r.ageHours != null) return r.ageHours! * 60;
    if (r.age != null) return r.age!.toDouble() * 1440;
    return double.maxFinite;
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _searchQuery = '';
      _selectedProtocol = 'All';
      _approvedOnly = false;
      _sortBy = 'Age';
      _sortAscending = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<RadarrRelease>> releasesValue =
        ref.watch(radarrReleasesProvider((widget.instance, widget.movie.id)));

    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('Search Releases'),
            Text(
              widget.movie.title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: <Widget>[
          // Filtering & Sorting Panel
          Card(
            margin: const EdgeInsets.all(Insets.md),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colors.outlineVariant.withOpacity(0.5),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Insets.md),
              child: Column(
                children: <Widget>[
                  // Search Bar
                  TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by title, group, or indexer...',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: Insets.md,
                        vertical: Insets.sm,
                      ),
                    ),
                    onChanged: (String val) =>
                        setState(() => _searchQuery = val),
                  ),
                  const SizedBox(height: Insets.sm),
                  // Protocol Selection SegmentedButton
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<String>(
                      segments: const <ButtonSegment<String>>[
                        ButtonSegment<String>(
                          value: 'All',
                          label: Text('All Protocols'),
                        ),
                        ButtonSegment<String>(
                          value: 'Torrent',
                          label: Text('Torrents'),
                        ),
                        ButtonSegment<String>(
                          value: 'Usenet',
                          label: Text('Usenet'),
                        ),
                      ],
                      selected: <String>{_selectedProtocol},
                      onSelectionChanged: (Set<String> newSelection) {
                        setState(() => _selectedProtocol = newSelection.first);
                      },
                      showSelectedIcon: false,
                    ),
                  ),
                  const SizedBox(height: Insets.sm),
                  // Sort and Filter chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: <Widget>[
                        // Sort Dropdown Button Trigger Chip
                        PopupMenuButton<String>(
                          child: Chip(
                            avatar: const Icon(Icons.sort, size: 16),
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text('Sort: $_sortBy'),
                                const SizedBox(width: 4),
                                Icon(
                                  _sortAscending
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  size: 16,
                                ),
                              ],
                            ),
                          ),
                          itemBuilder: (BuildContext context) =>
                              <PopupMenuEntry<String>>[
                            const PopupMenuItem<String>(
                              value: 'Age',
                              child: Text('Age'),
                            ),
                            const PopupMenuItem<String>(
                              value: 'Size',
                              child: Text('Size'),
                            ),
                            const PopupMenuItem<String>(
                              value: 'Seeders',
                              child: Text('Seeders'),
                            ),
                            const PopupMenuItem<String>(
                              value: 'Score',
                              child: Text('Score'),
                            ),
                          ],
                          onSelected: (String val) {
                            if (_sortBy == val) {
                              setState(() => _sortAscending = !_sortAscending);
                            } else {
                              setState(() {
                                _sortBy = val;
                                // Age default ascending (newest first); others default descending (largest/most first)
                                _sortAscending = val == 'Age';
                              });
                            }
                          },
                        ),
                        const SizedBox(width: Insets.xs),
                        // Filter Chip for Approved Only
                        FilterChip(
                          avatar: Icon(
                            _approvedOnly
                                ? Icons.check_circle
                                : Icons.check_circle_outline,
                            size: 16,
                          ),
                          label: const Text('Approved Only'),
                          selected: _approvedOnly,
                          onSelected: (bool selected) {
                            setState(() => _approvedOnly = selected);
                          },
                        ),
                        if (_searchQuery.isNotEmpty ||
                            _selectedProtocol != 'All' ||
                            _approvedOnly) ...<Widget>[
                          const SizedBox(width: Insets.xs),
                          // Clear filters chip
                          ActionChip(
                            avatar: const Icon(Icons.clear_all, size: 16),
                            label: const Text('Reset'),
                            onPressed: _clearFilters,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(radarrReleasesProvider((widget.instance, widget.movie.id)));
              },
              child: AsyncValueView<List<RadarrRelease>>(
                value: releasesValue,
                onRetry: () {
                  ref.invalidate(radarrReleasesProvider((widget.instance, widget.movie.id)));
                },
                loading: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Insets.xl),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        const CircularProgressIndicator(),
                        const SizedBox(height: Insets.lg),
                        Text(
                          'Querying Indexers...',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: Insets.sm),
                        Text(
                          'Contacting your configured indexers in real time. This can take up to a minute depending on indexer response times.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (List<RadarrRelease> list) {
                  if (list.isEmpty) {
                    return const EmptyView(
                      icon: Icons.search_off,
                      title: 'No releases found',
                      message:
                          'No matching releases were found on your indexers.',
                    );
                  }

                  // Apply search filter locally
                  Iterable<RadarrRelease> filtered = list;
                  if (_searchQuery.isNotEmpty) {
                    final String query = _searchQuery.toLowerCase();
                    filtered = filtered.where((RadarrRelease r) =>
                        r.title.toLowerCase().contains(query) ||
                        (r.indexer != null &&
                            r.indexer!.toLowerCase().contains(query)) ||
                        r.releaseGroup.toLowerCase().contains(query));
                  }

                  // Apply protocol filter locally
                  if (_selectedProtocol != 'All') {
                    final bool wantsTorrent = _selectedProtocol == 'Torrent';
                    filtered = filtered.where(
                      (RadarrRelease r) => r.isTorrent == wantsTorrent,
                    );
                  }

                  // Apply status filter locally
                  if (_approvedOnly) {
                    filtered =
                        filtered.where((RadarrRelease r) => r.approved);
                  }

                  final List<RadarrRelease> sortedList = filtered.toList();

                  // Apply sorting locally
                  sortedList.sort((RadarrRelease a, RadarrRelease b) {
                    int cmp = 0;
                    switch (_sortBy) {
                      case 'Size':
                        cmp = a.size.compareTo(b.size);
                        break;
                      case 'Seeders':
                        cmp = (a.seeders ?? 0).compareTo(b.seeders ?? 0);
                        break;
                      case 'Score':
                        cmp =
                            a.customFormatScore.compareTo(b.customFormatScore);
                        break;
                      case 'Age':
                      default:
                        final double ageA = _getAgeMinutes(a);
                        final double ageB = _getAgeMinutes(b);
                        cmp = ageA.compareTo(ageB);
                        break;
                    }
                    return _sortAscending ? cmp : -cmp;
                  });

                  if (sortedList.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          const Icon(
                            Icons.filter_list_off,
                            size: 48,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: Insets.sm),
                          Text(
                            'No matching filters',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: Insets.xs),
                          Text(
                            'Try adjusting your search query or filters.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.outline,
                            ),
                          ),
                          const SizedBox(height: Insets.md),
                          FilledButton.icon(
                            onPressed: _clearFilters,
                            icon: const Icon(Icons.clear_all),
                            label: const Text('Reset All Filters'),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.only(bottom: Insets.lg),
                    itemCount: sortedList.length,
                    itemBuilder: (BuildContext context, int index) {
                      final RadarrRelease release = sortedList[index];
                      return _ReleaseTile(
                        instance: widget.instance,
                        movie: widget.movie,
                        release: release,
                        onGrabbed: () {
                          ref.invalidate(radarrMovieByIdProvider((widget.instance, widget.movie.id)));
                          ref.invalidate(radarrMoviesProvider(widget.instance));
                          Navigator.pop(context);
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReleaseTile extends ConsumerStatefulWidget {
  const _ReleaseTile({
    required this.instance,
    required this.movie,
    required this.release,
    required this.onGrabbed,
  });

  final Instance instance;
  final RadarrMovie movie;
  final RadarrRelease release;
  final VoidCallback onGrabbed;

  @override
  ConsumerState<_ReleaseTile> createState() => _ReleaseTileState();
}

class _ReleaseTileState extends ConsumerState<_ReleaseTile> {
  bool _grabbing = false;

  Future<void> _grab() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('Grab release?'),
        content: Text(widget.release.title),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Grab'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _grabbing = true);
    try {
      final RadarrApi api =
          await ref.read(radarrApiProvider(widget.instance).future);
      await api.grabRelease(widget.release);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Release grabbed successfully!')),
        );
        widget.onGrabbed();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to grab release: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _grabbing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    final bool isDark = theme.brightness == Brightness.dark;
    final RadarrRelease r = widget.release;

    final String sizeStr = _fmtSize(r.size);

    // Premium quality color coding
    Color qualityBg;
    Color qualityFg;
    final String q = r.quality.toLowerCase();
    if (q.contains('2160') || q.contains('4k') || q.contains('uhd')) {
      qualityBg = isDark ? const Color(0xFF311B92) : const Color(0xFFEDE7F6);
      qualityFg = isDark ? const Color(0xFFD1C4E9) : const Color(0xFF512DA8);
    } else if (q.contains('1080') || q.contains('fhd')) {
      qualityBg = isDark ? const Color(0xFF1B5E20) : const Color(0xFFE8F5E9);
      qualityFg = isDark ? const Color(0xFFC8E6C9) : const Color(0xFF2E7D32);
    } else if (q.contains('720') || q.contains('hd')) {
      qualityBg = isDark
          ? const Color(0xFFE65100).withOpacity(0.3)
          : const Color(0xFFFFF3E0);
      qualityFg = isDark ? const Color(0xFFFFCC80) : const Color(0xFFE65100);
    } else {
      qualityBg = colors.surfaceVariant;
      qualityFg = colors.onSurfaceVariant;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: Insets.md),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colors.outlineVariant.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: r.downloadAllowed ? _grab : null,
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Title and Grab action row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    r.isTorrent ? Icons.swap_vert : Icons.newspaper_outlined,
                    color: r.isTorrent ? Colors.green : Colors.cyan,
                    size: 20,
                  ),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: Text(
                      r.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (_grabbing)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12),
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else
                        IconButton(
                          icon: Icon(
                            Icons.cloud_download_outlined,
                            color: r.downloadAllowed
                                ? colors.primary
                                : colors.onSurface.withOpacity(0.38),
                          ),
                          onPressed: r.downloadAllowed ? _grab : null,
                          tooltip: r.downloadAllowed
                              ? 'Grab release'
                              : 'Download not allowed',
                        ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        tooltip: 'Link options',
                        onSelected: (String action) async {
                          String? linkToCopy;
                          String label = '';
                          if (action == 'magnet') {
                            linkToCopy = r.guid;
                            label = 'Magnet link';
                          } else if (action == 'download') {
                            linkToCopy = r.downloadUrl;
                            label = 'Download link';
                          } else if (action == 'info') {
                            linkToCopy = r.infoUrl;
                            label = 'Info page link';
                          }

                          if (linkToCopy != null && linkToCopy.isNotEmpty) {
                            await Clipboard.setData(ClipboardData(text: linkToCopy));
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Copied $label to clipboard!')),
                              );
                            }
                          } else {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Link is not available.')),
                              );
                            }
                          }
                        },
                        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                          if (r.isTorrent && r.isMagnet)
                            const PopupMenuItem<String>(
                              value: 'magnet',
                              child: Row(
                                children: <Widget>[
                                  Icon(Icons.link, size: 18),
                                  SizedBox(width: 8),
                                  Text('Copy Magnet Link'),
                                ],
                              ),
                            ),
                          if (r.downloadUrl != null && r.downloadUrl!.isNotEmpty)
                            PopupMenuItem<String>(
                              value: 'download',
                              child: Row(
                                children: <Widget>[
                                  const Icon(Icons.download, size: 18),
                                  const SizedBox(width: 8),
                                  Text(r.isTorrent ? 'Copy Torrent Link' : 'Copy NZB Link'),
                                ],
                              ),
                            ),
                          if (r.infoUrl != null && r.infoUrl!.isNotEmpty)
                            const PopupMenuItem<String>(
                              value: 'info',
                              child: Row(
                                children: <Widget>[
                                  Icon(Icons.info_outline, size: 18),
                                  SizedBox(width: 8),
                                  Text('Copy Info Page Link'),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: Insets.sm),
              // Horizontal row of metadata badges
              Wrap(
                spacing: 6,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  // Quality badge
                  if (r.quality.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: qualityBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        r.quality,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: qualityFg,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  // Indexer badge
                  if (r.indexer != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        r.indexer!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  // Size badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      sizeStr,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  // Age badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      r.ageLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  // Custom format score badge
                  if (r.customFormatScore != 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: r.customFormatScore > 0
                            ? Colors.green.withOpacity(0.1)
                            : Colors.red.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Score: ${r.customFormatScore > 0 ? "+" : ""}${r.customFormatScore}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: r.customFormatScore > 0
                              ? Colors.green
                              : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  // Languages
                  for (final String lang in r.languages)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colors.outlineVariant.withOpacity(0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        lang.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colors.onSurface,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
              // Torrent seeders & leechers counts
              if (r.isTorrent) ...<Widget>[
                const SizedBox(height: Insets.sm),
                Row(
                  children: <Widget>[
                    const Icon(
                      Icons.arrow_upward,
                      size: 14,
                      color: Colors.green,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${r.seeders ?? 0} seeders',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: Insets.md),
                    const Icon(
                      Icons.arrow_downward,
                      size: 14,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${r.leechers ?? 0} leechers',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
              // Rejection reasons block
              if (!r.approved && r.rejections.isNotEmpty) ...<Widget>[
                const SizedBox(height: Insets.sm),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(Insets.xs),
                  decoration: BoxDecoration(
                    color: colors.errorContainer.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colors.error.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: colors.error,
                          ),
                          const SizedBox(width: Insets.xs),
                          Text(
                            'Rejections:',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: colors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ...r.rejections.map(
                        (String reason) => Padding(
                          padding: const EdgeInsets.only(left: 18, bottom: 2),
                          child: Text(
                            '• $reason',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onErrorContainer,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _fmtSize(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
  double value = bytes.toDouble();
  int unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final String text = value >= 100 || unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}
