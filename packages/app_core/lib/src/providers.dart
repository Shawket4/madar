import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The booted core. The app overrides this on the post-boot subtree:
/// `ProviderScope(overrides: [coreProvider.overrideWithValue(core)])`.
/// Reading it before boot is a programmer error.
final coreProvider = Provider<MadarCore>(
  (_) => throw StateError('coreProvider read before boot override'),
);

/// Convenience: the bridge handle (every screen's call surface).
final bridgeProvider = Provider<MadarBridge>(
  (ref) => ref.watch(coreProvider).bridge,
);

/// The shell truth: the core-derived route + the session snapshot.
/// [ShellNotifier.refresh] is the old `onStateChanged` — call it after any
/// bridge call that can move `app_route()` or the session.
class ShellState {
  const ShellState({required this.route, required this.session});

  final AppRoute route;
  final SessionSnapshot? session;
}

class ShellNotifier extends Notifier<ShellState> {
  @override
  ShellState build() {
    final bridge = ref.watch(bridgeProvider);
    return ShellState(
      route: bridge.appRoute(),
      session: bridge.currentSession(),
    );
  }

  /// Re-read route + session from the core; notifies only on change.
  void refresh() {
    final bridge = ref.read(bridgeProvider);
    final next = ShellState(
      route: bridge.appRoute(),
      session: bridge.currentSession(),
    );
    if (next.route != state.route || next.session != state.session) {
      state = next;
    }
    ref.read(realtimeArmerProvider)();
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
