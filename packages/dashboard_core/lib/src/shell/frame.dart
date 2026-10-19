/// The app frame (`routes/_app/route.tsx`): on a window at least 760 wide
/// the web's layout — the ink sidebar, the ink header, the page, the foot —
/// and below that the phone's: an ink app bar, the page, and a bottom bar of
/// Home, Orders, Reports and More (the full sidebar as a drawer).
///
/// The frame also holds what the web's layout holds once for every page: the
/// one realtime connection for the selected branch, the scope a deep link
/// carries (`?branchId=&preset=&from=&to=`), and Ctrl/Cmd+K. Beyond the web,
/// the open page refreshes by hand ([DashPageRefresh]): pulled down, from
/// its header, or Cmd+R (Ctrl+R off Apple).
library;

import 'package:dashboard_core/src/authz/gates.dart' show errorMessage;
import 'package:dashboard_core/src/data/query_cache.dart';
import 'package:dashboard_core/src/gateways/realtime.dart';
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/providers.dart';
import 'package:dashboard_core/src/scope/period.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:dashboard_core/src/shell/command_palette.dart';
import 'package:dashboard_core/src/shell/footer.dart';
import 'package:dashboard_core/src/shell/header.dart';
import 'package:dashboard_core/src/shell/offline_banner.dart';
import 'package:dashboard_core/src/shell/shell_nav.dart';
import 'package:dashboard_core/src/shell/shell_prefs.dart';
import 'package:dashboard_core/src/shell/sidebar.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Whether [event] refreshes the open page: Cmd+R on Apple, Ctrl+R elsewhere.
bool isRefreshShortcut(KeyEvent event) {
  if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyR) {
    return false;
  }
  final k = HardwareKeyboard.instance;
  final apple =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  return apple ? k.isMetaPressed : k.isControlPressed;
}

