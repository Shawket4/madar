/// Test support: the core's own words, for widget and render tests.
///
/// A test cannot load the Rust library, so a fake bridge answers `tr`. Fakes
/// used to answer from a hand-copied table, and every key the copy lacked
/// rendered as its raw key in the PNGs ("charge.no_methods" where a person
/// would read a sentence) — the pictures were then no evidence of what a
/// teller sees. This reads the real EN and AR tables straight out of
/// `rust-core/crates/madar-core/src/i18n.rs`, so a render test shows the
/// words that ship, and a word changed in the core changes in the picture.
///
/// Not for app code: it reads a source file off disk.
library;

import 'dart:io';

import 'package:app_core/src/generated/capabilities.dart';

final Map<String, Map<String, String>> _tables = {};

/// The core's table for [lang] (`en` or `ar`), parsed once per test process.
Map<String, String> coreWordTable(String lang) =>
    _tables[lang] ??= _parse(_i18nSource(), lang);

/// `bridge.tr` as the core resolves it: the locale's language, then English,
/// then the key itself.
String coreWord(String key, {bool arabic = false}) {
  if (arabic) {
    final ar = coreWordTable('ar')[key];
    if (ar != null) return ar;
  }
  return coreWordTable('en')[key] ?? key;
}

String _i18nSource() {
  var dir = Directory.current.absolute;
  while (true) {
    final file = File('${dir.path}/rust-core/crates/madar-core/src/i18n.rs');
    if (file.existsSync()) return file.readAsStringSync();
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError(
        'coreWordTable: rust-core/crates/madar-core/src/i18n.rs not found '
        'above ${Directory.current.path}',
      );
    }
    dir = parent;
  }
}

/// The `"key" => "value"` arms of `fn en` / `fn ar` — including the arms
/// written as a block (`"key" => { "value" }`) when a line runs long.
Map<String, String> _parse(String source, String lang) {
  final start = source.indexOf('fn $lang(key: &str)');
  if (start < 0) throw StateError('coreWordTable: no `fn $lang` in i18n.rs');
  // The table ends where the next top-level item begins.
  final next = source.indexOf('\nfn ', start + 1);
  final tests = source.indexOf('\n#[cfg(test)]', start + 1);
  final ends = [next, tests].where((i) => i > 0);
  final end = ends.isEmpty
      ? source.length
      : ends.reduce((a, b) => a < b ? a : b);
  final body = source.substring(start, end);
  final arm = RegExp(r'"([A-Za-z0-9_.\-]+)"\s*=>\s*\{?\s*"((?:[^"\\]|\\.)*)"');
  return {
    for (final m in arm.allMatches(body))
      m.group(1)!: m
          .group(2)!
          .replaceAll(r'\"', '"')
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\\', r'\'),
  };
}

// ── capabilities in fake bridges ───────────────────────────────────────────

const _ownerRoles = {'super_admin', 'org_admin'};
const _knownRoles = {'branch_manager', 'teller', 'waiter', 'kitchen'};

/// A stand-in for `MadarBridge.can` in hand-written fake bridges. Fakes
/// describe a person by role; the real core answers from effective
/// capabilities. This maps a role to the registry defaults the screens gate
/// on, so a fake "waiter" behaves like a waiter. A null or unknown role is a
/// teller, which is what the fakes meant before.
bool fakeCan(String? role, String cap) {
  final r = role ?? 'teller';
  if (_ownerRoles.contains(r)) return true;
  final manager = r == 'branch_manager';
  final teller = r == 'teller' || manager || !_knownRoles.contains(r);
  switch (cap) {
    case Cap.paymentsTake || Cap.tillOpen || Cap.ordersCreate:
      return teller;
    case Cap.ticketsOpen:
      return teller || r == 'waiter';
    case Cap.kitchenDisplayRead:
      return true;
    case Cap.tillReadBranch || Cap.tillForceClose || Cap.reportsPosMetrics:
      return manager;
    default:
      return teller || r == 'waiter';
  }
}

/// `noSuchMethod` helper: the answer for a `can` / `canAskManager`
/// invocation, or null when the invocation is something else.
///
/// [role] is read only for a `can` call, so a fake whose `currentSession` is
/// itself answered by `noSuchMethod` does not recurse.
bool? fakeCanInvocation(Invocation invocation, String? Function() role) {
  if (invocation.memberName == #can) {
    return fakeCan(role(), invocation.namedArguments[#cap]! as String);
  }
  if (invocation.memberName == #canAskManager) return false;
  return null;
}
