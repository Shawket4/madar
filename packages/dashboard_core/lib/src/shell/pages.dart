/// What the frame draws around and instead of a page: the gates a page sits
/// behind ([DashRouteHost]), the page-not-found page, and the placeholder an
/// area's page shows until its port lands.
library;

import 'package:dashboard_core/src/authz/authz_providers.dart';
import 'package:dashboard_core/src/authz/gates.dart';
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/routes/route.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The title a route's page carries (for `Restricted` and the placeholder).
String routeTitle(DashRoute route, Translator t) {
  final key = route.titleKey;
  if (key == null) return route.titleFallback ?? '';
  return t(key, defaultValue: route.titleFallback);
}

/// Hosts one page: the module gate (a page of a switched-off module is not
/// reachable by its path), then the page's own gate as the web's pages run
/// it — `Restricted` once the person's permissions are known and lack every
/// capability the page needs, nothing while they load, platform-only pages
/// for platform admins only. A set-up-only page is a nav rule: the page
/// itself opens for whoever holds its capabilities (the web's `SetupPage`).
class DashRouteHost extends ConsumerWidget {
  const DashRouteHost({
    required this.route,
    required this.state,
    this.framed = true,
    super.key,
  });

  final DashRoute route;
  final GoRouterState state;

  /// Inside the frame (module-gated, as the web's `_app` layout).
  final bool framed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = routeTitle(route, ref.watch(tProvider));
    final builder = route.builder;
    Widget body = _PageGate(
      route: route,
      title: title,
      child: Builder(
        builder: (context) => builder == null
            ? DashPlaceholderPage(title: title)
            : builder(context, state),
      ),
    );
    if (framed) body = ModuleGate(path: state.uri.path, child: body);
    return Material(color: context.madarColors.bg, child: body);
  }
}

class _PageGate extends ConsumerWidget {
  const _PageGate({
    required this.route,
    required this.title,
    required this.child,
  });

  final DashRoute route;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = route.caps;
    if (!route.platformOnly && caps.isEmpty) return child;
    final a = ref.watch(authzProvider);
    if (!a.ready) {
      final error = a.error;
      if (error == null) return const SizedBox.shrink();
      final t = ref.watch(tProvider);
      return Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: DashErrorState(
          title: t('shell.accessLoadError'),
          message: errorMessage(error, t),
          retryLabel: t('common.retry'),
          onRetry: () => ref.read(authzProvider.notifier).refresh(),
        ),
      );
    }
    final allowed = route.platformOnly ? a.platform : a.canAny(caps);
    return allowed ? child : Restricted(title: title);
  }
}

/// A path no page answers (the web shows its router's bare "Not Found").
class DashNotFoundPage extends ConsumerWidget {
  const DashNotFoundPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return Material(
      color: context.madarColors.bg,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: DashMetrics.proseWide),
            child: DashEmptyState(
              icon: 'compass',
              title: t('shell.notFoundTitle'),
              description: t('shell.notFoundBody'),
              action: DashButton(
                label: t('shell.backHome'),
                icon: 'house',
                variant: DashButtonVariant.outline,
                onPressed: () => context.go('/'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An area's page before its port lands: the page's title and a calm word
/// that it is on its way (never an empty frame, never a raw key).
class DashPlaceholderPage extends ConsumerWidget {
  const DashPlaceholderPage({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: title,
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
