import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/app_manifest.dart';
import 'app_catalog.dart';

/// A generated app: a slug id, display metadata, and a map of relative
/// file paths to their file contents.
class GeneratedApp {
  final String id;
  final String name;
  final String description;
  final Map<String, String> files;

  const GeneratedApp({
    required this.id,
    required this.name,
    required this.description,
    required this.files,
  });
}

/// A parse failure with the raw model text kept for the user to inspect/retry.
class GenerateParseException implements Exception {
  final String message;
  final String rawText;
  GenerateParseException(this.message, this.rawText);

  @override
  String toString() => message;
}

/// Knows the app structure, builds the system prompt for the LLM, parses its
/// output, and writes the generated app into the user's apps directory.
class AppGenerator {
  /// The contract that tells the LLM what a Good Vibes app is. Also shown in
  /// the Vibe Studio UI so users understand what will be built.
  static const String appStructureSpec = '''
## What a Good Vibes app is

A Good Vibes app is a small, self-contained HTML app stored in its own folder. 
It is created from a folder containing:

- manifest.json - metadata about the app
- index.html - the entry point (a single self-contained HTML file)
- optional extra files, e.g. styles.css, script.js, icon.svg, assets

### manifest.json schema
{
  "id": "kebab-case-unique-slug",
  "name": "Human readable name",
  "description": "One or two sentence summary",
  "version": "1.0.0",
  "icon": "icon.svg",      // optional, relative path to an icon
  "entry": "index.html"    // optional, defaults to index.html
}

### Rules for good apps
- Everything must be self-contained: no external CDNs, no network requests,
  no remote fonts or images. Inline CSS and JS in index.html is fine.
- Use relative paths for any local assets.
- It must run correctly when index.html is opened in a browser.
- Give it a nice, cohesive look: a pleasant layout, sane fonts and colors,
  and support for light/dark color schemes where reasonable.
- Keep it simple and single-purpose. One screen is fine.
- Do not use localStorage (the browser may clear it); keep state in memory.

### Output format

Reply with exactly one app block, fenced like this:

<app>
id: pomodoro-timer
name: Pomodoro Timer
description: A simple focus timer that chimes every 25 minutes.

=== FILE: index.html ===
<!DOCTYPE html>
<html>
... your entire, complete, working page ...
</html>

=== FILE: styles.css ===
...optional extra files follow the same pattern...
</app>

Rules:
- The <app> and </app> markers must be on their own lines.
- After the closing </app> you may add nothing except optional closing words.
- The three header lines (id, name, description) come first.
- Every file is introduced by a "=== FILE: <path> ===" line and its content runs
  until the next "=== FILE:" line or the closing </app>. Put each file's full
  contents between its marker and the next marker.
- index.html is REQUIRED and must be a complete, valid page that runs when
  opened in a browser. Inline CSS and JS in index.html is encouraged.
- Never truncate or elide a file - write every file completely.
- The "id" must be a kebab-case slug unique to this app. If the user asks for
  something similar to an existing app, pick a distinct id.
''';

  /// Build the system prompt: the app structure plus the currently installed
  /// apps (so the model knows what exists), optionally including a reference
  /// app's source as a style/structure exemplar.
  static Future<String> buildSystemPrompt({
    List<InstalledApp> installedApps = const [],
    InstalledApp? referenceApp,
  }) async {
    final buffer = StringBuffer()
      ..writeln('You are the Good Vibes app builder. You turn a user\'s casual '
          'request into a working HTML app that gets installed into their local '
          'app store.')
      ..writeln()
      ..writeln(appStructureSpec)
      ..writeln('## Installed apps')
      ..writeln('Here is the current app store so you know what already exists '
          'and can match the vibe of a request like "make me one like the '
          'calculator".')
      ..writeln();

    final apps = installedApps;
    if (apps.isEmpty) {
      buffer.writeln('- (no apps installed yet)');
    } else {
      for (final app in apps) {
        buffer
            .writeln('- ${app.manifest.name} (id: ${app.manifest.id}): '
                '${app.manifest.description}');
      }
    }

    if (referenceApp != null) {
      buffer
        ..writeln()
        ..writeln('## Reference app: ${referenceApp.manifest.name}')
        ..writeln('The user chose this app as the style and structure to '
            'emulate. Here is its source - study the look, layout, and '
            'implementation so your new app feels like part of the same '
            'family, but build something new.')
        ..writeln()
        ..writeln('<reference-app-source>')
        ..writeln(await _readReferenceSource(referenceApp))
        ..writeln('</reference-app-source>');
    }

    buffer
      ..writeln()
      ..writeln('Remember: reply with only the ```json code block described '
          'above. Do not add commentary outside the code block.');

    return buffer.toString();
  }

  static Future<String> _readReferenceSource(InstalledApp app) async {
    final file = File(app.entryPath);
    if (!await file.exists()) return '(entry file missing)';
    return file.readAsString();
  }

  static final _slugRe = RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$');

  /// Parse the model's reply into a [GeneratedApp]. Tries, in order:
  /// 1. the `<app>` fenced-file format (see [appStructureSpec]),
  /// 2. a ```json code block (for models that still emit JSON),
  /// 3. a bare HTML document as the whole app.
  static GeneratedApp parse(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw GenerateParseException('The model did not return any code.', text);
    }

    final block = _tryAppBlock(trimmed);
    if (block != null) return block;

