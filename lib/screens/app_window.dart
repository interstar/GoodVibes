import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';

/// Opens a web app in a browser-style native window (embedded WebView).
Future<void> openAppInBrowser({
  required String url,
  required String title,
}) async {
  final available = await WebviewWindow.isWebviewAvailable();
  if (!available) {
    throw StateError('WebView is not available on this system.');
  }

  final webview = await WebviewWindow.create(
    configuration: CreateConfiguration(
      windowWidth: 1100,
      windowHeight: 800,
      title: title,
      titleBarHeight: 44,
      titleBarTopPadding: Platform.isMacOS ? 24 : 0,
    ),
  );
  webview.launch(url);
}
