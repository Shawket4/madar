// A sheet that closes itself and opens the next thing in the same tap closes
// with `MadarSheet.close`, never `Navigator.maybePop()`.
//
// The bug this pins (T2 B3, POS 0.10.0 on the iPad): after "Make it a meal"
// and a Clear, a tap on the Latte tile did nothing — no line, no sheet, no
// toast. The cart's ⋯ sheet closed itself with `maybePop()` and raised the
// "Clear the cart?" confirm in the same tick. `NavigatorState.maybePop` is
// async (it awaits `willPop`) and DROPS the pop when the navigator's history
// changed in the meantime — which the confirm's push always does. So the ⋯
// sheet never closed: after "Clear cart" it was still up, and its scrim took
// the next tap on the menu, which only dismissed it.
//
// `MadarSheet.close` starts the slide-out at once and, when something was
// pushed over the sheet since, removes the sheet itself rather than popping
// whatever is on top (design_system/sheet.dart).
//
// This reads the SOURCE of every package the POS is built from, the way a
// lint would: an un-awaited `maybePop(…)` followed by more work in the same
// block fails here. An awaited one is fine (the next step runs after the
// pop), and so is one that ends its callback.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The workspace root, from this package's test working directory.
const _root = '../..';

/// This app, the spine, the kit, and every feature package the app depends on
/// (read from its pubspec, so a new feature is covered the day it is added).
List<String> _posSources() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final features = RegExp(r'^\s+feature_(\w+):', multiLine: true)
      .allMatches(pubspec)
      .map((m) => 'packages/features/${m.group(1)}/lib')
      .toList();
  expect(features, isNotEmpty, reason: 'read the feature list from pubspec');
  return [
    'apps/madar/lib',
    'packages/app_core/lib',
    'packages/design_system/lib',
    ...features,
  ];
}

/// Each `path:line` where a statement-level, un-awaited `maybePop(…)` is
/// followed by another statement before its block ends.
List<String> _closeThenOpen(String path, String source) {
  final lines = source.split('\n');
  final call = RegExp(r'^\s*[\w.()]*\.maybePop(<[^>]*>)?\([^;]*\);\s*$');
  final out = <String>[];
  for (var i = 0; i < lines.length; i++) {
    if (!call.hasMatch(lines[i])) continue;
    var j = i + 1;
    while (j < lines.length) {
      final t = lines[j].trim();
      if (t.isNotEmpty && !t.startsWith('//')) break;
      j++;
    }
    final next = j < lines.length ? lines[j].trim() : '';
    final ends =
        next.startsWith('}') ||
        next.startsWith(')') ||
        next.startsWith('return');
    if (!ends) out.add('$path:${i + 1}: ${lines[i].trim()} → $next');
  }
  return out;
}

void main() {
  test(
    'a sheet closing before the next surface closes with MadarSheet.close',
    () {
      final offenders = <String>[];
      for (final dir in _posSources()) {
        final d = Directory('$_root/$dir');
        expect(d.existsSync(), isTrue, reason: '$dir exists');
        for (final f in d.listSync(recursive: true).whereType<File>()) {
          if (!f.path.endsWith('.dart') || f.path.contains('/generated/')) {
            continue;
          }
          offenders.addAll(
            _closeThenOpen(
              f.path.substring(_root.length + 1),
              f.readAsStringSync(),
            ),
          );
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'maybePop() drops its pop when something is pushed before it runs; '
            'close the sheet with MadarSheet.close(context) instead',
      );
    },
  );

  test('the scan finds the shape it forbids', () {
    const bad = '''
      onTap: () {
        Navigator.of(sheetContext).maybePop();
        // A comment between them does not hide it.
        unawaited(_confirmClearCart(context, ref, tableId));
      },
''';
    const fine = '''
      onTap: () {
        MadarSheet.close<void>(sheetContext);
        unawaited(_confirmClearCart(context, ref, tableId));
      },
      onClose: () {
        Navigator.of(sheetContext).maybePop();
      },
      Future<void> done() async {
        await Navigator.of(context).maybePop();
        shell.refresh();
      }
''';
    expect(_closeThenOpen('bad.dart', bad), hasLength(1));
    expect(_closeThenOpen('fine.dart', fine), isEmpty);
  });
}
