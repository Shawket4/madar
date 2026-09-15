/// The Settings sub-sheets: Printer, Station, Device, Diagnostics,
/// Legal. A Settings row shows the one-line summary; the sheet holds the
/// controls. Each is presented with `showMadarSheet` and built from the
/// kit — no control in here is this package's own.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart' show PrintState;
import 'package:feature_settings/src/labels.dart';
import 'package:feature_settings/src/settings_provider.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, TextInputAction;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Diagonal-inch cutoff range between the phone (portrait-locked) and
/// tablet (landscape-locked) orientation behaviour. Half-inch steps; some
/// ~7" tablets under-report their density and land just under the default.
const double _thresholdStep = 0.5;
const double _thresholdMin = 5;
const double _thresholdMax = 10;

/// Recent warnings shown before the feed is cut.
const int _warningsShown = 15;

/// Public legal documents — a static site independent of the API, so the
/// address stays valid offline. Shown in full and copied on tap: a till
/// rarely has a browser.
const String _legalBase = 'https://legal.madar-pos.cloud';

Future<void> showPrinterSheet(BuildContext context) => showMadarSheet<void>(
  context,
  size: SheetSize.large,
  builder: (_) => const _PrinterSheet(),
);

Future<void> showStationSheet(BuildContext context) => showMadarSheet<void>(
  context,
  size: SheetSize.hug,
  builder: (_) => const _StationSheet(),
);

Future<void> showDeviceSheet(BuildContext context) => showMadarSheet<void>(
  context,
  size: SheetSize.large,
  builder: (_) => const _DeviceSheet(),
);

Future<void> showDiagnosticsSheet(BuildContext context) => showMadarSheet<void>(
  context,
  size: SheetSize.large,
  builder: (_) => const _DiagnosticsSheet(),
);

Future<void> showLegalSheet(BuildContext context) => showMadarSheet<void>(
  context,
  size: SheetSize.hug,
  builder: (_) => const _LegalSheet(),
);

/// The frame every sheet shares: an h2 title with a close tile, then the
/// content in its own scroll so a long feed never overflows the sheet.
class _SheetFrame extends ConsumerWidget {
  const _SheetFrame({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A write the core refused is said where it was made.
    final writeError = ref.watch(settingsProvider.select((s) => s.writeError));
    final layout = context.madarLayout;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        layout.gutter,
        Space.lg,
        layout.gutter,
        0,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MadarHeader(
            title: title,
            actions: [
              MadarHeaderAction(
                glyph: MadarGlyph.close,
                tooltip: ref.bridge.tr(key: 'common.close'),
                onTap: () => MadarSheet.close<void>(context),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          if (writeError != null) ...[
            NoticeBanner(
              text: writeError.of(ref.bridge),
              tone: ChipTone.danger,
              icon: 'exclamationmark.triangle',
              onTap: ref.read(settingsProvider.notifier).clearWriteError,
            ),
            const SizedBox(height: Space.md),
          ],
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsetsDirectional.only(
                bottom: MediaQuery.viewPaddingOf(context).bottom + Space.xl,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.lg,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A labelled segment: the section word above a [MadarSegmented].
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<MadarSegmentItem<T>> items;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        MadarSectionHeader(text: label),
        MadarSegmented<T>(items: items, value: value, onChanged: onChanged),
      ],
    );
  }
}

/// A caption under a field.
class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: MadarType.bodySm.copyWith(
        color: context.madarColors.textSecondary,
      ),
    );
  }
}

// ── Printer ──────────────────────────────────────────────────────────────

/// Transport (LAN / Bluetooth), the host or the paired device, paper width,
/// brand, and a test print that proves the whole path.
class _PrinterSheet extends ConsumerStatefulWidget {
  const _PrinterSheet();

  @override
  ConsumerState<_PrinterSheet> createState() => _PrinterSheetState();
}

class _PrinterSheetState extends ConsumerState<_PrinterSheet> {
  late final TextEditingController _host;

  @override
  void initState() {
    super.initState();
    _host = TextEditingController(
      text: printerAddressOf(ref.read(bridgeProvider).deviceConfig()),
    );
  }

