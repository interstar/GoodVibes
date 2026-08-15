import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:flutter/material.dart';

import 'app.dart';
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

  final llm = LlmService();
  try {
    await llm.init(apiKey: settings.apiKey);
  } catch (e) {
    // The rest of the app still works; generation will surface this error.
    debugPrint('Xybrid init failed: $e');
  }

  final catalog = AppCatalog(settings);
  await catalog.init();

  final server = LocalServer();
  await server.start(catalog.appsDir!.path);

  runApp(GoodVibesApp(
    settings: settings,
    catalog: catalog,
    server: server,
    llm: llm,
  ));
}
