import 'dart:async';

import 'package:design_system/design_system.dart' show ThemeChoice;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The booted core. The app overrides this on the post-boot subtree:
/// `ProviderScope(overrides: [coreProvider.overrideWithValue(core)])`.
/// Reading it before boot is a programmer error.
final coreProvider = Provider<MadarCore>(
  (_) => throw StateError('coreProvider read before boot override'),
);

/// Convenience: the bridge handle (every screen's call surface).
///
/// Watching this alone does NOT re-render on a language change — the handle
/// is one long-lived object, so the provider recomputes to the same value and
/// Riverpod correctly decides nobody needs telling. Use [BridgeRef.bridge]
/// from a widget that shows strings.
final bridgeProvider = Provider<MadarBridge>(
  (ref) => ref.watch(coreProvider).bridge,
);

/// The bridge, plus a dependency on the language it will answer in.
///
/// `bridge.tr(key:)` is an imperative call, not a provider read: a screen
/// pulls its strings once while building and then sits there holding them.
/// Nothing about switching language invalidated those screens, so a teller
/// who changed to Arabic got an Arabic settings sheet on top of a stack of
/// English ones — which reads as missing translations, and was reported as
/// exactly that.
///
/// So a screen that renders strings reads the bridge through here, and a
/// language switch rebuilds it like any other state change.
extension BridgeRef on WidgetRef {
  /// The bridge, re-read whenever the language changes.
  MadarBridge get bridge {
    watch(localeGenerationProvider);
    return watch(bridgeProvider);
  }
}

/// The same, for a Notifier or any other non-widget [Ref].
extension BridgeRefBase on Ref {
  /// The bridge, re-read whenever the language changes.
  MadarBridge get localizedBridge {
    watch(localeGenerationProvider);
    return watch(bridgeProvider);
  }
}

/// Bumped once per language switch. Its only job is to be watched.
///
/// A counter rather than the locale string so that re-selecting the language
/// already in force still rebuilds — the core may have loaded a different
/// set of strings underneath (a catalogue refresh re-keys item names by
/// locale) even when the tag has not moved.
final localeGenerationProvider = NotifierProvider<LocaleGeneration, int>(
  LocaleGeneration.new,
);

/// See [localeGenerationProvider].
class LocaleGeneration extends Notifier<int> {
  @override
  int build() => 0;

  /// Marks the strings stale for every screen.
  void bump() => state = state + 1;
}

/// The shell truth: the core-derived route + the session snapshot + whether
/// this device is walled to the open-till screen + THE till.
/// [ShellNotifier.refresh] is the old `onStateChanged` — call it after any
/// bridge call that can move `app_route()`, the session or the till.
class ShellState {
  const ShellState({
    required this.route,
    required this.session,
    required this.lock,
    this.till,
  });

  final AppRoute route;
  final SessionSnapshot? session;

  /// The core's ONE answer on the device lock (owner decision 2026-09-19):
  /// a cashier device with no open drawer reaches nothing but the open-till
  /// screen, Settings, sync, sign out and the manager-actions list. Waiters
  /// and kitchen devices hold no drawer and are never locked.
  final TillLockView lock;

  /// THE till — the signed-in person's own open till on this device, from
  /// the core's `own_open_till()`, or null when none is open here (always
  /// null for a waiter or a kitchen device).
  ///
  /// The ONE place the app keeps it. It is read in the same pass as [route]
  /// and [lock], which the core decides from the same answer, so the three
  /// can never disagree. Every screen that asks "is a till open?" or "which
  /// till?" — the cart, the Till tab, Charge, the open-till form, the Queue,
  /// Orders, sign-out — reads it from here and keeps no copy of its own.
  ///
  /// Screens used to load their own `currentTill()` at their own moment. The
  /// Sell screen's was loaded once per person, while the device was still
  /// locked; after a (re)configure → open till the cart kept saying "No till
  /// is open" over an open till (owner report 2026-09-25).
  final TillView? till;

  /// A till is open on this device for the signed-in person.
  bool get tillOpen => till != null;

  /// Shorthand — the shell reads this, never a role or a route, to decide
  /// which destinations exist.
  bool get locked => lock.locked;
}

