import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/auth_layout.dart';
import 'package:feature_auth/src/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Column width cap, as the other auth screens.
const double _columnMaxWidth = 480;

/// Hero tile diameter / glyph size.
const double _heroTile = 56;
const double _heroGlyph = 28;

/// Hero title size.
const double _heroTitleSize = 26;

/// What a kitchen-role account sees if it signs into the POS. The kitchen
/// display is its own app now (Madar Kitchen, `apps/kitchen`), so the till no
/// longer turns into a kitchen board: it says where to go and offers a way
/// out. The till's Queue → Kitchen segment, for one-device shops, stays.
class KitchenAccountScreen extends ConsumerWidget {
  /// Creates the kitchen-account notice.
  const KitchenAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AuthSplitScaffold(
      brandRatio: evenBrandRatio,
      formMaxWidth: _columnMaxWidth,
      formBuilder: (context, {required showLogo}) =>
          _column(context, ref, showLogo: showLogo),
    );
  }

  Widget _column(
    BuildContext context,
    WidgetRef ref, {
    required bool showLogo,
  }) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final branchName = bridge.deviceConfig().branchName ?? '';

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.lg,
      children: [
        if (showLogo) const MadarSymbol(size: _heroTile),
        Column(
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
              t('kitchen.use_app'),
              textAlign: TextAlign.center,
              style: MadarType.h1.copyWith(
                fontSize: _heroTitleSize,
                letterSpacing: 0,
                color: colors.textPrimary,
              ),
            ),
            Text(
              t('kitchen.use_app_desc'),
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
        ),
        MadarButton(
          label: t('home.sign_out'),
          onTap: () => unawaited(ref.read(authProvider.notifier).signOut()),
          icon: 'rectangle.portrait.and.arrow.right',
        ),
      ],
    );
  }
}
