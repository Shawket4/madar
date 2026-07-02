import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/auth_layout.dart';
import 'package:feature_auth/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Station column width cap (natives: `widthIn(max = 480.dp)`).
const double _columnMaxWidth = 480;

/// Hero tile diameter / glyph size (natives: 56.dp circle, 28.dp icon).
const double _heroTile = 56;
const double _heroGlyph = 28;

/// Hero title size (natives: 26.sp Black).
const double _heroTitleSize = 26;

/// Station row height (natives: 72.dp — fixed so every station aligns).
const double _stationRowHeight = 72;

/// Station leading tone-tile side (natives: 44.dp).
const double _stationTile = 44;

/// Default-station border emphasis (natives: 2.dp accent @ 0.55 alpha).
const double _defaultBorderWidth = 2;
const double _defaultBorderAlpha = 0.55;

/// Kitchen-display commissioning — the screen a kitchen-role device shows
/// once it's bound to a branch but has no station yet (the core routes here
/// via `AppRoute.deviceSetup`). Pick a station → the core pins it
/// (`setDeviceStation`) → the route recomputes to the kitchen display.
/// Mirrors the login brand-panel split (even 50/50 on wide). Mirror of the
/// natives' StationPickerScreen.kt.
class StationPickerScreen extends StatefulWidget {
  /// Creates the station picker.
  const StationPickerScreen({
    required this.core,
    required this.onStateChanged,
    super.key,
  });

  /// The core handle.
  final MadarCore core;

  /// Notifies the shell after any bridge call that can move the route.
  final void Function() onStateChanged;

  @override
  State<StationPickerScreen> createState() => _StationPickerScreenState();
}

class _StationPickerScreenState extends State<StationPickerScreen> {
  List<KdsStationView> _stations = const [];
  bool _loading = true;
  String? _error;

  MadarBridge get _bridge => widget.core.bridge;

  String _t(String key) => _bridge.tr(key: key);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Load the branch's stations (natives' `loadKdsStations` — failures fall
  /// back to an empty list, surfacing the "no stations" copy).
  Future<void> _load() async {
    var stations = const <KdsStationView>[];
    try {
      stations = await _bridge.kdsListStations();
    } on Exception catch (_) {}
    if (!mounted) return;
    setState(() {
      _stations = stations;
      _loading = false;
    });
  }

  /// Pin this device to [station] — the route recomputes to the KDS.
  Future<void> _pick(KdsStationView station) async {
    try {
      await _bridge.setDeviceStation(stationId: station.id);
    } on MadarError catch (e) {
      if (mounted) setState(() => _error = _bridge.humanMessage(e));
    } on Exception catch (_) {
      if (mounted) setState(() => _error = _t('err.generic'));
    }
    widget.onStateChanged();
  }

  /// Tear down the session (natives' `signOut`) — routing falls back to
  /// login. The shell owns the realtime/LAN lifecycles and reacts to the
  /// route change.
  Future<void> _signOut() async {
    try {
      _bridge.unsubscribeRealtime();
    } on Exception catch (_) {}
    try {
      await _bridge.logout(wipeOutbox: false);
    } on Exception catch (_) {}
    widget.onStateChanged();
  }

  @override
  Widget build(BuildContext context) {
    return AuthSplitScaffold(
      core: widget.core,
      brandRatio: evenBrandRatio,
      formMaxWidth: _columnMaxWidth,
      formBuilder: _column,
    );
  }

