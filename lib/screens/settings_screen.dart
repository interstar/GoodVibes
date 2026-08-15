import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/llm_service.dart';
import '../services/settings_service.dart';

/// Settings: Xybrid API key and the apps folder location.
class SettingsScreen extends StatefulWidget {
  final SettingsService settings;
  final LlmService llm;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.llm,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController _keyController;
  bool _obscure = true;
  String? _folderPath;
  bool _usingDefault = true;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController(text: widget.settings.apiKey ?? '');
    _loadFolder();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
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

  Future<void> _saveKey() async {
    final value = _keyController.text.trim();
    await widget.settings.setApiKey(value);
    await widget.llm.applyApiKey(widget.settings.apiKey);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value.isEmpty
                ? 'API key removed. On-device model will be used.'
                : 'API key saved.',
          ),
        ),
      );
    }
  }

  Future<void> _changeModel(String id) async {
    await widget.settings.setModelId(id);
    await widget.llm.setModelId(id);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Model set to $id.')),
      );
    }
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
          Text('AI', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _keyController,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Xybrid API key',
                      helperText: 'Optional. Enables cloud fallback for '
                          'higher-quality app generation. Get a free key at '
                          'dashboard.xybrid.dev',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onSubmitted: (_) => _saveKey(),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _saveKey,
                      child: const Text('Save key'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  Text('Model', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: widget.settings.modelId,
                      items: [
                        for (final id in LlmService.availableModelIds)
                          DropdownMenuItem<String>(
                            value: id,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    id,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  LlmService.isModelCached(id)
                                      ? 'ready on device'
                                      : 'cloud / download',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: LlmService.isModelCached(id)
                                            ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                            : Theme.of(context)
                                                .colorScheme
                                                .outline,
                                      ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (id) => id == null ? null : _changeModel(id),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Smaller cached models run instantly on this machine. '
                    'Bigger models download once (progress shows in the '
                    'Studio) or are served from the cloud while downloading.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text('Apps folder', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Location'),
              subtitle: Text(_folderPath ?? '…'),
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
                'Apps are plain HTML/CSS/JS folders. The AI runs via Xybrid.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
