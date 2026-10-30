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
    final root = _workspaceRoot();
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
    for (final (rel, lines) in _productSources(root)) {
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        for (final re in banned) {
          if (!re.hasMatch(code)) continue;
          // Elapsed time is zone-free: `now.difference(t.toLocal())` is fine.
          if (re.pattern.contains('toLocal') && code.contains('.difference(')) {
            continue;
          }
          if (allowed.containsKey((rel, re.pattern))) {
            used.add((rel, re.pattern));
            continue;
          }
          bad.add('$rel:${i + 1}: ${lines[i].trim()}');
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

  // A missing zone falls back to ONE constant, the kit's dashDefaultTimezone
  // (dashboard_core's appTimezone is it), never a literal of its own.
  test('the default zone is named once, as dashDefaultTimezone', () {
    final root = _workspaceRoot();
    final literal = RegExp('''['"]Africa/Cairo['"]''');
    // Where the name is written out, and why.
    const allowed = <String, String>{
      'packages/dashboard_kit/lib/src/foundation/l10n.dart':
          'the constant itself',
      // dashboard_api runs without the kit and the native bridge; its clock is
      // pinned to madar-time by mock_clock_parity_test.
      'packages/dashboard_api/lib/src/mock/mock_clock.dart': "the mock's clock",
      'packages/dashboard_api/lib/src/mock/handlers/core_handlers.dart':
          'one of the zones the mock /timezones lists',
      'packages/dashboard_features/setup/lib/src/integrations/handoff_content.dart':
          "an integrator's example response",
    };
    final bad = <String>[];
    final used = <String>{};
    for (final (rel, lines) in _productSources(root)) {
      for (var i = 0; i < lines.length; i++) {
        if (!literal.hasMatch(lines[i].split('//').first)) continue;
        if (allowed.containsKey(rel)) {
          used.add(rel);
          continue;
        }
        bad.add('$rel:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(
      bad,
      isEmpty,
      reason: 'use dashDefaultTimezone (dashboard_kit):\n${bad.join('\n')}',
    );
    expect(
      allowed.keys.toSet().difference(used),
      isEmpty,
      reason: 'unused allowances',
    );
  });
}

Directory _workspaceRoot() {
  var root = Directory.current;
  bool isWorkspace(Directory d) {
    final f = File('${d.path}/pubspec.yaml');
    return f.existsSync() && f.readAsStringSync().contains('melos:');
  }

  while (!isWorkspace(root)) {
    root = root.parent;
  }
  return root;
}

/// Every hand-written product source under apps/ and packages/ (no tests, no
/// generated code), as its path from the workspace root and its lines.
Iterable<(String, List<String>)> _productSources(Directory root) sync* {
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
      yield (p.substring(root.path.length + 1), f.readAsLinesSync());
    }
  }
}
