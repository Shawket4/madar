import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guardrail: every date/time shown is formatted in the BRANCH's timezone —
/// by the core on the POS and the staff app, through dashboard_core's
/// zone-aware format layer (madar-time over the dashboard bridge) on the
/// Flutter dashboard. No app or package may read the DEVICE zone for display
/// or for a business day: `toLocal()` (except elapsed-time math through
/// `.difference(`), a wall-clock field of `DateTime.now()`, `timeZoneOffset`,
/// intl's `DateFormat`, or a calendar day made from the device's clock
/// (`dashDay(… DateTime.now())`).
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
      RegExp(r'dashDay\([^;]*DateTime\.now\(\)'),
    ];
    // Where a banned shape is not a device-zone read, and why. Keyed by the
    // path from the workspace root and the pattern it may use.
    const allowed = <(String, String), String>{
      // The kit's date words: a calendar day's fields (`2026-10-08`, a
      // weekday) in the language's words. A day, never an instant.
      (
        'packages/dashboard_kit/lib/src/foundation/l10n.dart',
        r'\bDateFormat\(',
      ): 'formats calendar days, not instants',
      // A weekday's name from a fixed civil date (7 Jan 2024 is a Sunday).
      (
        'packages/dashboard_features/sell/lib/src/bookings/booking_settings_dialog.dart',
        r'\bDateFormat\(',
      ): 'a weekday name',
      (
        'packages/dashboard_features/setup/lib/src/booking_settings/booking_settings_data.dart',
        r'\bDateFormat\(',
      ): 'a weekday name',
      (
        'packages/dashboard_features/team/lib/src/shifts/shift_inputs.dart',
        r'\bDateFormat\(',
      ): 'a weekday name',
    };
    final bad = <String>[];
    final used = <(String, String)>{};
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
        final rel = p.substring(root.path.length + 1);
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
            if (allowed.containsKey((rel, re.pattern))) {
              used.add((rel, re.pattern));
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
    // An allowance nothing uses any more is dropped, so it cannot hide a
    // new device-zone read later.
    expect(
      allowed.keys.toSet().difference(used),
      isEmpty,
      reason: 'unused allowances',
    );
  });
}
