/// How a feature area plugs into the shell: its pages ([DashRoute]), its mock
/// backend handlers and its i18n supplements ([DashArea]).
library;

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/src/authz/authz_providers.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Builds a page from the router state (path parameters, query).
typedef DashPageBuilder =
    Widget Function(BuildContext context, GoRouterState state);

/// A route-level redirect: the new location, or null to stay.
typedef DashRedirect =
    String? Function(BuildContext context, GoRouterState state);

/// A tab on a page (the web's `route.tsx` tab bars). Each tab is a real
/// route when [path] is set, so it is deep-linkable.
class DashRouteTab {
  const DashRouteTab({
    required this.id,
    required this.labelKey,
    this.fallback,
    this.path,
    this.caps = const [],
    this.module,
  });

  /// Stable id (`profitability`, `tables`, …).
  final String id;
  final String labelKey;

  /// The web's inline English default for [labelKey], when it has one.
  final String? fallback;

  /// The tab's own path, if it has one; null = the tab is page state.
  final String? path;

  /// Shown to whoever holds ANY of these (empty = everyone who sees the page).
  final List<String> caps;
  final String? module;

  bool visibleTo(AuthzState s) {
    final m = module;
    if (m != null && s.modules.known && !s.modules.has(m)) return false;
    return caps.isEmpty || s.canAny(caps);
  }
}

/// One page (or a nested detail route) in the shell.
class DashRoute {
  const DashRoute({
    required this.path,
    this.builder,
    this.titleKey,
    this.titleFallback,
    this.caps = const [],
    this.module,
    this.platformOnly = false,
    this.setupOnly = false,
    this.tabs = const [],
    this.children = const [],
    this.redirect,
  });

  /// go_router path. Top-level routes are absolute (`/orders`); children are
  /// relative to their parent (`:itemId` under `/menu/items`).
  final String path;

  /// Null for a route that only redirects or only groups [children].
  final DashPageBuilder? builder;

  /// The page title's i18n key (and the web's English default for it).
  final String? titleKey;
  final String? titleFallback;

  /// Any-of capabilities, the same as the web's page/nav gate. Empty =
  /// everyone signed in.
  final List<String> caps;

  /// The org module the page belongs to (`pos`/`dawam`); the shell's
  /// `ModuleGate` also derives it from the path.
  final String? module;

  /// Platform (super admin) only.
  final bool platformOnly;

  /// The set-up checklist: open only while it is incomplete.
  final bool setupOnly;
  final List<DashRouteTab> tabs;
  final List<DashRoute> children;
  final DashRedirect? redirect;

  /// Whether this person may open the page (else the shell shows
  /// `Restricted`). Module checks are the `ModuleGate`'s.
  bool allows(AuthzState s) {
    if (platformOnly) return s.platform;
    if (setupOnly) return s.setupIncomplete && s.canAny(caps);
    return caps.isEmpty || s.canAny(caps);
  }

  /// The tabs this person sees.
  List<DashRouteTab> visibleTabs(AuthzState s) => [
    for (final t in tabs)
      if (t.visibleTo(s)) t,
  ];
}

/// Registers an area's mock backend handlers on the test/mock server.
typedef DashMockRegistrar = void Function(MockServer server, MockDb db);

/// One feature area: its pages, its mock handlers, its i18n supplements.
class DashArea {
  const DashArea({
    required this.key,
    required this.routes,
    this.registerMocks,
    this.i18nSupplements = const [],
  });

  /// `sell`, `catalog_menu`, …
  final String key;
  final List<DashRoute> routes;
  final DashMockRegistrar? registerMocks;

  /// Asset keys of the area's supplement tables, one per language
  /// (`packages/dashboard_sell/assets/i18n/en.json`); see [supplementAssets].
  final List<String> i18nSupplements;

  /// The conventional supplement asset keys of package `dashboard_<area>`.
  static List<String> supplementAssets(String area) => [
    'packages/dashboard_$area/assets/i18n/en.json',
    'packages/dashboard_$area/assets/i18n/ar.json',
  ];
}

/// Every route of [areas], children flattened with their full paths.
List<(String, DashRoute)> flattenRoutes(List<DashArea> areas) {
  final out = <(String, DashRoute)>[];
  void walk(String base, DashRoute r) {
    final full = r.path.startsWith('/')
        ? r.path
        : '${base.endsWith('/') ? base : '$base/'}${r.path}';
    out.add((full, r));
    for (final c in r.children) {
      walk(full, c);
    }
  }

  for (final a in areas) {
    for (final r in a.routes) {
      walk('/', r);
    }
  }
  return out;
}
