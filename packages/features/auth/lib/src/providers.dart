import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// PIN length window: auto-submit at 6, reject below 4 (natives' maxPin /
/// submit guard). Shared by teller sign-in and mid-shift re-auth.
const int _maxPin = 6;
const int _minPin = 4;

/// Sentinel for [AuthState.copyWith]'s nullable `error`.
const Object _unset = Object();

/// Device-setup is two steps: a manager authenticates, then picks the branch.
enum SetupPhase {
  /// Org email + password.
  credentials,

  /// Choose the branch to bind the till to.
  pickBranch,
}

/// The whole auth-flow surface: teller PIN entry (login + re-auth share the
/// buffer — they can never be on screen together), the manager device-setup
/// stepper, and the KDS station-picker list.
class AuthState {
  /// Creates an auth state (defaults = idle credentials phase).
  const AuthState({
    this.phase = SetupPhase.credentials,
    this.busy = false,
    this.error,
    this.pin = '',
    this.failCount = 0,
    this.configVersion = 0,
    this.branches = const [],
    this.stations = const [],
    this.stationsLoading = true,
  });

  /// Which device-setup step is showing.
  final SetupPhase phase;

  /// A bridge auth call is in flight (dims inputs, spins the CTA).
  final bool busy;

  /// Human-readable failure from the last auth call, if any.
  final String? error;

  /// Digits entered so far (drives the PIN dots).
  final String pin;

  /// Monotonic failure counter — bumped on EVERY rejected submit (including
  /// local short-PIN / empty-name guards that set no [error]) so the forms
  /// can `ref.listen` and run the shake + warning haptic exactly once per
  /// failure, like the natives' `fail()`.
  final int failCount;

  /// Bumped whenever a bridge call mutates `deviceConfig()` (reconfigure
  /// begin/cancel, branch bind) — screens that render from `deviceConfig()`
  /// watch this to re-read it.
  final int configVersion;

  /// Branches offered on [SetupPhase.pickBranch].
  final List<BranchView> branches;

  /// Stations offered on the KDS station picker.
  final List<KdsStationView> stations;

  /// The station list is still loading.
  final bool stationsLoading;

  /// Copy with the given fields replaced ([error] supports null-out).
  AuthState copyWith({
    SetupPhase? phase,
    bool? busy,
    Object? error = _unset,
    String? pin,
    int? failCount,
    int? configVersion,
    List<BranchView>? branches,
    List<KdsStationView>? stations,
    bool? stationsLoading,
  }) {
    return AuthState(
      phase: phase ?? this.phase,
      busy: busy ?? this.busy,
      error: identical(error, _unset) ? this.error : error as String?,
      pin: pin ?? this.pin,
      failCount: failCount ?? this.failCount,
      configVersion: configVersion ?? this.configVersion,
      branches: branches ?? this.branches,
      stations: stations ?? this.stations,
      stationsLoading: stationsLoading ?? this.stationsLoading,
    );
  }
}

