/// Settings state — the Riverpod spine behind the settings screen: the device
/// config mirror (custody lives in the CORE; this only mirrors), printer
/// brand + test-print lifecycle, till/station binding, the LAN hub, and the
/// diagnostics feed. Route-moving actions (station bind) refresh the shell;
/// reconfigure/sign-out return success so the screen pops before the shell
/// re-reads.
library;

import 'package:app_core/app_core.dart';
import 'package:feature_checkout/feature_checkout.dart'
    show PrintState, kReceiptChars;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Default JetDirect (raw-TCP) printer port — the natives' `parsePrinter`
/// fallback.
const int _jetDirectPort = 9100;

/// Wire name → [PrinterBrand] (the natives' brand mapping).
PrinterBrand _brandOf(String? wire) =>
    wire == 'star' ? PrinterBrand.star : PrinterBrand.epson;

/// Split `"host"` / `"host:port"` → (host, port); default JetDirect 9100
/// (the natives' `parsePrinter`).
(String, int) _parsePrinter(String raw) {
  final trimmed = raw.trim();
  final colon = trimmed.lastIndexOf(':');
  if (colon < 0) return (trimmed, _jetDirectPort);
  final port = int.tryParse(trimmed.substring(colon + 1)) ?? _jetDirectPort;
  return (trimmed.substring(0, colon), port);
}

/// Reassemble `"host:port"` from the core's split printer config (the
/// natives' `printerAddress`). Empty when no printer is bound. The screen
/// seeds its printer field from this.
String printerAddressOf(DeviceConfigView config) {
  final host = config.printerHost?.trim() ?? '';
  if (host.isEmpty) return '';
  final port = config.printerPort;
  return (port != null && port != _jetDirectPort) ? '$host:$port' : host;
}

const Object _keep = Object();

/// Immutable settings-screen state: the config mirror plus everything the
/// cards render.
class SettingsState {
  const SettingsState({
    required this.config,
    required this.brand,
    this.till,
    this.stations = const [],
    this.diagnostics = const [],
    this.pending = 0,
    this.printState = PrintState.idle,
    this.pairedDevices = const [],
    this.scanningBt = false,
    this.floorAuthored = true,
    this.error,
    this.writeError,
  });

  /// The core's device-config mirror (till/station/printer/LAN bindings).
  final DeviceConfigView config;

  /// The selected printer brand chip.
  final PrinterBrand brand;

  /// Current till — the sign-out/reconfigure guard + the account card.
  final TillView? till;

  /// Bindable kitchen stations (KDS devices).
  final List<KdsStationView> stations;

  /// Recent warning/error log feed.
  final List<DiagLogView> diagnostics;

  /// Pending outbox count (diagnostics row).
  final int pending;

  /// Test-print lifecycle.
  final PrintState printState;

  /// Paired Bluetooth printers offered in the transport picker (populated by a
  /// scan; empty until the user refreshes while on the Bluetooth transport).
  final List<BtDevice> pairedDevices;

  /// True while listing paired Bluetooth devices.
  final bool scanningBt;

  /// The branch has a floor layout mirrored. An empty mirror is the floor's
  /// feature gate, so a shop that expected a Floor tab and has none finds
  /// the reason under Diagnostics. Optimistically true until loaded.
  final bool floorAuthored;

  /// Guard-failure banner text (open-till sign-out/reconfigure).
  final UiText? error;

  /// The last device write the core refused (printer, till, LAN hub, …), or
  /// null. Writes used to fail silently, so a till looked bound to a
  /// printer or a drawer it was not.
  final UiText? writeError;

  /// Whether the drawer is open (blocks sign-out and reconfigure).
  bool get hasOpenTill => till?.isOpen ?? false;

  /// Copy with the given fields replaced. `null` keeps the current value
  /// ([error] and [till] are never cleared through here — a fresh
  /// [SettingsNotifier.load] rebuilds the state whole).
  SettingsState copyWith({
    DeviceConfigView? config,
    PrinterBrand? brand,
    TillView? till,
    List<KdsStationView>? stations,
    List<DiagLogView>? diagnostics,
    int? pending,
    PrintState? printState,
    List<BtDevice>? pairedDevices,
    bool? scanningBt,
    bool? floorAuthored,
    UiText? error,
    Object? writeError = _keep,
  }) {
    return SettingsState(
      config: config ?? this.config,
      brand: brand ?? this.brand,
      till: till ?? this.till,
      stations: stations ?? this.stations,
      diagnostics: diagnostics ?? this.diagnostics,
      pending: pending ?? this.pending,
      printState: printState ?? this.printState,
      pairedDevices: pairedDevices ?? this.pairedDevices,
      scanningBt: scanningBt ?? this.scanningBt,
      floorAuthored: floorAuthored ?? this.floorAuthored,
      error: error ?? this.error,
      writeError: identical(writeError, _keep)
          ? this.writeError
          : writeError as UiText?,
    );
  }
}

