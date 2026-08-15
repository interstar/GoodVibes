import 'package:flutter/material.dart';

import 'screens/settings_screen.dart';
import 'screens/store_screen.dart';
import 'screens/vibe_screen.dart';
import 'services/app_catalog.dart';
import 'services/llm_service.dart';
import 'services/local_server.dart';
import 'services/settings_service.dart';

/// Root widget: bottom navigation between the Store, Vibe Studio, and Settings.
class GoodVibesApp extends StatelessWidget {
  final SettingsService settings;
  final AppCatalog catalog;
  final LocalServer server;
  final LlmService llm;

  const GoodVibesApp({
    super.key,
    required this.settings,
    required this.catalog,
    required this.server,
    required this.llm,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Good Vibes',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6A5AE0),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6A5AE0),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: _HomeShell(
        settings: settings,
        catalog: catalog,
        server: server,
        llm: llm,
      ),
    );
  }
}

class _HomeShell extends StatefulWidget {
  final SettingsService settings;
  final AppCatalog catalog;
  final LocalServer server;
  final LlmService llm;

  const _HomeShell({
    required this.settings,
    required this.catalog,
    required this.server,
    required this.llm,
  });

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell> {
  int _index = 0;
  String? _editTargetId;

  @override
  Widget build(BuildContext context) {
    final editTarget =
        _editTargetId == null ? null : widget.catalog.byId(_editTargetId!);
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          StoreScreen(
            catalog: widget.catalog,
            server: widget.server,
            settings: widget.settings,
            onEdit: (app) => setState(() {
              _editTargetId = app.manifest.id;
              _index = 1;
            }),
          ),
          VibeScreen(
            catalog: widget.catalog,
            llm: widget.llm,
            settings: widget.settings,
            server: widget.server,
            editTarget: editTarget,
            onEditTargetChanged: (app) =>
                setState(() => _editTargetId = app?.manifest.id),
          ),
          SettingsScreen(settings: widget.settings, llm: widget.llm),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Store',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Studio',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
