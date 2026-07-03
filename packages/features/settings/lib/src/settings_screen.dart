/// Settings — a pixel-and-behavior port of the Kotlin SettingsScreen.kt:
/// account card, appearance + language (provider-owned prefs), printer
/// (host:port + brand + test print), till/station binding, LAN relay,
/// device reconfigure, diagnostics (versions, server, pending, realtime,
/// recent warnings), and sign-out. Full-screen over the order screen; the
/// header's back pops it via `Navigator.maybePop`.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/feature_checkout.dart' show PrintState;
import 'package:feature_settings/src/settings_provider.dart';
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// Native metrics (SettingsScreen.kt) that fall between the 4-pt Space
// steps — kept verbatim so the Flutter chrome measures identically.

/// Content column cap (natives: widthIn(max = 640.dp)).
const double _contentMaxWidth = 640;

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

/// The settings overlay. All state flows from [settingsProvider] (plus the
/// app-core locale/dark-mode providers); the screen owns only its text
/// controllers.
class SettingsScreen extends ConsumerStatefulWidget {
  /// Creates the settings screen.
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _deviceCode;
  late final TextEditingController _printerHost;
  late final TextEditingController _lanHub;

  @override
  void initState() {
    super.initState();
    final bridge = ref.read(bridgeProvider);
    final config = bridge.deviceConfig();
    _deviceCode = TextEditingController(text: bridge.deviceCode());
    _printerHost = TextEditingController(text: printerAddressOf(config));
    _lanHub = TextEditingController(text: config.lanHub ?? '');
    unawaited(ref.read(settingsProvider.notifier).load());
  }

  @override
  void dispose() {
    _deviceCode.dispose();
    _printerHost.dispose();
    _lanHub.dispose();
    super.dispose();
  }

