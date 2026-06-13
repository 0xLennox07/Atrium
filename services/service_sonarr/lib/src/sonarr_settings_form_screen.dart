import 'package:core_models/core_models.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'sonarr_providers.dart';

class SonarrSettingsFormScreen extends ConsumerStatefulWidget {
  const SonarrSettingsFormScreen({
    required this.instance,
    required this.category,
    this.itemRaw,
    super.key,
  });

  final Instance instance;
  final String category; // 'downloadclient', 'indexer', 'notification', 'importlist'
  final Map<String, dynamic>? itemRaw;

  @override
  ConsumerState<SonarrSettingsFormScreen> createState() => _SonarrSettingsFormScreenState();
}

class _ScrollBehavior extends ScrollBehavior {
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) {
    return child;
  }
}

class _SonarrSettingsFormScreenState extends ConsumerState<SonarrSettingsFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();

  Map<String, dynamic>? _selectedTemplate;
  List<Map<String, dynamic>> _fields = [];
  final Map<String, bool> _obscurePasswords = {};
  bool _showAdvanced = false;
  bool _testing = false;
  bool _saving = false;

  bool get _isEdit => widget.itemRaw != null;

  String get _categoryDisplayName {
    switch (widget.category) {
      case 'downloadclient':
        return 'Download Client';
      case 'indexer':
        return 'Indexer';
      case 'notification':
        return 'Notification';
      case 'importlist':
        return 'Import List';
      default:
        return 'Settings';
    }
  }

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _selectedTemplate = widget.itemRaw;
      _nameController.text = (widget.itemRaw!['name'] as String?) ?? '';
      if (widget.itemRaw!['fields'] != null) {
        _fields = (widget.itemRaw!['fields'] as List<dynamic>)
            .map((dynamic f) => Map<String, dynamic>.from(f as Map<dynamic, dynamic>))
            .toList();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _onTemplateSelected(Map<String, dynamic> template) {
    setState(() {
      _selectedTemplate = template;
      _nameController.text = (template['name'] as String?) ?? (template['implementationName'] as String?) ?? '';
      if (template['fields'] != null) {
        _fields = (template['fields'] as List<dynamic>)
            .map((dynamic f) => Map<String, dynamic>.from(f as Map<dynamic, dynamic>))
            .toList();
      }
    });
  }

  AsyncValue<List<Map<String, dynamic>>> _getSchemaValue() {
    switch (widget.category) {
      case 'downloadclient':
        return ref.watch(sonarrDownloadClientSchemaProvider(widget.instance));
      case 'indexer':
        return ref.watch(sonarrIndexerSchemaProvider(widget.instance));
      case 'notification':
        return ref.watch(sonarrNotificationSchemaProvider(widget.instance));
      case 'importlist':
        return ref.watch(sonarrImportListSchemaProvider(widget.instance));
      default:
        return const AsyncValue.loading();
    }
  }

  Map<String, dynamic> _buildPayload() {
    final payload = Map<String, dynamic>.from(_selectedTemplate!);
    payload['fields'] = _fields;
    payload['name'] = _nameController.text.trim();
    return payload;
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _testing = true);

    final api = await ref.read(sonarrApiProvider(widget.instance).future);
    final payload = _buildPayload();

    try {
      switch (widget.category) {
        case 'downloadclient':
          await api.testDownloadClientRaw(payload);
          break;
        case 'indexer':
          await api.testIndexerRaw(payload);
          break;
        case 'notification':
          await api.testNotificationRaw(payload);
          break;
        case 'importlist':
          await api.testImportListRaw(payload);
          break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Connection test successful!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test failed: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final api = await ref.read(sonarrApiProvider(widget.instance).future);
    final payload = _buildPayload();

    try {
      if (_isEdit) {
        switch (widget.category) {
          case 'downloadclient':
            await api.updateDownloadClientRaw(payload);
            break;
          case 'indexer':
            await api.updateIndexerRaw(payload);
            break;
          case 'notification':
            await api.updateNotificationRaw(payload);
            break;
          case 'importlist':
            await api.updateImportListRaw(payload);
            break;
        }
      } else {
        switch (widget.category) {
          case 'downloadclient':
            await api.createDownloadClientRaw(payload);
            break;
          case 'indexer':
            await api.createIndexerRaw(payload);
            break;
          case 'notification':
            await api.createNotificationRaw(payload);
            break;
          case 'importlist':
            await api.createImportListRaw(payload);
            break;
        }
      }

      // Invalidate target provider
      switch (widget.category) {
        case 'downloadclient':
          ref.invalidate(sonarrDownloadClientsProvider(widget.instance));
          break;
        case 'indexer':
          ref.invalidate(sonarrIndexersProvider(widget.instance));
          break;
        case 'notification':
          ref.invalidate(sonarrNotificationsProvider(widget.instance));
          break;
        case 'importlist':
          ref.invalidate(sonarrImportListsProvider(widget.instance));
          break;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$_categoryDisplayName saved!')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_selectedTemplate == null) {
      // Show list of provider schemas
      final schemaVal = _getSchemaValue();
      return Scaffold(
        appBar: AppBar(
          title: Text('Select $_categoryDisplayName Type'),
        ),
        body: AsyncValueView<List<Map<String, dynamic>>>(
          value: schemaVal,
          data: (templates) {
            if (templates.isEmpty) {
              return Center(child: Text('No $_categoryDisplayName templates available.'));
            }
            return ListView.builder(
              padding: Insets.page,
              itemCount: templates.length,
              itemBuilder: (context, idx) {
                final template = templates[idx];
                final name = (template['implementationName'] as String?) ?? 'Unknown';
                final info = (template['infoLink'] as String?) ?? '';
                return Card(
                  margin: const EdgeInsets.only(bottom: Insets.md),
                  child: ListTile(
                    title: Text(name, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: info.isNotEmpty ? Text(info, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _onTemplateSelected(template),
                  ),
                );
              },
            );
          },
        ),
      );
    }

    // Otherwise render form for selected template
    final implementationName = (_selectedTemplate!['implementationName'] as String?) ?? '';
    final title = _isEdit ? 'Edit $implementationName' : 'Add $implementationName';

    final visibleFields = _fields.where((f) {
      if (!_showAdvanced && f['advanced'] == true) return false;
      if (f['hidden'] == 'hidden') return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Advanced', style: TextStyle(fontSize: 12)),
              Switch(
                value: _showAdvanced,
                onChanged: (val) => setState(() => _showAdvanced = val),
              ),
            ],
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ScrollConfiguration(
          behavior: _ScrollBehavior(),
          child: ListView(
            padding: Insets.page,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  helperText: 'Unique name for this configuration',
                  border: OutlineInputBorder(),
                ),
                validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: Insets.md),
              ...visibleFields.map((field) {
                final String fieldType = (field['type'] as String?) ?? 'textbox';
                final String label = (field['label'] as String?) ?? (field['name'] as String? ?? '');
                final String? help = field['helpText'] as String?;

                switch (fieldType) {
                  case 'checkbox':
                    return Container(
                      margin: const EdgeInsets.only(bottom: Insets.md),
                      decoration: BoxDecoration(
                        border: Border.all(color: theme.dividerColor),
                        borderRadius: Radii.card,
                      ),
                      child: SwitchListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: Insets.md),
                        title: Text(label),
                        subtitle: help != null ? Text(help) : null,
                        value: (field['value'] as bool?) ?? false,
                        onChanged: (val) => setState(() => field['value'] = val),
                      ),
                    );

                  case 'select':
                    final options = (field['selectOptions'] as List<dynamic>?)
                            ?.map((dynamic e) => e as Map<String, dynamic>)
                            .toList() ??
                        <Map<String, dynamic>>[];
                    final currentValue = field['value'];
                    // Ensure currentValue is in options
                    final hasMatch = options.any((opt) => opt['value'] == currentValue);
                    final dropdownValue = hasMatch ? currentValue : (options.isNotEmpty ? options[0]['value'] : null);

                    return Container(
                      margin: const EdgeInsets.only(bottom: Insets.md),
                      child: DropdownButtonFormField<dynamic>(
                        initialValue: dropdownValue,
                        decoration: InputDecoration(
                          labelText: label,
                          helperText: help,
                          border: const OutlineInputBorder(),
                        ),
                        items: options.map((opt) {
                          return DropdownMenuItem<dynamic>(
                            value: opt['value'],
                            child: Text((opt['name'] ?? opt['value'] ?? '').toString()),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => field['value'] = val),
                      ),
                    );

                  case 'number':
                    return Container(
                      margin: const EdgeInsets.only(bottom: Insets.md),
                      child: TextFormField(
                        initialValue: (field['value'] ?? '').toString(),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: label,
                          helperText: help,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (val) => field['value'] = num.tryParse(val) ?? val,
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) return 'Required';
                          if (num.tryParse(val) == null) return 'Must be a valid number';
                          return null;
                        },
                      ),
                    );

                  case 'password':
                    final name = field['name'] as String;
                    final obscure = _obscurePasswords[name] ?? true;
                    return Container(
                      margin: const EdgeInsets.only(bottom: Insets.md),
                      child: TextFormField(
                        initialValue: (field['value'] ?? '').toString(),
                        obscureText: obscure,
                        decoration: InputDecoration(
                          labelText: label,
                          helperText: help,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscurePasswords[name] = !obscure),
                          ),
                        ),
                        onChanged: (val) => field['value'] = val,
                        validator: (val) => (val == null || val.trim().isEmpty) ? 'Required' : null,
                      ),
                    );

                  case 'textbox':
                  default:
                    return Container(
                      margin: const EdgeInsets.only(bottom: Insets.md),
                      child: TextFormField(
                        initialValue: (field['value'] ?? '').toString(),
                        decoration: InputDecoration(
                          labelText: label,
                          helperText: help,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (val) => field['value'] = val,
                        validator: (val) {
                          // Allow optional textbox fields
                          if (field['name'] == 'directory') return null; // directory is typically optional
                          if (val == null || val.trim().isEmpty) return 'Required';
                          return null;
                        },
                      ),
                    );
                }
              }),
              const SizedBox(height: Insets.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testing ? null : _testConnection,
                      icon: _testing
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.science_outlined),
                      label: const Text('Test'),
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined),
                      label: Text(_isEdit ? 'Save Changes' : 'Create'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
