import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/ai_profile.dart';
import '../services/ai_profile_store.dart';
import '../services/llm_service.dart';
import '../services/settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final SettingsService settings;
  final LlmService llm;
  final AiProfileStore profileStore;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.llm,
    required this.profileStore,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _folderPath;
  bool _usingDefault = true;

  @override
  void initState() {
    super.initState();
    _loadFolder();
  }

  Future<void> _loadFolder() async {
    final dir = await widget.settings.appsDir();
    final def = await SettingsService.defaultAppsDir();
    if (mounted) {
      setState(() {
        _folderPath = dir.path;
        _usingDefault = p.equals(dir.path, def.path);
      });
    }
  }

  Future<void> _activate(AiProfile profile) async {
    await widget.profileStore.setActiveProfile(profile.id);
    await widget.llm.setActiveProfile(widget.profileStore.activeProfile);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AI profile set to ${profile.name}.')),
      );
    }
  }

  Future<void> _editProfile(AiProfile profile) async {
    final result = await showDialog<AiProfile>(
      context: context,
      builder: (ctx) => AiProfileEditorDialog(existing: profile),
    );
    if (result == null) return;
    await widget.profileStore.saveProfile(result, apiKey: result.apiKey);
    if (result.id == widget.profileStore.activeProfile.id) {
      await widget.llm.setActiveProfile(widget.profileStore.activeProfile);
    }
  }

  Future<void> _addProfile(AiProviderType provider) async {
    final result = await showDialog<AiProfile>(
      context: context,
      builder: (ctx) => AiProfileEditorDialog(provider: provider),
    );
    if (result == null) return;
    await widget.profileStore.saveProfile(result, apiKey: result.apiKey);
    await widget.profileStore.setActiveProfile(result.id);
    await widget.llm.setActiveProfile(widget.profileStore.activeProfile);
  }

  Future<void> _deleteProfile(AiProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${profile.name}?'),
        content: const Text(
          'The profile and its stored API key will be removed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.profileStore.deleteProfile(profile.id);
    await widget.llm.setActiveProfile(widget.profileStore.activeProfile);
  }

  Future<void> _pickFolder() async {
    final controller = TextEditingController(text: _folderPath ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Apps folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Folder path',
            hintText: '/home/you/GoodVibes/apps',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Use this folder'),
          ),
        ],
      ),
    );
    if (value != null && value.isNotEmpty) {
      await widget.settings.setAppsDir(value);
      await _loadFolder();
    }
  }

  Future<void> _resetFolder() async {
    await widget.settings.clearAppsDirOverride();
    await _loadFolder();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('AI profiles', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: widget.profileStore,
            builder: (context, _) {
              final active = widget.profileStore.activeProfile;
              return Column(
                children: [
                  for (final profile in widget.profileStore.profiles)
                    _AiProfileCard(
                      profile: profile,
                      active: profile.id == active.id,
                      onActivate: () => _activate(profile),
                      onEdit: () => _editProfile(profile),
                      onDelete: widget.profileStore.profiles.length <= 1
                          ? null
                          : () => _deleteProfile(profile),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<AiProviderType>(
                      tooltip: 'Add AI profile',
                      onSelected: _addProfile,
                      itemBuilder: (ctx) => const [
                        PopupMenuItem(
                          value: AiProviderType.openAiCompatible,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.cloud_outlined),
                            title: Text('OpenAI-compatible'),
                          ),
                        ),
                        PopupMenuItem(
                          value: AiProviderType.xybrid,
                          child: ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.memory_outlined),
                            title: Text('Xybrid'),
                          ),
                        ),
                      ],
                      child: const _AddProfileButton(),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          Text('Apps folder', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Location'),
              subtitle: Text(_folderPath ?? '...'),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickFolder,
            ),
          ),
          if (!_usingDefault)
            Card(
              child: ListTile(
                leading: const Icon(Icons.settings_backup_restore),
                title: const Text('Use default location'),
                onTap: _resetFolder,
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              if (_folderPath != null) {
                await SettingsService.openFolder(_folderPath!);
              }
            },
            icon: const Icon(Icons.open_in_new),
            label: const Text('Open apps folder'),
          ),
          const SizedBox(height: 24),
          Text('About', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          const Card(
            child: ListTile(
              leading: Icon(Icons.auto_awesome),
              title: Text('Good Vibes'),
              subtitle: Text(
                'A local app store you vibe-code into existence.\n'
                'Apps are plain HTML/CSS/JS folders. AI profiles can use local or cloud models.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddProfileButton extends StatelessWidget {
  const _AddProfileButton();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add, color: scheme.onPrimary, size: 18),
          const SizedBox(width: 8),
          Text('Add profile', style: TextStyle(color: scheme.onPrimary)),
        ],
      ),
    );
  }
}

class AiProfileEditorDialog extends StatefulWidget {
  final AiProfile? existing;
  final AiProviderType? provider;

  const AiProfileEditorDialog({super.key, this.existing, this.provider})
    : assert(existing != null || provider != null);

  @override
  State<AiProfileEditorDialog> createState() => _AiProfileEditorDialogState();
}

