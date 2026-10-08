/// The ink sidebar (`app-sidebar.tsx`): the shop's mark, then the nav groups
/// this person sees — a group past four entries folds the rest behind "N
/// more", a parent opens to its children (open at first when the page is one
/// of them), the most specific leaf is the active one. On a wide window it
/// folds to an icon rail; on a phone it is the drawer behind "More".
library;

import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/routes/nav.dart';
import 'package:dashboard_core/src/shell/brand_mark.dart';
import 'package:dashboard_core/src/shell/footer.dart';
import 'package:dashboard_core/src/shell/prefetch.dart';
import 'package:dashboard_core/src/shell/shell_nav.dart';
import 'package:dashboard_core/src/shell/shell_prefs.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The sidebar's widths: the web's 16rem, its phone sheet's 18rem, and an
/// icon rail that keeps every glyph a full tap target.
abstract final class SidebarMetrics {
  static const double width = 256;
  static const double drawerWidth = 288;
  static const double rail = DashMetrics.target + Space.md;
  static const double row = DashMetrics.target;
}

/// The sidebar's hairlines and washes, from the chrome tokens.
extension SidebarColors on MadarColors {
  Color get sidebarBorder => onChrome.withValues(alpha: 0.08);
}

class DashSidebar extends ConsumerStatefulWidget {
  const DashSidebar({
    required this.path,
    this.collapsed = false,
    this.drawer = false,
    this.onNavigate,
    super.key,
  });

  /// The current location's path.
  final String path;

  /// Folded to the icon rail (wide windows only).
  final bool collapsed;

  /// Drawn as the phone's drawer: full width, the foot included.
  final bool drawer;

  /// Called after a destination is chosen (the drawer closes).
  final VoidCallback? onNavigate;

  @override
  ConsumerState<DashSidebar> createState() => _DashSidebarState();
}

class _DashSidebarState extends ConsumerState<DashSidebar> {
  /// Parents opened or closed by hand (`Collapsible` state), by label key.
  final Map<String, bool> _open = {};

  /// Groups expanded past the fold by hand (`manuallyExpanded`).
  final Set<String> _expanded = {};

  /// The active row, scrolled into view when the page changes (a deep link
  /// to a page low in the list never leaves its row out of sight).
  final GlobalKey _activeKey = GlobalKey();
  String? _revealed;

