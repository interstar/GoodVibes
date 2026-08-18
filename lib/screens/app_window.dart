import 'dart:convert';
import 'dart:io';

import 'package:desktop_webview_window/desktop_webview_window.dart';

/// Opens a web app in a browser-style native window (embedded WebView) with
/// Good Vibes controls injected over the generated app.
Future<void> openAppInBrowser({
  required String url,
  required String title,
  void Function(String? consoleText)? onEdit,
}) async {
  final available = await WebviewWindow.isWebviewAvailable();
  if (!available) {
    throw StateError('WebView is not available on this system.');
  }

  final webview = await _createWindow(title: title);
  if (Platform.isLinux || Platform.isMacOS) {
    webview.registerJavaScriptMessageHandler('goodVibes', (_, body) async {
      final closeAfterAction = await _handleGoodVibesMessage(
        url: url,
        body: body,
        onEdit: onEdit,
      );
      if (closeAfterAction) {
        webview.close();
      }
    });
  }
  webview.addScriptToExecuteOnDocumentCreated(_appChromeScript);
  webview.launch(url);
}

/// Opens a web app URL in the user's normal system browser.
Future<void> openAppInSystemBrowser({required String url}) async {
  ProcessResult result;
  if (Platform.isLinux) {
    result = await Process.run('xdg-open', [url]);
  } else if (Platform.isMacOS) {
    result = await Process.run('open', [url]);
  } else if (Platform.isWindows) {
    result = await Process.run('cmd', ['/c', 'start', '', url]);
  } else {
    throw StateError('Opening a system browser is not supported here.');
  }

  if (result.exitCode != 0) {
    final message = [
      result.stderr,
      result.stdout,
    ].where((part) => part.toString().trim().isNotEmpty).join('\n');
    throw StateError(message.isEmpty ? 'Browser command failed.' : message);
  }
}

Future<bool> _handleGoodVibesMessage({
  required String url,
  required dynamic body,
  required void Function(String? consoleText)? onEdit,
}) async {
  final Object? decoded;
  try {
    decoded = body is String ? jsonDecode(body) : body;
  } catch (_) {
    return false;
  }
  if (decoded is! Map) return false;
  final action = decoded['action'] as String?;
  final consoleText = decoded['console'] as String?;
  if (action == 'edit') {
    onEdit?.call(consoleText);
    return true;
  } else if (action == 'browser') {
    await openAppInSystemBrowser(url: url);
  }
  return false;
}

Future<Webview> _createWindow({required String title}) {
  return WebviewWindow.create(
    configuration: CreateConfiguration(
      windowWidth: 1100,
      windowHeight: 800,
      title: title,
      titleBarHeight: Platform.isLinux ? 0 : 44,
      titleBarTopPadding: Platform.isMacOS ? 24 : 0,
    ),
  );
}