  @override
  void dispose() {
    _host.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final notifier = ref.read(settingsProvider.notifier);
    final config = ref.watch(settingsProvider.select((s) => s.config));
    final brand = ref.watch(settingsProvider.select((s) => s.brand));
    final printState = ref.watch(settingsProvider.select((s) => s.printState));
    final bluetooth = (config.printerTransport ?? 'lan') == 'bluetooth';
    final status = switch (printState) {
      PrintState.idle => null,
      PrintState.printing => (t('receipt.printing'), colors.textSecondary),
      PrintState.printed => (t('receipt.printed'), colors.success),
      PrintState.failed => (t('receipt.print_failed'), colors.danger),
      PrintState.noPrinter => (t('receipt.no_printer'), colors.warning),
    };
    return _SheetFrame(
      title: t('settings.printer'),
      children: [
        _Choice<String>(
          label: t('settings.printer_transport'),
          items: [
            MadarSegmentItem(
              'lan',
              t('settings.printer_lan'),
              glyph: MadarGlyph.wifi,
            ),
            MadarSegmentItem('bluetooth', t('settings.printer_bluetooth')),
          ],
          value: bluetooth ? 'bluetooth' : 'lan',
          onChanged: (kind) => unawaited(notifier.setTransport(kind)),
        ),
        if (bluetooth)
          _BluetoothPicker(config: config)
        else
          MadarField(
            controller: _host,
            placeholder: t('settings.printer_hint'),
            glyph: MadarGlyph.printer,
            keyboardType: TextInputType.url,
            onChanged: (value) => unawaited(notifier.persistPrinter(value)),
          ),
        _Choice<int>(
          label: t('settings.printer_paper'),
          items: [
            MadarSegmentItem(paperDots58, t('settings.printer_paper_58')),
            MadarSegmentItem(paperDots80, t('settings.printer_paper_80')),
          ],
          value: effectivePaperDots(config),
          onChanged: (dots) => unawaited(notifier.setPaperDots(dots)),
        ),
        _Choice<PrinterBrand>(
          label: t('settings.printer_brand'),
          items: [
            MadarSegmentItem(PrinterBrand.epson, t('settings.printer_epson')),
            MadarSegmentItem(PrinterBrand.star, t('settings.printer_star')),
          ],
          value: brand,
          onChanged: (b) =>
              unawaited(notifier.persistPrinter(_host.text, brand: b)),
        ),
        MadarButton(
          label: t('settings.printer_test'),
          glyph: MadarGlyph.printer,
          variant: MadarButtonVariant.secondary,
          loading: printState == PrintState.printing,
          onTap: () => unawaited(notifier.testPrint()),
        ),
        if (status != null)
          Text(status.$1, style: MadarType.bodySm.copyWith(color: status.$2)),
      ],
    );
  }
}

/// Paired-device picker for the Bluetooth transport. Pairing happens in the
/// OS settings (SPP, PIN 0000/1234); this lists ALREADY-paired devices and
/// binds the chosen one. The empty state points back to the OS to pair.
class _BluetoothPicker extends ConsumerWidget {
  const _BluetoothPicker({required this.config});

  final DeviceConfigView config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final notifier = ref.read(settingsProvider.notifier);
    final devices = ref.watch(settingsProvider.select((s) => s.pairedDevices));
    final scanning = ref.watch(settingsProvider.select((s) => s.scanningBt));
    final selected = config.printerBtAddress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        MadarButton(
          label: bridge.tr(key: 'settings.printer_bt_scan'),
          glyph: MadarGlyph.refresh,
          variant: MadarButtonVariant.secondary,
          size: MadarButtonSize.compact,
          loading: scanning,
          onTap: () => unawaited(notifier.loadPairedDevices()),
        ),
        if (devices.isEmpty && !scanning && selected == null)
          _Caption(bridge.tr(key: 'settings.printer_bt_none')),
        if (devices.isNotEmpty)
          MadarCard(
            flush: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, device) in devices.indexed) ...[
                  if (index > 0) const MadarHairline.row(),
                  MadarListRow.pick(
                    title: device.name,
                    selected: device.address == selected,
                    onTap: () => unawaited(notifier.selectBtDevice(device)),
                  ),
                ],
              ],
            ),
          ),
        // A bound device missing from the (unscanned / stale) list — still
        // name what is bound, so the binding is visible without a scan.
        if (selected != null && !devices.any((d) => d.address == selected))
          MadarSummaryLine(
            label: bridge.tr(key: 'settings.printer_bluetooth'),
            value: config.printerBtName ?? selected,
          ),
      ],
    );
  }
}

