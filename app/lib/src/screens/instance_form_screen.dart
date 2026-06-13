import 'package:core_models/core_models.dart';
import 'package:core_profile/core_profile.dart';
import 'package:core_ui/core_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Add / edit an instance. When [instanceId] is null this is an "add" form;
/// otherwise it pre-fills from the existing instance.
///
/// The auth fields shown depend on the selected [ServiceKind]'s auth style:
/// api-key services show one field; user/pass services show two; Plex shows a
/// token field.
class InstanceFormScreen extends ConsumerStatefulWidget {
  const InstanceFormScreen({this.instanceId, super.key});

  final String? instanceId;

  @override
  ConsumerState<InstanceFormScreen> createState() => _InstanceFormScreenState();
}

class _InstanceFormScreenState extends ConsumerState<InstanceFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _localUrl = TextEditingController();
  final TextEditingController _externalUrl = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _pollingInterval = TextEditingController(text: '5');

  ServiceKind _kind = ServiceKind.sonarr;
  UrlMode _urlMode = UrlMode.auto;
  bool _allowSelfSigned = false;
  bool _loaded = false;

  bool get _isEdit => widget.instanceId != null;

  @override
  void dispose() {
    _name.dispose();
    _localUrl.dispose();
    _externalUrl.dispose();
    _apiKey.dispose();
    _username.dispose();
    _password.dispose();
    _pollingInterval.dispose();
    super.dispose();
  }

  void _hydrateFrom(Instance instance) {
    if (_loaded) {
      return;
    }
    _loaded = true;
    _name.text = instance.name;
    _localUrl.text = instance.localUrl;
    _externalUrl.text = instance.externalUrl;
    _kind = instance.kind;
    _urlMode = instance.urlMode;
    _allowSelfSigned = instance.allowSelfSignedCerts;
    _pollingInterval.text = instance.pollingIntervalSeconds.toString();
    switch (instance.auth) {
      case InstanceAuthApiKey(:final String apiKey):
        _apiKey.text = apiKey;
      case InstanceAuthPlex(:final String token):
        _apiKey.text = token;
      case InstanceAuthUserPass(:final String username, :final String password):
        _username.text = username;
        _password.text = password;
      case InstanceAuthCookie(:final String username, :final String password):
        _username.text = username;
        _password.text = password;
    }
  }

  InstanceAuth _buildAuth() {
    return switch (_kind.authStyle) {
      AuthStyle.apiKey => InstanceAuth.apiKey(apiKey: _apiKey.text.trim()),
      AuthStyle.plexToken =>
        InstanceAuth.plexToken(token: _apiKey.text.trim()),
      AuthStyle.userPass => InstanceAuth.userPass(
          username: _username.text.trim(),
          password: _password.text,
        ),
      AuthStyle.cookieLogin => InstanceAuth.cookieLogin(
          username: _username.text.trim(),
          password: _password.text,
        ),
      AuthStyle.none => const InstanceAuth.apiKey(apiKey: ''),
    };
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final ProfileListController controller =
        ref.read(profileListProvider.notifier);
    Profile? profile = ref.read(activeProfileProvider);
    profile ??= await controller.createProfile('Default');
    // After creating, make it active.
    await ref.read(activeProfileIdProvider.notifier).select(profile.id);

    final String id =
        widget.instanceId ?? ref.read(profileRepositoryProvider).newInstanceId();
    final Instance instance = Instance(
      id: id,
      name: _name.text.trim(),
      kind: _kind,
      localUrl: _localUrl.text.trim(),
      externalUrl: _externalUrl.text.trim(),
      urlMode: _urlMode,
      auth: _buildAuth(),
      allowSelfSignedCerts: _allowSelfSigned,
      pollingIntervalSeconds: int.tryParse(_pollingInterval.text.trim()) ?? 5,
    );
    await controller.upsertInstance(profile.id, instance);
    if (mounted) {
      context.pop();
    }
  }

  Future<void> _delete() async {
    final Profile? profile = ref.read(activeProfileProvider);
    if (profile == null || widget.instanceId == null) {
      return;
    }
    await ref
        .read(profileListProvider.notifier)
        .deleteInstance(profile.id, widget.instanceId!);
    if (mounted) {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isEdit) {
      final Instance? existing =
          ref.watch(instanceByIdProvider(widget.instanceId!));
      if (existing != null) {
        _hydrateFrom(existing);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit service' : 'Add service'),
        actions: <Widget>[
          if (_isEdit)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: Insets.page,
          children: <Widget>[
            DropdownButtonFormField<ServiceKind>(
              initialValue: _kind,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Service',
              ),
              items: <DropdownMenuItem<ServiceKind>>[
                for (final ServiceKind k in ServiceKind.values)
                  DropdownMenuItem<ServiceKind>(
                    value: k,
                    child: Text('${k.displayName} - ${k.tagline}'),
                  ),
              ],
              onChanged: (ServiceKind? k) =>
                  setState(() => _kind = k ?? _kind),
            ),
            const SizedBox(height: Insets.md),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Name',
                hintText: 'e.g. Home ${_kind.displayName}',
              ),
              textInputAction: TextInputAction.next,
              validator: (String? v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: Insets.lg),
            Text(
              'Connection',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: Insets.sm),
            TextFormField(
              controller: _localUrl,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: 'Local URL',
                hintText: 'http://192.168.1.10:${_kind.defaultPort}',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: _validateUrlsTogether,
            ),
            const SizedBox(height: Insets.md),
            TextFormField(
              controller: _externalUrl,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'External URL',
                hintText: 'https://sonarr.example.com',
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
              validator: _validateUrlsTogether,
            ),
            const SizedBox(height: Insets.md),
            DropdownButtonFormField<UrlMode>(
              initialValue: _urlMode,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'URL selection',
              ),
              items: const <DropdownMenuItem<UrlMode>>[
                DropdownMenuItem<UrlMode>(
                  value: UrlMode.auto,
                  child: Text('Auto (probe local, fall back to external)'),
                ),
                DropdownMenuItem<UrlMode>(
                  value: UrlMode.forceLocal,
                  child: Text('Always local'),
                ),
                DropdownMenuItem<UrlMode>(
                  value: UrlMode.forceExternal,
                  child: Text('Always external'),
                ),
              ],
              onChanged: (UrlMode? m) =>
                  setState(() => _urlMode = m ?? _urlMode),
            ),
            const SizedBox(height: Insets.lg),
            Text(
              'Authentication',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: Insets.sm),
            ..._authFields(),
            const SizedBox(height: Insets.md),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow self-signed certificates'),
              subtitle: const Text(
                'Skip TLS validation for this instance only.',
              ),
              value: _allowSelfSigned,
              onChanged: (bool v) => setState(() => _allowSelfSigned = v),
            ),
            if (_kind == ServiceKind.glances) ...<Widget>[
              const SizedBox(height: Insets.lg),
              Text(
                'Polling',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: Insets.sm),
              TextFormField(
                controller: _pollingInterval,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Polling Interval (seconds)',
                  hintText: '5',
                ),
                keyboardType: TextInputType.number,
                validator: (String? v) {
                  final int? val = int.tryParse(v?.trim() ?? '');
                  if (val == null || val < 1) return 'Must be at least 1 second';
                  return null;
                },
              ),
            ],
            const SizedBox(height: Insets.xl),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_isEdit ? 'Save changes' : 'Add service'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _authFields() {
    switch (_kind.authStyle) {
      case AuthStyle.apiKey:
        return <Widget>[
          TextFormField(
            controller: _apiKey,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'API key',
            ),
            autocorrect: false,
            validator: (String? v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ];
      case AuthStyle.plexToken:
        return <Widget>[
          TextFormField(
            controller: _apiKey,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Plex token (X-Plex-Token)',
            ),
            autocorrect: false,
            validator: (String? v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
        ];
      case AuthStyle.userPass:
      case AuthStyle.cookieLogin:
        return <Widget>[
          TextFormField(
            controller: _username,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Username',
            ),
            autocorrect: false,
            textInputAction: TextInputAction.next,
            validator: (String? v) =>
                (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: Insets.md),
          TextFormField(
            controller: _password,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Password',
            ),
            obscureText: true,
            validator: (String? v) =>
                (v == null || v.isEmpty) ? 'Required' : null,
          ),
        ];
      case AuthStyle.none:
        return const <Widget>[];
    }
  }

  /// At least one of local / external must be a valid URL.
  String? _validateUrlsTogether(String? _) {
    final bool localOk = _isValidUrl(_localUrl.text);
    final bool externalOk = _isValidUrl(_externalUrl.text);
    if (!localOk && !externalOk) {
      return 'Enter at least one valid URL (local or external)';
    }
    return null;
  }

  bool _isValidUrl(String raw) {
    if (raw.trim().isEmpty) {
      return false;
    }
    final Uri? uri = Uri.tryParse(raw.trim());
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }
}