const String _appChromeScript = r'''
(function () {
  if (window.__goodVibesChromeInstalled) return;
  window.__goodVibesChromeInstalled = true;

  const MAX_ROWS = 250;
  const entries = [];
  let consoleRoot;
  let consoleBody;
  let badge;
  let expanded = false;
  let errorCount = 0;

  function stringify(value) {
    try {
      if (value instanceof Error) return value.stack || value.message || String(value);
      if (typeof value === 'string') return value;
      return JSON.stringify(value, null, 2);
    } catch (_) {
      return String(value);
    }
  }

  function exportLog() {
    return entries.map((entry) => '[' + entry.time + '] ' + entry.level.toUpperCase() + ': ' + entry.text).join('\n');
  }

  function sendGoodVibes(action) {
    const payload = JSON.stringify({ action: action, console: exportLog() });
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.goodVibes) {
        window.webkit.messageHandlers.goodVibes.postMessage(payload);
        return;
      }
    } catch (_) {}
    append('warn', ['Good Vibes control bridge is not available in this window.']);
  }

  function ensureUi() {
    if (consoleRoot || !document.documentElement) return;
    const host = document.body || document.documentElement;

    const style = document.createElement('style');
    style.textContent = `
      #good-vibes-toolbar, #good-vibes-console {
        box-sizing: border-box;
        z-index: 2147483647;
        font: 12px/1.35 ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      }
      #good-vibes-toolbar *, #good-vibes-console * { box-sizing: border-box; }
      #good-vibes-toolbar {
        position: fixed;
        top: 14px;
        right: 14px;
        display: flex;
        gap: 6px;
        padding: 6px;
        border-radius: 10px;
        background: rgba(15, 23, 42, 0.88);
        border: 1px solid rgba(148, 163, 184, 0.45);
        box-shadow: 0 12px 32px rgba(0, 0, 0, 0.28);
        backdrop-filter: blur(10px);
      }
      #good-vibes-toolbar button, #good-vibes-console button {
        all: unset;
        cursor: pointer;
        border-radius: 7px;
        color: #f8fafc;
        background: rgba(148, 163, 184, 0.16);
      }
      #good-vibes-toolbar button {
        min-width: 34px;
        height: 30px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        padding: 0 9px;
        font-weight: 700;
      }
      #good-vibes-toolbar button:hover, #good-vibes-console .gvc-action:hover,
      #good-vibes-console .gvc-title:hover { background: rgba(148, 163, 184, 0.28); }
      #good-vibes-console {
        position: fixed;
        right: 14px;
        bottom: 14px;
        width: min(560px, calc(100vw - 28px));
        max-height: min(360px, calc(100vh - 28px));
        color: #f8fafc;
        background: rgba(15, 23, 42, 0.96);
        border: 1px solid rgba(148, 163, 184, 0.5);
        box-shadow: 0 18px 48px rgba(0, 0, 0, 0.35);
        border-radius: 10px;
        overflow: hidden;
      }
      #good-vibes-console .gvc-head {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 8px 10px;
        background: rgba(30, 41, 59, 0.98);
        border-bottom: 1px solid rgba(148, 163, 184, 0.25);
      }
      #good-vibes-console .gvc-title {
        flex: 1;
        padding: 4px 8px;
        font-weight: 700;
      }
      #good-vibes-console .gvc-badge {
        min-width: 18px;
        height: 18px;
        padding: 0 6px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        border-radius: 999px;
        background: #475569;
        color: white;
        font-size: 11px;
      }
      #good-vibes-console.has-errors .gvc-badge { background: #dc2626; }
      #good-vibes-console .gvc-action {
        padding: 4px 8px;
        color: #cbd5e1;
      }
      #good-vibes-console .gvc-body {
        display: none;
        max-height: 300px;
        overflow: auto;
        padding: 8px 0;
        font: 12px/1.35 ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
      }
      #good-vibes-console.expanded .gvc-body { display: block; }
      #good-vibes-console .gvc-row {
        white-space: pre-wrap;
        word-break: break-word;
        padding: 4px 10px;
        border-left: 3px solid transparent;
      }
      #good-vibes-console .gvc-log { color: #e2e8f0; }
      #good-vibes-console .gvc-warn { color: #fde68a; border-left-color: #f59e0b; }
      #good-vibes-console .gvc-error { color: #fecaca; border-left-color: #ef4444; }
      #good-vibes-console .gvc-info { color: #bfdbfe; border-left-color: #3b82f6; }
    `;
    host.appendChild(style);

    const toolbar = document.createElement('nav');
    toolbar.id = 'good-vibes-toolbar';
    toolbar.innerHTML = `
      <button type="button" class="gv-edit" title="Edit this app">Edit</button>
      <button type="button" class="gv-browser" title="Open in system browser">Browser</button>
      <button type="button" class="gv-console" title="Show console">Console</button>
    `;
    host.appendChild(toolbar);
    toolbar.querySelector('.gv-edit').addEventListener('click', () => sendGoodVibes('edit'));
    toolbar.querySelector('.gv-browser').addEventListener('click', () => sendGoodVibes('browser'));
    toolbar.querySelector('.gv-console').addEventListener('click', toggle);

    consoleRoot = document.createElement('section');
    consoleRoot.id = 'good-vibes-console';
    consoleRoot.innerHTML = `
      <div class="gvc-head">
        <button class="gvc-title" type="button">Good Vibes Console</button>
        <span class="gvc-badge">0</span>
        <button class="gvc-action gvc-copy" type="button">Copy</button>
        <button class="gvc-action gvc-clear" type="button">Clear</button>
      </div>
      <div class="gvc-body"></div>
    `;
    host.appendChild(consoleRoot);
    consoleBody = consoleRoot.querySelector('.gvc-body');
    badge = consoleRoot.querySelector('.gvc-badge');
    consoleRoot.querySelector('.gvc-title').addEventListener('click', toggle);
    consoleRoot.querySelector('.gvc-copy').addEventListener('click', copyLog);
    consoleRoot.querySelector('.gvc-clear').addEventListener('click', clearLog);
    render();
  }

  function toggle() {
    expanded = !expanded;
    consoleRoot.classList.toggle('expanded', expanded);
  }

  function append(level, args) {
    try {
      const text = args.map(stringify).join(' ');
      entries.push({ level, text, time: new Date().toLocaleTimeString() });
      if (entries.length > MAX_ROWS) entries.shift();
      if (level === 'error') errorCount += 1;
      ensureUi();
      render();
    } catch (_) {}
  }

  function render() {
    if (!consoleRoot || !consoleBody) return;
    consoleRoot.classList.toggle('has-errors', errorCount > 0);
    badge.textContent = String(errorCount || entries.length);
    consoleBody.replaceChildren(...entries.map((entry) => {
      const row = document.createElement('div');
      row.className = 'gvc-row gvc-' + entry.level;
      row.textContent = '[' + entry.time + '] ' + entry.level.toUpperCase() + ': ' + entry.text;
      return row;
    }));
    consoleBody.scrollTop = consoleBody.scrollHeight;
  }

  function clearLog() {
    entries.length = 0;
    errorCount = 0;
    render();
  }

  async function copyLog() {
    try { await navigator.clipboard.writeText(exportLog()); } catch (_) {}
  }

  ['log', 'info', 'warn', 'error'].forEach((name) => {
    const original = console[name] ? console[name].bind(console) : console.log.bind(console);
    console[name] = function (...args) {
      append(name === 'log' ? 'log' : name, args);
      try {
        original(...args);
      } catch (_) {}
    };
  });

  window.addEventListener('error', (event) => {
    append('error', [
      event.message || 'Script error',
      event.filename ? event.filename + ':' + event.lineno + ':' + event.colno : '',
      event.error && event.error.stack ? event.error.stack : '',
    ].filter(Boolean));
  });

  window.addEventListener('unhandledrejection', (event) => {
    append('error', ['Unhandled promise rejection:', event.reason]);
  });

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', ensureUi, { once: true });
  } else {
    ensureUi();
  }
  append('info', ['Good Vibes app controls ready']);
})();
''';
