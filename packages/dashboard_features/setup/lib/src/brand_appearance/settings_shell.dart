/// The Settings shell (`features/settings/settings-shell.tsx`, SET-SHL-001
/// to 007): one page title ("Settings"), the list of panes at the start —
/// a rail from 1024 wide, a picker above the pane below that — and the pane
/// itself at reading width, embedded (its title renders as a pane heading).
///
/// Every `/settings/*` route wraps its pane in this shell (`routes.dart`).
/// The panes listed are the generated settings nav (`settingsNav`) through
/// the web's `visibleSettings` rule: module first (every module-tagged pane
/// hides until the modules are known), then platform-only, then any-of
/// capabilities; a group with nothing visible is not drawn.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class SettingsShell extends ConsumerWidget {
  const SettingsShell({required this.path, required this.child, super.key});

  /// The current location's path.
  final String path;

  /// The pane.
  final Widget child;

  /// The rail's width (the web's `232px` column).
  static const double railWidth = 232;

  /// The phone picker's width from 640 (`sm:w-80`).
  static const double pickerWidth = 320;

  /// Whether [item] is the pane at [path]: Appearance only on the index,
  /// any other pane on its own path or below it.
  static bool isActive(SettingsNavLeaf item, String path) {
    final p = normalizePath(path);
    if (item.to == '/settings') return p == '/settings';
    return p == item.to || p.startsWith('${item.to}/');
  }

  /// The panes this person sees, as [visibleSettings] decides.
  static List<SettingsNavGroup> groupsFor(Authz authz, OrgModulesState mods) =>
      visibleSettings(authz, mods.known ? mods.modules : const []);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final groups = groupsFor(
      ref.watch(authzProvider),
      ref.watch(orgModulesProvider),
    );
    SettingsNavLeaf? current;
    for (final g in groups) {
      for (final i in g.items) {
        if (current == null && isActive(i, path)) current = i;
      }
    }
    final viewport = MediaQuery.sizeOf(context).width;
    final pane = Align(
      alignment: AlignmentDirectional.topStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: DashPageWidth.reading.max),
        child: DashEmbeddedPages(child: child),
      ),
    );

    return DashPageScaffold(
      title: t('nav.settings'),
      body: viewport >= DashBreakpoints.lg
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: railWidth,
                  child: _SettingsRail(groups: groups, path: path),
                ),
                const SizedBox(width: Space.xxl),
                Expanded(child: pane),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DashSelect<String>(
                    options: [
                      for (final g in groups)
                        for (final i in g.items)
                          DashOption(
                            value: i.to,
                            label: t(i.labelKey, defaultValue: i.fallback),
                            icon: i.icon,
                          ),
                    ],
                    value: current?.to,
                    placeholder: t('nav.settings'),
                    semanticLabel: t('settings.pickPane'),
                    sheetTitle: t('settings.pickPane'),
                    width: viewport >= DashBreakpoints.sm ? pickerWidth : null,
                    onChanged: (to) => context.go(to),
                  ),
                ),
                const SizedBox(height: Space.xl),
                pane,
              ],
            ),
    );
  }
}

/// The wide layout's list of panes, grouped.
class _SettingsRail extends ConsumerWidget {
  const _SettingsRail({required this.groups, required this.path});

  final List<SettingsNavGroup> groups;
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Semantics(
      container: true,
      label: t('nav.settings'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.lg + Space.xs,
        children: [
          for (final g in groups)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: DashMetrics.hair,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: Space.md,
                    end: Space.md,
                    bottom: Space.xs,
                  ),
                  child: Text(
                    t(g.labelKey, defaultValue: g.fallback).toUpperCase(),
                    style: DashType.tableHeader.copyWith(color: c.textMuted),
                  ),
                ),
                for (final i in g.items)
                  _RailEntry(
                    icon: i.icon,
                    label: t(i.labelKey, defaultValue: i.fallback),
                    active: SettingsShell.isActive(i, path),
                    onTap: () => context.go(i.to),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RailEntry extends StatelessWidget {
  const _RailEntry({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      selected: active,
      pressScale: false,
      semanticLabel: label,
      excludeChildSemantics: true,
      builder: (context, s) => Container(
        height: DashMetrics.target,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: active
              ? c.accentBg
              : s.highlighted
              ? c.accentBg.withValues(alpha: 0.5)
              : null,
          borderRadius: BorderRadius.circular(Radii.xs),
          border: s.focused ? Border.all(color: c.ring, width: 2) : null,
        ),
        child: Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [
            if (active)
              PositionedDirectional(
                start: 0,
                top: Space.sm,
                bottom: Space.sm,
                child: Container(
                  width: DashMetrics.ring,
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: Row(
                spacing: Space.sm + DashMetrics.hair,
                children: [
                  DashIcon(
                    icon,
                    size: IconSize.sm,
                    color: active ? c.textPrimary : c.textSecondary,
                  ),
                  Expanded(
                    child: MadarClippedText(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashType.body.copyWith(
                        color: active ? c.textPrimary : c.textSecondary,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