class ShellNotifier extends Notifier<ShellState> {
  /// Unlocked — what a shell that could not get an answer must assume.
  ///
  /// The lock decides what a whole shop can reach. Walling the counter
  /// because a call did not come back would turn any bridge hiccup into a
  /// closed till, so the failure direction is "open"; the core's own
  /// `till_lock()` fails the same way (an unknown permission set shows the
  /// form rather than claiming the cashier may not open a drawer).
  static const _unlocked = TillLockView(
    locked: false,
    reason: '',
    title: '',
    body: '',
    canOpen: true,
    holdsDrawer: false,
  );

  /// One pass over the core: the route, the session, the lock and the till,
  /// all local and synchronous. A till the core could not report keeps the
  /// last honest reading ([previous]) rather than guessing "none".
  ShellState _read(MadarBridge bridge, {ShellState? previous}) {
    TillLockView lock;
    try {
      lock = bridge.tillLock();
    } on Object catch (_) {
      lock = _unlocked;
    }
    TillView? till;
    try {
      till = bridge.ownOpenTill();
    } on Object catch (_) {
      till = previous?.till;
    }
    return ShellState(
      route: bridge.appRoute(),
      session: bridge.currentSession(),
      lock: lock,
      till: till,
    );
  }

  @override
  ShellState build() {
    // The drawer moves without any screen calling the shell too: a pull lands
    // a close made on the dashboard or another device, a queued open or close
    // is acknowledged, the reconcile adopts a till the server holds. Each of
    // those changes the core's `tills` table, which bumps [drawerTickProvider]
    // — so the one answer follows the core, not the next screen change.
    ref.listen(drawerTickProvider, (_, _) => _reread());
    return _read(ref.watch(bridgeProvider));
  }

  /// Re-read route + session + lock + till from the core; notifies only on
  /// change.
  void refresh() {
    _reread();
    ref.read(realtimeArmerProvider)();
  }

  void _reread() {
    final next = _read(ref.read(bridgeProvider), previous: state);
    if (next.route != state.route ||
        next.session != state.session ||
        next.lock != state.lock ||
        next.till != state.till) {
      state = next;
    }
  }

  /// Reconcile this person's till with the synced till rows — the core may
  /// adopt the till the server holds for this device, or drop one closed
  /// elsewhere — then re-read. Local (no network); a failure leaves the
  /// device's own answer standing.
  ///
  /// The ONE way the app asks for it: screens call this, never
  /// `refreshTill()` themselves, so whatever the reconcile decides reaches
  /// every reader at once. A re-read, not a re-arm: the Till tab reconciles
  /// on every drawer tick, and arming realtime is a sign-in's business.
  Future<void> reconcileTill() async {
    try {
      await ref.read(bridgeProvider).refreshTill();
    } on Object catch (_) {
      // The local answer stands; the next reconcile tries again.
    }
    if (!ref.mounted) return;
    _reread();
  }
}

final shellProvider = NotifierProvider<ShellNotifier, ShellState>(
  ShellNotifier.new,
);

/// Locale + direction, owned by the core's i18n. [LocaleNotifier.set]
/// persists via the host callback the app installs at boot.
class LocaleState {
  const LocaleState({required this.locale, required this.rtl});

  final String locale;
  final bool rtl;
}

class LocaleNotifier extends Notifier<LocaleState> {
  @override
  LocaleState build() {
    final bridge = ref.watch(bridgeProvider);
    return LocaleState(locale: bridge.locale(), rtl: bridge.isRtl());
  }

