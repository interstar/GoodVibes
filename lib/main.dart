import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'services/ai_profile_store.dart';
import 'services/app_catalog.dart';
import 'services/llm_service.dart';
import 'services/local_server.dart';
import 'services/settings_service.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // On Linux, the webview plugin launches a nested Flutter engine for its
  // title bar; run that app and exit. On other platforms this is a no-op.
  if (runWebViewTitleBarWidget(args)) {
    return;
  }

  final settings = SettingsService();
  await settings.init();

  final profileStore = AiProfileStore();
  await profileStore.init();

  final llm = LlmService(profile: profileStore.activeProfile);
  // Provider initialization can perform network I/O and must never block the
  // window from appearing. It is awaited lazily on first use, with a timeout
  // inside the service so a hung handshake surfaces an error instead of an
  // invisible app.
  unawaited(
    llm.init().catchError((Object e) {
      debugPrint('AI provider init failed (will retry on next use): $e');
    }),
  );

  final catalog = AppCatalog(settings);
  await catalog.init();

  final server = LocalServer();
  await server.start(catalog.appsDir!.path);

  runApp(
    GoodVibesApp(
      settings: settings,
      catalog: catalog,
      server: server,
      llm: llm,
      profileStore: profileStore,
    ),
  );
}