// ── Station ──────────────────────────────────────────────────────────────

/// Which kitchen station this display shows (kitchen devices only). The
/// station rides the route, so binding refreshes the shell.
class _StationSheet extends ConsumerWidget {
  const _StationSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final notifier = ref.read(settingsProvider.notifier);
    final stations = ref.watch(settingsProvider.select((s) => s.stations));
    final stationId = ref.watch(
      settingsProvider.select((s) => s.config.stationId),
    );
    return _SheetFrame(
      title: bridge.tr(key: 'setup.choose_station'),
      children: [
        MadarCard(
          flush: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, station) in stations.indexed) ...[
                if (index > 0) const MadarHairline.row(),
                MadarListRow.pick(
                  title: station.name,
                  selected: stationId == station.id,
                  onTap: () => unawaited(notifier.bindStation(station.id)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Device ───────────────────────────────────────────────────────────────

/// The till's identity: the device code (the `<DEVICE>` segment of every
/// order ref), the branch it is bound to, the LAN hub, and re-provisioning
/// (guarded by an open drawer).
class _DeviceSheet extends ConsumerStatefulWidget {
  const _DeviceSheet();

  @override
  ConsumerState<_DeviceSheet> createState() => _DeviceSheetState();
}

class _DeviceSheetState extends ConsumerState<_DeviceSheet> {
  late final TextEditingController _code;
  late final TextEditingController _hub;

  /// Re-reads the (local, sync) LAN status while the sheet is open, so peers
  /// found and a retry that succeeded show up without reopening it.
  Timer? _lanTick;

  @override
  void initState() {
    super.initState();
    _lanTick = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
    final bridge = ref.read(bridgeProvider);
    _code = TextEditingController(text: bridge.deviceCode());
    _hub = TextEditingController(text: bridge.deviceConfig().lanHub ?? '');
  }

  @override
  void dispose() {
    _lanTick?.cancel();
    _code.dispose();
    _hub.dispose();
    super.dispose();
  }

  /// Pop the sheet AND the settings screen, then refresh the shell — the
  /// route flips to DeviceSetup on the shell subtree, not under an overlay.
  Future<void> _reconfigure() async {
    final shell = ref.read(shellProvider.notifier);
    final ok = await ref.read(settingsProvider.notifier).reconfigure();
    if (!ok || !mounted) return;
    final navigator = Navigator.of(context);
    await navigator.maybePop();
    await navigator.maybePop();
    shell.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final notifier = ref.read(settingsProvider.notifier);
    final config = ref.watch(settingsProvider.select((s) => s.config));
    final hasOpenTill = ref.watch(
      settingsProvider.select((s) => s.hasOpenTill),
    );
    final error = ref.watch(settingsProvider.select((s) => s.error));
    final lan = bridge.lanStatus();
    final lanActive = lan.running;
    final lanError = lan.lastError;
    final discovery = [
      if (lan.nativeDiscoveryActive) t('settings.lan_disc_bonjour'),
      if (lan.mdnsActive) t('settings.lan_disc_mdns'),
      if (lan.beaconActive) t('settings.lan_disc_beacon'),
      if (lan.manualHubCount > 0) t('settings.lan_disc_manual'),
    ];
    return _SheetFrame(
      title: t('settings.device'),
      children: [
        if (error != null)
          NoticeBanner(
            text: error.of(ref.bridge),
            icon: 'exclamationmark.circle',
          ),
        MadarSectionHeader(text: t('settings.device_code')),
        MadarField(
          controller: _code,
          placeholder: t('settings.device_code_hint'),
          glyph: MadarGlyph.tag,
          textInputAction: TextInputAction.done,
          onChanged: notifier.setDeviceCode,
        ),
        _Caption(t('settings.device_code_caption')),
        MadarSummaryLine(
          label: t('login.branch'),
          value: config.branchName ?? '—',
        ),
        MadarSectionHeader(text: t('settings.lan')),
        MadarField(
          controller: _hub,
          placeholder: t('settings.lan_hub_hint'),
          glyph: MadarGlyph.wifi,
          keyboardType: TextInputType.url,
          onChanged: (value) => unawaited(notifier.setLanHub(value)),
        ),
        _Caption(t('settings.lan_caption')),
        MadarSummaryLine(
          label: t(lanActive ? 'settings.lan_active' : 'settings.lan_offline'),
          value: lanActive
              ? '${bridge.lanPeerCount()} ${t('settings.lan_peers')}'
              : '—',
          tone: lanActive ? MadarTone.success : null,
        ),
        if (lanActive) ...[
          MadarSummaryLine(
            label: t('settings.lan_port'),
            value: '${lan.tcpPort ?? '—'}',
          ),
          MadarSummaryLine(
            label: t('settings.lan_discovery'),
            value: discovery.isEmpty
                ? t('settings.lan_discovery_none')
                : discovery.join(' · '),
            muted: discovery.isEmpty,
          ),
        ],
        if (!lanActive && lanError != null) ...[
          MadarSummaryLine(
            label: t('settings.lan_last_error'),
            value: lanError,
            tone: MadarTone.warning,
          ),
          _Caption(t('settings.lan_retrying')),
        ],
        MadarButton(
          label: t('settings.reconfigure'),
          glyph: MadarGlyph.settings,
          variant: MadarButtonVariant.secondary,
          enabled: !hasOpenTill,
          tooltip: hasOpenTill ? t('settings.reconfigure_shift_open') : null,
          onTap: () => unawaited(_reconfigure()),
        ),
        if (hasOpenTill) _Caption(t('settings.reconfigure_shift_open')),
      ],
    );
  }
}

// ── Diagnostics ──────────────────────────────────────────────────────────

/// Versions, server, clock, channels, the floor gate, the orientation
/// knobs (moved here from Appearance — nobody flips a screen daily), and
/// the recent-warnings feed.
class _DiagnosticsSheet extends ConsumerWidget {
  const _DiagnosticsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final pending = ref.watch(settingsProvider.select((s) => s.pending));
    final floorAuthored = ref.watch(
      settingsProvider.select((s) => s.floorAuthored),
    );
    final diagnostics = ref.watch(
      settingsProvider.select((s) => s.diagnostics),
    );
    final live =
        ref.watch(realtimeConnectedProvider) && bridge.isRealtimeSubscribed();
    final skew = bridge.clockSkewMinutes();
    final lanActive = bridge.lanActive();
    // Null until this device has reached the server once — then the row is
    // simply absent rather than claiming a mode.
    final routing = ref.watch(kitchenRoutingModeProvider);
    return _SheetFrame(
      title: t('settings.diagnostics'),
      children: [
        if (!floorAuthored)
          NoticeBanner(text: t('settings.no_floor_hint'), icon: 'tablecells'),
        MadarCard.column(
          spacing: 0,
          children: [
            MadarSummaryLine(
              label: t('settings.version'),
              value: bridge.version(),
            ),
            MadarSummaryLine(
              label: t('settings.server'),
              value: bridge.baseUrl(),
            ),
            MadarSummaryLine(
              label: t('settings.environment'),
              value: bridge.environment(),
            ),
            MadarSummaryLine(
              label: t('settings.clock'),
              value: skew == 0
                  ? t('settings.clock_ok')
                  : '${skew.abs()} ${t('settings.minutes_off')}',
              tone: skew.abs() >= 5 ? MadarTone.warning : null,
            ),
            MadarSummaryLine(
              label: t('settings.realtime'),
              value: t(live ? 'settings.realtime_on' : 'settings.realtime_off'),
              tone: live ? MadarTone.success : null,
            ),
            MadarSummaryLine(
              label: t('settings.lan'),
              value: lanActive
                  ? '${bridge.lanPeerCount()} ${t('settings.lan_peers')}'
                  : t('settings.lan_offline'),
              tone: lanActive ? MadarTone.success : null,
            ),
            // Why there is (or is not) a Kitchen segment on the Queue — the
            // exact question this sheet exists to answer. Read-only: the mode
            // belongs to the branch, and the dashboard owns it.
            if (routing != null)
              MadarSummaryLine(
                label: t('settings.kitchen_routing'),
                value: t('settings.routing_$routing'),
                muted: routing == 'off',
              ),
            MadarSummaryLine(label: t('settings.pending'), value: '$pending'),
          ],
        ),
        // Tablets lock to ONE landscape; this flips between the two. Phones
        // are portrait-locked, so the flip is hidden there.
        MadarCard.column(
          children: [
            if (OrientationController.instance.canFlip)
              const _OrientationFlip(),
            const _TabletThreshold(),
          ],
        ),
        if (diagnostics.isNotEmpty) ...[
          MadarSectionHeader(
            text: t('settings.recent_warnings'),
            trailing: MadarButton(
              label: t('settings.clear'),
              variant: MadarButtonVariant.ghost,
              size: MadarButtonSize.compact,
              onTap: () => unawaited(
                ref.read(settingsProvider.notifier).clearDiagnostics(),
              ),
            ),
          ),
          MadarCard.column(
            children: [
              for (final entry in diagnostics.take(_warningsShown))
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 2,
                  children: [
                    Text(
                      entry.message,
                      style: MadarType.bodySm.copyWith(
                        color: entry.level == 'error'
                            ? colors.danger
                            : colors.warning,
                      ),
                    ),
                    Text(
                      entry.at,
                      textDirection: TextDirection.ltr,
                      style: MadarType.num.copyWith(color: colors.textMuted),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Flips the locked landscape orientation on tablets.
class _OrientationFlip extends ConsumerWidget {
  const _OrientationFlip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    return ListenableBuilder(
      listenable: OrientationController.instance,
      builder: (context, _) {
        return Row(
          children: [
            Expanded(
              child: Text(
                bridge.tr(key: 'settings.orientation'),
                style: MadarType.body.copyWith(color: colors.textSecondary),
              ),
            ),
            MadarButton(
              label: bridge.tr(key: 'settings.flip_screen'),
              glyph: MadarGlyph.refresh,
              variant: MadarButtonVariant.secondary,
              size: MadarButtonSize.compact,
              onTap: OrientationController.instance.flip,
            ),
          ],
        );
      },
    );
  }
}

/// Diagonal-inch cutoff between phone and tablet orientation behaviour.
/// Two keys around the inch figure; half-inch steps.
class _TabletThreshold extends ConsumerWidget {
  const _TabletThreshold();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    return ListenableBuilder(
      listenable: OrientationController.instance,
      builder: (context, _) {
        final controller = OrientationController.instance;
        final inches = controller.tabletThresholdInches;
        void step(double delta) => controller.setTabletThresholdInches(
          (inches + delta).clamp(_thresholdMin, _thresholdMax),
        );
        return Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: Text(
                bridge.tr(key: 'settings.tablet_threshold'),
                style: MadarType.body.copyWith(color: colors.textSecondary),
              ),
            ),
            MadarButton(
              label: '',
              glyph: MadarGlyph.minus,
              variant: MadarButtonVariant.secondary,
              size: MadarButtonSize.compact,
              enabled: inches > _thresholdMin,
              onTap: () => step(-_thresholdStep),
            ),
            SizedBox(
              width: Metrics.glyphTileLarge,
              child: Text(
                '${inches.toStringAsFixed(1)}"',
                textAlign: TextAlign.center,
                textDirection: TextDirection.ltr,
                style: MadarType.numMd.copyWith(color: colors.textPrimary),
              ),
            ),
            MadarButton(
              label: '',
              glyph: MadarGlyph.plus,
              variant: MadarButtonVariant.secondary,
              size: MadarButtonSize.compact,
              enabled: inches < _thresholdMax,
              onTap: () => step(_thresholdStep),
            ),
          ],
        );
      },
    );
  }
}

// ── Legal ────────────────────────────────────────────────────────────────

/// The privacy policy and terms. Tapping a row copies its address.
class _LegalSheet extends ConsumerWidget {
  const _LegalSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    Widget row(String labelKey, String url) => MadarRow(
      title: bridge.tr(key: labelKey),
      subtitle: url.replaceFirst('https://', ''),
      glyph: MadarGlyph.note,
      chevron: false,
      onTap: () => unawaited(Clipboard.setData(ClipboardData(text: url))),
    );
    return _SheetFrame(
      title: bridge.tr(key: 'settings.legal'),
      children: [
        MadarCard(
          flush: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              row('settings.legal_privacy', '$_legalBase/privacy-policy.html'),
              const MadarHairline.row(),
              row('settings.legal_terms', '$_legalBase/terms-of-service.html'),
            ],
          ),
        ),
        _Caption(bridge.tr(key: 'settings.legal_hint')),
      ],
    );
  }
}
