import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/feature_auth.dart';
import 'package:feature_history/feature_history.dart';
import 'package:feature_incoming/feature_incoming.dart';
import 'package:feature_order/feature_order.dart';
import 'package:feature_settings/feature_settings.dart';
import 'package:feature_shift/feature_shift.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:madar/app/notifications.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// How often the outbox pill re-reads `syncStatus()` between the events
/// that announce a change. A fire queued while offline announces nothing,
/// and the pill is the one place the till admits what it has not sent.
const Duration _pillBeat = Duration(seconds: 10);

/// A device clock this far from the server's is worth a banner: chits and
/// receipts start carrying times nobody recognises.
const int _clockSkewBannerMinutes = 5;

// ── Chrome state: the toast, and which realtime activity has been seen ─────

/// Chrome-owned rendered state: the transient toast and the tick values
/// already acknowledged by the teller (the sticky new-order toast clears
/// when the Queue is looked at, not on a timer).
class ChromeState {
  const ChromeState({this.toast, this.seenDelivery = 0, this.seenTicket = 0});

  final ToastData? toast;
  final int seenDelivery;
  final int seenTicket;

  static const Object _keep = Object();

  ChromeState copyWith({
    Object? toast = _keep,
    int? seenDelivery,
    int? seenTicket,
  }) {
    return ChromeState(
      toast: identical(toast, _keep) ? this.toast : toast as ToastData?,
      seenDelivery: seenDelivery ?? this.seenDelivery,
      seenTicket: seenTicket ?? this.seenTicket,
    );
  }
}

class ChromeNotifier extends Notifier<ChromeState> {
  Timer? _toastTimer;

  @override
  ChromeState build() {
    ref.onDispose(() => _toastTimer?.cancel());
    return const ChromeState();
  }

  /// Show a transient toast — auto-dismisses after 2.6s (the natives'
  /// toast lifetime).
  void showToast(
    String text, {
    ChipTone tone = ChipTone.accent,
    String icon = 'bell',
    String? actionLabel,
    bool sticky = false,
  }) {
    state = state.copyWith(
      toast: ToastData(
        id: DateTime.now().millisecondsSinceEpoch,
        text: text,
        tone: tone,
        icon: icon,
        actionLabel: actionLabel,
        sticky: sticky,
      ),
    );
    _toastTimer?.cancel();
    if (sticky) return;
    _toastTimer = Timer(const Duration(milliseconds: 2600), dismissToast);
  }

  void dismissToast() {
    _toastTimer?.cancel();
    if (state.toast != null) state = state.copyWith(toast: null);
  }

  /// Stamp the current tick values as seen — the Queue was looked at.
  void markIncomingSeen() {
    state = state.copyWith(
      seenDelivery: ref.read(deliveryTickProvider),
      seenTicket: ref.read(ticketTickProvider),
    );
    dismissToast();
  }
}

final chromeProvider = NotifierProvider<ChromeNotifier, ChromeState>(
  ChromeNotifier.new,
);

// ── The outbox pill's truth ────────────────────────────────────────────────

/// What the top bar's pill says, reduced from the core's `syncStatus()`:
/// the pill's four states with their count, plus the two facts the banners
/// under the bar need (auth paused, clock skew).
class OutboxSnapshot {
  const OutboxSnapshot({
    this.state = OutboxState.synced,
    this.count = 0,
    this.online = true,
    this.authPaused = false,
    this.clockSkewMinutes = 0,
  });

  final OutboxState state;

  /// Queued rows, or dead rows when [state] is stuck.
  final int count;
  final bool online;
  final bool authPaused;
  final int clockSkewMinutes;
}

/// Reads the outbox for the pill. Every signal that can move it triggers a
/// re-read (a connectivity pulse, a realtime tick, a route change); the
/// shell's own beat covers the queued op nothing announces.
class OutboxNotifier extends Notifier<OutboxSnapshot> {
  @override
  OutboxSnapshot build() {
    ref
      ..listen(connectivityPulseProvider, (_, _) => unawaited(refresh()))
      ..listen(ticketTickProvider, (_, _) => unawaited(refresh()))
      ..listen(deliveryTickProvider, (_, _) => unawaited(refresh()))
      ..listen(kitchenTickProvider, (_, _) => unawaited(refresh()))
      ..listen(floorTickProvider, (_, _) => unawaited(refresh()))
      ..listen(shellProvider, (_, _) => unawaited(refresh()));
    return const OutboxSnapshot();
  }

