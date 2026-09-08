import 'dart:typed_data';

import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';

import 'qbittorrent_client.dart';
import 'qbittorrent_providers.dart';

/// Bottom sheet to add a torrent to a qBittorrent instance.
///
/// Two input modes:
/// * **Link** - one or more magnet links / `.torrent` URLs (one per line).
/// * **File** - a picked `.torrent` file, uploaded as multipart bytes.
///
/// Plus optional category (dropdown of the server's categories), an optional
/// save path override, and "start paused" / "sequential" toggles.
///
/// Returns `true` via `Navigator.pop` when something was successfully added,
/// so the caller can refresh the torrent list.
enum AddTorrentMode { link, file }

/// One `.torrent` handed to the sheet, as bytes plus a name to show.
///
/// A record rather than a class so the app can pass these in without the
/// service packages needing a shared type to depend on.
typedef TorrentFileArg = ({Uint8List bytes, String? name});

class AddTorrentSheet extends ConsumerStatefulWidget {
  const AddTorrentSheet({
    required this.instance,
    this.initialMode = AddTorrentMode.link,
    this.initialLink,
    this.initialFiles,
    super.key,
  });

  final Instance instance;
  final AddTorrentMode initialMode;

  /// A magnet link or `.torrent` URL to open the sheet with, filled into the
  /// link field. Set when another app shares a torrent with Atrium.
  final String? initialLink;

  /// `.torrent` files handed over by another app. When set the sheet opens in
  /// file mode with these already in hand, so there is nothing to pick. A
  /// batch shares one category, save path and paused choice.
  final List<TorrentFileArg>? initialFiles;

  /// Opens the sheet and returns whether a torrent was added.
  static Future<bool> show(
    BuildContext context,
    Instance instance, {
    AddTorrentMode initialMode = AddTorrentMode.link,
    String? initialLink,
    List<TorrentFileArg>? initialFiles,
  }) async {
    final bool? added = await showDialog<bool>(
      context: context,
      builder: (_) => AddTorrentSheet(
        instance: instance,
        initialMode: initialMode,
        initialLink: initialLink,
        initialFiles: initialFiles,
      ),
    );
    return added ?? false;
  }

  @override
  ConsumerState<AddTorrentSheet> createState() => _AddTorrentSheetState();
}

class _AddTorrentSheetState extends ConsumerState<AddTorrentSheet> {
  final TextEditingController _links = TextEditingController();
  final TextEditingController _savePath = TextEditingController();

  // Shared files force file mode: there is nothing left to pick.
  late final AddTorrentMode _mode = (widget.initialFiles?.isNotEmpty ?? false)
      ? AddTorrentMode.file
      : widget.initialMode;
  final List<TorrentFileArg> _files = <TorrentFileArg>[];
  int _done = 0;
  String? _category;

  /// The server's global save path, once preferences arrive.
  String _defaultSavePath = '';

  /// Whether the field has been filled in from the server yet. The prefill is
  /// one-shot: it must not keep reasserting itself over someone's typing every
  /// time this rebuilds.
  bool _prefilledSavePath = false;