class _AiProfileEditorDialogState extends State<AiProfileEditorDialog> {
  late AiProviderType _provider;
  late TextEditingController _nameController;
  late TextEditingController _endpointController;
  late TextEditingController _modelController;
  late TextEditingController _keyController;
  late TextEditingController _temperatureController;
  late TextEditingController _maxTokensController;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _provider = existing?.provider ?? widget.provider!;
    _nameController = TextEditingController(
      text: existing?.name ?? _defaultName,
    );
    _endpointController = TextEditingController(
      text: existing?.baseUrl ?? _defaultBaseUrl,
    );
    _modelController = TextEditingController(
      text: existing?.model ?? _defaultModel,
    );
    _keyController = TextEditingController(text: existing?.apiKey ?? '');
    _temperatureController = TextEditingController(
      text: (existing?.temperature ?? 0.4).toString(),
    );
    _maxTokensController = TextEditingController(
      text: (existing?.maxTokens ?? 4096).toString(),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _endpointController.dispose();
    _modelController.dispose();
    _keyController.dispose();
    _temperatureController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  String get _defaultName => switch (_provider) {
    AiProviderType.xybrid => 'Xybrid',
    AiProviderType.openAiCompatible => 'OpenAI-compatible',
  };

  String get _defaultBaseUrl => switch (_provider) {
    AiProviderType.xybrid => '',
    AiProviderType.openAiCompatible => 'https://api.together.ai/v1',
  };

  String get _defaultModel => switch (_provider) {
    AiProviderType.xybrid => LlmService.defaultModelId,
    AiProviderType.openAiCompatible => '',
  };

  bool get _needsEndpoint => _provider == AiProviderType.openAiCompatible;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null ? 'Add AI profile' : 'Edit AI profile',
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<AiProviderType>(
                initialValue: _provider,
                decoration: const InputDecoration(labelText: 'Provider'),
                items: const [
                  DropdownMenuItem(
                    value: AiProviderType.openAiCompatible,
                    child: Text('OpenAI-compatible'),
                  ),
                  DropdownMenuItem(
                    value: AiProviderType.xybrid,
                    child: Text('Xybrid'),
                  ),
                ],
                onChanged: widget.existing == null
                    ? (provider) {
                        if (provider == null || provider == _provider) return;
                        setState(() {
                          _provider = provider;
                          _nameController.text = _defaultName;
                          _endpointController.text = _defaultBaseUrl;
                          _modelController.text = _defaultModel;
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              if (_needsEndpoint) ...[
                TextField(
                  controller: _endpointController,
                  decoration: const InputDecoration(
                    labelText: 'Endpoint',
                    helperText: 'Example: https://api.together.ai/v1',
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (_provider == AiProviderType.xybrid)
                DropdownButtonFormField<String>(
                  initialValue: _modelController.text.isEmpty
                      ? LlmService.defaultModelId
                      : _modelController.text,
                  decoration: const InputDecoration(labelText: 'Model'),
                  items: [
                    for (final id in LlmService.availableModelIds)
                      DropdownMenuItem(value: id, child: Text(id)),
                  ],
                  onChanged: (id) {
                    if (id != null) _modelController.text = id;
                  },
                )
              else
                TextField(
                  controller: _modelController,
                  decoration: const InputDecoration(labelText: 'Model id'),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _keyController,
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: 'API key',
                  helperText: _provider == AiProviderType.xybrid
                      ? 'Optional. Leave blank to use on-device only.'
                      : 'Stored in the platform secure store.',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _temperatureController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Temperature',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _maxTokensController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Max tokens',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    final endpoint = _endpointController.text.trim();
    final model = _modelController.text.trim();
    if (name.isEmpty || model.isEmpty || (_needsEndpoint && endpoint.isEmpty)) {
      return;
    }
    final temperature =
        double.tryParse(_temperatureController.text.trim()) ?? 0.4;
    final maxTokens = int.tryParse(_maxTokensController.text.trim()) ?? 4096;
    final id = widget.existing?.id ?? _newProfileId(name);
    Navigator.pop(
      context,
      AiProfile(
        id: id,
        name: name,
        provider: _provider,
        model: model,
        baseUrl: _needsEndpoint ? endpoint : null,
        apiKey: _keyController.text.trim(),
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );
  }

  static String _newProfileId(String name) {
    final slug = name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final base = slug.isEmpty ? 'ai-profile' : slug;
    return '$base-${DateTime.now().millisecondsSinceEpoch}';
  }
}

class _AiProfileCard extends StatelessWidget {
  final AiProfile profile;
  final bool active;
  final VoidCallback onActivate;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;

  const _AiProfileCard({
    required this.profile,
    required this.active,
    required this.onActivate,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconButton(
              tooltip: active ? 'Active profile' : 'Use this profile',
              onPressed: active ? null : onActivate,
              icon: Icon(
                active ? Icons.check_circle : Icons.radio_button_unchecked,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.name, style: theme.textTheme.titleMedium),
                  Text(
                    _subtitle,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit profile',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: 'Delete profile',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
      ),
    );
  }

  String get _subtitle {
    return switch (profile.provider) {
      AiProviderType.xybrid =>
        profile.apiKey == null || profile.apiKey!.isEmpty
            ? '${profile.model} - on-device only'
            : '${profile.model} - cloud fallback enabled',
      AiProviderType.openAiCompatible =>
        '${profile.model} - ${profile.baseUrl ?? 'no endpoint'}',
    };
  }
}
