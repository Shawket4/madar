import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/auth_layout.dart';
import 'package:feature_auth/src/providers.dart';
import 'package:feature_auth/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
class StationPickerScreen extends ConsumerStatefulWidget {
  /// Creates the station picker.
  const StationPickerScreen({super.key});

  @override
  ConsumerState<StationPickerScreen> createState() =>
      _StationPickerScreenState();
}

class _StationPickerScreenState extends ConsumerState<StationPickerScreen> {
  @override
  void initState() {
    super.initState();
    // Post-frame: provider writes are illegal while the tree is building.
    unawaited(
      Future.microtask(() => ref.read(authProvider.notifier).loadStations()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthSplitScaffold(
      brandRatio: evenBrandRatio,
      formMaxWidth: _columnMaxWidth,
      formBuilder: _column,
    );
  }

  Widget _column(BuildContext context, {required bool showLogo}) {
    final colors = context.madarColors;
    final loading = ref.watch(authProvider.select((s) => s.stationsLoading));
    final stations = ref.watch(authProvider.select((s) => s.stations));
    final error = ref.watch(authProvider.select((s) => s.error));
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.lg,
      children: [
        if (showLogo) const MadarSymbol(size: _heroTile),
        // ── Hero greeting (the commissioning prompt IS the hero) ──────────
        _greeting(context, t),
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
              text: t('setup.title'),
              icon: 'square.stack.3d.up.fill',
            ),
            if (loading)
              Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Center(
                  child: CircularProgressIndicator(color: colors.accent),
                ),
              )
            else if (stations.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.md),
                child: SizedBox(
                  width: double.infinity,
                  child: Text(
                    t('setup.no_stations'),
                    textAlign: TextAlign.center,
                    style: MadarType.bodySm.copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.textMuted,
                    ),
                  ),
                ),
              )
            else
              for (final station in stations)
                _StationCard(
                  station: station,
                  defaultLabel: t('setup.station_default'),
                  onTap: () => unawaited(
                    ref.read(authProvider.notifier).pickStation(station),
                  ),
                ),
          ],
        ),
        // ── Recessive exit ─────────────────────────────────────────────────
        MadarButton(
          label: t('home.sign_out'),
          onPressed: () => unawaited(ref.read(authProvider.notifier).signOut()),
          variant: AuthButtonVariant.ghost,
          icon: 'rectangle.portrait.and.arrow.right',
        ),
      ],
    );
  }

  /// The commissioning hero — accent-tinted station tile, bold title,
  /// supporting line, and the bound branch as an info chip.
  Widget _greeting(BuildContext context, String Function(String) t) {
    final colors = context.madarColors;
    final branchName = ref.read(bridgeProvider).deviceConfig().branchName ?? '';

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
          t('setup.choose_station'),
          textAlign: TextAlign.center,
          style: MadarType.h1.copyWith(
            fontSize: _heroTitleSize,
            letterSpacing: 0,
            color: colors.textPrimary,
          ),
        ),
        Text(
          t('setup.choose_station_desc'),
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
