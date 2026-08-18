import 'package:flutter/material.dart';

import '../services/app_catalog.dart';
import '../services/app_chat_store.dart';
import '../services/local_server.dart';
import '../services/settings_service.dart';
import 'app_window.dart';

/// The app store: a grid of installed apps that can be opened in an embedded
/// browser, refreshed, or deleted.
class StoreScreen extends StatelessWidget {
  final AppCatalog catalog;
  final LocalServer server;
  final SettingsService settings;

  /// Called when the user picks "Edit" on an app; the shell switches to the
  /// Studio with that app as the edit target.
  final void Function(
    InstalledApp app, {
    required bool loadTranscript,
    String? initialDraft,
  })?
  onEdit;
  final VoidCallback? onNewApp;

  const StoreScreen({
    super.key,
    required this.catalog,
    required this.server,
    required this.settings,
    this.onEdit,
    this.onNewApp,
  });

  Future<void> _open(BuildContext context, InstalledApp app) async {
    final url = server.urlForApp(app.manifest.id);
    try {
      await openAppInBrowser(
        url: url,
        title: app.manifest.name,
        onEdit: (consoleText) =>
            _editFromAppWindow(app, consoleText: consoleText),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open "${app.manifest.name}": $e')),
        );
      }
    }
  }

  Future<void> _edit(BuildContext context, InstalledApp app) async {
    var loadTranscript = false;
    if (await AppChatStore.hasTranscript(app)) {
      if (!context.mounted) return;
      final choice = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Edit ${app.manifest.name}'),
          content: const Text(
            'Reload the previous chat transcript for this app?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Start fresh'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Reload transcript'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      loadTranscript = choice;
    }
    onEdit?.call(app, loadTranscript: loadTranscript);
  }

  void _editFromAppWindow(InstalledApp app, {required String? consoleText}) {
    onEdit?.call(
      app,
      loadTranscript: true,
      initialDraft: _consoleDraft(consoleText),
    );
  }

  static String? _consoleDraft(String? consoleText) {
    final trimmed = consoleText?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return 'Please help me debug this app. The app console currently says:\n\n$trimmed';
  }

  Future<void> _confirmDelete(BuildContext context, InstalledApp app) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${app.manifest.name}?'),
        content: const Text(
          'This will remove the app from your folder. '
          'This cannot be undone.',
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
    if (confirmed == true) {
      await catalog.delete(app.manifest.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Good Vibes'),
        actions: [
          IconButton(
            tooltip: 'New app',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: onNewApp,
          ),
          IconButton(
            tooltip: 'Open apps folder',
            icon: const Icon(Icons.folder_open),
            onPressed: () async {
              final dir = await settings.appsDir();
              await SettingsService.openFolder(dir.path);
            },
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: catalog.refresh,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: catalog,
        builder: (context, _) {
          final apps = catalog.apps;
          if (apps.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.widgets_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No apps yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Vibe a new one in the Studio tab.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            );
          }
          return GridView.builder(
            padding: const EdgeInsets.all(24),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 320,
              mainAxisExtent: 220,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: apps.length,
            itemBuilder: (context, index) {
              final app = apps[index];
              return _AppCard(
                app: app,
                server: server,
                onOpen: () => _open(context, app),
                onEdit: () => _edit(context, app),
                onDelete: () => _confirmDelete(context, app),
              );
            },
          );
        },
      ),
    );
  }
}

class _AppCard extends StatelessWidget {
  final InstalledApp app;
  final LocalServer server;
  final VoidCallback onOpen;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AppCard({
    required this.app,
    required this.server,
    required this.onOpen,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = app.manifest;
    final iconUrl = m.icon == null ? null : server.urlForAsset(m.id, m.icon!);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppIcon(iconUrl: iconUrl, name: m.name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      m.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') onEdit();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Edit'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.delete_outline),
                          title: Text('Delete'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Text(
                  m.description,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Open'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// App icon: loads the manifest icon (served locally) or falls back to a
/// colored tile with the app's initial.
class AppIcon extends StatelessWidget {
  final String? iconUrl;
  final String name;

  const AppIcon({super.key, this.iconUrl, required this.name});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const size = 48.0;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
    );

    if (iconUrl == null) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        iconUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}