  Future<void> refresh() async {
    final bridge = ref.read(bridgeProvider);
    SyncStatusView status;
    try {
      status = await bridge.syncStatus();
    } on Object {
      // A store hiccup leaves the last honest reading in place.
      return;
    }
    final OutboxState pillState;
    final int count;
    // Refused work outranks everything: someone has to act. Offline is a
    // supported mode, not an error, and the queued count rides on it.
    if (status.failed > 0) {
      pillState = OutboxState.stuck;
      count = status.failed;
    } else if (!status.online) {
      pillState = OutboxState.offline;
      count = status.pending;
    } else if (status.pending > 0) {
      pillState = OutboxState.queued;
      count = status.pending;
    } else {
      pillState = OutboxState.synced;
      count = 0;
    }
    state = OutboxSnapshot(
      state: pillState,
      count: count,
      online: status.online,
      authPaused: status.authPaused,
      clockSkewMinutes: bridge.clockSkewMinutes(),
    );
  }
}

final outboxProvider = NotifierProvider<OutboxNotifier, OutboxSnapshot>(
  OutboxNotifier.new,
);

/// The till this device is bound to, by name. `listTills()` is
/// write-through cached, so this resolves offline too; null when the device
/// has no till (a waiter's phone) and the top bar shows the branch alone.
final tillNameProvider = FutureProvider<String?>((ref) async {
  final bridge = ref.localizedBridge;
  // Re-resolve when the session moves (a reconfigure lands here too).
  ref.watch(shellProvider.select((s) => s.session?.userId));
  // …and when Settings re-binds the device to another till: the top bar
  // must not keep naming the drawer it left.
  final tillId = ref.watch(settingsProvider.select((s) => s.config.tillId));
  if (tillId == null) return null;
  try {
    final tills = await bridge.listTills();
    return tills.where((t) => t.id == tillId).firstOrNull?.name;
  } on Exception {
    return null;
  }
});

// ── The shells ─────────────────────────────────────────────────────────────

/// Which of the three shells a person gets.
///
/// A waiter owns tables and never touches a drawer; a teller's day is
/// counter sales around the drawer; a manager is a teller whose Till sees
/// every drawer in the branch — so the manager gets the teller shell and
/// the widening happens inside the Till tab, by role, where the drawers
/// are. Nothing below the shell asks the role: the shell decides which
/// tabs exist and which side a shared screen is mounted on (`canCharge`).
enum ShellKind {
  waiter,
  teller;

  static ShellKind of(String? role) =>
      role == 'waiter' ? ShellKind.waiter : ShellKind.teller;
}

/// The tabs, by key. Bodies are built on first visit and kept alive after,
/// so switching tabs keeps a half-built cart and a chosen floor section.
enum _Tab {
  sell('nav.sell', MadarGlyph.bag),
  floor('nav.floor', MadarGlyph.grid),
  queue('nav.queue', MadarGlyph.inbox),
  till('nav.till', MadarGlyph.wallet),
  bills('nav.bills', MadarGlyph.receipt),
  me('nav.me', MadarGlyph.user),

  /// Off the rail: the teller's Settings (and Sync under it), owned by the
  /// person button. While it is in front no rail tab is lit — the rail
  /// never claims a page belongs to Sell when it does not.
  settings('settings.title', MadarGlyph.settings);

  const _Tab(this.labelKey, this.glyph);

  final String labelKey;
  final MadarGlyph glyph;
}

/// The signed-in person's shell: the dark rail (tablet) or bottom bar
/// (phone) with the role's tabs, the top bar with branch · till · the one
/// outbox pill, the banners that need a person (auth paused, clock skew),
/// the app-level alert toast + chime, and the routing that binds the
/// feature packages together.
///
/// Waiter: Floor · Bills · Me. Teller and manager: Sell · Floor · Queue ·
/// Till. Floor exists only where a floor is authored. The home tab follows
/// the shop: a teller with no shift lands on Till (the open-shift card is
/// there), otherwise Floor when every sale goes on a table, else Sell.
class RoleShell extends ConsumerStatefulWidget {
  const RoleShell({super.key});

