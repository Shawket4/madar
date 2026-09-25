// Every message the POS shows goes through ONE place — and nothing a screen
// is told is left in a state nobody draws.
//
// The bug this pins (2026-09-25): the order, cart, floor and bill screens
// kept their toasts in `OrderState.toast` and their failures in
// `OrderState.error`. The only widgets that drew either were deleted with the
// legacy order screen (944b5fd5), and for two weeks "Being edited on another
// till", "This bill was closed on another till" and every refused round were
// said to nobody. Other screens drew their own toast on their own page, so a
// message raised while that page was not in front (a hidden tab, a pushed
// page, a sheet over it) was drawn where nobody could see it.
//
// The rule now: a toast is raised through `appToastProvider` (app_core) and
// drawn by the ONE `AppToastHost` above the navigator, over every tab, page
// and sheet. A screen cannot forget to listen, because no screen listens.
//
// This test reads the SOURCE of every package the POS app is built from, the
// way a lint would, so the next screen that keeps its own toast, or a state
// that keeps a message no widget reads, fails here and not in a shop.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The workspace root, from this package's test working directory.
const _root = '../..';

/// The one file allowed to build a toast and draw it.
const _appToast = 'packages/app_core/lib/src/app_toast.dart';

/// The packages the POS is built from: this app, the spine, and every
/// feature package this app depends on (read from its pubspec, so a new
/// feature is covered the day it is added).
List<String> _posSources() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final features = RegExp(r'^\s+feature_(\w+):', multiLine: true)
      .allMatches(pubspec)
      .map((m) => 'packages/features/${m.group(1)}/lib')
      .toList();
  expect(features, isNotEmpty, reason: 'read the feature list from pubspec');
  return ['apps/madar/lib', 'packages/app_core/lib', ...features];
}

/// Every hand-written Dart file under [dirs], as `path → source`.
Map<String, String> _read(List<String> dirs) {
  final out = <String, String>{};
  for (final dir in dirs) {
    final d = Directory('$_root/$dir');
    expect(d.existsSync(), isTrue, reason: '$dir exists');
    for (final f in d.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('.g.dart') || f.path.contains('/generated/')) {
        continue;
      }
      out[f.path.substring(_root.length + 1)] = f.readAsStringSync();
    }
  }
  return out;
}

/// `file:line` for every match of [pattern] outside [allowed].
List<String> _hits(
  Map<String, String> files,
  RegExp pattern, {
  Set<String> allowed = const {},
}) {
  final hits = <String>[];
  files.forEach((path, src) {
    if (allowed.contains(path)) return;
    final lines = src.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i].trimLeft();
      if (line.startsWith('//')) continue;
      if (pattern.hasMatch(line)) hits.add('$path:${i + 1}: ${line.trim()}');
    }
  });
  return hits;
}

void main() {
  late Map<String, String> files;

  setUpAll(() => files = _read(_posSources()));

  test('the one app-level toast host is the only place a toast is drawn', () {
    expect(files.containsKey(_appToast), isTrue, reason: 'the host exists');
    expect(
      _hits(files, RegExp(r'\bToastHost\('), allowed: {_appToast}),
      isEmpty,
      reason:
          'a screen that draws its own toast shows it only while that screen '
          'is in front; raise it through appToastProvider instead',
    );
  });

  test('no screen or notifier builds or keeps a toast of its own', () {
    expect(
      _hits(files, RegExp(r'\bToastData\('), allowed: {_appToast}),
      isEmpty,
      reason: 'build a toast through appToastProvider.show',
    );
    expect(
      _hits(
        files,
        RegExp(r'^final\s+ToastData\?\s+\w+;'),
        allowed: {_appToast},
      ),
      isEmpty,
      reason:
          'a toast kept in a feature state is drawn only by a widget that '
          'remembers to watch it — the bug this test exists for',
    );
  });

  test('every message a state keeps for a screen is read by a widget', () {
    // A `UiText?` (or `String? …error…`) field on a `…State` class is a
    // message kept for LATER. A widget that watches that state's provider
    // has to read it, or it is said to nobody: `OrderState.error` was set by
    // every failed round and drawn by nothing, while other screens' `error`
    // fields were drawn — so a check by field name alone passes it.
    final decl = RegExp(r'^final\s+(UiText\?|String\?)\s+(\w+)\s*;');
    final message = RegExp('[eE]rror|[mM]essage|[nN]otice');
    // state type -> the providers that hold it: every provider declaration
    // naming the type, typed (`final NotifierProvider<N, S> xProvider =`) or
    // not (`final xProvider = NotifierProvider<N, S>(`).
    final providerDecl = RegExp(
      r'final\s+([^=;]*?)\b(\w+Provider)\s*=([^;]*);',
    );
    final typeName = RegExp(r'\b[A-Z]\w*\b');
    final providersOf = <String, Set<String>>{};
    for (final src in files.values) {
      for (final m in providerDecl.allMatches(src)) {
        final statement = '${m.group(1)} ${m.group(3)}';
        for (final t in typeName.allMatches(statement)) {
          (providersOf[t.group(0)!] ??= {}).add(m.group(2)!);
        }
      }
    }
    final widgetFiles = {
      for (final e in files.entries)
        if (e.value.contains('Widget build(')) e.key: e.value,
    };
    final unread = <String>[];
    var checked = 0;
    files.forEach((path, src) {
      String? owner;
      final lines = src.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final cls = RegExp(
          r'^(?:final\s+|sealed\s+|base\s+)?class\s+(\w+)',
        ).firstMatch(line);
        if (cls != null) owner = cls.group(1);
        if (owner == null || !owner.endsWith('State')) continue;
        final m = decl.firstMatch(line.trimLeft());
        if (m == null) continue;
        final name = m.group(2)!;
        if (m.group(1) != 'UiText?' && !message.hasMatch(name)) continue;
        checked += 1;
        // Read as a property (`s.error`, `state.loadError`), never written
        // (`this.error`) nor a constructor (`UiText.error(`).
        final read = RegExp('\\b(?!this\\b)[a-z]\\w*\\.$name\\b(?!\\s*\\()');
        // Where the state is watched: through its provider, or — a state
        // with no provider (a form's own) — by its type.
        final handles = providersOf[owner] ?? {owner};
        final seen = widgetFiles.values.any(
          (w) => handles.any(w.contains) && read.hasMatch(w),
        );
        if (!seen) unread.add('$path:${i + 1}: $owner.$name');
      }
    });
    // Not vacuous: the auth, checkout, history, queue, settings and till
    // forms keep a dozen and more.
    expect(checked, greaterThan(12), reason: 'the scan found the fields');
    expect(
      unread,
      isEmpty,
      reason:
          'kept for a screen that never reads it: show it through '
          'appToastProvider, or draw it where the person is looking',
    );
  });
}
