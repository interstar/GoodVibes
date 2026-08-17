import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:good_vibes/services/ai_profile.dart';
import 'package:good_vibes/services/app_generator.dart';
import 'package:good_vibes/services/llm_service.dart';
import 'package:path/path.dart' as p;

/// End-to-end test of the live LLM flow: load the on-device model (downloading
/// it on first run), stream a generation request, parse the resulting JSON, and
/// write the app to disk.
///
/// Run explicitly:
///   flutter test integration_test/llm_live_test.dart -d linux
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('vibe flow: generate, parse, and install an app', (tester) async {
    final llm = LlmService(modelId: 'llama-3.2-1b');
    await llm.init();

    // Load the model, streaming download progress so the long first run is
    // visible in the console.
    await llm.ensureReady(
      onStatus: (status) {
        if (status.percentage != null) {
          debugPrint('downloading model: ${status.percentage}%');
        } else if (status.isError) {
          debugPrint('model load error: ${status.message}');
        }
      },
    );

    // A faithful version of the Vibe Studio's system prompt.
    final system = await AppGenerator.buildSystemPrompt(
      installedApps: const [],
    );
    final context = AiConversation();
    context.setSystem(system);

    debugPrint('--- generating ---');
    final buffer = StringBuffer();
    var lastPrint = 0;
    await for (final token in llm.streamChat(
      context,
      'Build a simple pomodoro timer app.',
    )) {
      if (token.isError) {
        fail('generation failed: ${token.errorMessage}');
      }
      buffer.write(token.text);
      if (buffer.length - lastPrint >= 200) {
        debugPrint('...${buffer.length} chars so far');
        lastPrint = buffer.length;
      }
    }
    context.pushAssistant(buffer.toString());

    final text = buffer.toString();
    debugPrint('--- model output length: ${text.length} chars ---');
    debugPrint('--- RAW OUTPUT START ---\n$text\n--- RAW OUTPUT END ---');
    expect(text.trim().isNotEmpty, isTrue);

    // Parse + install exactly like the UI does.
    final generated = AppGenerator.parse(text);
    final appsDir = await Directory.systemTemp.createTemp('gv_e2e_apps');
    final installed = await AppGenerator.write(
      appsDir: appsDir,
      app: generated,
    );

    expect(File(p.join(installed.dir, 'manifest.json')).existsSync(), isTrue);
    expect(File(p.join(installed.dir, 'index.html')).existsSync(), isTrue);
    debugPrint('installed app id: ${generated.id}');
    debugPrint('installed app name: ${generated.name}');
    debugPrint('installed files: ${generated.files.keys.toList()}');
  }, timeout: const Timeout(Duration(minutes: 45)));
}
