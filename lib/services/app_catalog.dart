import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;

import '../models/app_manifest.dart';
import 'settings_service.dart';

/// An app on disk, with its manifest and resolved directory.
class InstalledApp {
  final AppManifest manifest;
  final String dir;

  const InstalledApp({required this.manifest, required this.dir});

  /// Absolute path to the app's entry file.
  String get entryPath => p.join(dir, manifest.entry);
}

/// Scans the user's apps directory, seeds bundled samples on first run, and
/// notifies listeners when the set of apps changes.
class AppCatalog extends ChangeNotifier {
  final SettingsService _settings;

  Directory? _appsDir;
  List<InstalledApp> _apps = [];
  String? _error;

  AppCatalog(this._settings);

  List<InstalledApp> get apps => List.unmodifiable(_apps);
  Directory? get appsDir => _appsDir;
  String? get error => _error;

  Future<void> init() async {
    _appsDir = await _settings.appsDir();
    await _appsDir!.create(recursive: true);
    await _seedSamples();
    await refresh();
  }

  Future<void> refresh() async {
    try {
      final entries = _appsDir == null
          ? const Stream.empty()
          : _appsDir!.list(followLinks: false).where((e) =>
              e is Directory && !p.basename(e.path).startsWith('.'));

      final found = <InstalledApp>[];
      await for (final entity in entries) {
        final dir = entity.path;
        final manifestFile = File(p.join(dir, 'manifest.json'));
        if (!await manifestFile.exists()) continue;
        try {
          final json = jsonDecode(await manifestFile.readAsString())
              as Map<String, dynamic>;
          var manifest = AppManifest.fromJson(json);
          if (manifest.id.isEmpty) {
            manifest = AppManifest(
              id: p.basename(dir),
              name: manifest.name,
              description: manifest.description,
              version: manifest.version,
              icon: manifest.icon,
              entry: manifest.entry,
            );
          }
          found.add(InstalledApp(manifest: manifest, dir: dir));
        } catch (_) {
          // Skip directories with a broken manifest.
        }
      }
      found.sort((a, b) =>
          a.manifest.name.toLowerCase().compareTo(b.manifest.name.toLowerCase()));
      _apps = found;
      _error = null;
    } catch (e) {
      _error = '$e';
    }
    notifyListeners();
  }

  InstalledApp? byId(String id) {
    for (final app in _apps) {
      if (app.manifest.id == id) return app;
    }
    return null;
  }

  Future<bool> delete(String id) async {
    final app = byId(id);
    if (app == null) return false;
    try {
      await Directory(app.dir).delete(recursive: true);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  static const _sampleFiles = <String, String>{
    'manifest.json': 'assets/samples/hello-world/manifest.json',
    'index.html': 'assets/samples/hello-world/index.html',
    'icon.svg': 'assets/samples/hello-world/icon.svg',
  };

  /// Copy bundled sample apps into the user directory on first run.
  Future<void> _seedSamples() async {
    final dir = _appsDir!;
    final target = Directory(p.join(dir.path, 'hello-world'));
    if (await File(p.join(target.path, 'manifest.json')).exists()) return;

    await target.create(recursive: true);
    for (final entry in _sampleFiles.entries) {
      final data = await rootBundle.loadString(entry.value);
      await File(p.join(target.path, entry.key)).writeAsString(data);
    }
  }
}