  void set(String locale) {
    final bridge = ref.read(bridgeProvider)..setLocale(locale: locale);
    ref.read(localePersisterProvider)(locale);
    state = LocaleState(locale: bridge.locale(), rtl: bridge.isRtl());
    // Every screen already on stage is holding strings it pulled in the old
    // language. Nothing else invalidates them — `tr` is a plain call, not a
    // provider read — so this is what makes a language switch reach the
    // screens BEHIND the settings sheet rather than only the one in front.
    ref.read(localeGenerationProvider.notifier).bump();
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, LocaleState>(
  LocaleNotifier.new,
);

/// Host hooks the APP overrides at boot (they touch the host vault, which
/// lives outside this package). Defaults are no-ops so tests run bare.
final localePersisterProvider = Provider<void Function(String)>((_) => (_) {});
typedef ThemePersister = void Function({required bool dark});

void _noopThemePersist({required bool dark}) {}

final themePersisterProvider = Provider<ThemePersister>(
  (_) => _noopThemePersist,
);
final realtimeArmerProvider = Provider<void Function()>((_) => () {});

/// Dark-mode preference (light default, matching the natives). The app
/// seeds the boot value via `darkModeProvider.overrideWith(() =>
/// DarkModeNotifier(initialDark: ...))` — an override, never a build-time
/// mutation (mutating providers during widget builds is forbidden).
class DarkModeNotifier extends Notifier<bool> {
  DarkModeNotifier({this.initialDark = false});

  /// The vault-persisted value the ready scope boots with.
  final bool initialDark;

  @override
  bool build() => initialDark;

  /// User toggle — updates + persists through the host hook.
  void setDark({required bool dark}) {
    state = dark;
    ref.read(themePersisterProvider)(dark: dark);
  }
}

final darkModeProvider = NotifierProvider<DarkModeNotifier, bool>(
  DarkModeNotifier.new,
);

class ThemeChoiceNotifier extends Notifier<ThemeChoice> {
  ThemeChoiceNotifier({this.initial = ThemeChoice.light});

  /// The vault-persisted value the ready scope boots with.
  final ThemeChoice initial;

  @override
  ThemeChoice build() => initial;

  /// User pick — updates + persists through the host hook.
  void set(ThemeChoice choice) {
    state = choice;
    ref.read(themeChoicePersisterProvider)(choice);
  }
}

final themeChoiceProvider = NotifierProvider<ThemeChoiceNotifier, ThemeChoice>(
  ThemeChoiceNotifier.new,
);

/// Host hook the APP overrides at boot; a no-op so tests run bare.
final themeChoicePersisterProvider = Provider<void Function(ThemeChoice)>(
  (_) => (_) {},
);

/// How much the app animates: follow the device's reduced-motion flag, or
/// force full or reduced. Full is the default — the macOS engine never
/// reports the system's Reduce Motion, and a till that silently dropped its
/// add-to-cart feedback read as broken. Persisted through the host hook.
enum MotionChoice {
  system,
  full,
  reduced;

  /// The persisted name back to a choice; anything unknown is full.
  static MotionChoice parse(String? name) => switch (name) {
    'system' => MotionChoice.system,
    'reduced' => MotionChoice.reduced,
    _ => MotionChoice.full,
  };
}

class MotionChoiceNotifier extends Notifier<MotionChoice> {
  MotionChoiceNotifier({this.initial = MotionChoice.full});

  /// The vault-persisted value the ready scope boots with.
  final MotionChoice initial;

  @override
  MotionChoice build() => initial;

  /// User pick — updates + persists through the host hook.
  void set(MotionChoice choice) {
    state = choice;
    ref.read(motionChoicePersisterProvider)(choice);
  }
}

final motionChoiceProvider =
    NotifierProvider<MotionChoiceNotifier, MotionChoice>(
      MotionChoiceNotifier.new,
    );

/// Host hook the APP overrides at boot; a no-op so tests run bare.
final motionChoicePersisterProvider = Provider<void Function(MotionChoice)>(
  (_) => (_) {},
);

/// Where the Sell screen puts things on a tablet. [standard]: the menu
/// first, the cart as a column at the end, an item's choices in a sheet.
/// [legacy]: the cart first, the menu at the end, and an item's choices,
/// a combo, the charge or a note opening IN PLACE of the menu, the way the
/// cashier apps tellers come from lay it out. A phone always sells the
/// standard way: it has no room for the two side by side.
///
/// A per-device preference like the theme: any teller may switch it, it is
/// no permission and never leaves the till. Persisted through the host hook.
enum SellLayout {
  standard,
  legacy;

  /// The persisted name back to a layout; anything unknown is [standard].
  static SellLayout parse(String? name) =>
      name == 'legacy' ? SellLayout.legacy : SellLayout.standard;
}

class SellLayoutNotifier extends Notifier<SellLayout> {
  SellLayoutNotifier({this.initial = SellLayout.standard});

  /// The vault-persisted value the ready scope boots with.
  final SellLayout initial;

  @override
  SellLayout build() => initial;

  /// User pick — updates + persists through the host hook.
  void set(SellLayout layout) {
    state = layout;
    ref.read(sellLayoutPersisterProvider)(layout);
  }
}

final sellLayoutProvider = NotifierProvider<SellLayoutNotifier, SellLayout>(
  SellLayoutNotifier.new,
);

/// Host hook the APP overrides at boot; a no-op so tests run bare.
final sellLayoutPersisterProvider = Provider<void Function(SellLayout)>(
  (_) => (_) {},
);

/// Per-board realtime ticks — bumped by the app's SSE listener; boards
/// watch and reload. The natives' tick counters.
class TickNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final kitchenTickProvider = NotifierProvider<TickNotifier, int>(
  TickNotifier.new,
);
final ticketTickProvider = NotifierProvider<TickNotifier, int>(
  TickNotifier.new,
);
final deliveryTickProvider = NotifierProvider<TickNotifier, int>(
  TickNotifier.new,
);

/// Bumped on every `floor.*` / `table.*` / `held_order.*` / `transfer.*`
/// event — the dashboard re-arranged the room, a table changed state, or
/// another till parked/seated a party. The order surface re-pulls the floor.
final floorTickProvider = NotifierProvider<TickNotifier, int>(TickNotifier.new);

/// Bumped on every `booking.*` event — a table got reserved, a booked party
/// is due, a booking moved or was cancelled. The arrivals list re-pulls.
final bookingTickProvider = NotifierProvider<TickNotifier, int>(
  TickNotifier.new,
);

/// Bumped when a manual sync has refreshed the catalogue in the core — the
/// Sell screen re-reads its menu on it. Without it the screen kept the menu
/// it loaded at start-up, so recipe-step animations downloaded by the sync
/// (and any menu edits) stayed invisible until the app restarted.
final catalogTickProvider = NotifierProvider<TickNotifier, int>(
  TickNotifier.new,
);

/// Bumped whenever the drawer's figures may have moved: a pay in / pay out
/// recorded here, a cash sale, refund, void or settle, or a realtime event
/// that can carry another till's sale. The Till and close-till surfaces
/// re-read the core's till report on it. A shell refresh is NOT that
/// signal — it only emits when the route or session changes, which a cash
/// movement never does.
final drawerTickProvider = NotifierProvider<TickNotifier, int>(
  TickNotifier.new,
);

/// Bumped when the core says its sync moved (`sync.status`, `sync.changed`):
/// the sync-on-open strip and the Sync section re-read the core's status on
/// it instead of polling.
final syncTickProvider = NotifierProvider<TickNotifier, int>(TickNotifier.new);

/// Bumped when an attempt to open a till found one ALREADY open for this
/// person here — the way in refused over an open till, or the core answered
/// `already_open` (a stale form, a race, the server's till resumed). Nothing
/// new was opened; the shell's chrome says so (`till.already_open`) over
/// whichever tab the teller lands on.
final tillAlreadyOpenProvider = NotifierProvider<TickNotifier, int>(
  TickNotifier.new,
);

/// Bumped when the core emptied every cart outside a sign-in (closing a
/// till). Each open cart re-reads its context on it.
final cartsClearedTickProvider = NotifierProvider<TickNotifier, int>(
  TickNotifier.new,
);

/// Where this branch expects a fired round to be SEEN: `kds` (a screen in the
/// kitchen), `till` (the counter bumps it itself), `both`, or `off` (nothing
/// is routed at all). `null` until this device has reached the server once.
///
/// Re-read on every connectivity pulse, because it is a shop-level setting a
/// manager can change from the dashboard mid-till: a till that was offline
/// when the kitchen moved onto a screen must not keep bumping for the rest of
/// the day. The core caches the last known answer, so this survives going
/// offline; only a device that has NEVER reached the server sees `null`.
class KitchenRoutingModeNotifier extends Notifier<String?> {
  @override
  String? build() {
    // listen, NOT watch: a pulse should refresh the answer, not throw the
    // last known one away and blink the Kitchen segment out of the header
    // every time the link flaps.
    ref.listen(connectivityPulseProvider, (_, _) => unawaited(refresh()));
    unawaited(refresh());
    return null;
  }

  /// Re-read the mode. The core answers from its cache when the server is
  /// unreachable, so this only stays `null` on a device that has never
  /// reached it at all.
  Future<void> refresh() async {
    try {
      state = await ref.read(bridgeProvider).kitchenRoutingMode();
    } on MadarError catch (e) {
      // Signed out, or no branch bound yet — not worth a banner. A transport
      // failure is worth a connectivity re-check.
      ref.read(connectivityRefreshProvider.notifier).reportError(e);
    }
  }
}

final kitchenRoutingModeProvider =
    NotifierProvider<KitchenRoutingModeNotifier, String?>(
      KitchenRoutingModeNotifier.new,
    );

/// Does the TILL show kitchen work in this mode? The Rust twin is
/// `kds::till_shows_kitchen`; both must answer the same, and both answer
/// `false` to an unknown mode.
///
/// `till` and `both` are the modes where a fired round is meant to be seen at
/// the counter. In `kds` the kitchen owns the board and a till that bumps is
/// bumping behind the cook's back; in `off` nothing is routed anywhere.
bool tillShowsKitchen(String? mode) => mode == 'till' || mode == 'both';

/// Is anything routed to a kitchen at all? `off` is a shop that fires nothing
/// — no chit, no board, no readiness to draw. Unknown is NOT off.
bool kitchenIsRouted(String? mode) => mode != 'off';

/// SSE connection state — the KDS header dot / reconnecting banner.
class ConnectedNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  // Notifier state writes must go through a method; a positional bool
  // matches the SSE callback shape it's fed from.
  // ignore: avoid_positional_boolean_parameters, use_setters_to_change_properties
  void update(bool connected) => state = connected;
}

final realtimeConnectedProvider = NotifierProvider<ConnectedNotifier, bool>(
  ConnectedNotifier.new,
);

/// The latest core-raised alert, sequence-paired so identical consecutive
/// commands still notify (AlertCommand is a value type).
class AlertNotifier extends Notifier<(int, AlertCommand)?> {
  int _seq = 0;

