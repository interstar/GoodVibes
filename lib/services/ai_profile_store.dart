import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai_profile.dart';
import 'llm_service.dart';

class AiProfileStore extends ChangeNotifier {
  static const _profilesKey = 'ai_profiles_v1';
  static const _activeProfileKey = 'ai_active_profile_id';
  static const _legacyApiKey = 'xybrid_api_key';
  static const _legacyModelId = 'model_id';

  final FlutterSecureStorage _secureStorage;
  late SharedPreferences _prefs;

  List<AiProfile> _profiles = [];
  String? _activeProfileId;

  AiProfileStore({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  List<AiProfile> get profiles => List.unmodifiable(_profiles);

  AiProfile get activeProfile {
    return profileById(_activeProfileId ?? '') ?? _profiles.first;
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _load();
  }

  AiProfile? profileById(String id) {
    for (final profile in _profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  Future<void> saveProfile(AiProfile profile, {String? apiKey}) async {
    await _writeApiKey(profile.id, apiKey);
    final loaded = profile.copyWith(apiKey: await _readApiKey(profile.id));
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index == -1) {
      _profiles = [..._profiles, loaded];
    } else {
      _profiles = [
        for (var i = 0; i < _profiles.length; i++)
          if (i == index) loaded else _profiles[i],
      ];
    }
    await _persistMetadata();
    notifyListeners();
  }

  Future<void> deleteProfile(String id) async {
    if (_profiles.length <= 1) return;
    _profiles = _profiles.where((p) => p.id != id).toList();
    await _secureStorage.delete(key: _secretKey(id));
    if (_activeProfileId == id) {
      _activeProfileId = _profiles.first.id;
      await _prefs.setString(_activeProfileKey, _activeProfileId!);
    }
    await _persistMetadata();
    notifyListeners();
  }

  Future<void> setActiveProfile(String id) async {
    if (profileById(id) == null) return;
    _activeProfileId = id;
    await _prefs.setString(_activeProfileKey, id);
    notifyListeners();
  }

  Future<void> setXybridModel(String id) async {
    final current = profileById('xybrid') ?? activeProfile;
    final updated = current.copyWith(model: id);
    await saveProfile(updated);
    await _prefs.setString(_legacyModelId, id);
  }

  Future<void> setXybridApiKey(String value) async {
    final trimmed = value.trim();
    final current = profileById('xybrid') ?? activeProfile;
    await saveProfile(current, apiKey: trimmed.isEmpty ? null : trimmed);
    await _prefs.remove(_legacyApiKey);
  }

  Future<void> _load() async {
    final raw = _prefs.getString(_profilesKey);
    if (raw == null || raw.isEmpty) {
      await _createDefaultProfiles();
      return;
    }

    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      await _createDefaultProfiles();
      return;
    }

    final profiles = <AiProfile>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final metadata = Map<String, dynamic>.from(item);
      final id = metadata['id'] as String?;
      if (id == null || id.isEmpty) continue;
      profiles.add(
        AiProfile.fromMetadataJson(metadata, apiKey: await _readApiKey(id)),
      );
    }

    if (profiles.isEmpty) {
      await _createDefaultProfiles();
      return;
    }

    _profiles = profiles;
    _activeProfileId = _prefs.getString(_activeProfileKey);
    if (profileById(_activeProfileId ?? '') == null) {
      _activeProfileId = _profiles.first.id;
      await _prefs.setString(_activeProfileKey, _activeProfileId!);
    }
  }

  Future<void> _createDefaultProfiles() async {
    final legacyModel =
        _prefs.getString(_legacyModelId) ?? LlmService.defaultModelId;
    final legacyKey = _prefs.getString(_legacyApiKey);
    final xybrid = AiProfile.xybrid(model: legacyModel, apiKey: legacyKey);
    _profiles = [xybrid];
    _activeProfileId = xybrid.id;
    if (legacyKey != null && legacyKey.isNotEmpty) {
      await _secureStorage.write(key: _secretKey(xybrid.id), value: legacyKey);
      await _prefs.remove(_legacyApiKey);
    }
    await _prefs.setString(_activeProfileKey, xybrid.id);
    await _persistMetadata();
  }

  Future<void> _persistMetadata() async {
    final json = jsonEncode(
      _profiles.map((profile) => profile.toMetadataJson()).toList(),
    );
    await _prefs.setString(_profilesKey, json);
  }

  Future<String?> _readApiKey(String profileId) {
    return _secureStorage.read(key: _secretKey(profileId));
  }

  Future<void> _writeApiKey(String profileId, String? apiKey) async {
    final trimmed = apiKey?.trim() ?? '';
    if (trimmed.isEmpty) {
      await _secureStorage.delete(key: _secretKey(profileId));
    } else {
      await _secureStorage.write(key: _secretKey(profileId), value: trimmed);
    }
  }

  static String _secretKey(String profileId) => 'ai.profile.$profileId.apiKey';
}
