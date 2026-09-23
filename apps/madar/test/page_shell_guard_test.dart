// Every page in the product is framed by ONE shell, `MadarPageScaffold`,
// which owns the only `Scaffold` and the only safe-area decision. A raw
// `Scaffold(` anywhere else is a page that guesses its own insets again —
// the bug that put sign-in, the splash and a table's Sell under the clock.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:madar/app/boot.dart';

/// The workspace root, from this package's test working directory.
const _root = '../..';

void main() {
  test('no page builds its own Scaffold outside the page shell', () {
    final offenders = <String>[];
    for (final top in ['apps', 'packages']) {
      final dir = Directory('$_root/$top');
      for (final f
          in dir
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()) {
        final path = f.path.replaceAll(r'\', '/');
        if (!path.endsWith('.dart') ||
            !path.contains('/lib/') ||
            path.contains('/build/') ||
            path.contains('/.dart_tool/') ||
            path.contains('/ephemeral/') ||
            path.contains('/.symlinks/') ||
            path.contains('/generated/') ||
            // The till-rescue app is a standalone one-screen tool outside the
            // workspace (its own pubspec, no design_system; see
            // apps/rescue/README.md and the root analysis_options exclude):
            // it cannot use the page shell, and it must never depend on it.
            path.contains('/apps/rescue/') ||
            path.endsWith('design_system/lib/src/page.dart')) {
          continue;
        }
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i].trimLeft();
          if (line.startsWith('//')) continue;
          if (RegExp(r'(^|[^A-Za-z_.])Scaffold\(').hasMatch(line)) {
            offenders.add('$path:${i + 1}');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: 'use MadarPageScaffold instead');
  });

  test('the migrated screens build no rows or tables of their own', () {
    // Till, tills, Orders, Settings and sign-in are on the spec
    // (docs/design/SPEC.md §7–8): records go in MadarDataTable, lists in
    // MadarListRow. A private `_SomethingRow` / `_SomethingTable` class here
    // is a hand-built row drifting from the kit again — the owner's "Past
    // tills and Orders look nothing alike". Composites that only arrange
    // kit rows are named for what they hold, not "Row".
    const packages = ['till', 'history', 'settings', 'auth'];
    final bespoke = RegExp(r'^class (_\w*(Row|Table))\b');
    final raw = RegExp(r'CircularProgressIndicator\(');
    final offenders = <String>[];
    for (final pkg in packages) {
      final dir = Directory('$_root/packages/features/$pkg/lib');
      for (final f in dir.listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (bespoke.hasMatch(lines[i]) || raw.hasMatch(lines[i])) {
            offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: 'use MadarDataTable / MadarListRow');
  });

  test('a failed boot never shows a raw key for Retry', () {
    expect(bootRetryFallback('en'), 'Retry');
    expect(bootRetryFallback('ar'), 'إعادة المحاولة');
    expect(bootRetryFallback(), isNot('sync.retry'));
  });
}