  @override
  (int, AlertCommand)? build() => null;

  void emit(AlertCommand cmd) => state = (++_seq, cmd);
}

final alertProvider = NotifierProvider<AlertNotifier, (int, AlertCommand)?>(
  AlertNotifier.new,
);

/// Bumped when any layer catches a 401 with a live session — the order
/// surface watches it and presents the re-auth sheet.
class ReauthNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final reauthRequestProvider = NotifierProvider<ReauthNotifier, int>(
  ReauthNotifier.new,
);

/// Bumped when a screen's chrome asks for the shell's nav drawer (the
/// narrow layouts' More menu — the natives' phone drawer). The order top
/// bar's leading toggle bumps it; the app shell listens and presents.
class NavDrawerNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void request() => state++;
}

final navDrawerRequestProvider = NotifierProvider<NavDrawerNotifier, int>(
  NavDrawerNotifier.new,
);

/// Bumped each time the app-level connectivity service refreshes the core's
/// online state (OS network change / app resume / a failed request). Screens
/// that show connectivity (the sync chip, the offline banner) watch this and
/// re-read `syncStatus()` — so offline/online reflects the DEVICE's actual
/// reachability app-wide, not just after a request times out.
class ConnectivityPulseNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void pulse() => state++;
}

final connectivityPulseProvider =
    NotifierProvider<ConnectivityPulseNotifier, int>(
      ConnectivityPulseNotifier.new,
    );