  void _reveal() {
    final path = widget.path;
    if (_revealed == path) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      // Not shown yet (the org's modules still loading hide a module row):
      // the next build tries again.
      if (!mounted || ctx == null || _revealed == path) return;
      _revealed = path;
      Scrollable.ensureVisible(ctx, alignment: 0.5);
    });
  }

  void _go(String to) {
    widget.onNavigate?.call();
    context.go(to);
  }

  bool _parentOpen(NavParent p) =>
      _open.putIfAbsent(p.labelKey, () => widget.path.startsWith(p.basePath));

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = ref.watch(tProvider);
    final visible = ref.watch(navLeafVisibleProvider);
    final groups = visibleNavGroups(visible);
    final rail = widget.collapsed && !widget.drawer;
    _reveal();
    final width = widget.drawer
        ? SidebarMetrics.drawerWidth
        : rail
        ? SidebarMetrics.rail
        : SidebarMetrics.width;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: t('shell.navigation'),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: c.chrome,
          border: widget.drawer
              ? null
              : BorderDirectional(end: BorderSide(color: c.sidebarBorder)),
        ),
        child: SafeArea(
          right: false,
          left: false,
          bottom: widget.drawer,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!rail) _SidebarBrand(onTap: () => _go('/')),
              if (rail) const SizedBox(height: Space.sm),
              Expanded(
                // Every row built (a few dozen): a lazy list never builds a
                // row below the fold, so the active one could not be revealed.
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(Space.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final g in groups) ..._group(context, g, rail),
                    ],
                  ),
                ),
              ),
              if (widget.drawer) const _DrawerFoot(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _group(BuildContext context, VisibleNavGroup g, bool rail) {
    final t = ref.read(tProvider);
    final c = context.madarColors;
    final entries = g.entries;
    final overflow = entries.length > navGroupCollapseThreshold;
    final hidden = overflow
        ? entries.sublist(navGroupCollapseThreshold)
        : const <NavEntry>[];
    final activeHidden = hidden.any(
      (e) => entryPaths(
        e,
      ).any((p) => widget.path == p || widget.path.startsWith('$p/')),
    );
    final expanded =
        !overflow || _expanded.contains(g.group.labelKey) || activeHidden;
    final shown = expanded
        ? entries
        : entries.sublist(0, navGroupCollapseThreshold);
    return [
      if (!rail)
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.sm,
            Space.sm,
            Space.sm,
            Space.xs,
          ),
          child: Semantics(
            header: true,
            child: Text(
              t(g.group.labelKey, defaultValue: g.group.fallback),
              style: DashType.smallMedium.copyWith(color: c.onChromeMuted),
            ),
          ),
        )
      else
        const SizedBox(height: Space.xs),
      for (final e in shown) _entry(context, e, rail),
      if (overflow)
        _NavRow(
          icon: 'chevron-down',
          iconTurned: expanded,
          label: expanded
              ? t('nav.showLess', defaultValue: 'Show less')
              : t(
                  'nav.showMoreCount',
                  count: entries.length - navGroupCollapseThreshold,
                  defaultValue: '{{count}} more',
                ),
          rail: rail,
          muted: true,
          onTap: () => setState(() {
            if (!_expanded.remove(g.group.labelKey)) {
              _expanded.add(g.group.labelKey);
            }
          }),
        ),
    ];
  }

  Widget _entry(BuildContext context, NavEntry e, bool rail) {
    final t = ref.read(tProvider);
    final visible = ref.read(navLeafVisibleProvider);
    final label = t(e.labelKey, defaultValue: e.fallback);
    switch (e) {
      case NavLeaf(:final to):
        final active = navActive(to, widget.path);
        return PrefetchOnIntent(
          to: to,
          child: _NavRow(
            key: active ? _activeKey : null,
            icon: e.icon,
            label: label,
            rail: rail,
            active: active,
            onTap: () => _go(to),
          ),
        );
      case NavParent():
        final open = _parentOpen(e);
        final children = e.children.where(visible).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            PrefetchOnIntent(
              to: e.basePath,
              child: _NavRow(
                icon: e.icon,
                label: label,
                rail: rail,
                active: widget.path.startsWith(e.basePath),
                expanded: open,
                trailing: rail ? null : _Chevron(open: open),
                onTap: () {
                  if (rail) {
                    // An icon on the folded rail cannot show its children:
                    // unfold and open the group (the web's rail hides them).
                    _open[e.labelKey] = true;
                    ref.read(sidebarCollapsedProvider.notifier).set(false);
                    return;
                  }
                  setState(() => _open[e.labelKey] = !open);
                },
              ),
            ),
            if (open && !rail)
              Container(
                margin: const EdgeInsetsDirectional.only(
                  start: Space.md + DashMetrics.hair,
                  top: DashMetrics.hair,
                  bottom: DashMetrics.hair,
                ),
                padding: const EdgeInsetsDirectional.only(start: Space.sm),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    start: BorderSide(color: context.madarColors.sidebarBorder),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final child in children)
                      PrefetchOnIntent(
                        to: child.to,
                        child: _NavRow(
                          key: navActive(child.to, widget.path)
                              ? _activeKey
                              : null,
                          icon: child.icon,
                          label: t(
                            child.labelKey,
                            defaultValue: child.fallback,
                          ),
                          rail: false,
                          active: navActive(child.to, widget.path),
                          onTap: () => _go(child.to),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
    }
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron({required this.open});
  final bool open;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // chevron-right, turned a quarter toward the reader when open.
    final turns = open ? (rtl ? -0.25 : 0.25) : 0.0;
    return AnimatedRotation(
      turns: turns,
      duration: DashMotion.of(context, DashMotion.base),
      child: DashIcon(
        DashIcon.forward(context),
        size: IconSize.sm,
        color: context.madarColors.onChromeMuted,
      ),
    );
  }
}

/// One row of the sidebar (`SidebarMenuButton`): a glyph and a label, the
/// raised patch when active, a wash under the pointer.
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    super.key,
    required this.label,
    required this.rail,
    required this.onTap,
    this.active = false,
    this.muted = false,
    this.expanded,
    this.trailing,
    this.iconTurned = false,
  });

  final String icon;
  final String label;
  final bool rail;
  final bool active;
  final bool muted;
  final bool? expanded;
  final Widget? trailing;
  final bool iconTurned;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final fg = muted ? c.onChromeMuted : c.onChrome;
    return Padding(
      padding: const EdgeInsets.only(bottom: DashMetrics.hair),
      child: DashPressable(
        onTap: onTap,
        selected: active,
        expanded: expanded,
        pressScale: false,
        semanticLabel: label,
        tooltip: rail ? label : null,
        excludeChildSemantics: true,
        builder: (context, s) {
          final bg = active
              ? c.chromeRaised
              : s.highlighted
              ? c.chromeAlt
              : null;
          final glyph = AnimatedRotation(
            turns: iconTurned ? 0.5 : 0,
            duration: DashMotion.of(context, DashMotion.base),
            child: DashIcon(
              icon,
              size: IconSize.sm,
              color: active ? c.brand : (muted ? c.onChromeMuted : fg),
            ),
          );
          return Container(
            height: SidebarMetrics.row,
            padding: EdgeInsetsDirectional.symmetric(
              horizontal: rail ? 0 : Space.sm,
            ),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Radii.xs),
              border: s.focused
                  ? Border.all(color: c.onChromeMuted, width: 2)
                  : null,
            ),
            child: rail
                ? Center(child: glyph)
                : Row(
                    spacing: Space.sm,
                    children: [
                      glyph,
                      Expanded(
                        child: MadarClippedText(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DashType.body.copyWith(
                            color: fg,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      ?trailing,
                    ],
                  ),
          );
        },
      ),
    );
  }
}

