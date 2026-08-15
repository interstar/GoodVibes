import 'dart:io';

import 'package:flutter/material.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:xybrid_flutter/xybrid_flutter.dart';

import 'package:good_vibes/models/app_manifest.dart';
import 'package:good_vibes/services/app_catalog.dart';
import 'package:good_vibes/services/app_generator.dart';
import 'package:good_vibes/services/llm_service.dart';

/// Live end-to-end test of the EDIT flow: seed an app on disk, ask the
/// on-device model to add a feature, and verify the app is updated in place
/// (same id, untouched files preserved).
///
/// Uses the cached on-device model llama-3.2-1b (no API key required).
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('edits an existing app in place', (tester) async {
    final dir = await Directory.systemTemp.createTemp('gv_edit_test_');

    // Seed an app on disk, the way AppCatalog would.
    final appDir = Directory('${dir.path}/counter');
    await appDir.create(recursive: true);
    File('${appDir.path}/index.html').writeAsStringSync(
      '<!DOCTYPE html><html><body><div id="count">0</div>'
      '<button id="inc" onclick="count.textContent=+count.textContent+1">+</button>'
      '</body></html>',
    );
    File('${appDir.path}/icon.svg').writeAsStringSync('<svg/>');
    File('${appDir.path}/manifest.json').writeAsStringSync(
      const AppManifest(
        id: 'counter',
        name: 'Counter',
        description: 'A simple counter',
        version: '1.0.0',
        icon: 'icon.svg',
      ).encode(),
    );
    final app = InstalledApp(
      manifest: const AppManifest(
        id: 'counter',
        name: 'Counter',
        description: 'A simple counter',
        version: '1.0.0',
        icon: 'icon.svg',
      ),
      dir: appDir.path,
    );

    final llm = LlmService(modelId: 'llama-3.2-1b');
    await llm.init();
    await llm.ensureModel();

    final context = ConversationContext();
    final system = await AppGenerator.buildSystemPrompt(editApp: app);
    context.setSystem(system);
    const userText = 'Add a reset button that sets the count back to 0.';

    final buffer = StringBuffer();
    final cancel = CancellationToken();
    await for (final token in llm.streamChat(context, userText,
        cancellationToken: cancel)) {
      if (token.isError) {
        fail('Stream error: ${token.errorMessage}');
      }
      buffer.write(token.token);
    }

    final fullText = buffer.toString().trim();
    debugPrint('--- EDIT RAW OUTPUT (${fullText.length} chars) ---');
    debugPrint(fullText);
    debugPrint('--- END ---');

    expect(fullText, isNotEmpty);

    final generated = AppGenerator.parse(fullText);
    final installed = await AppGenerator.write(
      appsDir: dir,
      app: generated,
      overrideId: 'counter',
      keepUnmentionedFiles: true,
    );

    // Same id, in place.
    expect(installed.manifest.id, 'counter');
    expect(installed.dir, appDir.path);

    // New functionality landed in index.html.
    final newHtml =
        File('${appDir.path}/index.html').readAsStringSync();
    expect(newHtml.toLowerCase(), contains('reset'));

    // Untouched files survived.
    expect(File('${appDir.path}/icon.svg').existsSync(), isTrue);

    await dir.delete(recursive: true);
  });
}