  Widget _column(BuildContext context, {required bool showLogo}) {
    final colors = context.madarColors;
    final error = _error;

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.lg,
      children: [
        if (showLogo) const MadarSymbol(size: _heroTile),
        // ── Hero greeting (the commissioning prompt IS the hero) ──────────
        _greeting(context),
        if (error != null)
          NoticeBanner(
            text: error,
            tone: ChipTone.danger,
            icon: 'exclamationmark.circle',
          ),
        // ── Station list on its own bordered surface card ─────────────────
        SurfaceCard(
          children: [
            SectionHeader(
              text: _t('setup.title'),
              icon: 'square.stack.3d.up.fill',
            ),
            if (_loading)
              Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Center(
                  child: CircularProgressIndicator(color: colors.accent),
                ),
              )
            else if (_stations.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.md),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    _t('setup.no_stations'),
                    textAlign: TextAlign.center,
                    style: MadarType.bodySm.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.textMuted,
                    ),
                  ),
                ),
              )
            else
              for (final station in _stations)
                _StationCard(
                  station: station,
                  defaultLabel: _t('setup.station_default'),
                  onTap: () => unawaited(_pick(station)),
                ),
          ],
        ),
        // ── Recessive exit ─────────────────────────────────────────────────
        MadarButton(
          label: _t('home.sign_out'),
          onPressed: () => unawaited(_signOut()),
          variant: AuthButtonVariant.ghost,
          icon: 'rectangle.portrait.and.arrow.right',
        ),
      ],
    );
  }

  /// The commissioning hero — accent-tinted station tile, bold title,
  /// supporting line, and the bound branch as an info chip.
  Widget _greeting(BuildContext context) {
    final colors = context.madarColors;
    final branchName = _bridge.deviceConfig().branchName ?? '';

    return Column(
      spacing: Space.sm,
      children: [
        Container(
          width: _heroTile,
          height: _heroTile,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.accentBg,
          ),
          alignment: Alignment.center,
          child: MadarIcon(
            'fork.knife',
            tint: colors.accent,
            size: _heroGlyph,
          ),
        ),
        Text(
          _t('setup.choose_station'),
          textAlign: TextAlign.center,
          style: MadarType.h1.copyWith(
            fontSize: _heroTitleSize,
            letterSpacing: 0,
            color: colors.textPrimary,
          ),
        ),
        Text(
          _t('setup.choose_station_desc'),
          textAlign: TextAlign.center,
          style: MadarType.bodySm.copyWith(
            fontWeight: FontWeight.w500,
            color: colors.textMuted,
          ),
        ),
        if (branchName.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Space.xs),
            child: StatusChip(
              label: branchName,
              tone: ChipTone.info,
              icon: 'building.2',
            ),
          ),
      ],
    );
  }
}

/// One selectable station — leading tone-tile + name; the default station is
/// flagged with an accent chip and lifted with a heavier accent border +
/// filled tile. Fixed row height so every station aligns. Mirror of the
/// natives' `StationCard`.
class _StationCard extends StatelessWidget {
  const _StationCard({
    required this.station,
    required this.defaultLabel,
    required this.onTap,
  });

  final KdsStationView station;
  final String defaultLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final isDefault = station.isDefault;

    return TactileScale(
      haptic: false,
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: _stationRowHeight,
        padding: const EdgeInsets.symmetric(horizontal: Space.lg),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(
            color: isDefault
                ? colors.accent.withValues(alpha: _defaultBorderAlpha)
                : colors.borderLight,
            width: isDefault ? _defaultBorderWidth : 1,
          ),
          boxShadow: elevationShadows(context, MadarElevation.card),
        ),
        child: Row(
          spacing: Space.md,
          children: [
            // The default station gets a FILLED accent tile so it reads as
            // "this one" at a glance; the rest stay tinted.
            Container(
              width: _stationTile,
              height: _stationTile,
              decoration: BoxDecoration(
                color: isDefault ? colors.accent : colors.accentBg,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              alignment: Alignment.center,
              child: MadarIcon(
                'fork.knife',
                tint: isDefault ? colors.textOnAccent : colors.accent,
                size: IconSize.xl,
              ),
            ),
            Expanded(
              child: Text(
                station.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.h3.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
            if (isDefault)
              StatusChip(label: defaultLabel, tone: ChipTone.accent),
            MadarIcon('chevron.forward', tint: colors.textMuted),
          ],
        ),
      ),
    );
  }
}