  @override
  ConsumerState<RoleShell> createState() => _RoleShellState();
}

class _RoleShellState extends ConsumerState<RoleShell> {
  /// Created on the first chime, not at mount: the platform player is a
  /// channel call, and a shell that renders in a test host has no channel.
  AudioPlayer? _player;
  NotificationService? _notifications;
  Timer? _pillBeatTimer;

  /// Bodies already visited, kept alive in the stack.
  final Map<_Tab, Widget> _bodies = {};

  /// Each tab's own page stack. A page pushed from a tab renders inside the
  /// content area, so the rail, the top bar and the phone's tab bar stand
  /// around every screen (design_system `tab_stack.dart`).
  final Map<_Tab, GlobalKey<NavigatorState>> _stacks = {
    for (final tab in _Tab.values)
      tab: GlobalKey<NavigatorState>(debugLabel: 'tab.${tab.name}'),
  };

  /// The tab in front, as last built.
  _Tab? _current;

  /// The tab the person chose; null follows the home tab.
  _Tab? _chosen;

  /// Which Queue segment to open on first build — the new-order toast's
  /// *View* lands on Online, the tab itself on Bills.
  QueueSegment _queueInitial = QueueSegment.bills;

  bool _reauthShowing = false;

  ShellKind get _kind => ShellKind.of(ref.read(shellProvider).session?.role);

  @override
  void initState() {
    super.initState();
    // OS notifications for the realtime channel. Async init — the in-app
    // toast + chime work immediately; a notification that arrives before
    // init just skips.
    unawaited(
      NotificationService.initialize(channelName: _t('notif.channel')).then((
        s,
      ) {
        if (mounted) _notifications = s;
      }),
    );
    HardwareKeyboard.instance.addHandler(_onKey);
    _pillBeatTimer = Timer.periodic(
      _pillBeat,
      (_) => unawaited(ref.read(outboxProvider.notifier).refresh()),
    );
    // Post-frame: notifier writes during initState land mid-build. The
    // shared order truth (catalog, floor, open bills) is what the tabs and
    // their badges read, so it loads whichever tab is first; the teller's
    // Queue badge needs its feeds before the Queue is ever visited.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(orderProvider.notifier).ensureInit());
      if (_kind == ShellKind.teller) {
        final queue = ref.read(incomingProvider.notifier);
        unawaited(queue.loadOpenTickets());
        unawaited(queue.loadDeliveryOrders());
      }
      unawaited(ref.read(outboxProvider.notifier).refresh());
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _pillBeatTimer?.cancel();
    final player = _player;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }

  /// For callbacks (alerts, taps) — they run at the moment of the event, in
  /// the language in force then. The build reads [BridgeRef.bridge] instead,
  /// which is what re-renders the chrome when the language changes.
  String _t(String key) => ref.read(bridgeProvider).tr(key: key);

  // ── navigation ─────────────────────────────────────────────────────────────

  /// Where a global page lives. Shift and cash pages belong to the Till;
  /// Settings and Sync to the person — the waiter's Me tab, the teller's
  /// off-rail Settings stack. They used to be pushed onto whichever tab was
  /// in front, so the rail said Sell over Settings, and coming back to Sell
  /// showed Settings instead of the counter.
  _Tab _ownerOf(_OwnedPage page) => switch (page) {
    _OwnedPage.orders || _OwnedPage.closeShift => _Tab.till,
    _OwnedPage.settings ||
    _OwnedPage.sync => _kind == ShellKind.waiter ? _Tab.me : _Tab.settings,
  };