  /// Set once the field is edited by hand, so a slow preferences fetch landing
  /// afterwards does not overwrite what was typed.
  bool _savePathEdited = false;
  bool _paused = false;
  bool _sequential = false;
  bool _skipHashCheck = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final List<TorrentFileArg>? shared = widget.initialFiles;
    if (shared != null && shared.isNotEmpty) {
      _files.addAll(shared);
    }
    if (widget.initialLink != null) {
      _links.text = widget.initialLink!;
    }
  }

  String get _fileLabel => switch (_files.length) {
        0 => 'Choose .torrent files',
        1 => _files.first.name ?? 'One torrent',
        final int n => '$n torrents',
      };

  @override
  void dispose() {
    _links.dispose();
    _savePath.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_busy) {
      return false;
    }
    return _mode == AddTorrentMode.link
        ? _links.text.trim().isNotEmpty
        : _files.isNotEmpty;
  }

  Future<void> _pickFile() async {
    // pickFiles is already multi-select; the old code then took .single, which
    // throws outright when more than one file is chosen.
    final FilePickerResult? res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['torrent'],
    );
    final List<PlatformFile> picked = res?.files ?? <PlatformFile>[];
    if (picked.isEmpty) {
      return;
    }
    final List<TorrentFileArg> read = <TorrentFileArg>[];
    for (final PlatformFile file in picked) {
      read.add((bytes: await file.readAsBytes(), name: file.name));
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _files
        ..clear()
        ..addAll(read);
    });
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final QbittorrentClient client =
          await ref.read(qbittorrentClientProvider(widget.instance).future);
      final String? savePath =
          _savePath.text.trim().isEmpty ? null : _savePath.text.trim();

      if (_mode == AddTorrentMode.link) {
        final List<String> urls = _links.text
            .split('\n')
            .map((String s) => s.trim())
            .where((String s) => s.isNotEmpty)
            .toList();
        await client.addUrls(
          urls,
          category: _category,
          savePath: savePath,
          paused: _paused,
          sequential: _sequential,
          skipHashCheck: _skipHashCheck,
        );
      } else {
        // One failure does not abandon the rest of the batch.
        int failed = 0;
        for (final TorrentFileArg file in _files) {
          try {
            await client.addTorrentFile(
              file.bytes,
              filename: file.name ?? 'shared.torrent',
              category: _category,
              savePath: savePath,
              paused: _paused,
              sequential: _sequential,
              skipHashCheck: _skipHashCheck,
            );
          } catch (_) {
            failed++;
          }
          if (mounted) {
            setState(() => _done++);
          }
        }
        if (failed == _files.length) {
          throw StateError(
            _files.length == 1
                ? 'Could not add that torrent.'
                : 'None of the ${_files.length} torrents could be added.',
          );
        }
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      setState(() {
        _busy = false;
        _error = 'Could not add: $e';
      });
    }
  }

  /// Fills the save path in from the server the first time it is known.
  ///
  /// Called from build rather than initState because the value arrives with
  /// the preferences fetch. It only writes to the controller, so there is no
  /// setState and no rebuild loop.
  void _prefillSavePath(Map<String, dynamic>? prefs) {
    if (prefs == null) {
      return;
    }
    _defaultSavePath = prefs['save_path']?.toString() ?? '';
    if (_prefilledSavePath || _savePathEdited || _defaultSavePath.isEmpty) {
      return;
    }
    if (_savePath.text.isEmpty) {
      _savePath.text = _defaultSavePath;
    }
    _prefilledSavePath = true;
  }

  /// Moves the save path to match a newly chosen category.
  ///
  /// This is what qBittorrent's own web interface does: picking a category
  /// rewrites the field, and a category that defines no path of its own falls
  /// back to the global default rather than blanking it.
  void _applyCategoryPath(String? category, Map<String, String> paths) {
    final String forCategory = category == null ? '' : (paths[category] ?? '');
    _savePath.text =
        forCategory.isNotEmpty ? forCategory : _defaultSavePath;
    // The field now holds a server value again, not a hand-typed one.
    _savePathEdited = false;
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AsyncValue<Map<String, String>> categoryPaths =
        ref.watch(qbitCategoryPathsProvider(widget.instance));
    _prefillSavePath(
      ref.watch(qbitPreferencesProvider(widget.instance)).value,
    );

    return AlertDialog(
      title: const Text('Add torrent'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_mode == AddTorrentMode.link)
              TextField(
                controller: _links,
                minLines: 2,
                maxLines: 5,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Magnet links or .torrent URLs',
                  hintText: 'magnet:?xt=… (one per line)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              )
            else
              OutlinedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open),
                label: Text(_fileLabel),
              ),
            const SizedBox(height: Insets.md),
            categoryPaths.when(
              data: (Map<String, String> paths) {
                final List<String> cats = paths.keys.toList()..sort();
                return DropdownButtonFormField<String>(
                  initialValue: _category,
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(
                      child: Text('None'),
                    ),
                    ...cats.map(
                      (String c) => DropdownMenuItem<String>(
                        value: c,
                        child: Text(c),
                      ),
                    ),
                  ],
                  onChanged: (String? v) {
                    setState(() => _category = v);
                    _applyCategoryPath(v, paths);
                  },
                );
              },
              loading: () => const LinearProgressIndicatorM3E(
                shape: ProgressM3EShape.flat,
              ),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: Insets.sm),
            TextField(
              controller: _savePath,
              onChanged: (_) => _savePathEdited = true,
              decoration: const InputDecoration(
                labelText: 'Save path',
                hintText: 'Leave blank for the default',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Insets.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start paused'),
              value: _paused,
              onChanged: (bool v) => setState(() => _paused = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Download in sequential order'),
              value: _sequential,
              onChanged: (bool v) => setState(() => _sequential = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Skip hash check'),
              subtitle: const Text(
                'Assume the files are already complete and correct. '
                'qBittorrent rechecks the whole torrent if a piece later '
                'fails.',
              ),
              value: _skipHashCheck,
              onChanged: (bool v) => setState(() => _skipHashCheck = v),
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: Insets.sm),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _canSubmit ? _submit : null,
          icon: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: ExpressiveProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          label: Text(_addLabel),
        ),
      ],
    );
  }

  /// A batch can take a while, so the button counts rather than just spinning.
  String get _addLabel {
    if (_mode != AddTorrentMode.file || _files.length <= 1) {
      return 'Add';
    }
    return _busy ? 'Adding $_done of ${_files.length}' : 'Add ${_files.length}';
  }
}
