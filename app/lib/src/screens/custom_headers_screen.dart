import 'package:core_models/core_models.dart';
import 'package:core_networking/core_networking.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Edit the HTTP headers merged onto every instance request.
///
/// Two scopes: the active profile's global headers (sent with every request
/// from every instance) and per-instance headers (edited on an inner screen;
/// they win over global keys on collision). Service auth headers still win
/// last because the auth interceptors run per-request.
class CustomHeadersScreen extends ConsumerStatefulWidget {
  const CustomHeadersScreen({super.key});

  @override
  ConsumerState<CustomHeadersScreen> createState() =>
      _CustomHeadersScreenState();
}

class _CustomHeadersScreenState extends ConsumerState<CustomHeadersScreen> {
  @override
  Widget build(BuildContext context) {
    final Profile? profile = ref.watch(activeProfileProvider);
    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Custom Headers')),
        body: const EmptyView(
          icon: Icons.language_outlined,
          title: 'No profile',
          message: 'Create a profile before adding headers.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Custom Headers')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Insets.xl),
        children: <Widget>[
          _HeadersSectionHeader(
            'Global headers',
            subtitle: 'Sent with every request, all instances',
            onAdd: _editGlobalHeader,
          ),
          if (profile.globalHeaders.isEmpty)
            const _NoHeadersHint('No global headers')
          else
            Padding(
              padding: Insets.pageH,
              child: Column(
                children: <Widget>[
                  for (final MapEntry<String, String> entry
                      in profile.globalHeaders.entries)
                    _HeaderCard(
                      name: entry.key,
                      value: entry.value,
                      onEdit: () => _editGlobalHeader(original: entry),
                      onDelete: () => _deleteGlobalHeader(profile, entry.key),
                    ),
                ],
              ),
            ),
          const _HeadersSectionHeader(
            'Per instance',
            subtitle: 'Override or extend global headers for one instance',
          ),
          if (profile.instances.isEmpty)
            const _NoHeadersHint('No instances in this profile')
          else
            Padding(
              padding: Insets.pageH,
              child: Column(
                children: <Widget>[
                  for (final Instance instance in profile.instances)
                    _InstanceRow(
                      instance: instance,
                      onTap: () => pushScreen<void>(
                        context,
                        _InstanceHeadersScreen(instanceId: instance.id),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editGlobalHeader({
    MapEntry<String, String>? original,
  }) async {
    final MapEntry<String, String>? result =
        await showDialog<MapEntry<String, String>>(
      context: context,
      builder: (BuildContext context) => _HeaderDialog(
        initial: original,
        appliesTo: ref.read(activeProfileProvider)?.instances ??
            const <Instance>[],
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    final Profile? current = ref.read(activeProfileProvider);
    if (current == null) {
      return;
    }
    final Map<String, String> next =
        Map<String, String>.of(current.globalHeaders);
    if (original != null && original.key != result.key) {
      next.remove(original.key);
    }
    next[result.key] = result.value;
    await ref
        .read(profileListProvider.notifier)
        .updateProfile(current.copyWith(globalHeaders: next));
  }

  Future<void> _deleteGlobalHeader(Profile profile, String key) async {
    final Map<String, String> next =
        Map<String, String>.of(profile.globalHeaders)..remove(key);
    await ref
        .read(profileListProvider.notifier)
        .updateProfile(profile.copyWith(globalHeaders: next));
  }
}

/// Inner editor for one instance's headers, reached from the per-instance
/// list. Saves through the regular instance save path (`upsertInstance`).
class _InstanceHeadersScreen extends ConsumerStatefulWidget {
  const _InstanceHeadersScreen({required this.instanceId});

  final String instanceId;

  @override
  ConsumerState<_InstanceHeadersScreen> createState() =>
      _InstanceHeadersScreenState();
}

class _InstanceHeadersScreenState
    extends ConsumerState<_InstanceHeadersScreen> {
  @override
  Widget build(BuildContext context) {
    final Instance? instance =
        ref.watch(instanceByIdProvider(widget.instanceId));
    if (instance == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Instance headers')),
        body: const EmptyView(
          icon: Icons.language_outlined,
          title: 'Instance not found',
          message: 'It may have been removed from the profile.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(instance.name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Insets.xl),
        children: <Widget>[
          _HeadersSectionHeader(
            'Headers',
            subtitle: 'Sent with every request to this instance',
            onAdd: _editHeader,
          ),
          if (instance.customHeaders.isEmpty)
            const _NoHeadersHint('No headers for this instance')
          else
            Padding(
              padding: Insets.pageH,
              child: Column(
                children: <Widget>[
                  for (final MapEntry<String, String> entry
                      in instance.customHeaders.entries)
                    _HeaderCard(
                      name: entry.key,
                      value: entry.value,
                      onEdit: () => _editHeader(original: entry),
                      onDelete: () => _deleteHeader(instance, entry.key),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _save(Instance instance, Map<String, String> headers) async {
    final Profile? profile = ref.read(activeProfileProvider);
    if (profile == null) {
      return;
    }
    await ref.read(profileListProvider.notifier).upsertInstance(
          profile.id,
          instance.copyWith(customHeaders: headers),
        );
  }

  Future<void> _editHeader({
    MapEntry<String, String>? original,
  }) async {
    final Instance? target = ref.read(instanceByIdProvider(widget.instanceId));
    final MapEntry<String, String>? result =
        await showDialog<MapEntry<String, String>>(
      context: context,
      builder: (BuildContext context) => _HeaderDialog(
        initial: original,
        appliesTo:
            target == null ? const <Instance>[] : <Instance>[target],
      ),
    );
    if (result == null || !mounted) {
      return;
    }
    final Instance? current = ref.read(instanceByIdProvider(widget.instanceId));
    if (current == null) {
      return;
    }
    final Map<String, String> next =
        Map<String, String>.of(current.customHeaders);
    if (original != null && original.key != result.key) {
      next.remove(original.key);
    }
    next[result.key] = result.value;
    await _save(current, next);
  }

  Future<void> _deleteHeader(Instance instance, String key) async {
    final Map<String, String> next =
        Map<String, String>.of(instance.customHeaders)..remove(key);
    await _save(instance, next);
  }
}

class _HeadersSectionHeader extends StatelessWidget {
  const _HeadersSectionHeader(this.title, {this.subtitle, this.onAdd});

  final String title;
  final String? subtitle;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.lg,
        Insets.sm,
        Insets.xs,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
          if (onAdd != null)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add header',
              onPressed: onAdd,
            ),
        ],
      ),
    );
  }
}

class _NoHeadersHint extends StatelessWidget {
  const _NoHeadersHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.xs, Insets.lg, 0),
      child: Text(
        text,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.outline),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.name,
    required this.value,
    required this.onEdit,
    required this.onDelete,
  });

  final String name;
  final String value;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: InkWell(
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.sm,
            Insets.xs,
            Insets.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Insets.xxs),
                    Text(
                      value,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete header',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstanceRow extends StatelessWidget {
  const _InstanceRow({required this.instance, required this.onTap});

  final Instance instance;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int count = instance.customHeaders.length;
    return Card(
      margin: const EdgeInsets.only(bottom: Insets.sm),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(Insets.md),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  ServiceVisuals.icon(instance.kind),
                  size: 22,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      instance.name,
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: Insets.xxs),
                    Text(
                      instance.kind.displayName,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ),
              if (count > 0) ...<Widget>[
                const SizedBox(width: Insets.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Insets.sm + Insets.xxs,
                    vertical: Insets.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$count',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: Insets.xs),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.outline,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add / edit form for one header. Pops with a `MapEntry(name, value)`.
class _HeaderDialog extends StatefulWidget {
  const _HeaderDialog({this.initial, this.appliesTo = const <Instance>[]});

  final MapEntry<String, String>? initial;

  /// The instances this header will be sent to: every one in the profile for
  /// a global header, or the single one for a per-instance header. Used only
  /// to warn about names that will not survive the trip.
  final List<Instance> appliesTo;

  @override
  State<_HeaderDialog> createState() => _HeaderDialogState();
}

class _HeaderDialogState extends State<_HeaderDialog> {
  /// RFC 7230 token characters - the set allowed in an HTTP header name.
  static final RegExp _tokenPattern = RegExp(r'^[!#$%&*+.^_|~0-9A-Za-z-]+$');

  /// Why the name being typed will not do what the user expects, if so.
  String? get _conflict =>
      headerConflictWarning(_name.text, widget.appliesTo);

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.key ?? '');
  late final TextEditingController _value =
      TextEditingController(text: widget.initial?.value ?? '');

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    Navigator.of(context).pop(
      MapEntry<String, String>(_name.text.trim(), _value.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initial == null ? 'Add header' : 'Edit header'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextFormField(
              controller: _name,
              autofocus: widget.initial == null,
              textInputAction: TextInputAction.next,
              // Proxy-Authorization rather than X-Api-Key: this screen exists
              // for reverse-proxy auth, and it is the one name no service in
              // the stack overwrites or refuses.
              decoration: const InputDecoration(
                labelText: 'Header name',
                hintText: proxyAuthHeaderName,
              ),
              onChanged: (String _) => setState(() {}),
              validator: (String? v) {
                final String name = (v ?? '').trim();
                if (name.isEmpty) {
                  return 'Enter a header name';
                }
                if (!_tokenPattern.hasMatch(name)) {
                  return 'No spaces or colons allowed';
                }
                return null;
              },
            ),
            if (_conflict != null) ...<Widget>[
              const SizedBox(height: Insets.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: Insets.xs),
                  Expanded(
                    child: Text(
                      _conflict!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.error,
                          ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Insets.md),
            TextFormField(
              controller: _value,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: 'Value'),
              onFieldSubmitted: (String _) => _submit(),
              validator: (String? v) =>
                  (v ?? '').trim().isEmpty ? 'Enter a value' : null,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