  /// Open [page] in its owning tab: bring that tab to the front, then show
  /// the page on its stack. A page already on the stack is returned to
  /// rather than pushed again, so a double tap never stacks two copies.
  void _openOwned(_OwnedPage page) {
    final owner = _ownerOf(page);
    // The teller's Settings stack's ROOT is Settings itself.
    final isRoot = owner == _Tab.settings && page == _OwnedPage.settings;
    if (_current != owner) {
      setState(() => _chosen = owner);
    }
    void show() {
      if (!mounted) return;
      final stack = _stacks[owner]!.currentState;
      if (stack == null) return;
      if (isRoot) {
        stack.popUntil((r) => r.isFirst);
        return;
      }
      var present = false;
      stack.popUntil((r) {
        if (r.settings.name == page.name) present = true;
        return present || r.isFirst;
      });
      if (present) return;
      stack.push(
        MaterialPageRoute<void>(
          settings: RouteSettings(name: page.name),
          builder: (_) => page.build(),
        ),
      );
    }

    // The owner's stack may not exist until the frame that mounts it.
    if (_stacks[owner]!.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => show());
    } else {
      show();
    }
  }

  /// Debug-only pushes that belong to no tab.
  void _push(Widget Function() build) {
    unawaited(MadarPages.push<void>(context, (_) => build()));
  }

  /// The page stack of the tab in front.
  NavigatorState? get _activeStack =>
      _current == null ? null : _stacks[_current]!.currentState;

  /// A stack moved: system back's answer (pop the stack, or leave the app)
  /// follows it.
  void _onStackChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// Escape backs out of a page the way the back tile does — the active
  /// tab's stack first — unless a surface (a sheet, a modal) is over the
  /// shell, which answers Escape itself.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !mounted) {
      return false;
    }
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final stack = _activeStack;
    if (stack == null || !stack.canPop()) return false;
    stack.maybePop();
    return true;
  }

  /// Bumped by every incoming-order alert; the rung tab reads it as its
  /// [MadarTab.ring]. A counter rather than a flag, because two orders
  /// thirty seconds apart have to ring twice.
  int _ring = 0;

  /// The tab an incoming-order alert points at — the same choice
  /// [_viewIncoming] makes, so the ring and the toast's View agree.
  _Tab get _ringTab =>
      _kind == ShellKind.waiter || !_bodies.containsKey(_Tab.queue)
      ? _Tab.bills
      : _Tab.queue;

  void _select(_Tab tab) {
    final stack = _stacks[tab]!.currentState;
    final reselect = tab == _current;
    // Tapping the tab already in front takes its stack back to its root.
    if (reselect) stack?.popUntil((r) => r.isFirst);
    // The Sell tab is the counter and only the counter. Tabs live in an
    // IndexedStack, so SellScreen's initState runs once; aiming the cart
    // back at takeaway has to happen every time the tab's ROOT is shown —
    // including a re-tap of the tab already in front of the teller. A
    // table's Sell left standing on the Sell stack keeps its table; it
    // re-aims the cart itself when its tab comes back.
    final toTakeaway =
        tab == _Tab.sell && (reselect || !(stack?.canPop() ?? false));
    void aim() =>
        unawaited(ref.read(orderProvider.notifier).pointCartAtTakeaway());
    if (reselect) {
      if (toTakeaway) aim();
      return;
    }
    setState(() => _chosen = tab);
    // After the frame that puts the tab in front: a table's Sell on the tab
    // being left notes the table it was for as it goes behind, before the
    // cart is aimed away from it.
    if (toTakeaway) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) aim();
      });
    }
  }

  /// A Queue › Bills row opens the Bill, on the teller's side.
  Future<void> _openBill(BuildContext context, TicketView ticket) async {
    await MadarPages.push<void>(
      context,
      (_) => BillScreen(ticketId: ticket.id, canCharge: true),
    );
  }

  /// The sticky alert's *View*: a teller lands on Queue › Online, a waiter
  /// on Bills (a `ticket.ready` is what rings a waiter's phone).
  void _viewIncoming() {
    ref.read(chromeProvider.notifier).markIncomingSeen();
    if (_kind == ShellKind.waiter) {
      _select(_Tab.bills);
      return;
    }
    if (_bodies.containsKey(_Tab.queue)) {
      ref.read(incomingProvider.notifier).setSegment(QueueSegment.online);
    } else {
      _queueInitial = QueueSegment.online;
    }
    _select(_Tab.queue);
  }

  Widget _body(_Tab tab) {
    final teller = _kind == ShellKind.teller;
    return switch (tab) {
      _Tab.sell => const SellScreen(),
      // canCharge is the one place a role reaches a shared screen, and it is
      // decided HERE, by which shell mounted it — never by a flag below.
      _Tab.floor => FloorScreen(canCharge: teller),
      _Tab.queue => QueueScreen(
        initialSegment: _queueInitial,
        onOpenBill: _openBill,
      ),
      _Tab.till => TillScreen(
        onOpenOrders: () => _openOwned(_OwnedPage.orders),
      ),
      _Tab.bills => const BillsScreen(canCharge: false),
      _Tab.me => const MeScreen(),
      _Tab.settings => const SettingsScreen(),
    };
  }

  // ── the name sheet ─────────────────────────────────────────────────────────

  /// Tapping the signed-in person is the whole of "More". A waiter's Me tab
  /// already is that sheet, so theirs just goes there.
  Future<void> _openPerson() async {
    if (_kind == ShellKind.waiter) {
      _select(_Tab.me);
      return;
    }
    await showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (sheetContext) => _PersonSheet(
        onSettings: () {
          Navigator.of(sheetContext).maybePop();
          _openOwned(_OwnedPage.settings);
        },
        onSignOut: () {
          Navigator.of(sheetContext).maybePop();
          unawaited(_confirmThenSignOut());
        },
      ),
    );
  }

  /// The person sheet's Sign out asks the same question Settings and Me do.
  Future<void> _confirmThenSignOut() async {
    if (!mounted) return;
    if (!await confirmSignOut(context, ref)) return;
    await _signOut();
  }

  Future<void> _signOut() async {
    // Nobody signs out mid-shift — the drawer has to be counted first.
    final bridge = ref.read(bridgeProvider);
    ShiftView? shift;
    try {
      shift = await bridge.currentShift();
    } on Exception catch (_) {}
    if (!mounted) return;
    if (shift?.isOpen ?? false) {
      ref
          .read(chromeProvider.notifier)
          .showToast(
            _t('settings.sign_out_shift_open'),
            tone: ChipTone.danger,
            icon: 'lock',
          );
      return;
    }
    bridge.unsubscribeRealtime();
    try {
      await bridge.lanStop();
    } on Exception catch (_) {}
    try {
      await bridge.logout(wipeOutbox: false);
    } on Exception catch (_) {}
    ref.read(shellProvider.notifier).refresh();
  }

  // ── alerts, re-auth ────────────────────────────────────────────────────────

  /// Core-raised alert: localized text decided in Rust; the shell renders
  /// an in-app toast + chime + haptic AND posts an OS notification for
  /// notify (so it surfaces when the app is backgrounded); chime-only for
  /// ping, haptic-only for haptic.
  void _onAlert(AlertCommand cmd) {
    switch (cmd) {
      case AlertCommand_Notify(:final title, :final body, :final tag):
        // The chime is not enough on a floor: half these rooms are loud, and
        // a tablet on a stand with the sound down is normal. Ring the tab the
        // alert's own View would take you to, so the glance that follows the
        // toast lands on the right place even after the toast is gone.
        if (mounted) setState(() => _ring += 1);
        // Sticky: a new order deserves attention until someone actually
        // looks — it clears on markIncomingSeen, not on a timer.
        ref
            .read(chromeProvider.notifier)
            .showToast(
              body.isEmpty ? title : '$title — $body',
              actionLabel: _t('chrome.view'),
              sticky: true,
            );
        _chime();
        MadarHaptics.impact();
        unawaited(_notifications?.post(title: title, body: body, tag: tag));
      case AlertCommand_Ping():
        _chime();
      case AlertCommand_Haptic():
        MadarHaptics.success();
    }
  }

  void _chime() {
    // Prefix cleared: AssetSource prepends 'assets/' by default, which broke
    // the design_system package path (silent chime). The bundled key is
    // 'packages/design_system/assets/sounds/new_order.wav' verbatim.
    final player = _player ??= AudioPlayer()
      ..audioCache = AudioCache(prefix: '');
    unawaited(
      player.play(
        AssetSource('packages/design_system/assets/sounds/new_order.wav'),
      ),
    );
  }

  /// A bridge call 401'd with a live session — present the re-auth sheet
  /// once per request; the guard clears when the flow completes so a later
  /// request re-presents. Online only: re-auth mints a token from the
  /// server, so offline the prompt would be a dead end; the pill tells that
  /// story and the reconnect re-raises the request.
  void _onReauthRequest() {
    if (_reauthShowing || !mounted) return;
    if (!ref.read(outboxProvider).online) return;
    _reauthShowing = true;
    unawaited(_handleAuthPaused().whenComplete(() => _reauthShowing = false));
  }

  Future<void> _handleAuthPaused() async {
    final outcome = await showReauthSheet(context);
    if (!mounted || outcome == null) return;
    switch (outcome) {
      case ReauthOutcome.resumed:
        await ref.read(outboxProvider.notifier).refresh();
        ref
            .read(chromeProvider.notifier)
            .showToast(
              _t('chrome.sync_resumed'),
              tone: ChipTone.success,
              icon: 'checkmark.circle',
            );
      case ReauthOutcome.switchTeller:
        // A different person signs in: the drawer closes first when one is
        // open (the close screen routes onward); a waiter has none to close.
        ShiftView? shift;
        try {
          shift = await ref.read(bridgeProvider).currentShift();
        } on Exception catch (_) {}
        if (!mounted) return;
        if (shift?.isOpen ?? false) {
          _openOwned(_OwnedPage.closeShift);
        } else {
          await _signOut();
        }
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  List<_Tab> _tabsFor(ShellKind kind, {required bool hasFloor}) =>
      switch (kind) {
        ShellKind.waiter => [if (hasFloor) _Tab.floor, _Tab.bills, _Tab.me],
        ShellKind.teller => [
          _Tab.sell,
          if (hasFloor) _Tab.floor,
          _Tab.queue,
          _Tab.till,
        ],
      };

  /// Where the shell opens: the room for a waiter, the drawer for a teller
  /// with no shift, the room where every sale goes on a table, else Sell.
  _Tab _homeFor(
    ShellKind kind, {
    required bool hasFloor,
    required bool requireTable,
    required bool noShift,
  }) => switch (kind) {
    ShellKind.waiter => hasFloor ? _Tab.floor : _Tab.bills,
    ShellKind.teller =>
      noShift ? _Tab.till : (requireTable && hasFloor ? _Tab.floor : _Tab.sell),
  };

  @override
  Widget build(BuildContext context) {
    ref
      ..listen(alertProvider, (_, next) {
        // The notifier pairs each command with a sequence counter so
        // identical consecutive commands still fire — only the command
        // matters here.
        final cmd = next?.$2;
        if (cmd != null) _onAlert(cmd);
      })
      ..listen(reauthRequestProvider, (_, _) => _onReauthRequest())
      // The Android channel's name is shown in the OS's notification
      // settings; it follows the app's language like every other word.
      ..listen(localeProvider, (_, _) {
        unawaited(_notifications?.rename(_t('notif.channel')));
      })
      // Realtime ticks keep the badges honest whichever tab is showing: the
      // waiter's Bills count and the teller's Queue count read providers the
      // hidden tabs are not reloading.
      ..listen(ticketTickProvider, (_, _) {
        unawaited(ref.read(orderProvider.notifier).loadOpenTickets());
        if (_kind == ShellKind.teller) {
          unawaited(ref.read(incomingProvider.notifier).loadOpenTickets());
        }
      })
      ..listen(deliveryTickProvider, (_, _) {
        if (_kind == ShellKind.teller) {
          unawaited(ref.read(incomingProvider.notifier).loadDeliveryOrders());
        }
      })
      // The drawer closed under the teller (a force-close, a reconcile):
      // the Till is where the open-shift card is.
      ..listen(shellProvider.select((s) => s.route), (prev, next) {
        if (next is AppRoute_OpenShift && prev is! AppRoute_OpenShift) {
          _select(_Tab.till);
        }
      });
    // Locale switches must re-resolve every chrome string.
    ref.watch(localeProvider);
    final bridge = ref.bridge;
    final session = ref.watch(shellProvider.select((s) => s.session));
    final route = ref.watch(shellProvider.select((s) => s.route));
    final kind = ShellKind.of(session?.role);
    final hasFloor = ref.watch(orderProvider.select((s) => s.hasFloor));
    final tabs = _tabsFor(kind, hasFloor: hasFloor);
    final home = _homeFor(
      kind,
      hasFloor: hasFloor,
      requireTable: session?.requireTableForOrders ?? false,
      noShift: route is AppRoute_OpenShift,
    );
    // Every stack the shell keeps: the rail's tabs plus the teller's
    // off-rail Settings owner.
    final stackTabs = [...tabs, if (kind == ShellKind.teller) _Tab.settings];
    var current = _chosen ?? home;
    if (!stackTabs.contains(current)) current = home;
    _bodies.putIfAbsent(current, () => _body(current));
    _current = current;
    final stackCanPop = _stacks[current]!.currentState?.canPop() ?? false;

    final billsReady = ref.watch(
      orderProvider.select(
        (s) => s.openTickets.where((t) => t.status == 'ready').length,
      ),
    );
    final queueBadge = ref.watch(incomingProvider.select((s) => s.queueBadge));
    final outbox = ref.watch(outboxProvider);
    final tillName = ref.watch(tillNameProvider).value;
    final toast = ref.watch(chromeProvider.select((s) => s.toast));
    final colors = context.madarColors;
    final layout = context.madarLayout;

    final name = session?.displayName ?? '';
    final person = MadarPerson(
      name: name,
      initial: name.isEmpty ? '·' : name.characters.first.toUpperCase(),
      online: outbox.online,
    );
    final pillWord = switch (outbox.state) {
      OutboxState.synced => bridge.tr(key: 'chrome.online'),
      OutboxState.queued => bridge.tr(key: 'chrome.queued'),
      OutboxState.offline => bridge.tr(key: 'chrome.offline'),
      OutboxState.stuck => bridge.tr(key: 'chrome.stuck'),
    };

    final banners = <Widget>[
      if (outbox.authPaused)
        NoticeBanner(
          text: bridge.tr(key: 'chrome.auth_paused'),
          icon: 'lock',
          onTap: _onReauthRequest,
          trailing: Text(
            bridge.tr(key: 'chrome.auth_paused_action'),
            style: MadarType.label.copyWith(color: colors.warning),
          ),
        ),
      if (outbox.clockSkewMinutes.abs() >= _clockSkewBannerMinutes)
        NoticeBanner(
          text: bridge.tr(key: 'chrome.clock_skew'),
          icon: 'clock',
        ),
    ];

    // The top bar took the status-bar inset and, on a phone, the tab bar
    // takes the home indicator; the bodies must not pad for either again.
    final body = MediaQuery.removePadding(
      context: context,
      removeTop: true,
      removeBottom: layout.isPhone,
      child: Column(
        children: [
          if (banners.isNotEmpty)
            Padding(
              padding: EdgeInsetsDirectional.only(
                start: layout.gutter,
                end: layout.gutter,
                top: Space.sm,
              ),
              child: Column(spacing: Space.sm, children: banners),
            ),
          Expanded(
            child: IndexedStack(
              index: stackTabs.indexOf(current),
              children: [
                for (final tab in stackTabs)
                  KeyedSubtree(
                    key: ValueKey(tab),
                    child: _bodies[tab] == null
                        ? const SizedBox.shrink()
                        : MadarTabStack(
                            navigatorKey: _stacks[tab]!,
                            active: tab == current,
                            onStackChanged: _onStackChanged,
                            // The rail's glyph, in the leading slot of the
                            // tab root's header (SPEC §2).
                            glyph: tab.glyph,
                            child: _bodies[tab]!,
                          ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    // System back pops the tab in front's page stack first; only at its
    // root does back leave the shell.
    return PopScope<Object?>(
      canPop: !stackCanPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _activeStack?.maybePop();
      },
      child: Material(
        color: colors.chrome,
        child: Stack(
          children: [
            MadarShellScaffold(
              tabs: [
                for (final tab in tabs)
                  MadarTab(
                    key: tab.name,
                    label: bridge.tr(key: tab.labelKey),
                    glyph: tab.glyph,
                    badge: switch (tab) {
                      _Tab.bills => billsReady,
                      _Tab.queue => queueBadge,
                      _ => 0,
                    },
                    // Only the tab you are NOT on: ringing the screen already
                    // in front of the teller is noise.
                    ring: tab == _ringTab && tab != current ? _ring : 0,
                  ),
              ],
              selectedIndex: tabs.indexOf(current),
              onSelect: (i) => _select(tabs[i]),
              person: person,
              onPersonTap: () => unawaited(_openPerson()),
              // The kit's own board, for whoever is building on it. Debug
              // builds only; it is not a row anybody sells from.
              onMarkTap: kDebugMode ? () => _push(GalleryScreen.new) : null,
              topBar: MadarTopBar(
                title: _branchName(bridge, session),
                subtitle: tillName,
                pill: MadarOutboxPill(
                  state: outbox.state,
                  label: pillWord,
                  count: outbox.count,
                  onTap: () => _openOwned(_OwnedPage.sync),
                ),
              ),
              body: body,
            ),
            if (toast != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: ToastHost(
                  toast,
                  onDismiss: (_) =>
                      ref.read(chromeProvider.notifier).dismissToast(),
                  // Only the sticky new-order alert carries an action.
                  onAction: _viewIncoming,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The branch the device is bound to; the session's name is the fallback
  /// on a device whose binding lost its label.
  String _branchName(MadarBridge bridge, SessionSnapshot? session) {
    try {
      final bound = bridge.deviceConfig().branchName?.trim();
      if (bound != null && bound.isNotEmpty) return bound;
    } on Object catch (_) {}
    // Never the raw id: a UUID is not a place anybody works.
    return bridge.tr(key: 'login.branch');
  }
}

/// A page the shell opens from outside any tab, with the tab that owns it.
enum _OwnedPage {
  settings,
  sync,
  orders,
  closeShift;

  Widget build() => switch (this) {
    _OwnedPage.settings => const SettingsScreen(),
    _OwnedPage.sync => const SyncScreen(),
    _OwnedPage.orders => const OrderHistoryScreen(),
    _OwnedPage.closeShift => const CloseShiftScreen(),
  };
}

/// The name sheet: who is signed in, Language, Settings, Sign out. That is
/// the whole of "More" — the rail, the drawer and the More sheet are gone.
class _PersonSheet extends ConsumerWidget {
  const _PersonSheet({required this.onSettings, required this.onSignOut});

  final VoidCallback onSettings;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final session = ref.watch(shellProvider.select((s) => s.session));
    final online = ref.watch(outboxProvider.select((s) => s.online));
    final shiftOpen = ref.watch(orderProvider.select((s) => s.shiftOpen));
    final name = session?.displayName ?? '';
    final role = session?.role ?? '';
    final roleWord = bridge.tr(key: 'role.$role');
    final person = MadarPerson(
      name: name,
      initial: name.isEmpty ? '·' : name.characters.first.toUpperCase(),
      online: online,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsetsDirectional.all(Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            Row(
              spacing: Space.md,
              children: [
                MadarAvatar(person: person),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.h2.copyWith(color: colors.textPrimary),
                      ),
                      // The role word only once the core knows it; a raw
                      // key is not a job title.
                      if (roleWord != 'role.$role')
                        Text(
                          roleWord,
                          style: MadarType.bodySm.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.sm,
              children: [
                MadarSectionHeader(text: bridge.tr(key: 'settings.language')),
                const LanguageSegment(),
              ],
            ),
            MadarCard(
              flush: true,
              child: MadarRow(
                title: bridge.tr(key: 'settings.title'),
                glyph: MadarGlyph.settings,
                dense: true,
                onTap: onSettings,
              ),
            ),
            MadarButton(
              label: bridge.tr(key: 'settings.sign_out'),
              glyph: MadarGlyph.signOut,
              variant: MadarButtonVariant.danger,
              enabled: !shiftOpen,
              tooltip: shiftOpen
                  ? bridge.tr(key: 'settings.sign_out_shift_open')
                  : null,
              onTap: onSignOut,
            ),
          ],
        ),
      ),
    );
  }
}
