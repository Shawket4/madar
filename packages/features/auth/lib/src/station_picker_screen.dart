import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/auth_layout.dart';
import 'package:feature_auth/src/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Station column width cap (natives: `widthIn(max = 480.dp)`).
const double _columnMaxWidth = 480;

/// Hero tile diameter / glyph size (natives: 56.dp circle, 28.dp icon).
const double _heroTile = 56;
const double _heroGlyph = 28;

/// Hero title size (natives: 26.sp Black).
const double _heroTitleSize = 26;

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
    final loading = ref.watch(authProvider.select((s) => s.stationsLoading));
    final stations = ref.watch(authProvider.select((s) => s.stations));
    final stationsError = ref.watch(
      authProvider.select((s) => s.stationsError),
    );
    final error = ref.watch(authProvider.select((s) => s.error));
    final bridge = ref.bridge;
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
            text: error.of(ref.bridge),
            tone: ChipTone.danger,
            icon: 'exclamationmark.circle',
          ),
        // ── The stations, as rows in one card ─────────────────────────────
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            if (loading)
              const MadarCard(
                flush: true,
                child: SkeletonScope(child: SkeletonList(count: 3)),
              )
            else if (stationsError != null)
              // Could not ask is not "none": say why and offer the retry.
              MadarCard(
                child: ErrorState(
                  message: stationsError.of(bridge),
                  retryLabel: t('history.retry'),
                  onRetry: () =>
                      unawaited(ref.read(authProvider.notifier).loadStations()),
                ),
              )
            else if (stations.isEmpty)
              MadarCard(
                child: EmptyState(icon: 'tray', title: t('setup.no_stations')),
              )
            else
              MadarCard.column(
                flush: true,
                children: [
                  for (final (i, station) in stations.indexed) ...[
                    if (i > 0) const MadarHairline.row(),
                    MadarListRow.nav(
                      title: station.name,
                      glyph: MadarGlyph.flame,
                      valueText: station.isDefault
                          ? t('setup.station_default')
                          : null,
                      onTap: () => unawaited(
                        ref.read(authProvider.notifier).pickStation(station),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
        // ── Recessive exit ─────────────────────────────────────────────────
        MadarButton(
          label: t('home.sign_out'),
          onTap: () => unawaited(ref.read(authProvider.notifier).signOut()),
          variant: MadarButtonVariant.ghost,
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
          child: MadarIcon('fork.knife', tint: colors.accent, size: _heroGlyph),
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
