import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ai_profile.dart';
import 'app_catalog.dart';

class AppChatEntry {
  final bool fromUser;
  final String text;
  final String? errorDetail;

  const AppChatEntry({
    required this.fromUser,
    required this.text,
    this.errorDetail,
  });

  factory AppChatEntry.fromJson(Map<String, dynamic> json) {
    return AppChatEntry(
      fromUser: json['fromUser'] as bool? ?? false,
      text: json['text'] as String? ?? '',
      errorDetail: json['errorDetail'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'fromUser': fromUser,
    'text': text,
    if (errorDetail != null) 'errorDetail': errorDetail,
  };
}

class AppChatSession {
  final List<AppChatEntry> transcript;
  final AiConversation conversation;

  const AppChatSession({required this.transcript, required this.conversation});
}

class AppChatStore {
  static const _dirName = '.goodvibes';
  static const _fileName = 'chat.json';

  static File _fileFor(InstalledApp app) {
    return File(p.join(app.dir, _dirName, _fileName));
  }

  static Future<bool> hasTranscript(InstalledApp app) async {
    return _fileFor(app).exists();
  }

  static Future<AppChatSession?> load(InstalledApp app) async {
    final file = _fileFor(app);
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) return null;
    final entriesJson = decoded['messages'];
    if (entriesJson is! List) return null;

    final entries = <AppChatEntry>[];
    final conversation = AiConversation();
    for (final item in entriesJson) {
      if (item is! Map) continue;
      final entry = AppChatEntry.fromJson(Map<String, dynamic>.from(item));
      if (entry.text.isEmpty) continue;
      entries.add(entry);
      if (entry.errorDetail != null) continue;
      if (entry.fromUser) {
        conversation.pushUser(entry.text);
      } else {
        conversation.pushAssistant(entry.text);
      }
    }
    return AppChatSession(transcript: entries, conversation: conversation);
  }

  static Future<void> save({
    required InstalledApp app,
    required List<AppChatEntry> transcript,
  }) async {
    final file = _fileFor(app);
    await file.parent.create(recursive: true);
    final data = {
      'version': 1,
      'appId': app.manifest.id,
      'updatedAt': DateTime.now().toIso8601String(),
      'messages': transcript.map((entry) => entry.toJson()).toList(),
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  static Future<void> delete(InstalledApp app) async {
    final file = _fileFor(app);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