/// The sidebar's head: the shop's own logo on the branding tier, Madar's
/// lockup otherwise; a tap goes home.
class _SidebarBrand extends ConsumerWidget {
  const _SidebarBrand({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final brand = ref.watch(publicBrandProvider).value;
    final logo = brand?.logoUrl?.trim();
    final own =
        (brand?.customBranding ?? false) && logo != null && logo.isNotEmpty;
    const madar = ShellWordmark(height: Space.xxl - Space.xs, reversed: true);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.sm, 0),
      child: DashPressable(
        onTap: onTap,
        pressScale: false,
        semanticLabel: own ? brand!.name : t('app.name'),
        excludeChildSemantics: true,
        builder: (context, s) => Container(
          height: Metrics.buttonHeight - Space.sm,
          padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.sm),
          alignment: AlignmentDirectional.centerStart,
          child: own
              ? Image.network(
                  logo,
                  height: Space.xxl - Space.xs,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => madar,
                )
              : madar,
        ),
      ),
    );
  }
}

/// The drawer's foot on a phone (the wide frame's footer).
class _DrawerFoot extends ConsumerWidget {
  const _DrawerFoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.lg,
        Space.sm,
        Space.lg,
        Space.sm,
      ),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.sidebarBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            copyrightLine(ref),
            textAlign: TextAlign.center,
            style: DashType.small.copyWith(color: c.onChromeMuted),
          ),
          DashLegalLinks(color: c.onChromeMuted),
        ],
      ),
    );
  }
}