/// Whether [event] folds or unfolds the sidebar: Ctrl/Cmd+B (the web's
/// `SIDEBAR_KEYBOARD_SHORTCUT`, either modifier on every platform).
bool isSidebarShortcut(KeyEvent event) {
  if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyB) {
    return false;
  }
  final k = HardwareKeyboard.instance;
  return k.isMetaPressed || k.isControlPressed;
}

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
  late final _refresh = DashPageRefresh(_refreshPage);

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _refresh.dispose();
    super.dispose();
  }

  /// Everything the open page shows, read again from the server; a failure
  /// keeps what is shown and says why.
  Future<void> _refreshPage() async {
    final failed = await ref.read(queryCacheProvider).refetchActive();
    if (failed == null || !mounted) return;
    DashToast.error(context, errorMessage(failed, ref.read(tProvider)));
  }

  bool _onKey(KeyEvent event) {
    if (!mounted) return false;
    if (isRefreshShortcut(event)) {
      _refresh.refresh();
      return true;
    }
    if (isSidebarShortcut(event)) {
      // The web's toggleSidebar: the rail on a wide window, the drawer on a
      // phone.
      final scaffold = _scaffold.currentState;
      if (scaffold == null) {
        ref.read(sidebarCollapsedProvider.notifier).toggle();
      } else if (scaffold.isDrawerOpen) {
        scaffold.closeDrawer();
      } else {
        scaffold.openDrawer();
      }
      return true;
    }
    if (!isPaletteShortcut(event)) return false;
    if (dashPaletteOpen) {
      Navigator.of(context, rootNavigator: true).maybePop();
    } else {
      showDashCommandPalette(context);
    }
    return true;
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
      // After the frame: a provider cannot change while the tree builds.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(shellPathProvider.notifier).show(uri.path);
      });
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
        child: Stack(
          children: [
            Row(
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
                        const DashOfflineBanner(),
                        Expanded(
                          child: _PageWithFoot(
                            path: path,
                            page: _PageSlot(
                              refresh: _refresh,
                              child: widget.child,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            PositionedDirectional(
              start: collapsed ? SidebarMetrics.rail : SidebarMetrics.width,
              top: 0,
              bottom: 0,
              width: Space.sm,
              child: const _SidebarEdge(),
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
          const DashOfflineBanner(),
          Expanded(
            child: _PageSlot(refresh: _refresh, child: widget.child),
          ),
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
  const _PageSlot({required this.refresh, required this.child});
  final DashPageRefresh refresh;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: DashPageRefreshScope(controller: refresh, child: child),
  );
}

/// The page and, under it, the foot. The web's foot follows the content, so
/// it is seen at the end of the page: here it shows while the page's scroll
/// is at its end, or the page does not scroll.
class _PageWithFoot extends StatefulWidget {
  const _PageWithFoot({required this.path, required this.page});
  final String path;
  final Widget page;

  @override
  State<_PageWithFoot> createState() => _PageWithFootState();
}

class _PageWithFootState extends State<_PageWithFoot> {
  final _foot = GlobalKey();
  bool _shown = true;

  @override
  void didUpdateWidget(_PageWithFoot old) {
    super.didUpdateWidget(old);
    // A new page starts with its foot; its scroll says otherwise.
    if (old.path != widget.path) _shown = true;
  }

  bool _onScroll(Notification n) {
    final m = switch (n) {
      ScrollNotification(:final metrics, depth: 0) => metrics,
      ScrollMetricsNotification(:final metrics, depth: 0) => metrics,
      _ => null,
    };
    if (m == null || m.axis != Axis.vertical) return false;
    // Showing the foot takes its height from the page, which then has that
    // much more to scroll: it hides only past that, or it would flicker.
    final footHeight = _foot.currentContext?.size?.height ?? 0;
    final shown = _shown ? m.extentAfter <= footHeight + 1 : m.extentAfter < 1;
    if (shown != _shown) setState(() => _shown = shown);
    return false;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(
        child: NotificationListener<Notification>(
          onNotification: _onScroll,
          child: widget.page,
        ),
      ),
      if (_shown) SafeArea(key: _foot, top: false, child: const DashFooter()),
    ],
  );
}

/// The thin toggle along the sidebar's inner edge (`SidebarRail`): a click
/// folds or unfolds it; a hairline shows under the pointer. Out of the tab
/// order, as on the web (Ctrl/Cmd+B is the keyboard's way).
class _SidebarEdge extends ConsumerStatefulWidget {
  const _SidebarEdge();

  @override
  ConsumerState<_SidebarEdge> createState() => _SidebarEdgeState();
}

class _SidebarEdgeState extends ConsumerState<_SidebarEdge> {
  final _focus = FocusNode(skipTraversal: true);

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = ref.watch(tProvider)('ui.sidebar.toggle');
    final c = context.madarColors;
    return DashPressable(
      focusNode: _focus,
      pressScale: false,
      semanticLabel: label,
      tooltip: label,
      onTap: () => ref.read(sidebarCollapsedProvider.notifier).toggle(),
      builder: (context, s) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: Container(
          width: DashMetrics.hair,
          color: s.highlighted ? c.input : null,
        ),
      ),
    );
  }
}

/// Holds the selected branch's realtime connection while the frame is up
/// (`useBranchRealtime`, mounted once so navigating never reconnects); a
/// page outside the frame (sign-in) has none.
class _LiveUpdates extends ConsumerStatefulWidget {
  const _LiveUpdates();

  @override
  ConsumerState<_LiveUpdates> createState() => _LiveUpdatesState();
}

class _LiveUpdatesState extends ConsumerState<_LiveUpdates> {
  BranchRealtime? _rt;

  @override
  void initState() {
    super.initState();
    ref.listenManual(branchRealtimeProvider, (_, rt) {
      _rt?.release();
      _rt = rt?..hold();
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _rt?.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
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
                      to: s.to,
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
    this.to,
  });

  final String icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final String? to;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      to: to,
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
