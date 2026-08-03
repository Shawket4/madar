import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/nav.dart';
import 'header_controls.dart';
import 'providers.dart';

const double _sidebarWidth = 264;

/// The authenticated app frame: a role-filtered sidebar (from [kNav]) + a
/// single top header carrying the branch + period scope and the account menu.
/// Permanent sidebar on wide layouts; a drawer on narrow ones.
class AppShell extends ConsumerWidget {
  const AppShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    return ResponsiveBuilder(
      builder: (context, info) {
        if (info.isWide) {
          return Scaffold(
            backgroundColor: c.bg,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: _sidebarWidth,
                  child: _Sidebar(location: location),
                ),
                Expanded(
                  child: Column(
                    children: [
                      const _Header(showMenu: false),
                      Expanded(child: child),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Scaffold(
          backgroundColor: c.bg,
          drawer: Drawer(
            backgroundColor: c.surface,
            child: _Sidebar(location: location),
          ),
          body: Column(
            children: [
              const _Header(showMenu: true),
              Expanded(child: child),
            ],
          ),
        );
      },
    );
  }
}

/// The top header: branch selector (left, shrinks to fit) + period selector and
/// account menu (right). No page title — the sidebar shows the active section.
class _Header extends StatelessWidget {
  const _Header({required this.showMenu});

  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      height: 64,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.lg),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          if (showMenu)
            Builder(
              builder: (context) => Padding(
                padding: const EdgeInsetsDirectional.only(end: Space.sm),
                child: IconButton(
                  onPressed: () => Scaffold.of(context).openDrawer(),
                  icon: MadarIcon('line.3.horizontal', tint: c.textSecondary),
                ),
              ),
            ),
          const Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: BranchSelector(),
            ),
          ),
          const SizedBox(width: Space.sm),
          const PeriodSelector(),
          const SizedBox(width: Space.sm),
          const UserMenu(),
        ],
      ),
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    final t = ref.watch(tProvider);
    final role = ref.watch(sessionProvider)?.role ?? '';
    return Container(
      color: c.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 64,
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
            ),
            alignment: AlignmentDirectional.centerStart,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                const MadarSymbol(size: 26),
                const SizedBox(width: Space.sm),
                Text(
                  t('app.title'),
                  style: MadarType.h3.copyWith(color: c.textPrimary),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: Space.md),
              children: [
                for (final group in kNav)
                  ..._buildGroup(context, ref, group, role, t),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroup(
    BuildContext context,
    WidgetRef ref,
    NavGroup group,
    String role,
    String Function(String) t,
  ) {
    final c = context.madarColors;
    final visible = <Widget>[];
    for (final entry in group.entries) {
      switch (entry) {
        case NavLeaf():
          if (entry.visibleTo(role)) {
            visible.add(_NavTile(leaf: entry, active: location == entry.path));
          }
        case NavParent():
          final kids = entry.children.where((l) => l.visibleTo(role)).toList();
          if (kids.isEmpty) continue;
          for (final leaf in kids) {
            visible.add(_NavTile(leaf: leaf, active: location == leaf.path));
          }
      }
    }
    if (visible.isEmpty) return const [];
    final label = t(group.labelKey);
    return [
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(
          Space.lg,
          Space.md,
          Space.lg,
          Space.xs,
        ),
        child: Text(
          (label == group.labelKey ? group.fallback : label).toUpperCase(),
          style: MadarType.labelSm.copyWith(
            color: c.textMuted,
            letterSpacing: MadarType.tracking,
          ),
        ),
      ),
      ...visible,
    ];
  }
}

class _NavTile extends ConsumerWidget {
  const _NavTile({required this.leaf, required this.active});

  final NavLeaf leaf;
  final bool active;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.madarColors;
    final t = ref.watch(tProvider);
    final label = t(leaf.labelKey);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.sm,
        vertical: 1,
      ),
      child: Material(
        color: active ? c.accentBg : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.sm),
          onTap: () => context.go(leaf.path),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.md,
              vertical: 10,
            ),
            child: Row(
              children: [
                MadarIcon(
                  leaf.icon,
                  tint: active ? c.accent : c.textSecondary,
                  size: IconSize.xl,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    label == leaf.labelKey ? leaf.fallback : label,
                    style: MadarType.body.copyWith(
                      color: active ? c.accent : c.textSecondary,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
