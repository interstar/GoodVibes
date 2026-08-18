import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:good_vibes/models/app_manifest.dart';
import 'package:good_vibes/services/app_catalog.dart';
import 'package:good_vibes/services/app_generator.dart';

void main() {
  group('AppGenerator.parse', () {
    test('parses the fenced-file app block format', () {
      final text =
          'Sure! Here it is:\n\n'
          '<app>\n'
          'id: pomodoro-timer\n'
          'name: Pomodoro Timer\n'
          'description: A focus timer\n'
          '\n'
          '=== FILE: index.html ===\n'
          '<!DOCTYPE html>\n'
          '<html><body>hi</body></html>\n'
          '=== FILE: styles.css ===\n'
          'body { color: red; }\n'
          '</app>\n'
          'Enjoy!';

      final app = AppGenerator.parse(text);
      expect(app.id, 'pomodoro-timer');
      expect(app.name, 'Pomodoro Timer');
      expect(app.files['index.html'], contains('<!DOCTYPE html>'));
      expect(app.files['styles.css'], contains('body { color: red; }'));
    });

    test('keeps multi-line file contents intact', () {
      final text =
          '<app>\n'
          'id: notes\n'
          'name: Notes\n'
          'description: a\n'
          '=== FILE: index.html ===\n'
          'line1\n'
          'line2\n'
          '\n'
          'line4\n'
          '</app>';

      final app = AppGenerator.parse(text);
      expect(app.files['index.html'], 'line1\nline2\n\nline4');
    });

    test('extracts the json code block from a chatty reply', () {
      final text =
          'Sure! Here is your app:\n\n'
          '```json\n'
          '{\n'
          '  "id": "pomodoro-timer",\n'
          '  "name": "Pomodoro Timer",\n'
          '  "description": "A focus timer",\n'
          '  "files": {\n'
          '    "index.html": "<!DOCTYPE html>",\n'
          '    "styles.css": "body {}"\n'
          '  }\n'
          '}\n'
          '```\n'
          'Enjoy!';

      final app = AppGenerator.parse(text);
      expect(app.id, 'pomodoro-timer');
      expect(app.name, 'Pomodoro Timer');
      expect(app.files['index.html'], '<!DOCTYPE html>');
      expect(app.files['styles.css'], 'body {}');
    });

    test('parses a bare json block with no fences', () {
      final text =
          '{"id":"notes","name":"Notes","description":"","files":'
          '{"index.html":"<html></html>"}}';

      final app = AppGenerator.parse(text);
      expect(app.id, 'notes');
      expect(app.files['index.html'], '<html></html>');
    });

    test('rescues a bare html reply into an index.html app', () {
      final app = AppGenerator.parse(
        '<!DOCTYPE html><html><body>hi</body></html>',
      );
      expect(app.id, 'my-app');
      expect(app.files['index.html'], contains('<body>'));
    });

    test('rejects a truncated <app> block with no closing tag', () {
      final text =
          '<app>\n'
          'id: timer\n'
          'name: Timer\n'
          'description: a\n'
          '=== FILE: index.html ===\n'
          '<!DOCTYPE html>\n'
          '<html><body>hi</body></html>';
      expect(
        () => AppGenerator.parse(text),
        throwsA(isA<GenerateParseException>()),
      );
    });

    test('rejects an invalid id', () {
      expect(
        () => AppGenerator.parse(
          '{"id":"Bad ID","name":"x","files":'
          '{"index.html":""}}',
        ),
        throwsA(isA<GenerateParseException>()),
      );
      expect(
        () => AppGenerator.parse(
          '<app>\nid: Bad ID\nname: x\n'
          '=== FILE: index.html ===\nhi\n</app>',
        ),
        throwsA(isA<GenerateParseException>()),
      );
    });

    test('rejects output without index.html', () {
      expect(
        () => AppGenerator.parse(
          '{"id":"ok","name":"x","files":'
          '{"style.css":""}}',
        ),
        throwsA(isA<GenerateParseException>()),
      );
    });

    test('rejects non-app output', () {
      expect(
        () => AppGenerator.parse('Sorry, I could not build that.'),
        throwsA(isA<GenerateParseException>()),
      );
    });
  });

  group('AppGenerator.write', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('gv_test_');
    });

    tearDown(() async {
      await temp.delete(recursive: true);
    });

    GeneratedApp generated(String id) => GeneratedApp(
      id: id,
      name: 'Test App',
      description: 'desc',
      files: {'index.html': '<html>new</html>'},
    );

    test('writes into the generated id by default', () async {
      final app = await AppGenerator.write(
        appsDir: temp,
        app: generated('alpha'),
      );
      expect(app.manifest.id, 'alpha');
      expect(app.dir, endsWith('/alpha'));
      expect(
        File('${app.dir}/index.html').readAsStringSync(),
        '<html>new</html>',
      );
    });

    test('overrideId forces the target folder and manifest id', () async {
      final app = await AppGenerator.write(
        appsDir: temp,
        app: generated('renamed-elsewhere'),
        overrideId: 'existing-app',
      );
      expect(app.manifest.id, 'existing-app');
      expect(
        File('${app.dir}/manifest.json').readAsStringSync(),
        contains('"id": "existing-app"'),
      );
    });

    test('keepUnmentionedFiles preserves untouched files', () async {
      final existing = Directory('${temp.path}/beta');
      await existing.create(recursive: true);
      File('${existing.path}/icon.svg').writeAsStringSync('<svg/>');

      final app = await AppGenerator.write(
        appsDir: temp,
        app: generated('beta'),
        overrideId: 'beta',
        keepUnmentionedFiles: true,
      );
      expect(File('${app.dir}/icon.svg').existsSync(), isTrue);
      expect(
        File('${app.dir}/index.html').readAsStringSync(),
        '<html>new</html>',
      );
    });

    test('without keepUnmentionedFiles a stale folder is wiped', () async {
      final existing = Directory('${temp.path}/gamma');
      await existing.create(recursive: true);
      File('${existing.path}/old.js').writeAsStringSync('leftover');

      final app = await AppGenerator.write(
        appsDir: temp,
        app: generated('gamma'),
      );
      expect(File('${app.dir}/old.js').existsSync(), isFalse);
      expect(File('${app.dir}/index.html').existsSync(), isTrue);
    });
  });

  group('AppGenerator.buildSystemPrompt', () {
    final installed = InstalledApp(
      manifest: const AppManifest(
        id: 'hello-world',
        name: 'Hello World',
        description: 'Greeter',
        version: '1.0.0',
      ),
      dir: '/nope/hello-world',
    );

    test(
      'edit mode instructs the model to keep the id and include source',
      () async {
        final prompt = await AppGenerator.buildSystemPrompt(editApp: installed);
        expect(prompt, contains('Task: edit the existing app'));
        expect(prompt, contains('The id MUST stay "hello-world"'));
        expect(prompt, contains('Output the COMPLETE updated files'));
      },
    );

    test('edit mode ignores the reference app', () async {
      final prompt = await AppGenerator.buildSystemPrompt(
        referenceApp: installed,
        editApp: installed,
      );
      expect(prompt, contains('Task: edit the existing app'));
      expect(prompt, isNot(contains('Reference app:')));
    });
  });

  group('AppGenerator.findMissingReferences', () {
    test('flags referenced files that were not emitted', () {
      final app = GeneratedApp(
        id: 'x',
        name: 'X',
        description: '',
        files: {
          'index.html':
              '<script src="app.js"></script><link href="styles.css" rel="stylesheet">',
        },
      );
      expect(AppGenerator.findMissingReferences(app), ['app.js', 'styles.css']);
    });

    test('ignores emitted files, urls, anchors and existing files', () async {
      final temp = await Directory.systemTemp.createTemp('gv_miss_');
      File('${temp.path}/styles.css').writeAsStringSync('body{}');
      addTearDown(() => temp.delete(recursive: true));

      final app = GeneratedApp(
        id: 'x',
        name: 'X',
        description: '',
        files: {
          'index.html':
              '<script src="app.js"></script><link href="styles.css" '
              'rel="stylesheet"><a href="#sec">x</a><a href="https://a.b/c">y</a>',
          'app.js': 'console.log(1)',
        },
      );
      expect(
        AppGenerator.findMissingReferences(app, existingDir: temp),
        isEmpty,
      );
    });
  });

  group('AppGenerator default helpers', () {
    test('spec embeds the default template', () {
      expect(AppGenerator.appStructureSpec, contains('### Default template'));
      expect(
        AppGenerator.appStructureSpec,
        contains(AppGenerator.defaultTemplate),
      );
    });

    test('default template wires up Tailwind, Inter and the store helper', () {
      final t = AppGenerator.defaultTemplate;
      expect(t, contains('cdn.tailwindcss.com'));
      expect(t, contains('@theme'));
      expect(t, contains('--font-sans'));
      expect(t, contains('fonts.googleapis.com'));
      expect(t, contains('family=Inter'));
      expect(t, contains('const store'));
      expect(t, contains('localStorage.getItem'));
      expect(t, contains('localStorage.setItem'));
      expect(t, contains('BUILD YOUR APP INSIDE <main>'));
    });

    test('spec no longer forbids CDNs, remote fonts or localStorage', () {
      final spec = AppGenerator.appStructureSpec;
      expect(spec, isNot(contains('no external CDNs')));
      expect(spec, isNot(contains('Do not use localStorage')));
      expect(spec, contains('store.get'));
      expect(spec, contains('Tailwind utility classes'));
    });
  });
}
