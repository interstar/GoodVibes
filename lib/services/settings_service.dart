import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'llm_service.dart';

/// Small persisted settings (Xybrid API key, model id, apps folder override).
class SettingsService {
  static const _keyApiKey = 'xybrid_api_key';
  static const _keyAppsDir = 'apps_dir';
  static const _keyModelId = 'model_id';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  String? get apiKey => _prefs.getString(_keyApiKey);

  Future<void> setApiKey(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await _prefs.remove(_keyApiKey);
    } else {
      await _prefs.setString(_keyApiKey, trimmed);
    }
  }

  String get modelId => _prefs.getString(_keyModelId) ?? LlmService.defaultModelId;

  Future<void> setModelId(String value) async {
    await _prefs.setString(_keyModelId, value);
  }

  /// The directory that holds app folders (`~/GoodVibes/apps` by default).
  Future<Directory> appsDir() async {
    final override = _prefs.getString(_keyAppsDir);
    if (override != null && override.isNotEmpty) {
      return Directory(override);
    }
    return defaultAppsDir();
  }

  Future<void> setAppsDir(String path) async {
    await _prefs.setString(_keyAppsDir, path);
  }

  Future<void> clearAppsDirOverride() async {
    await _prefs.remove(_keyAppsDir);
  }

  /// `~/GoodVibes/apps`, resolved from the platform home directory.
  static Future<Directory> defaultAppsDir() async {
    final home = homeDir();
    if (home != null) {
      return Directory(p.join(home, 'GoodVibes', 'apps'));
    }
    // Fallback to the platform documents directory.
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, 'GoodVibes', 'apps'));
  }

  static String? homeDir() {
    if (Platform.isWindows) {
      return Platform.environment['USERPROFILE'];
    }
    return Platform.environment['HOME'];
  }

  /// Open the given folder in the platform file manager.
  static Future<void> openFolder(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    if (Platform.isLinux) {
      await Process.run('xdg-open', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    }
  }
}
