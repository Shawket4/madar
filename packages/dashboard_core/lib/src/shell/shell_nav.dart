/// The rules the sidebar, the command palette and the phone's bottom bar
/// share: which leaves this person sees (`leafVisible` with the org's
/// modules and the set-up checklist), which one is active, and the palette's
/// matching.
library;

import 'package:dashboard_core/src/authz/authz_providers.dart';
import 'package:dashboard_core/src/generated/nav.dart';
import 'package:dashboard_core/src/routes/nav.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a leaf shows for the signed-in person (the web's `visible`):
/// module-tagged leaves stay hidden until the org's modules are known.
final navLeafVisibleProvider = Provider<bool Function(NavLeaf leaf)>((ref) {
  final s = ref.watch(authzStateProvider);
  final modules = s.modules.known ? s.modules.modules : const <String>[];
  final setupIncomplete = s.setupIncomplete;
  return (leaf) => leafVisible(
    leaf,
    s.authz,
    modules: modules,
    setupIncomplete: setupIncomplete,
  );
});

/// A group with the entries this person sees (a parent shows while any of
/// its children does).
class VisibleNavGroup {
  const VisibleNavGroup(this.group, this.entries);

  final NavGroup group;
  final List<NavEntry> entries;
}

/// The sidebar's groups for [visible], empty groups dropped.
List<VisibleNavGroup> visibleNavGroups(
  bool Function(NavLeaf) visible, [
  List<NavGroup> groups = dashNav,
]) => [
  for (final g in groups)
    if ([
          for (final e in g.entries)
            if (switch (e) {
              NavLeaf() => visible(e),
              NavParent(:final children) => children.any(visible),
            })
              e,
        ]
        case final entries when entries.isNotEmpty)
      VisibleNavGroup(g, entries),
];

/// Every leaf destination, so the most specific one wins (`NAV_TARGETS`).
final List<String> navTargets = [for (final l in navLeaves()) l.to];

/// Whether the leaf at [to] is the active one for [pathname] (`useIsActive`):
/// `/` only on `/`; otherwise [to] or below it, unless a longer leaf owns the
/// path.
bool navActive(String to, String pathname) {
  final path = normalizePath(pathname);
  if (to == '/') return path == '/';
  if (path != to && !path.startsWith('$to/')) return false;
  return !navTargets.any(
    (o) => o.length > to.length && (path == o || path.startsWith('$o/')),
  );
}

/// Every path an entry owns (`entryPaths`).
List<String> entryPaths(NavEntry e) => switch (e) {
  NavLeaf(:final to) => [to],
  NavParent(:final basePath, :final children) => [
    basePath,
    for (final c in children) c.to,
  ],
};

/// A group past this many entries folds the rest behind "show more".
const int navGroupCollapseThreshold = 4;

// ── The phone's bottom bar ────────────────────────────────────────────────

/// One shortcut on the phone's bottom bar.
class BottomShortcut {
  const BottomShortcut({
    required this.id,
    required this.to,
    required this.labelKey,
    required this.fallback,
    required this.icon,
    required this.matches,
  });

  /// `home`, `orders`, `reports`.
  final String id;
  final String to;
  final String labelKey;
  final String fallback;
  final String icon;

  /// Whether a path belongs to this shortcut (it lights up).
  final bool Function(String path) matches;
}

/// Home, Orders and Reports, as this person may open them: Orders only with
/// its leaf visible; Reports to the first report this person sees. Home is
/// always there (a Dawam-only org's home is its team, as on the web).
List<BottomShortcut> bottomShortcuts(bool Function(NavLeaf) visible) {
  final out = <BottomShortcut>[
    BottomShortcut(
      id: 'home',
      to: '/',
      labelKey: 'shell.home',
      fallback: 'Home',
      icon: 'house',
      matches: (p) => normalizePath(p) == '/',
    ),
  ];
  final leaves = navLeaves();
  final orders = leaves.where((l) => l.to == '/orders');
  if (orders.isNotEmpty && visible(orders.first)) {
    out.add(
      BottomShortcut(
        id: 'orders',
        to: '/orders',
        labelKey: orders.first.labelKey,
        fallback: orders.first.fallback,
        icon: orders.first.icon,
        matches: (p) => navActive('/orders', p),
      ),
    );
  }
  final reportsGroup = dashNav.where((g) => g.labelKey == 'nav.reports');
  if (reportsGroup.isNotEmpty) {
    final g = reportsGroup.first;
    final reports = navLeaves([g]);
    final first = reports.where(visible);
    if (first.isNotEmpty) {
      out.add(
        BottomShortcut(
          id: 'reports',
          to: first.first.to,
          labelKey: g.labelKey,
          fallback: g.fallback,
          icon: 'bar-chart-3',
          matches: (p) => reports.any((l) => navActive(l.to, p)),
        ),
      );
    }
  }
  return out;
}

// ── The command palette's matching ───────────────────────────────────────

/// How well [query] matches [text] (cmdk's ranking, simplified): 0 = no
/// match. Every query character must appear in order; a whole substring
/// beats scattered letters, a match at a word start beats one inside a
/// word, and an earlier match beats a later one.
double paletteScore(String text, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return 1;
  final t = text.toLowerCase();
  final at = t.indexOf(q);
  if (at >= 0) {
    final wordStart = at == 0 || _isBoundary(t.codeUnitAt(at - 1));
    return 2 + (wordStart ? 1 : 0) + 1 / (1 + at);
  }
  // Subsequence.
  var i = 0;
  var gaps = 0;
  var last = -1;
  for (final ch in q.runes) {
    if (_isSpace(ch)) continue;
    var found = -1;
    for (var j = i; j < t.length; j++) {
      if (t.codeUnitAt(j) == ch) {
        found = j;
        break;
      }
    }
    if (found < 0) return 0;
    if (last >= 0 && found != last + 1) gaps++;
    last = found;
    i = found + 1;
  }
  return 1 / (1 + gaps);
}

bool _isSpace(int c) => c == 0x20;

bool _isBoundary(int c) =>
    c == 0x20 || c == 0x2F || c == 0x2D || c == 0x5F || c == 0x2E;