/// The THREE facts a screen can mean by "offline", kept apart on purpose.
///
/// They used to be fused into one boolean that every feature re-cached in its
/// own state class, so two screens could hold different answers between pulses
/// and the app contradicted itself — a banner reading offline over a top bar
/// reading online, on a device that was online. There is ONE reachability fact
/// and it lives in the Rust core (`session.snapshot.online`, surfaced as
/// `syncStatus().online`); this is its single Dart mirror. A feature reads it,
/// it does not keep its own copy.
///
/// Pick the one you actually mean:
/// * [reachable] — "we can reach the server right now". The ONLY thing that may
///   be worded "offline". It already carries the core's hysteresis, so it does
///   not flicker on one failed request.
/// * [queued] / [dead] — "there is work waiting" / "work the server refused".
///   Local facts that say nothing about reachability: a device with a backlog
///   can be perfectly online, and a screen that only needs to know whether
///   something is queued must NOT say offline.
/// * [lanPeers] — "this device is on a LAN with other tills". Needs no internet
///   at all, so it must never be gated on [reachable].
class ConnectivitySignal {
  const ConnectivitySignal({
    this.reachable = true,
    this.queued = 0,
    this.dead = 0,
    this.lanPeers = 0,
  });

  /// Can we reach the server right now? The core's confirmed signal.
  final bool reachable;

  /// Outbox rows waiting to go. NOT a reachability fact.
  final int queued;

