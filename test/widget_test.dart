import 'package:flutter_test/flutter_test.dart';

import 'package:good_vibes/services/app_generator.dart';

void main() {
  group('AppGenerator.parse', () {
    test('parses the fenced-file app block format', () {
      final text = 'Sure! Here it is:\n\n'
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
      final text = '<app>\n'
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
      final text = 'Sure! Here is your app:\n\n'
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
      final text = '{"id":"notes","name":"Notes","description":"","files":'
          '{"index.html":"<html></html>"}}';

      final app = AppGenerator.parse(text);
      expect(app.id, 'notes');
      expect(app.files['index.html'], '<html></html>');
    });

    test('rescues a bare html reply into an index.html app', () {
      final app = AppGenerator.parse('<!DOCTYPE html><html><body>hi</body></html>');
      expect(app.id, 'my-app');
      expect(app.files['index.html'], contains('<body>'));
    });

    test('rejects an invalid id', () {
      expect(
        () => AppGenerator.parse('{"id":"Bad ID","name":"x","files":'
            '{"index.html":""}}'),
        throwsA(isA<GenerateParseException>()),
      );
      expect(
        () => AppGenerator.parse('<app>\nid: Bad ID\nname: x\n'
            '=== FILE: index.html ===\nhi\n</app>'),
        throwsA(isA<GenerateParseException>()),
      );
    });

    test('rejects output without index.html', () {
      expect(
        () => AppGenerator.parse('{"id":"ok","name":"x","files":'
            '{"style.css":""}}'),
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
}