    final jsonBlock = _tryJsonBlock(trimmed);
    if (jsonBlock != null) return jsonBlock;

    final html = _tryHtmlFallback(trimmed);
    if (html != null) return html;

    throw GenerateParseException(
      'The model\'s output did not look like a Good Vibes app. It should '
      'contain an <app> block (see the format spec).',
      text,
    );
  }

  static bool _isValidSlug(String id) => _slugRe.hasMatch(id);

  static String _safeName(String? name, String id) {
    final n = name?.trim() ?? '';
    if (n.isNotEmpty) return n;
    return id;
  }

  static Map<String, String> _filterFiles(Map<String, String> files) {
    final clean = <String, String>{};
    for (final entry in files.entries) {
      final name = entry.key.replaceAll('\\', '/');
      if (name.isEmpty || name == '.' || name.contains('../')) continue;
      clean[name] = entry.value;
    }
    return clean;
  }

  static GeneratedApp _finish(
    String id,
    String name,
    String description,
    Map<String, String> files,
    String text,
  ) {
    final cleanId = id.trim().toLowerCase();
    if (!_isValidSlug(cleanId)) {
      throw GenerateParseException(
        'The generated app has an invalid id ("$id"). It must be a '
        'kebab-case slug.',
        text,
      );
    }
    final cleanFiles = _filterFiles(files);
    if (!cleanFiles.containsKey('index.html')) {
      throw GenerateParseException(
        'The generated app is missing its index.html entry file.',
        text,
      );
    }
    return GeneratedApp(
      id: cleanId,
      name: _safeName(name, cleanId),
      description: description.trim(),
      files: cleanFiles,
    );
  }

  /// Parse the `<app>...</app>` fenced-file format.
  static GeneratedApp? _tryAppBlock(String text) {
    final match =
        RegExp(r'<app>([\s\S]*?)</app>', caseSensitive: false).firstMatch(text);
    if (match == null) return null;
    final body = match.group(1)!;

    final fileMarker = RegExp(
      r'^=== FILE:\s*(.+?)\s*===\s*$',
      multiLine: true,
    );

    final starts = <int>[];
    final markerEnds = <int>[];
    final names = <String>[];
    for (final m in fileMarker.allMatches(body)) {
      starts.add(m.start);
      markerEnds.add(m.end);
      names.add(m.group(1)!.trim());
    }
    if (starts.isEmpty) return null;

    // Everything before the first file marker is the metadata header.
    final header = body.substring(0, starts.first);
    String? id, name, description;
    for (final line in header.split('\n')) {
      final m = RegExp(r'^\s*(id|name|description)\s*:\s*(.*)$')
          .firstMatch(line);
      if (m == null) continue;
      final key = m.group(1)!;
      final value = m.group(2)!.trim();
      if (key == 'id') {
        id = value;
      } else if (key == 'name') {
        name = value;
      } else if (key == 'description') {
        description = value;
      }
    }

    final files = <String, String>{};
    for (var i = 0; i < starts.length; i++) {
      final contentEnd = i + 1 < starts.length ? starts[i + 1] : body.length;
      files[names[i]] = body.substring(markerEnds[i], contentEnd).trim();
    }

    return _finish(id ?? '', name ?? '', description ?? '', files, text);
  }

  /// Parse the legacy ```json code block format.
  static GeneratedApp? _tryJsonBlock(String text) {
    final match = RegExp(r'```json\s*([\s\S]*?)```', caseSensitive: false)
        .firstMatch(text);
    final raw = match?.group(1)?.trim() ?? text.trim();
    if (raw.isEmpty || !raw.startsWith('{')) return null;

    Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }

    final files = <String, String>{};
    final filesJson = json['files'];
    if (filesJson is Map) {
      filesJson.forEach((key, value) {
        final name = key.toString();
        files[name] = value?.toString() ?? '';
      });
    }
    return _finish(
      json['id'] as String? ?? '',
      json['name'] as String? ?? '',
      json['description'] as String? ?? '',
      files,
      text,
    );
  }

  /// Rescue: if the whole reply is an HTML document, use it as index.html.
  static GeneratedApp? _tryHtmlFallback(String text) {
    final lower = text.toLowerCase();
    if (!(lower.startsWith('<!doctype') ||
        lower.startsWith('<html') ||
        lower.startsWith('<head') ||
        lower.startsWith('<body'))) {
      return null;
    }
    return GeneratedApp(
      id: 'my-app',
      name: 'My App',
      description: '',
      files: {'index.html': text},
    );
  }

  /// Write the generated app into `appsDir/<id>`, overwriting an existing app
  /// with the same id. Returns the installed app.
  static Future<InstalledApp> write({
    required Directory appsDir,
    required GeneratedApp app,
  }) async {
    final dir = Directory(p.join(appsDir.path, app.id));
    await dir.create(recursive: true);

    for (final entry in app.files.entries) {
      final target = File(p.join(dir.path, entry.key));
      await target.parent.create(recursive: true);
      await target.writeAsString(entry.value);
    }

    final manifest = AppManifest(
      id: app.id,
      name: app.name,
      description: app.description,
      version: '1.0.0',
      icon: app.files.containsKey('icon.svg') ? 'icon.svg' : null,
    );
    await File(p.join(dir.path, 'manifest.json')).writeAsString(manifest.encode());
    return InstalledApp(manifest: manifest, dir: dir.path);
  }
}