  /// Outbox rows the server refused — someone has to act. NOT reachability.
  final int dead;

  /// Live LAN peers. Independent of the internet.
  final int lanPeers;

  /// "There is work waiting" — queued or refused.
  bool get hasQueuedWork => queued > 0 || dead > 0;
}

/// THE Dart mirror of the core's one connectivity signal. Re-reads on every
/// [connectivityPulseProvider] bump (the app-level service pulses after each
/// OS network change, app resume, failed request or timer re-check), so every
/// screen watching this sees the same answer at the same time.
class ConnectivityNotifier extends Notifier<ConnectivitySignal> {
  @override
  ConnectivitySignal build() {
    ref.listen(connectivityPulseProvider, (_, _) => refresh());
    // Read the core NOW rather than on a microtask: a first frame that guessed
    // and then corrected itself is the same contradiction this provider exists
    // to remove.
    return _read() ?? const ConnectivitySignal();
  }

  void refresh() {
    final next = _read();
    if (next != null) state = next;
  }

  /// The core's answer, or null if it could not be asked — in which case the
  /// last honest reading stands. Guessing "offline" here is exactly how the UI
  /// used to contradict itself.
  ConnectivitySignal? _read() {
    final bridge = ref.read(bridgeProvider);
    try {
      final status = bridge.syncStatus();
      var peers = 0;
      try {
        peers = bridge.lanPeerCount();
      } on Object {
        // The LAN relay is optional; its absence is not a connectivity fact.
      }
      return ConnectivitySignal(
        reachable: status.online,
        queued: status.pendingOutbox,
        dead: status.deadOutbox,
        lanPeers: peers,
      );
    } on Object {
      return null;
    }
  }
}

final connectivityProvider =
    NotifierProvider<ConnectivityNotifier, ConnectivitySignal>(
      ConnectivityNotifier.new,
    );

/// True only for TRANSPORT-class failures (the device/link is down, or the
/// server is unreachable) — the errors that should trigger a connectivity
/// re-check. Business errors (`Unauthenticated`/`Forbidden`/`Validation`/
/// `Server` 5xx/`Internal`) say nothing about reachability, so they must NOT.
bool isTransportError(MadarError error) =>
    error is MadarError_Offline || error is MadarError_Transient;

/// The app-wide "re-check connectivity NOW" hook. The app registers the
/// connectivity service's debounced `refresh` here at boot; any provider that
/// catches a transport-class failure calls [reportError] (or [request]) and
/// the service does ONE `/health` confirm + pulse. This is what replaces the
/// old periodic polling: connectivity is re-evaluated on OS network events,
/// app resume, and *actual failed requests* — never on a blanket timer.
class ConnectivityRefreshNotifier extends Notifier<void Function()?> {
  @override
  void Function()? build() => null;

  /// The app installs the service's `refresh` closure here at boot.
  // ignore: use_setters_to_change_properties
  void register(void Function() refresh) => state = refresh;

  /// Unconditionally ask the service to re-check (OS/resume paths).
  void request() => state?.call();

  /// Ask the service to re-check ONLY when [error] is transport-class — the
  /// single call every provider's `catch` uses, so the transport test lives
  /// in one place.
  void reportError(Object error) {
    if (error is MadarError && isTransportError(error)) state?.call();
  }
}

final connectivityRefreshProvider =
    NotifierProvider<ConnectivityRefreshNotifier, void Function()?>(
      ConnectivityRefreshNotifier.new,
    );

/// The app-wide "this device was wiped" hook. A reconfigure wipe leaves every
/// provider holding state derived from data that no longer exists, so the app
/// registers a closure here that throws the whole [ProviderContainer] away and
/// mounts a fresh one (a first launch). Unregistered (a test), [reset] is a
/// shell refresh.
class DeviceResetNotifier extends Notifier<void Function()?> {
  @override
  void Function()? build() => null;

  /// The app installs its container reset here at boot.
  // ignore: use_setters_to_change_properties
  void register(void Function() reset) => state = reset;

  /// Start over from a fresh container.
  void reset() {
    final hook = state;
    if (hook != null) {
      hook();
    } else {
      ref.read(shellProvider.notifier).refresh();
    }
  }
}

final deviceResetProvider =
    NotifierProvider<DeviceResetNotifier, void Function()?>(
      DeviceResetNotifier.new,
    );