/// The settings controller. All bridge writes flow through here; the screen
/// only renders [SettingsState] and forwards taps/keystrokes.
class SettingsNotifier extends Notifier<SettingsState> {
  MadarBridge get _bridge => ref.read(bridgeProvider);

  bool get _isKitchenDevice =>
      ref.read(shellProvider).session?.role == 'kitchen';

  @override
  SettingsState build() {
    final config = ref.localizedBridge.deviceConfig();
    return SettingsState(config: config, brand: _brandOf(config.printerBrand));
  }

  /// Swallow bridge failures on best-effort reads/writes (the natives'
  /// `runCatching`) — settings must render offline with whatever's cached. A
  /// transport-class failure nudges the connectivity service (one debounced
  /// probe).
  Future<T?> _quiet<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Exception catch (e) {
      ref.read(connectivityRefreshProvider.notifier).reportError(e);
      return null;
    }
  }

  /// Prime the screen: till (sign-out/reconfigure guards + account card),
  /// the till or station list, pending count, and the diagnostics feed.
  /// Rebuilds the state whole, so a fresh mount starts clean (no stale
  /// error banner or print status).
  Future<void> load() async {
    final config = _bridge.deviceConfig();
    final till = await _quiet(_bridge.currentTill);
    final stations = _isKitchenDevice
        ? await _quiet(_bridge.kdsListStations) ?? const <KdsStationView>[]
        : const <KdsStationView>[];
    final pending = await _quiet(_bridge.pendingOutboxCount) ?? 0;
    final diagnostics =
        await _quiet(_bridge.recentLogs) ?? const <DiagLogView>[];
    // The floor mirror is local; reading it is free and never throws
    // offline. Null (a failed read) keeps the optimistic default.
    final floor = await _quiet(_bridge.floorLayout);
    state = SettingsState(
      config: config,
      brand: _brandOf(config.printerBrand),
      till: till,
      stations: stations,
      diagnostics: diagnostics,
      pending: pending,
      floorAuthored: floor == null || floor.tables.isNotEmpty,
    );
  }

  // ── device writes (custody lives in the CORE; the state only mirrors) ────

  /// A device WRITE: unlike [_quiet] a refusal is surfaced in
  /// [SettingsState.writeError] (and cleared by the next write that lands).
  /// Returns false when the core refused.
  Future<bool> _write(Future<void> Function() body) async {
    try {
      await body();
      if (state.writeError != null) state = state.copyWith(writeError: null);
      return true;
    } on MadarError catch (e) {
      ref.read(connectivityRefreshProvider.notifier).reportError(e);
      state = state.copyWith(writeError: UiText.error(e));
      return false;
    } on Exception catch (e) {
      ref.read(connectivityRefreshProvider.notifier).reportError(e);
      state = state.copyWith(writeError: const UiText.key('err.generic'));
      return false;
    }
  }

  /// Dismiss the write-failure banner.
  void clearWriteError() => state = state.copyWith(writeError: null);

  /// Persist this till's device code per keystroke (the core sanitizes;
  /// blank is ignored and keeps the current code).
  void setDeviceCode(String code) => _bridge.setDeviceCode(code: code);

  /// Persist the printer (split "host:port" + brand wire name) and re-read
  /// the config mirror. Passing [brand] also flips the brand chip.
  Future<void> persistPrinter(String address, {PrinterBrand? brand}) async {
    if (brand != null) state = state.copyWith(brand: brand);
    final wire = state.brand == PrinterBrand.star ? 'star' : 'epson';
    final (host, port) = _parsePrinter(address);
    await _write(
      () => _bridge.setDevicePrinter(
        host: host.isEmpty ? null : host,
        port: port,
        brand: wire,
      ),
    );
    state = state.copyWith(config: _bridge.deviceConfig());
  }

  /// Switch the printer transport — `"lan"` (raw-TCP) or `"bluetooth"`
  /// (Classic SPP) — and re-mirror. Entering Bluetooth kicks off a paired-
  /// device scan so the picker is ready.
  Future<void> setTransport(String kind) async {
    await _write(() => _bridge.setDevicePrinterTransport(kind: kind));
    state = state.copyWith(config: _bridge.deviceConfig());
    if (kind == 'bluetooth') await loadPairedDevices();
  }

  /// Pin the receipt paper width in dots — 384 (58 mm) or 576 (80 mm) — and
  /// re-mirror so the picker highlights the choice. The core renders the raster
  /// to this width on the next print.
  Future<void> setPaperDots(int dots) async {
    await _write(() => _bridge.setDevicePrinterPaper(dots: dots));
    state = state.copyWith(config: _bridge.deviceConfig());
  }

  /// List the OS's paired Bluetooth printers into [SettingsState.pairedDevices]
  /// (requests the runtime permission first). Best-effort: empty on denial or
  /// Bluetooth off.
  Future<void> loadPairedDevices() async {
    state = state.copyWith(scanningBt: true);
    final devices = await _quiet(
      () => ref.read(printerServiceProvider).listPairedDevices(),
    );
    state = state.copyWith(
      pairedDevices: devices ?? const <BtDevice>[],
      scanningBt: false,
    );
  }

  /// Bind the chosen paired Bluetooth printer (MAC + name) and re-mirror. Drops
  /// any open link so the next print reconnects to this device.
  Future<void> selectBtDevice(BtDevice device) async {
    await _write(() async {
      await ref.read(printerServiceProvider).disconnectBluetooth();
      await _bridge.setDevicePrinterBt(
        address: device.address,
        name: device.name,
      );
    });
    state = state.copyWith(config: _bridge.deviceConfig());
  }

  /// Persist a manual LAN hub address; empty clears it. The core registers
  /// it live if the relay is already running.
  Future<void> setLanHub(String value) async {
    final trimmed = value.trim();
    await _write(
      () => _bridge.setDeviceLanHub(hub: trimmed.isEmpty ? null : trimmed),
    );
    state = state.copyWith(config: _bridge.deviceConfig());
  }

  /// Bind this device's kitchen station (KDS devices). The station rides
  /// the route (`kitchenDisplay(stationId)`), so refresh the shell.
  Future<void> bindStation(String stationId) async {
    await _write(() => _bridge.setDeviceStation(stationId: stationId));
    state = state.copyWith(config: _bridge.deviceConfig());
    ref.read(shellProvider.notifier).refresh();
  }

  /// Render a tiny TEST receipt in the core and stream it to the
  /// configured printer — proves host/port/brand end-to-end.
  Future<void> testPrint() async {
    final tx = ref.read(printerServiceProvider).activeTransport();
    if (tx == null) {
      state = state.copyWith(printState: PrintState.noPrinter);
      return;
    }
    state = state.copyWith(printState: PrintState.printing);
    final config = _bridge.deviceConfig();
    final session = ref.read(shellProvider).session;
    try {
      final bytes = await _bridge.renderReceipt(
        receipt: _testReceipt(
          session?.displayName,
          _bridge.tr(key: 'settings.test_receipt_line'),
        ),
        storeName: config.branchName ?? '',
        currency: session?.currencyCode ?? '',
        width: kReceiptChars,
        brand: _brandOf(config.printerBrand),
      );
      await tx.send(bytes);
      state = state.copyWith(printState: PrintState.printed);
    } on Exception {
      state = state.copyWith(printState: PrintState.failed);
    }
  }

  /// A zero-total single-line receipt for the test page, its one line in
  /// the till's language like every other receipt.
  ReceiptView _testReceipt(String? tellerName, String line) {
    return ReceiptView(
      localOrderId: 'test-print',
      displayNumber: '',
      isVoided: false,
      lines: [
        ReceiptLineView(
          name: line,
          qty: 1,
          lineTotalMinor: 0,
          isBundle: false,
          addons: [],
          optionals: [],
          components: [],
        ),
      ],
      paymentLabel: '—',
      subtotalMinor: 0,
      discountMinor: 0,
      taxMinor: 0,
      serviceChargeMinor: 0,
      deliveryFeeMinor: 0,
      totalMinor: 0,
      tipMinor: 0,
      amountTenderedMinor: 0,
      changeMinor: 0,
      isCash: false,
      payments: const [],
      tellerName: tellerName,
      isDelivery: false,
      queuedOffline: false,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  // ── route-moving actions ──────────────────────────────────────────────────

  /// Re-provisioning is only allowed with a closed drawer (the natives'
  /// guard). Returns true when the screen should pop and refresh the shell
  /// (the route flips to DeviceSetup).
  Future<bool> reconfigure() async {
    if (state.hasOpenTill) {
      state = state.copyWith(
        error: const UiText.key('settings.reconfigure_shift_open'),
      );
      return false;
    }
    await _quiet(_bridge.startReconfigure);
    return true;
  }

  /// Sign-out (→ login) requires a closed drawer first. Tears down the
  /// realtime subscription + LAN relay, then the session (outbox kept).
  /// Returns true when the screen should pop and refresh the shell.
  Future<bool> signOut() async {
    if (state.hasOpenTill) {
      state = state.copyWith(
        error: const UiText.key('settings.sign_out_shift_open'),
      );
      return false;
    }
    _bridge.unsubscribeRealtime();
    await _quiet(_bridge.lanStop);
    await _quiet(() => _bridge.logout(wipeOutbox: false));
    return true;
  }

  /// Clear the recent-warnings feed.
  Future<void> clearDiagnostics() async {
    await _quiet(_bridge.clearLogs);
    state = state.copyWith(diagnostics: const []);
  }
}

/// The settings screen's state provider.
final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);
