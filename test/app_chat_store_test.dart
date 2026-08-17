import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:good_vibes/models/app_manifest.dart';
import 'package:good_vibes/services/ai_profile.dart';
import 'package:good_vibes/services/app_catalog.dart';
import 'package:good_vibes/services/app_chat_store.dart';

void main() {
  test('AppChatStore persists transcript and rebuilds conversation', () async {
    final temp = await Directory.systemTemp.createTemp('gv_chat_store_');
    addTearDown(() => temp.delete(recursive: true));

    final app = InstalledApp(
      manifest: const AppManifest(
        id: 'notes',
        name: 'Notes',
        description: '',
        version: '1.0.0',
      ),
      dir: temp.path,
    );

    await AppChatStore.save(
      app: app,
      transcript: const [
        AppChatEntry(fromUser: true, text: 'make a notes app'),
        AppChatEntry(fromUser: false, text: '<app>...</app>'),
        AppChatEntry(
          fromUser: false,
          text: 'bad output',
          errorDetail: 'parse failed',
        ),
      ],
    );

    expect(await AppChatStore.hasTranscript(app), isTrue);

    final loaded = await AppChatStore.load(app);
    expect(loaded, isNotNull);
    expect(loaded!.transcript, hasLength(3));
    expect(loaded.transcript.last.errorDetail, 'parse failed');
    expect(loaded.conversation.messages, hasLength(2));
    expect(loaded.conversation.messages.first.role, 'user');
    expect(loaded.conversation.messages.last.role, 'assistant');
  });

  test('AiConversation replaces system message', () {
    final conversation = AiConversation();
    conversation.setSystem('old');
    conversation.pushUser('hello');
    conversation.setSystem('new');

    expect(conversation.messages, hasLength(2));
    expect(conversation.messages.first.role, 'system');
    expect(conversation.messages.first.content, 'new');
  });
}
