import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardrail: every date/time shown is formatted by the core in the BRANCH's
/// timezone. No app or package may read the DEVICE zone for display:
/// `toLocal()` (except elapsed-time math through `.difference(`), a wall-clock
/// field of `DateTime.now()`, `timeZoneOffset`, or intl's `DateFormat`.
void main() {
  test('no app or package formats a time in the device zone', () {
    var root = Directory.current;
    bool isWorkspace(Directory d) {
      final f = File('${d.path}/pubspec.yaml');
      return f.existsSync() && f.readAsStringSync().contains('melos:');
    }

    while (!isWorkspace(root)) {
      root = root.parent;
    }
    final banned = <RegExp>[
      RegExp(r'\.toLocal\(\)'),
      RegExp(
        r'DateTime\.now\(\)\.(hour|minute|second|day|month|year|weekday)\b',
      ),
      RegExp(r'\.timeZoneOffset\b'),
      RegExp(r'\bDateFormat\('),
    ];
    final bad = <String>[];
    for (final top in ['apps', 'packages']) {
      final dir = Directory('${root.path}/$top');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        final p = f.path;
        if (!p.endsWith('.dart') ||
            p.contains('/generated/') ||
            p.contains('/.dart_tool/') ||
            p.contains('/build/') ||
            p.contains('/test/') ||
            p.endsWith('.g.dart')) {
          continue;
        }
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = lines[i].split('//').first;
          for (final re in banned) {
            if (!re.hasMatch(code)) continue;
            // Elapsed time is zone-free: `now.difference(t.toLocal())` is fine.
            if (re.pattern.contains('toLocal') &&
                code.contains('.difference(')) {
              continue;
            }
            bad.add('$p:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(
      bad,
      isEmpty,
      reason: 'format times through the core (branch zone):\n${bad.join('\n')}',
    );
  });
}
