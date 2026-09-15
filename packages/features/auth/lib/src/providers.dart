import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// PIN length window: auto-submit at 6, reject below 4 (natives' maxPin /
/// submit guard). Shared by teller sign-in and mid-till re-auth.
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
    this.stationsError,
  });

  /// Which device-setup step is showing.
  final SetupPhase phase;

  /// A bridge auth call is in flight (dims inputs, spins the CTA).
  final bool busy;

  /// Human-readable failure from the last auth call, if any.
  final UiText? error;

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

  /// Why the station list could not be read, or null. Distinct from an
  /// empty list: "this branch has no stations" and "we could not ask" call
  /// for different things from the person holding the tablet.
  final UiText? stationsError;

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
    Object? stationsError = _unset,
  }) {
    return AuthState(
      phase: phase ?? this.phase,
      busy: busy ?? this.busy,
      error: identical(error, _unset) ? this.error : error as UiText?,
      pin: pin ?? this.pin,
      failCount: failCount ?? this.failCount,
      configVersion: configVersion ?? this.configVersion,
      branches: branches ?? this.branches,
      stations: stations ?? this.stations,
      stationsLoading: stationsLoading ?? this.stationsLoading,
      stationsError: identical(stationsError, _unset)
          ? this.stationsError
          : stationsError as UiText?,
    );
  }
}

/// The auth-flow notifier — every bridge auth mutation lives here and ends
/// with `shellProvider.notifier.refresh()` (the old `onStateChanged`).
class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  MadarBridge get _bridge => ref.read(bridgeProvider);

  void _refreshShell() => ref.read(shellProvider.notifier).refresh();

  void _bumpFail() => state = state.copyWith(failCount: state.failCount + 1);

  /// Append a keypad digit. Returns true when the buffer just reached the
  /// auto-submit length — the caller then submits. Anything but a single
  /// ASCII digit is ignored (a hardware keyboard can send anything).
  bool pushDigit(String digit) {
    if (digit.length != 1 || !'0123456789'.contains(digit)) return false;
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

  /// Shared PIN sign-in tail (teller login and mid-till re-auth). Returns
  /// true on success; on failure clears the PIN and bumps [AuthState.failCount].
  Future<bool> _signInPin(String name) async {
    state = state.copyWith(busy: true, error: null);
    UiText? failure;
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
      failure = UiText.error(e);
    } on Exception catch (_) {
      failure = const UiText.key('err.generic');
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
  ///
  /// A local rejection says why and CLEARS the PIN. It used to keep it: the
  /// sixth digit auto-submits, a blank name refused it silently, and a full
  /// buffer refuses every further digit — the pad looked frozen.
  Future<void> signInTeller({required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(
        pin: '',
        error: const UiText.key('login.name_required'),
        failCount: state.failCount + 1,
      );
      return;
    }
    if (state.pin.length < _minPin) {
      state = state.copyWith(
        error: const UiText.key('login.pin_too_short'),
        failCount: state.failCount + 1,
      );
      return;
    }
    await _signInPin(trimmed);
  }

  /// Re-authenticate the SAME teller who owns the open till (no handover) —
  /// the natives' `reauth(pin)`. ONLINE-ONLY by design: this sheet exists to
  /// mint a fresh JWT from the server (an expired bearer parked the outbox),
  /// so the combined sign-in's offline PIN fallback would "succeed" locally
  /// without un-parking anything. A transport failure surfaces as the
  /// localized offline error and the sheet stays up. Returns true when sync
  /// actually resumed.
  Future<bool> reauthenticate() async {
    if (state.pin.length < _minPin) {
      _bumpFail();
      return false;
    }
    final name = _bridge.currentSession()?.displayName ?? '';
    state = state.copyWith(busy: true, error: null);
    UiText? failure;
    try {
      await _bridge.login(
        req: LoginRequest(
          mode: LoginMode.pin,
          name: name,
          pin: state.pin,
          branchId: _bridge.deviceConfig().branchId,
        ),
      );
    } on MadarError catch (e) {
      failure = UiText.error(e);
    } on Exception catch (_) {
      failure = const UiText.key('err.generic');
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
    UiText? failure;
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
      failure = UiText.error(e);
      await _quietLogout();
    } on Exception catch (_) {
      failure = const UiText.key('err.generic');
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
  ///
  /// A failed bind stays on the branch list with the reason. It used to be
  /// swallowed and followed by the logout and the reset, so the manager
  /// landed back on an empty credentials form with the device still unbound
  /// and no word about why.
  Future<void> bindBranch(BranchView branch) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, error: null);
    UiText? failure;
    try {
      await _bridge.setDeviceBranch(
        branchId: branch.id,
        branchName: branch.name,
      );
    } on MadarError catch (e) {
      failure = UiText.error(e);
    } on Exception catch (_) {
      failure = const UiText.key('err.generic');
    }
    if (failure != null) {
      state = state.copyWith(busy: false, error: failure);
      return;
    }
    state = state.copyWith(busy: false);
    await _quietLogout();
    _resetSetup();
    _refreshShell();
  }

  /// Re-confirm the existing branch to drop the reconfigure flag (natives'
  /// `cancelReconfigure`). A failure keeps the form up with the reason —
  /// resetting anyway would leave the device half-reconfigured.
  Future<void> cancelReconfigure() async {
    final config = _bridge.deviceConfig();
    final branchId = config.branchId;
    if (branchId != null && branchId.isNotEmpty) {
      UiText? failure;
      try {
        await _bridge.setDeviceBranch(
          branchId: branchId,
          branchName: config.branchName,
        );
      } on MadarError catch (e) {
        failure = UiText.error(e);
      } on Exception catch (_) {
        failure = const UiText.key('err.generic');
      }
      if (failure != null) {
        state = state.copyWith(error: failure);
        return;
      }
    }
    await _quietLogout();
    _resetSetup();
    _refreshShell();
  }

  /// Load the branch's stations. A failure is NOT an empty branch: it lands
  /// in [AuthState.stationsError] so the picker offers a retry instead of
  /// telling an offline tablet the branch has no stations. Read-only, so no
  /// shell refresh.
  Future<void> loadStations() async {
    state = state.copyWith(stationsLoading: true, stationsError: null);
    try {
      final stations = await _bridge.kdsListStations();
      state = state.copyWith(stations: stations, stationsLoading: false);
    } on MadarError catch (e) {
      state = state.copyWith(
        stationsLoading: false,
        stationsError: UiText.error(e),
      );
    } on Exception catch (_) {
      state = state.copyWith(
        stationsLoading: false,
        stationsError: const UiText.key('err.generic'),
      );
    }
  }

  /// Pin this device to [station] — the route recomputes to the KDS.
  Future<void> pickStation(KdsStationView station) async {
    UiText? failure;
    try {
      await _bridge.setDeviceStation(stationId: station.id);
    } on MadarError catch (e) {
      failure = UiText.error(e);
    } on Exception catch (_) {
      failure = const UiText.key('err.generic');
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
