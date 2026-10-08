/// The sidebar, the settings sub-nav, module tagging and the legacy redirects,
/// as data. The VALUES are generated from the web (`tool/gen_dashboard_nav.mjs`
/// -> `lib/src/generated/nav.dart`); this file holds their types and the rules
/// the web applies to them (`leafVisible`, `moduleOfPath`, `visibleSettings`).
library;

import 'package:dashboard_core/src/authz/authz.dart';
import 'package:dashboard_core/src/generated/nav.dart';

/// One page in the sidebar (`NavLeaf`).
class NavLeaf extends NavEntry {
  const NavLeaf({
    required this.to,
    required super.labelKey,
    required super.fallback,
    required super.icon,
    required super.lucide,
    this.caps,
    this.module,
    this.superAdminOnly = false,
    this.setup = false,
  });

  final String to;

  /// Visible when the person holds ANY of these. Null = everyone signed in.
  final List<String>? caps;

  /// The org module this page belongs to (`pos`/`dawam`). Null = every org.
  final String? module;

  /// Platform (super admin) only.
  final bool superAdminOnly;

  /// The set-up checklist (SA-4): shown, to whoever holds [caps], only while
  /// it is incomplete.
  final bool setup;
}

/// A collapsible group of leaves (`NavParent`).
class NavParent extends NavEntry {
  const NavParent({
    required super.labelKey,
    required super.fallback,
    required super.icon,
    required super.lucide,
    required this.basePath,
    required this.children,
  });

  /// Prefix that marks the whole group active.
  final String basePath;
  final List<NavLeaf> children;
}

/// A sidebar entry: a [NavLeaf] or a [NavParent].
sealed class NavEntry {
  const NavEntry({
    required this.labelKey,
    required this.fallback,
    required this.icon,
    required this.lucide,
  });

  final String labelKey;

  /// The web's English fallback for [labelKey].
  final String fallback;

  /// `MadarIcon` catalog name.
  final String icon;

  /// The web's Lucide icon, kebab-case (`armchair`), for a closer glyph later.
  final String lucide;
}

/// A titled section of the sidebar (`NavGroup`).
class NavGroup {
  const NavGroup({
    required this.labelKey,
    required this.fallback,
    required this.entries,
  });

  final String labelKey;
  final String fallback;
  final List<NavEntry> entries;
}

/// One pane under Settings (`SettingsLeaf`).
class SettingsNavLeaf {
  const SettingsNavLeaf({
    required this.to,
    required this.labelKey,
    required this.fallback,
    required this.descKey,
    required this.desc,
    required this.icon,
    required this.lucide,
    this.caps,
    this.module,
    this.superAdminOnly = false,
  });

  final String to;
  final String labelKey;
  final String fallback;
  final String descKey;
  final String desc;
  final String icon;
  final String lucide;
  final List<String>? caps;
  final String? module;
  final bool superAdminOnly;
}

/// A titled group of settings panes (`SettingsGroup`).
class SettingsNavGroup {
  const SettingsNavGroup({
    required this.labelKey,
    required this.fallback,
    required this.items,
  });

  final String labelKey;
  final String fallback;
  final List<SettingsNavLeaf> items;
}

/// Which query parameters a legacy redirect carries over.
enum RedirectQuery {
  /// None: the target opens bare.
  none,

  /// Only [LegacyRedirect.keys].
  keys,

  /// Every parameter.
  all,
}

/// A web route file that only redirects (`throw redirect(...)` in
/// `beforeLoad`): an old link or bookmark lands on the page that replaced it.
class LegacyRedirect {
  const LegacyRedirect({
    required this.from,
    required this.to,
    required this.source,
    this.query = RedirectQuery.none,
    this.keys = const [],
    this.replace = false,
  });

  final String from;
  final String to;

  /// The web route file, relative to `src/routes`.
  final String source;
  final RedirectQuery query;
  final List<String> keys;
  final bool replace;

