/// Settings — a pixel-and-behavior port of the Kotlin SettingsScreen.kt:
/// account card, appearance + language (host-owned prefs via callbacks),
/// printer (host:port + brand + test print), till/station binding, LAN
/// relay, device reconfigure, diagnostics (versions, server, pending,
/// realtime, recent warnings), and sign-out. Full-screen over the order
/// screen; the header's back pops it via `Navigator.maybePop`.
library;

import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart'
    show PrintState, kReceiptChars;
import 'package:flutter/material.dart'
    show
        Brightness,
        CircularProgressIndicator,
        InputDecoration,
        Material,
        MaterialType,
        Scaffold,
        TextField,
        Theme;
import 'package:flutter/widgets.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (SettingsScreen.kt) that fall between the 4-pt Space
// steps — kept verbatim so the Flutter chrome measures identically.

/// Content column cap (natives: widthIn(max = 640.dp)).
const double _contentMaxWidth = 640;

/// Header back chevron + title (natives: 17.dp / 17.sp Black; Cairo tops
/// out at ExtraBold so w800 stands in).
const double _headerIconSize = 17;
const double _headerTitleSize = 17;

/// Account avatar tile (natives: 48.dp, Radii.sm) and initial size (16.sp).
const double _avatarSize = 48;
const double _avatarInitialSize = 16;

/// Chip label size (natives: 13.sp SemiBold).
const double _chipLabelSize = 13;

/// CTA button spinner (natives: 20.dp / 2.5.dp) and outline width (1.5.dp).
const double _spinnerSize = 20;
const double _spinnerStroke = 2.5;
const double _outlineBorder = 1.5;

/// Text-field vertical inset (natives: 16.dp) and icon↔text gap (10.dp).
const double _fieldVPad = 16;
const double _fieldGap = 10;

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
/// natives' `printerAddress`). Empty when no printer is bound.
String _printerAddress(DeviceConfigView config) {
  final host = config.printerHost?.trim() ?? '';
  if (host.isEmpty) return '';
  final port = config.printerPort;
  return (port != null && port != _jetDirectPort) ? '$host:$port' : host;
}

/// The settings overlay. Takes the shared screen contract — [core] for
/// every bridge call, [onStateChanged] after any call that can move
/// `app_route()` (reconfigure / sign-out / station binding) — plus the two
/// host-pref callbacks: locale and theme live in the HOST vault, so the
/// screen only reports the choice and the shell persists + re-themes.
class SettingsScreen extends StatefulWidget {
  /// Creates the settings screen.
  const SettingsScreen({
    required this.core,
    required this.onStateChanged,
    required this.onLocaleChanged,
    required this.onThemeChanged,
    super.key,
  });

  /// The core handle every bridge call goes through.
  final MadarCore core;

  /// Invoked after any call that can move `app_route()`.
  final void Function() onStateChanged;

  /// The teller picked a language (`en` / `ar`). The host owns the pref:
  /// it calls the core's `setLocale`, persists to the vault, and rebuilds.
  final void Function(String locale) onLocaleChanged;

  /// The teller picked a theme. The host owns the pref (vault `light`/
  /// `dark`) and re-themes the app.
  // The single-bool shape is the agreed screen contract for host prefs.
  // ignore: avoid_positional_boolean_parameters
  final void Function(bool dark) onThemeChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  MadarBridge get _bridge => widget.core.bridge;

  late DeviceConfigView _config = _bridge.deviceConfig();
  late final TextEditingController _deviceCode = TextEditingController(
    text: _bridge.deviceCode(),
  );
  late final TextEditingController _printerHost = TextEditingController(
    text: _printerAddress(_config),
  );
  late final TextEditingController _lanHub = TextEditingController(
    text: _config.lanHub ?? '',
  );
  late PrinterBrand _brand = _brandOf(_config.printerBrand);

  ShiftView? _shift;
  List<TillView> _tills = const [];
  List<KdsStationView> _stations = const [];
  List<DiagLogView> _diagnostics = const [];
  int _pending = 0;
  String? _error;
  PrintState _printState = PrintState.idle;

  String _t(String key) => _bridge.tr(key: key);

  SessionSnapshot? get _session => _bridge.currentSession();

  bool get _isKitchenDevice => _session?.role == 'kitchen';