  /// Sign-out (guarded in the notifier): pop first, then refresh the shell
  /// so the route flip lands on the shell subtree, not this overlay.
  Future<void> _signOut() async {
    final shell = ref.read(shellProvider.notifier);
    final ok = await ref.read(settingsProvider.notifier).signOut();
    if (!ok || !mounted) return;
    await Navigator.of(context).maybePop();
    shell.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    // Pushed as its own route, so it re-derives direction from the locale
    // provider — the live en↔ar switch below re-flips it in place.
    final locale = ref.watch(localeProvider);
    final error = ref.watch(settingsProvider.select((s) => s.error));
    final isKitchen = ref.watch(
      shellProvider.select((s) => s.session?.role == 'kitchen'),
    );
    final hasTills = ref.watch(
      settingsProvider.select((s) => s.tills.isNotEmpty),
    );
    final hasStations = ref.watch(
      settingsProvider.select((s) => s.stations.isNotEmpty),
    );
    return Directionality(
      textDirection: locale.rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: colors.bg,
        body: Column(
          children: [
            MadarHeader(
              title: bridge.tr(key: 'settings.title'),
              onBack: () => unawaited(Navigator.of(context).maybePop()),
            ),
            Expanded(
              child: SafeArea(
                top: false,
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
                          if (error != null)
                            NoticeBanner(
                              text: error,
                              icon: 'exclamationmark.circle',
                            ),
                          const _AccountCard(),
                          const _AppearanceCard(),
                          const _LanguageCard(),
                          _PrinterCard(
                            deviceCode: _deviceCode,
                            printerHost: _printerHost,
                          ),
                          if (!isKitchen && hasTills) const _TillCard(),
                          if (isKitchen && hasStations) const _StationCard(),
                          _LanCard(controller: _lanHub),
                          const _DeviceCard(),
                          const _DiagnosticsCard(),
                          _Cta(
                            label: bridge.tr(key: 'settings.sign_out'),
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
            ),
          ],
        ),
      ),
    );
  }
}

/// Account: avatar initial tile, teller + branch, role chip.
class _AccountCard extends ConsumerWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final teller = ref.watch(
      settingsProvider.select((s) => s.shift?.tellerName),
    );
    final branchName =
        ref.watch(settingsProvider.select((s) => s.config.branchName)) ?? '';
    final role = ref.watch(shellProvider.select((s) => s.session?.role)) ?? '';
    final initial = (teller != null && teller.isNotEmpty)
        ? teller[0].toUpperCase()
        : '?';
    return _SettingsCard(
      title: bridge.tr(key: 'settings.account'),
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
}

/// Appearance: light/dark — drives [darkModeProvider] (the host persists).
class _AppearanceCard extends ConsumerWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final dark = ref.watch(darkModeProvider);
    return _SettingsCard(
      title: bridge.tr(key: 'settings.appearance'),
      children: [
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: _Chip(
                label: bridge.tr(key: 'settings.theme_light'),
                active: !dark,
                onTap: () =>
                    ref.read(darkModeProvider.notifier).setDark(dark: false),
              ),
            ),
            Expanded(
              child: _Chip(
                label: bridge.tr(key: 'settings.theme_dark'),
                active: dark,
                onTap: () =>
                    ref.read(darkModeProvider.notifier).setDark(dark: true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Language: live en/ar switch — strings + RTL re-resolve in place through
/// [localeProvider]. Labels are each language's own name, never translated
/// (natives).
class _LanguageCard extends ConsumerWidget {
  const _LanguageCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final locale = ref.watch(localeProvider.select((s) => s.locale));
    return _SettingsCard(
      title: bridge.tr(key: 'settings.language'),
      children: [
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: _Chip(
                label: 'English',
                active: locale.startsWith('en'),
                onTap: () => ref.read(localeProvider.notifier).set('en'),
              ),
            ),
            Expanded(
              child: _Chip(
                label: 'العربية',
                active: locale.startsWith('ar'),
                onTap: () => ref.read(localeProvider.notifier).set('ar'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Printer: this till's device code (the `<DEVICE>` segment of every
/// order_ref) lives alongside the printer host + brand (matches the
/// natives), plus the test print.
class _PrinterCard extends ConsumerWidget {
  const _PrinterCard({required this.deviceCode, required this.printerHost});

  final TextEditingController deviceCode;
  final TextEditingController printerHost;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final brand = ref.watch(settingsProvider.select((s) => s.brand));
    final printState = ref.watch(settingsProvider.select((s) => s.printState));
    final status = switch (printState) {
      PrintState.idle => null,
      PrintState.printing => (
        bridge.tr(key: 'receipt.printing'),
        colors.textMuted,
      ),
      PrintState.printed => (
        bridge.tr(key: 'receipt.printed'),
        colors.success,
      ),
      PrintState.failed => (
        bridge.tr(key: 'receipt.print_failed'),
        colors.danger,
      ),
      PrintState.noPrinter => (
        bridge.tr(key: 'receipt.no_printer'),
        colors.warning,
      ),
    };
    return _SettingsCard(
      title: bridge.tr(key: 'settings.printer'),
      children: [
        _SettingsTextField(
          controller: deviceCode,
          placeholder: bridge.tr(key: 'settings.device_code_hint'),
          icon: 'number',
          onChanged: ref.read(settingsProvider.notifier).setDeviceCode,
        ),
        Text(
          bridge.tr(key: 'settings.device_code_caption'),
          style: MadarType.labelSm.copyWith(
            fontWeight: FontWeight.w400,
            color: colors.textMuted,
          ),
        ),
        _SettingsTextField(
          controller: printerHost,
          placeholder: bridge.tr(key: 'settings.printer_hint'),
          icon: 'printer',
          onChanged: (value) => unawaited(
            ref.read(settingsProvider.notifier).persistPrinter(value),
          ),
        ),
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: _Chip(
                label: bridge.tr(key: 'settings.printer_epson'),
                active: brand == PrinterBrand.epson,
                onTap: () => unawaited(
                  ref
                      .read(settingsProvider.notifier)
                      .persistPrinter(
                        printerHost.text,
                        brand: PrinterBrand.epson,
                      ),
                ),
              ),
            ),
            Expanded(
              child: _Chip(
                label: bridge.tr(key: 'settings.printer_star'),
                active: brand == PrinterBrand.star,
                onTap: () => unawaited(
                  ref
                      .read(settingsProvider.notifier)
                      .persistPrinter(
                        printerHost.text,
                        brand: PrinterBrand.star,
                      ),
                ),
              ),
            ),
          ],
        ),
        _Cta(
          label: bridge.tr(key: 'receipt.print'),
          icon: 'printer',
          loading: printState == PrintState.printing,
          onTap: () =>
              unawaited(ref.read(settingsProvider.notifier).testPrint()),
        ),
        if (status != null)
          Text(
            status.$1,
            style: MadarType.labelSm.copyWith(color: status.$2),
          ),
      ],
    );
  }
}

/// Till (drawer) binding — which POS drawer this device controls.
/// Multi-till branches pin a device to one; others use the branch
/// default. Hidden on kitchen devices (they bind a station).
class _TillCard extends ConsumerWidget {
  const _TillCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final tills = ref.watch(settingsProvider.select((s) => s.tills));
    final tillId = ref.watch(settingsProvider.select((s) => s.config.tillId));
    return _SettingsCard(
      title: bridge.tr(key: 'settings.till'),
      children: [
        _PickerRow(
          label: bridge.tr(key: 'settings.till_default'),
          selected: tillId == null,
          onTap: () =>
              unawaited(ref.read(settingsProvider.notifier).bindTill(null)),
        ),
        for (final till in tills)
          _PickerRow(
            label: till.name,
            selected: tillId == till.id,
            onTap: () => unawaited(
              ref.read(settingsProvider.notifier).bindTill(till.id),
            ),
          ),
      ],
    );
  }
}

/// Station binding for kitchen devices — which station this display
/// shows (and routes chits for).
class _StationCard extends ConsumerWidget {
  const _StationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final stations = ref.watch(settingsProvider.select((s) => s.stations));
    final stationId = ref.watch(
      settingsProvider.select((s) => s.config.stationId),
    );
    return _SettingsCard(
      title: bridge.tr(key: 'setup.choose_station'),
      children: [
        for (final station in stations)
          _PickerRow(
            label: station.name,
            selected: stationId == station.id,
            onTap: () => unawaited(
              ref.read(settingsProvider.notifier).bindStation(station.id),
            ),
          ),
      ],
    );
  }
}

/// Optional fixed hub-IP for the LAN relay when mDNS auto-discovery
/// can't reach peers, plus the live relay diagnostics row.
class _LanCard extends ConsumerWidget {
  const _LanCard({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    // Config writes re-mirror through the provider — watching it keeps the
    // relay row fresh after each hub persist.
    ref.watch(settingsProvider.select((s) => s.config));
    final active = bridge.lanActive();
    return _SettingsCard(
      title: bridge.tr(key: 'settings.lan'),
      children: [
        _SettingsTextField(
          controller: controller,
          placeholder: bridge.tr(key: 'settings.lan_hub_hint'),
          icon: 'wifi',
          onChanged: (value) =>
              unawaited(ref.read(settingsProvider.notifier).setLanHub(value)),
        ),
        Text(
          bridge.tr(key: 'settings.lan_caption'),
          style: MadarType.labelSm.copyWith(
            fontWeight: FontWeight.w400,
            color: colors.textMuted,
          ),
        ),
        _InfoRow(
          label: active
              ? bridge.tr(key: 'settings.lan_active')
              : bridge.tr(key: 'settings.lan_offline'),
          value: active
              ? '${bridge.lanPeerCount()} ${bridge.tr(key: 'settings.lan_peers')}'
              : '—',
        ),
      ],
    );
  }
}

/// Device: the begin-reconfigure entry (guarded by an open drawer).
class _DeviceCard extends ConsumerWidget {
  const _DeviceCard();

  /// Pop first, then refresh the shell — the route flips to DeviceSetup on
  /// the shell subtree, not under this overlay.
  Future<void> _reconfigure(BuildContext context, WidgetRef ref) async {
    final shell = ref.read(shellProvider.notifier);
    final ok = await ref.read(settingsProvider.notifier).reconfigure();
    if (!ok || !context.mounted) return;
    await Navigator.of(context).maybePop();
    shell.refresh();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    return _SettingsCard(
      title: bridge.tr(key: 'settings.device'),
      children: [
        Semantics(
          button: true,
          child: TactileScale(
            onTap: () => unawaited(_reconfigure(context, ref)),
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
                    bridge.tr(key: 'settings.reconfigure'),
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
}

/// Diagnostics: core version, server, pending count, realtime channel
/// health, and the recent-warnings feed (with clear).
class _DiagnosticsCard extends ConsumerWidget {
  const _DiagnosticsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final pending = ref.watch(settingsProvider.select((s) => s.pending));
    final diagnostics = ref.watch(
      settingsProvider.select((s) => s.diagnostics),
    );
    return _SettingsCard(
      title: bridge.tr(key: 'settings.diagnostics'),
      children: [
        _InfoRow(
          label: bridge.tr(key: 'settings.version'),
          value: coreVersion(),
        ),
        _InfoRow(
          label: bridge.tr(key: 'settings.server'),
          value: bridge.baseUrl(),
        ),
        _InfoRow(
          label: bridge.tr(key: 'settings.pending'),
          value: '$pending',
        ),
        // Realtime (SSE) channel health — the teller's order alerts ride
        // this; surfacing it makes a silent drop diagnosable.
        _InfoRow(
          label: bridge.tr(key: 'settings.realtime'),
          value: bridge.isRealtimeSubscribed()
              ? bridge.tr(key: 'settings.realtime_on')
              : bridge.tr(key: 'settings.realtime_off'),
        ),
        if (diagnostics.isNotEmpty) ...[
          SizedBox(
            height: 1,
            child: ColoredBox(color: colors.borderLight),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  bridge.tr(key: 'settings.recent_warnings'),
                  style: MadarType.label.copyWith(color: colors.textMuted),
                ),
              ),
              TactileScale(
                onTap: () => unawaited(
                  ref.read(settingsProvider.notifier).clearDiagnostics(),
                ),
                child: Text(
                  bridge.tr(key: 'settings.clear'),
                  style: MadarType.label.copyWith(color: colors.accent),
                ),
              ),
            ],
          ),
          for (final entry in diagnostics.take(15))
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
/// that tints accent while focused, and per-keystroke [onChanged]. The
/// focus ring re-renders through a [ListenableBuilder] on the focus node —
/// no setState.
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

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ListenableBuilder(
      listenable: _focus,
      builder: (context, _) {
        final focused = _focus.hasFocus;
        return AnimatedContainer(
          duration: MotionSpec.standardDuration,
          curve: MotionSpec.standardCurve,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.lg,
            vertical: _fieldVPad,
          ),
          decoration: BoxDecoration(
            color: focused ? colors.surface : colors.surfaceAlt,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: focused ? colors.accent : colors.border,
              width: focused ? 2 : 1,
            ),
            boxShadow: focused
                ? [
                    BoxShadow(
                      color: colors.accent.withValues(
                        alpha: Opacities.focusGlow,
                      ),
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
                  tint: focused ? colors.accent : colors.textMuted,
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
      },
    );
  }
}
