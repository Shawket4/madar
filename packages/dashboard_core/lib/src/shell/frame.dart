/// The app frame (`routes/_app/route.tsx`): on a window at least 760 wide
/// the web's layout — the ink sidebar, the ink header, the page, the foot —
/// and below that the phone's: an ink app bar, the page, and a bottom bar of
/// Home, Orders, Reports and More (the full sidebar as a drawer).
///
/// The frame also holds what the web's layout holds once for every page: the
/// one realtime connection for the selected branch, the scope a deep link
/// carries (`?branchId=&preset=&from=&to=`), and Ctrl/Cmd+K.
library;

import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/providers.dart';
import 'package:dashboard_core/src/scope/period.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:dashboard_core/src/shell/command_palette.dart';
import 'package:dashboard_core/src/shell/footer.dart';
import 'package:dashboard_core/src/shell/header.dart';
import 'package:dashboard_core/src/shell/shell_nav.dart';
import 'package:dashboard_core/src/shell/shell_prefs.dart';
import 'package:dashboard_core/src/shell/sidebar.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The frame around every signed-in page.
class DashShell extends ConsumerStatefulWidget {
  const DashShell({required this.state, required this.child, super.key});

  final GoRouterState state;
  final Widget child;

  @override
  ConsumerState<DashShell> createState() => _DashShellState();
}

class _DashShellState extends ConsumerState<DashShell> {
  final _scaffold = GlobalKey<ScaffoldState>();
  Uri? _scopeFrom;
  bool _paletteOpen = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (!isPaletteShortcut(event) || !mounted) return false;
    if (_paletteOpen) {
      Navigator.of(context, rootNavigator: true).maybePop();
    } else {
      _openPalette();
    }
    return true;
  }

  Future<void> _openPalette() async {
    _paletteOpen = true;
    try {
      await showDashCommandPalette(context);
    } finally {
      _paletteOpen = false;
    }
  }

  /// A link that names the scope (`?branchId=…&preset=…`) sets it, as the
  /// web's URL-held scope does on a shared or deep link.
  void _applyScope(Uri uri) {
    final q = uri.queryParameters;
    final scope = ref.read(scopeProvider);
    final notifier = ref.read(scopeProvider.notifier);
    if (q.containsKey('branchId')) {
      final b = q['branchId']!.isEmpty ? null : q['branchId'];
      if (b != scope.branchId) notifier.setBranch(b);
    }
    final preset = ScopePreset.fromWire(q['preset']);
    if (preset == ScopePreset.custom) {
      final from = q['from'];
      final to = q['to'];
      if (from != null && to != null) notifier.setCustomRange(from, to);
    } else if (preset != null && preset != scope.preset) {
      notifier.setPreset(preset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uri = widget.state.uri;
    if (uri != _scopeFrom) {
      _scopeFrom = uri;
      const keys = {'branchId', 'preset'};
      if (uri.queryParameters.keys.any(keys.contains)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _applyScope(uri);
        });
      }
    }
    final phone = DashBreakpoints.isPhone(context);
    final path = uri.path;
    return Stack(
      children: [
        const _LiveUpdates(),
        Positioned.fill(
          child: phone ? _phone(context, path) : _wide(context, path),
        ),
      ],
    );
  }

  Widget _wide(BuildContext context, String path) {
    final c = context.madarColors;
    final collapsed = ref.watch(sidebarCollapsedProvider);
    return Material(
      color: c.chrome,
      child: SafeArea(
        bottom: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DashSidebar(path: path, collapsed: collapsed),
            Expanded(
              child: Material(
                color: c.bg,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DashHeader(paperContext: context),
                    Expanded(child: _PageSlot(child: widget.child)),
                    const SafeArea(top: false, child: DashFooter()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _phone(BuildContext context, String path) {
    final c = context.madarColors;
    return Scaffold(
      key: _scaffold,
      backgroundColor: c.bg,
      drawerScrimColor: c.scrim,
      drawer: Drawer(
        width: SidebarMetrics.drawerWidth,
        backgroundColor: c.chrome,
        shape: const RoundedRectangleBorder(),
        child: DashSidebar(
          path: path,
          drawer: true,
          onNavigate: () => _scaffold.currentState?.closeDrawer(),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashPhoneBar(paperContext: context),
          Expanded(child: _PageSlot(child: widget.child)),
        ],
      ),
      bottomNavigationBar: DashBottomBar(
        path: path,
        onMore: () => _scaffold.currentState?.openDrawer(),
      ),
    );
  }
}

/// The page's own semantics scope. The pages live in a nested navigator
/// whose route barrier blocks the semantics of whatever was painted before
/// it in the same scope — without a boundary here, the sidebar and the
/// header vanish from screen readers.
class _PageSlot extends StatelessWidget {
  const _PageSlot({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Semantics(container: true, explicitChildNodes: true, child: child);
}

/// Holds the selected branch's realtime connection while the frame is up
/// (`useBranchRealtime`, mounted once so navigating never reconnects).
class _LiveUpdates extends ConsumerWidget {
  const _LiveUpdates();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(branchRealtimeProvider);
    return const SizedBox.shrink();
  }
}

/// The phone's bottom bar: Home, Orders and Reports as this person may open
/// them, and More, which opens the full sidebar.
class DashBottomBar extends ConsumerWidget {
  const DashBottomBar({required this.path, required this.onMore, super.key});

  final String path;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final shortcuts = bottomShortcuts(ref.watch(navLeafVisibleProvider));
    final current = shortcuts.where((s) => s.matches(path)).firstOrNull;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: t('shell.navigation'),
      child: Container(
        decoration: BoxDecoration(
          color: c.chrome,
          border: Border(top: BorderSide(color: c.sidebarBorder)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: headerHeight,
            child: Row(
              children: [
                for (final s in shortcuts)
                  Expanded(
                    child: _BottomItem(
                      icon: s.icon,
                      label: t(s.labelKey, defaultValue: s.fallback),
                      active: identical(s, current),
                      onTap: () => context.go(s.to),
                    ),
                  ),
                Expanded(
                  child: _BottomItem(
                    icon: 'layout-grid',
                    label: t('common.more', defaultValue: 'More'),
                    active: current == null,
                    onTap: onMore,
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

class _BottomItem extends StatelessWidget {
  const _BottomItem({
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
        color: s.highlighted ? c.chromeAlt : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: DashMetrics.hair,
          children: [
            DashIcon(
              icon,
              size: IconSize.lg,
              color: active ? c.brand : c.onChromeMuted,
            ),
            MadarClippedText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.small.copyWith(
                color: active ? c.onChrome : c.onChromeMuted,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