/// The auth-flow notifier — every bridge auth mutation lives here and ends
/// with `shellProvider.notifier.refresh()` (the old `onStateChanged`).
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  MadarBridge get _bridge => ref.read(bridgeProvider);

  String _t(String key) => _bridge.tr(key: key);

  void _refreshShell() => ref.read(shellProvider.notifier).refresh();

  void _bumpFail() => state = state.copyWith(failCount: state.failCount + 1);

  /// Append a keypad digit. Returns true when the buffer just reached the
  /// auto-submit length — the caller then submits.
  bool pushDigit(String digit) {
    if (state.busy || state.pin.length >= _maxPin) return false;
    state = state.copyWith(error: null, pin: state.pin + digit);
    return state.pin.length == _maxPin;
  }

  /// Delete the last keypad digit.
  void popDigit() {
    if (state.pin.isEmpty) return;
    state = state.copyWith(pin: state.pin.substring(0, state.pin.length - 1));
  }

  /// Clear the PIN buffer + error/busy — called when the re-auth sheet opens
  /// so it never inherits leftovers from a previous entry.
  void resetEntry() =>
      state = state.copyWith(pin: '', error: null, busy: false);

  /// Shared PIN sign-in tail (teller login and mid-shift re-auth). Returns
  /// true on success; on failure clears the PIN and bumps [AuthState.failCount].
  Future<bool> _signInPin(String name) async {
    state = state.copyWith(busy: true, error: null);
    String? failure;
    try {
      await _bridge.signIn(
        req: LoginRequest(
          mode: LoginMode.pin,
          name: name,
          pin: state.pin,
          branchId: _bridge.deviceConfig().branchId,
        ),
      );
    } on MadarError catch (e) {
      failure = _bridge.humanMessage(e);
    } on Exception catch (_) {
      failure = _t('err.generic');
    }
    _refreshShell();
    state = state.copyWith(
      busy: false,
      error: failure,
      pin: failure != null ? '' : state.pin,
      failCount: failure != null ? state.failCount + 1 : state.failCount,
    );
    return failure == null;
  }

  /// Daily teller PIN sign-in (natives' `signIn`). Rejects an empty name or
  /// a short PIN locally (fail bump → shake), otherwise hits the bridge.
  Future<void> signInTeller({required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || state.pin.length < _minPin) {
      _bumpFail();
      return;
    }
    await _signInPin(trimmed);
  }

  /// Re-authenticate the SAME teller who owns the open shift (no handover) —
  /// the natives' `reauth(pin)`. Returns true when sync resumed.
  Future<bool> reauthenticate() async {
    if (state.pin.length < _minPin) {
      _bumpFail();
      return false;
    }
    final name = _bridge.currentSession()?.displayName ?? '';
    return _signInPin(name);
  }

  /// Re-enter device setup (natives' `beginReconfigure`) — the route/form
  /// recomputes to the manager setup flow.
  Future<void> beginReconfigure() async {
    try {
      await _bridge.startReconfigure();
    } on Exception catch (_) {}
    state = state.copyWith(configVersion: state.configVersion + 1);
    _refreshShell();
  }

  /// Best-effort logout — setup auth failures must never strand a session.
  Future<void> _quietLogout() async {
    try {
      await _bridge.logout(wipeOutbox: false);
    } on Exception catch (_) {}
  }

  /// Manager credentials → branch list (natives' `authenticateManager`).
  Future<void> authenticateManager({
    required String email,
    required String password,
  }) async {
    state = state.copyWith(busy: true, error: null);
    String? failure;
    var branches = const <BranchView>[];
    try {
      await _bridge.login(
        req: LoginRequest(
          mode: LoginMode.email,
          email: email.trim(),
          password: password,
        ),
      );
      branches = await _bridge.listBranches();
    } on MadarError catch (e) {
      failure = _bridge.humanMessage(e);
      await _quietLogout();
    } on Exception catch (_) {
      failure = _t('err.generic');
      await _quietLogout();
    }
    _refreshShell();
    state = state.copyWith(
      busy: false,
      error: failure,
      phase: failure == null ? SetupPhase.pickBranch : state.phase,
      branches: failure == null ? branches : state.branches,
    );
  }

  /// Reset the setup stepper to credentials and invalidate config-derived UI.
  void _resetSetup() {
    state = state.copyWith(
      phase: SetupPhase.credentials,
      branches: const [],
      error: null,
      configVersion: state.configVersion + 1,
    );
  }

  /// Bind the till to [branch], then sign the manager out so tellers sign in
  /// (natives' `bindBranch`).
  Future<void> bindBranch(BranchView branch) async {
    try {
      await _bridge.setDeviceBranch(
        branchId: branch.id,
        branchName: branch.name,
      );
    } on Exception catch (_) {}
    await _quietLogout();
    _resetSetup();
    _refreshShell();
  }

  /// Re-confirm the existing branch to drop the reconfigure flag (natives'
  /// `cancelReconfigure`).
  Future<void> cancelReconfigure() async {
    final config = _bridge.deviceConfig();
    final branchId = config.branchId;
    if (branchId != null && branchId.isNotEmpty) {
      try {
        await _bridge.setDeviceBranch(
          branchId: branchId,
          branchName: config.branchName,
        );
      } on Exception catch (_) {}
    }
    await _quietLogout();
    _resetSetup();
    _refreshShell();
  }

  /// Load the branch's stations (natives' `loadKdsStations` — failures fall
  /// back to an empty list, surfacing the "no stations" copy). Read-only, so
  /// no shell refresh.
  Future<void> loadStations() async {
    var stations = const <KdsStationView>[];
    try {
      stations = await _bridge.kdsListStations();
    } on Exception catch (_) {}
    state = state.copyWith(stations: stations, stationsLoading: false);
  }

  /// Pin this device to [station] — the route recomputes to the KDS.
  Future<void> pickStation(KdsStationView station) async {
    String? failure;
    try {
      await _bridge.setDeviceStation(stationId: station.id);
    } on MadarError catch (e) {
      failure = _bridge.humanMessage(e);
    } on Exception catch (_) {
      failure = _t('err.generic');
    }
    state = state.copyWith(error: failure);
    _refreshShell();
  }

  /// Tear down the session (natives' `signOut`) — routing falls back to
  /// login. The shell owns the realtime/LAN lifecycles and reacts to the
  /// route change.
  Future<void> signOut() async {
    try {
      _bridge.unsubscribeRealtime();
    } on Exception catch (_) {}
    await _quietLogout();
    _refreshShell();
  }
}

/// The auth-flow state — teller PIN, device setup, station picker, re-auth.
final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