  /// The target for [uri] (whose path is [from]), with the query it keeps.
  Uri apply(Uri uri) {
    final kept = switch (query) {
      RedirectQuery.none => const <String, List<String>>{},
      RedirectQuery.all => uri.queryParametersAll,
      RedirectQuery.keys => {
        for (final k in keys)
          if (uri.queryParametersAll.containsKey(k))
            k: uri.queryParametersAll[k]!,
      },
    };
    return Uri(path: to, queryParameters: kept.isEmpty ? null : kept);
  }
}

/// Trailing slashes off (but `/` stays `/`).
String normalizePath(String path) {
  if (path.length <= 1) return path;
  var p = path;
  while (p.length > 1 && p.endsWith('/')) {
    p = p.substring(0, p.length - 1);
  }
  return p;
}

/// The legacy redirect for [uri], or null when its path is a live page.
Uri? resolveLegacyRedirect(Uri uri) {
  final path = normalizePath(uri.path);
  for (final r in legacyRedirects) {
    if (r.from == path) return r.apply(uri);
  }
  return null;
}

/// Every leaf in [groups], parents flattened, in nav order.
List<NavLeaf> navLeaves([List<NavGroup> groups = dashNav]) => [
  for (final g in groups)
    for (final e in g.entries)
      ...switch (e) {
        NavLeaf() => [e],
        NavParent(:final children) => children,
      },
];

/// Whether a nav leaf shows for this person, in an org with these modules on
/// (`leafVisible`). [setupIncomplete] is true only once the set-up checklist
/// is known unfinished.
bool leafVisible(
  NavLeaf leaf,
  Authz authz, {
  List<String>? modules,
  bool setupIncomplete = false,
}) {
  final module = leaf.module;
  if (module != null && modules != null && !modules.contains(module)) {
    return false;
  }
  if (leaf.setup) {
    return setupIncomplete && authz.canAny(leaf.caps ?? const []);
  }
  if (leaf.superAdminOnly) return authz.platform;
  final caps = leaf.caps;
  if (caps != null) return authz.canAny(caps);
  return true;
}

/// Path prefix -> module: every module-tagged leaf except `/` (the home
/// redirect routes a Dawam-only org itself), then the extra routes.
final List<(String, String)> moduleRoutes = [
  for (final l in navLeaves())
    if (l.module != null && l.to != '/') (l.to, l.module!),
  ...extraModuleRoutes,
];

/// The module a path belongs to (`moduleOfPath`): the longest tagged prefix on
/// a segment boundary, so `/reports/staff-pool` is POS while `/reports/staff`
/// is Dawam. Null = every org.
String? moduleOfPath(String pathname) {
  final path = normalizePath(pathname);
  (String, String)? best;
  for (final r in moduleRoutes) {
    if (path == r.$1 || path.startsWith('${r.$1}/')) {
      if (best == null || r.$1.length > best.$1.length) best = r;
    }
  }
  return best?.$2;
}

/// The settings panes this person may see, in an org with these modules on
/// (`visibleSettings`). Until the modules are known, pass an empty list:
/// none of the module panes shows.
List<SettingsNavGroup> visibleSettings(Authz authz, List<String> modules) => [
  for (final g in settingsNav)
    if (_visibleItems(g, authz, modules) case final items when items.isNotEmpty)
      SettingsNavGroup(
        labelKey: g.labelKey,
        fallback: g.fallback,
        items: items,
      ),
];

List<SettingsNavLeaf> _visibleItems(
  SettingsNavGroup g,
  Authz authz,
  List<String> modules,
) => [
  for (final i in g.items)
    if (_settingVisible(i, authz, modules)) i,
];

bool _settingVisible(SettingsNavLeaf i, Authz authz, List<String> modules) {
  final module = i.module;
  if (module != null && !modules.contains(module)) return false;
  if (i.superAdminOnly) return authz.platform;
  final caps = i.caps;
  if (caps != null) return authz.canAny(caps);
  return true;
}