  bool get _hasOpenShift => _shift?.isOpen ?? false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _deviceCode.dispose();
    _printerHost.dispose();
    _lanHub.dispose();
    super.dispose();
  }

  /// Swallow bridge failures on best-effort reads/writes (the natives'
  /// `runCatching`) — settings must render offline with whatever's cached.
  Future<T?> _quiet<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Exception {
      return null;
    }
  }

  /// Prime the screen: shift (sign-out/reconfigure guards + account card),
  /// the till or station list, pending count, and the diagnostics feed.
  Future<void> _load() async {
    final shift = await _quiet(_bridge.currentShift);
    final tills = _isKitchenDevice
        ? const <TillView>[]
        : await _quiet(_bridge.listTills) ?? const <TillView>[];
    final stations = _isKitchenDevice
        ? await _quiet(_bridge.kdsListStations) ?? const <KdsStationView>[]
        : const <KdsStationView>[];
    final pending = await _quiet(_bridge.pendingOutboxCount) ?? 0;
    final diagnostics =
        await _quiet(_bridge.recentLogs) ?? const <DiagLogView>[];
    if (!mounted) return;
    setState(() {
      _shift = shift;
      _tills = tills;
      _stations = stations;
      _pending = pending;
      _diagnostics = diagnostics;
    });
  }

  // ── device writes (custody lives in the CORE; the screen only mirrors) ────

  /// Persist this till's device code per keystroke (the core sanitizes;
  /// blank is ignored and keeps the current code).
  void _deviceCodeChanged(String value) => _bridge.setDeviceCode(code: value);

  /// Persist the printer (split "host:port" + brand wire name) and re-read
  /// the config mirror.
  Future<void> _persistPrinter() async {
    final (host, port) = _parsePrinter(_printerHost.text);
    await _quiet(
      () => _bridge.setDevicePrinter(
        host: host.isEmpty ? null : host,
        port: port,
        brand: _brand == PrinterBrand.star ? 'star' : 'epson',
      ),
    );
    if (mounted) setState(() => _config = _bridge.deviceConfig());
  }

  void _brandChanged(PrinterBrand brand) {
    setState(() => _brand = brand);
    unawaited(_persistPrinter());
  }

  /// Persist a manual LAN hub address; empty clears it. The core registers
  /// it live if the relay is already running.
  Future<void> _lanHubChanged(String value) async {
    final trimmed = value.trim();
    await _quiet(
      () => _bridge.setDeviceLanHub(hub: trimmed.isEmpty ? null : trimmed),
    );
    if (mounted) setState(() => _config = _bridge.deviceConfig());
  }

  /// Bind this device's till (drawer); null = the branch default.
  Future<void> _bindTill(String? tillId) async {
    await _quiet(() => _bridge.setDeviceTill(tillId: tillId));
    if (mounted) setState(() => _config = _bridge.deviceConfig());
  }

  /// Bind this device's kitchen station (KDS devices). The station rides
  /// the route (`kitchenDisplay(stationId)`), so let the shell re-read it.
  Future<void> _bindStation(String stationId) async {
    await _quiet(() => _bridge.setDeviceStation(stationId: stationId));
    if (!mounted) return;
    setState(() => _config = _bridge.deviceConfig());
    widget.onStateChanged();
  }

  /// Render a tiny TEST receipt in the core and stream it to the
  /// configured printer — proves host/port/brand end-to-end.
  Future<void> _testPrint() async {
    final config = _bridge.deviceConfig();
    final host = config.printerHost?.trim() ?? '';
    if (host.isEmpty) {
      setState(() => _printState = PrintState.noPrinter);
      return;
    }
    setState(() => _printState = PrintState.printing);
    try {
      final bytes = await _bridge.renderReceipt(
        receipt: _testReceipt(),
        storeName: config.branchName ?? '',
        currency: _session?.currencyCode ?? '',
        width: kReceiptChars,
        brand: _brandOf(config.printerBrand),
      );
      await _bridge.sendToPrinter(
        host: host,
        port: config.printerPort ?? _jetDirectPort,
        bytes: bytes,
      );
      if (mounted) setState(() => _printState = PrintState.printed);
    } on Exception {
      if (mounted) setState(() => _printState = PrintState.failed);
    }
  }

  /// A zero-total single-line receipt for the test page (printed content,
  /// not UI chrome — the natives print receipts only, so no i18n key
  /// exists for it).
  ReceiptView _testReceipt() {
    return ReceiptView(
      localOrderId: 'test-print',
      isVoided: false,
      lines: const [
        ReceiptLineView(
          name: 'TEST',
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
      deliveryFeeMinor: 0,
      totalMinor: 0,
      tipMinor: 0,
      amountTenderedMinor: 0,
      changeMinor: 0,
      isCash: false,
      tellerName: _session?.displayName,
      isDelivery: false,
      queuedOffline: false,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  // ── route-moving actions ───────────────────────────────────────────────────

  /// Re-provisioning is only allowed with a closed drawer (the natives'
  /// guard). On success the shell's route flips to DeviceSetup.
  Future<void> _reconfigure() async {
    if (_hasOpenShift) {
      setState(() => _error = _t('settings.reconfigure_shift_open'));
      return;
    }
    await _quiet(_bridge.startReconfigure);
    if (!mounted) return;
    await Navigator.of(context).maybePop();
    widget.onStateChanged();
  }

  /// Sign-out (→ login) requires a closed drawer first. Tears down the
  /// realtime subscription + LAN relay, then the session (outbox kept).
  Future<void> _signOut() async {
    if (_hasOpenShift) {
      setState(() => _error = _t('settings.sign_out_shift_open'));
      return;
    }
    _bridge.unsubscribeRealtime();
    await _quiet(_bridge.lanStop);
    await _quiet(() => _bridge.logout(wipeOutbox: false));
    if (!mounted) return;
    await Navigator.of(context).maybePop();
    widget.onStateChanged();
  }

  Future<void> _clearDiagnostics() async {
    await _quiet(_bridge.clearLogs);
    if (mounted) setState(() => _diagnostics = const []);
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    // The screen is pushed as its own route, so it re-derives direction
    // from the core — the live en↔ar switch below re-flips it in place.
    return Directionality(
      textDirection: _bridge.isRtl() ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: colors.bg,
        body: Column(
          children: [
            _Header(
              title: _t('settings.title'),
              onBack: () => unawaited(Navigator.of(context).maybePop()),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsetsDirectional.all(Space.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: _contentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      spacing: Space.lg,
                      children: [
                        if (_error != null)
                          NoticeBanner(
                            text: _error!,
                            icon: 'exclamationmark.circle',
                          ),
                        _accountCard(context),
                        _appearanceCard(context),
                        _languageCard(),
                        _printerCard(context),
                        if (!_isKitchenDevice && _tills.isNotEmpty) _tillCard(),
                        if (_isKitchenDevice && _stations.isNotEmpty)
                          _stationCard(),
                        _lanCard(context),
                        _deviceCard(context),
                        _diagnosticsCard(context),
                        _Cta(
                          label: _t('settings.sign_out'),
                          icon: 'rectangle.portrait.and.arrow.right',
                          danger: true,
                          onTap: () => unawaited(_signOut()),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Account: avatar initial tile, teller + branch, role chip.
  Widget _accountCard(BuildContext context) {
    final colors = context.madarColors;
    final teller = _shift?.tellerName;
    final initial = (teller != null && teller.isNotEmpty)
        ? teller[0].toUpperCase()
        : '?';
    final branchName = _config.branchName ?? '';
    final role = _session?.role ?? '';
    return _SettingsCard(
      title: _t('settings.account'),
      children: [
        Row(
          spacing: Space.md,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: colors.navyBg,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: SizedBox.square(
                dimension: _avatarSize,
                child: Center(
                  child: Text(
                    initial,
                    style: MadarType.title.copyWith(
                      fontSize: _avatarInitialSize,
                      fontWeight: FontWeight.w700,
                      color: colors.navy,
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    teller ?? '—',
                    style: MadarType.title.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                  if (branchName.isNotEmpty)
                    Row(
                      spacing: Space.xs,
                      children: [
                        MadarIcon(
                          'storefront',
                          tint: colors.textMuted,
                          size: IconSize.sm,
                        ),
                        Flexible(
                          child: Text(
                            branchName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MadarType.label.copyWith(
                              fontWeight: FontWeight.w400,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (role.isNotEmpty)
              StatusChip(
                label: role.replaceAll('_', ' ').toUpperCase(),
                tone: ChipTone.info,
              ),
          ],
        ),
      ],
    );
  }

  /// Appearance: light/dark (the HOST vault stores exactly these two).
  Widget _appearanceCard(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _SettingsCard(
      title: _t('settings.appearance'),
      children: [
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: _Chip(
                label: _t('settings.theme_light'),
                active: !dark,
                onTap: () => widget.onThemeChanged(false),
              ),
            ),
            Expanded(
              child: _Chip(
                label: _t('settings.theme_dark'),
                active: dark,
                onTap: () => widget.onThemeChanged(true),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Language: live en/ar switch — strings + RTL re-resolve in place.
  /// Labels are each language's own name, never translated (natives).
  Widget _languageCard() {
    final locale = _bridge.locale();
    return _SettingsCard(
      title: _t('settings.language'),
      children: [
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: _Chip(
                label: 'English',
                active: locale.startsWith('en'),
                onTap: () {
                  widget.onLocaleChanged('en');
                  setState(() {});
                },
              ),
            ),
            Expanded(
              child: _Chip(
                label: 'العربية',
                active: locale.startsWith('ar'),
                onTap: () {
                  widget.onLocaleChanged('ar');
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Printer: this till's device code (the `<DEVICE>` segment of every
  /// order_ref) lives alongside the printer host + brand (matches the
  /// natives), plus the test print.
  Widget _printerCard(BuildContext context) {
    final colors = context.madarColors;
    final status = switch (_printState) {
      PrintState.idle => null,
      PrintState.printing => (_t('receipt.printing'), colors.textMuted),
      PrintState.printed => (_t('receipt.printed'), colors.success),
      PrintState.failed => (_t('receipt.print_failed'), colors.danger),
      PrintState.noPrinter => (_t('receipt.no_printer'), colors.warning),
    };
    return _SettingsCard(
      title: _t('settings.printer'),
      children: [
        _SettingsTextField(
          controller: _deviceCode,
          placeholder: _t('settings.device_code_hint'),
          icon: 'number',
          onChanged: _deviceCodeChanged,
        ),
        Text(
          _t('settings.device_code_caption'),
          style: MadarType.labelSm.copyWith(
            fontWeight: FontWeight.w400,
            color: colors.textMuted,
          ),
        ),
        _SettingsTextField(
          controller: _printerHost,
          placeholder: _t('settings.printer_hint'),
          icon: 'printer',
          onChanged: (_) => unawaited(_persistPrinter()),
        ),
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: _Chip(
                label: _t('settings.printer_epson'),
                active: _brand == PrinterBrand.epson,
                onTap: () => _brandChanged(PrinterBrand.epson),
              ),
            ),
            Expanded(
              child: _Chip(
                label: _t('settings.printer_star'),
                active: _brand == PrinterBrand.star,
                onTap: () => _brandChanged(PrinterBrand.star),
              ),
            ),
          ],
        ),
        _Cta(
          label: _t('receipt.print'),
          icon: 'printer',
          loading: _printState == PrintState.printing,
          onTap: () => unawaited(_testPrint()),
        ),
        if (status != null)
          Text(
            status.$1,
            style: MadarType.labelSm.copyWith(color: status.$2),
          ),
      ],
    );
  }

  /// Till (drawer) binding — which POS drawer this device controls.
  /// Multi-till branches pin a device to one; others use the branch
  /// default. Hidden on kitchen devices (they bind a station).
  Widget _tillCard() {
    return _SettingsCard(
      title: _t('settings.till'),
      children: [
        _PickerRow(
          label: _t('settings.till_default'),
          selected: _config.tillId == null,
          onTap: () => unawaited(_bindTill(null)),
        ),
        for (final till in _tills)
          _PickerRow(
            label: till.name,
            selected: _config.tillId == till.id,
            onTap: () => unawaited(_bindTill(till.id)),
          ),
      ],
    );
  }

  /// Station binding for kitchen devices — which station this display
  /// shows (and routes chits for).
  Widget _stationCard() {
    return _SettingsCard(
      title: _t('setup.choose_station'),
      children: [
        for (final station in _stations)
          _PickerRow(
            label: station.name,
            selected: _config.stationId == station.id,
            onTap: () => unawaited(_bindStation(station.id)),
          ),
      ],
    );
  }

  /// Optional fixed hub-IP for the LAN relay when mDNS auto-discovery
  /// can't reach peers, plus the live relay diagnostics row.
  Widget _lanCard(BuildContext context) {
    final colors = context.madarColors;
    final active = _bridge.lanActive();
    return _SettingsCard(
      title: _t('settings.lan'),
      children: [
        _SettingsTextField(
          controller: _lanHub,
          placeholder: _t('settings.lan_hub_hint'),
          icon: 'wifi',
          onChanged: (v) => unawaited(_lanHubChanged(v)),
        ),
        Text(
          _t('settings.lan_caption'),
          style: MadarType.labelSm.copyWith(
            fontWeight: FontWeight.w400,
            color: colors.textMuted,
          ),
        ),
        _InfoRow(
          label: active
              ? _t('settings.lan_active')
              : _t('settings.lan_offline'),
          value: active
              ? '${_bridge.lanPeerCount()} ${_t('settings.lan_peers')}'
              : '—',
        ),
      ],
    );
  }

  /// Device: the begin-reconfigure entry (guarded by an open drawer).
  Widget _deviceCard(BuildContext context) {
    final colors = context.madarColors;
    return _SettingsCard(
      title: _t('settings.device'),
      children: [
        Semantics(
          button: true,
          child: TactileScale(
            onTap: () => unawaited(_reconfigure()),
            child: Row(
              spacing: Space.lg,
              children: [
                MadarIcon(
                  'building.2',
                  tint: colors.textSecondary,
                  size: IconSize.xl,
                ),
                Expanded(
                  child: Text(
                    _t('settings.reconfigure'),
                    style: MadarType.title.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                MadarIcon('chevron.forward', tint: colors.textMuted),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Diagnostics: core version, server, pending count, realtime channel
  /// health, and the recent-warnings feed (with clear).
  Widget _diagnosticsCard(BuildContext context) {
    final colors = context.madarColors;
    return _SettingsCard(
      title: _t('settings.diagnostics'),
      children: [
        _InfoRow(label: _t('settings.version'), value: coreVersion()),
        _InfoRow(label: _t('settings.server'), value: _bridge.baseUrl()),
        _InfoRow(label: _t('settings.pending'), value: '$_pending'),
        // Realtime (SSE) channel health — the teller's order alerts ride
        // this; surfacing it makes a silent drop diagnosable.
        _InfoRow(
          label: _t('settings.realtime'),
          value: _bridge.isRealtimeSubscribed()
              ? _t('settings.realtime_on')
              : _t('settings.realtime_off'),
        ),
        if (_diagnostics.isNotEmpty) ...[
          SizedBox(
            height: 1,
            child: ColoredBox(color: colors.borderLight),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  _t('settings.recent_warnings'),
                  style: MadarType.label.copyWith(color: colors.textMuted),
                ),
              ),
              TactileScale(
                onTap: () => unawaited(_clearDiagnostics()),
                child: Text(
                  _t('settings.clear'),
                  style: MadarType.label.copyWith(color: colors.accent),
                ),
              ),
            ],
          ),
          for (final entry in _diagnostics.take(15))
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 1,
              children: [
                Text(
                  entry.message,
                  style: MadarType.label.copyWith(
                    fontWeight: FontWeight.w400,
                    color: entry.level == 'error'
                        ? colors.danger
                        : colors.warning,
                  ),
                ),
                Text(
                  entry.at,
                  style: MadarType.labelSm.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

/// Surface top bar: back chevron + bold title, over a hairline.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: colors.surface,
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.lg,
              vertical: Space.md,
            ),
            child: Row(
              spacing: Space.md,
              children: [
                Semantics(
                  button: true,
                  child: TactileScale(
                    onTap: onBack,
                    child: MadarIcon(
                      'chevron.backward',
                      tint: colors.textPrimary,
                      size: _headerIconSize,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    title,
                    style: MadarType.h3.copyWith(
                      fontSize: _headerTitleSize,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 1, child: ColoredBox(color: colors.border)),
      ],
    );
  }
}

/// The natives' `SettingsCard`: uppercase muted label above a bordered,
/// softly-elevated surface card.
class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Text(
          title.toUpperCase(),
          style: MadarType.label.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: MadarType.tracking,
            color: colors.textMuted,
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: colors.borderLight),
            boxShadow: MadarElevation.card.shadows(colors, dark: dark),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.all(Space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.md,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

/// Segmented choice chip: accent-filled when active, quiet bordered
/// surface otherwise (the natives' `Chip`).
class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Semantics(
      button: true,
      selected: active,
      child: TactileScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(vertical: Space.md),
          decoration: BoxDecoration(
            color: active ? colors.accent : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: active ? null : Border.all(color: colors.border),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: MadarType.bodySm.copyWith(
              fontSize: _chipLabelSize,
              fontWeight: FontWeight.w600,
              color: active ? colors.textOnAccent : colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Radio-style picker row (the natives' `TillRow`): leading check circle,
/// accent when selected.
class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Semantics(
      button: true,
      selected: selected,
      child: TactileScale(
        onTap: onTap,
        child: Row(
          spacing: Space.sm,
          children: [
            MadarIcon(
              selected ? 'checkmark.circle' : 'circle',
              tint: selected ? colors.accent : colors.textMuted,
              size: IconSize.lg,
            ),
            Expanded(
              child: Text(
                label,
                style: MadarType.body.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quiet label/value row.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Row(
      spacing: Space.md,
      children: [
        Text(
          label,
          style: MadarType.bodySm.copyWith(color: colors.textSecondary),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MadarType.bodySm.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// The natives' `MadarButton` at the two variants this screen needs:
/// outline (test print) and danger (sign out), with a centered spinner
/// while [loading].
class _Cta extends StatelessWidget {
  const _Cta({
    required this.label,
    required this.onTap,
    this.icon,
    this.danger = false,
    this.loading = false,
  });

  final String label;
  final VoidCallback onTap;
  final String? icon;
  final bool danger;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = danger ? colors.textOnAccent : colors.accent;
    final button = Container(
      height: Metrics.buttonHeight,
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.lg),
      decoration: BoxDecoration(
        color: danger ? colors.danger : null,
        borderRadius: BorderRadius.circular(Radii.md),
        border: danger
            ? null
            : Border.all(color: colors.accent, width: _outlineBorder),
      ),
      alignment: Alignment.center,
      child: loading
          ? SizedBox.square(
              dimension: _spinnerSize,
              child: CircularProgressIndicator(
                color: fg,
                strokeWidth: _spinnerStroke,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  MadarIcon(icon, tint: fg),
                  const SizedBox(width: Space.sm),
                ],
                Text(
                  label,
                  style: MadarType.title.copyWith(
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
    );
    if (loading) return button;
    return Semantics(
      button: true,
      child: TactileScale(
        onTap: () {
          MadarHaptics.impact();
          onTap();
        },
        child: button,
      ),
    );
  }
}

/// The natives' `MadarTextField`: rounded field with an animated focus
/// ring (accent border + glow, surfaceAlt → surface fill), a leading icon
/// that tints accent while focused, and per-keystroke [onChanged].
class _SettingsTextField extends StatefulWidget {
  const _SettingsTextField({
    required this.controller,
    required this.placeholder,
    required this.onChanged,
    this.icon,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final String? icon;

  @override
  State<_SettingsTextField> createState() => _SettingsTextFieldState();
}

class _SettingsTextFieldState extends State<_SettingsTextField> {
  final FocusNode _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (mounted) setState(() => _focused = _focus.hasFocus);
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return AnimatedContainer(
      duration: MotionSpec.standardDuration,
      curve: MotionSpec.standardCurve,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.lg,
        vertical: _fieldVPad,
      ),
      decoration: BoxDecoration(
        color: _focused ? colors.surface : colors.surfaceAlt,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: _focused ? colors.accent : colors.border,
          width: _focused ? 2 : 1,
        ),
        boxShadow: _focused
            ? [
                BoxShadow(
                  color: colors.accent.withValues(alpha: 0.35),
                  blurRadius: 8,
                ),
              ]
            : null,
      ),
      child: Row(
        spacing: _fieldGap,
        children: [
          if (widget.icon != null)
            MadarIcon(
              widget.icon,
              tint: _focused ? colors.accent : colors.textMuted,
              size: IconSize.lg,
            ),
          Expanded(
            child: Material(
              type: MaterialType.transparency,
              child: TextField(
                controller: widget.controller,
                focusNode: _focus,
                onChanged: widget.onChanged,
                cursorColor: colors.accent,
                style: MadarType.title.copyWith(
                  fontWeight: FontWeight.w400,
                  color: colors.textPrimary,
                ),
                decoration: InputDecoration.collapsed(
                  hintText: widget.placeholder,
                  hintStyle: MadarType.title.copyWith(
                    fontWeight: FontWeight.w400,
                    color: colors.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
