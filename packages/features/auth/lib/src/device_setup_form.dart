import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/providers.dart';
import 'package:feature_auth/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Setup title metrics (natives: 24.sp Black, −0.4 tracking).
const double _titleSize = 24;
const double _titleTracking = -0.4;

/// Branch row inset (natives: 14.dp both axes).
const double _branchRowPad = 14;

/// Branch row leading tone-tile side (natives: 36.dp).
const double _branchTile = 36;

/// Manager logo size on the narrow (stacked) layout (natives: 56.dp).
const double _logoSize = 56;

/// The manager device-setup form — CREDENTIALS (org email + password →
/// `login`) then PICK_BRANCH (`listBranches` → `setDeviceBranch`), all driven
/// by [authProvider]. Mirror of the natives' `DeviceSetupForm` in
/// LoginScreen.kt; shared by `DeviceSetupScreen` and the reconfigure path of
/// `LoginScreen`.
class DeviceSetupForm extends ConsumerStatefulWidget {
  /// Creates the setup form.
  const DeviceSetupForm({required this.showLogo, super.key});

  /// Show the brand mark above the form (narrow/stacked layout only).
  final bool showLogo;

  @override
  ConsumerState<DeviceSetupForm> createState() => _DeviceSetupFormState();
}

class _DeviceSetupFormState extends ConsumerState<DeviceSetupForm> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _authenticate() {
    unawaited(
      ref
          .read(authProvider.notifier)
          .authenticateManager(
            email: _email.text,
            password: _password.text,
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final phase = ref.watch(authProvider.select((s) => s.phase));
    final busy = ref.watch(authProvider.select((s) => s.busy));
    final error = ref.watch(authProvider.select((s) => s.error));
    final branches = ref.watch(authProvider.select((s) => s.branches));

    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    final picking = phase == SetupPhase.pickBranch;
    final isBranchConfigured =
        (bridge.deviceConfig().branchId ?? '').isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.lg,
      children: [
        if (widget.showLogo) const MadarSymbol(size: _logoSize),
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Column(
            spacing: Space.xs,
            children: [
              Text(
                picking ? t('setup.choose_branch') : t('setup.title'),
                textAlign: TextAlign.center,
                style: MadarType.h2.copyWith(
                  fontSize: _titleSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: _titleTracking,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                picking ? t('setup.choose_branch_desc') : t('setup.desc'),
                textAlign: TextAlign.center,
                style: MadarType.bodySm.copyWith(
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        if (picking)
          for (final branch in branches)
            _BranchRow(
              branch: branch,
              onTap: () => unawaited(
                ref.read(authProvider.notifier).bindBranch(branch),
              ),
            )
        else ...[
          MadarTextField(
            controller: _email,
            placeholder: t('setup.email'),
            icon: 'envelope',
            enabled: !busy,
            keyboardType: TextInputType.emailAddress,
          ),
          MadarTextField(
            controller: _password,
            placeholder: t('setup.password'),
            icon: 'lock',
            secure: true,
            enabled: !busy,
            onSubmitted: (_) => _authenticate(),
          ),
        ],
        if (error != null)
          NoticeBanner(
            text: error,
            tone: ChipTone.danger,
            icon: 'exclamationmark.circle',
          ),
        if (!picking)
          MadarButton(
            label: t('setup.continue'),
            onPressed: _authenticate,
            loading: busy,
            icon: 'arrow.right.circle',
          ),
        if (picking || isBranchConfigured)
          MadarButton(
            label: t('setup.cancel'),
            onPressed: () => unawaited(
              ref.read(authProvider.notifier).cancelReconfigure(),
            ),
            variant: AuthButtonVariant.ghost,
          ),
      ],
    );
  }
}

/// A selectable branch — raised surface row with the signature leading
/// tone-tile (teal glyph on accentBg) + trailing disclosure chevron, matching
/// the order screen's row language (natives' `BranchRow`).
class _BranchRow extends StatelessWidget {
  const _BranchRow({required this.branch, required this.onTap});

  final BranchView branch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      haptic: false,
      onTap: () {
        MadarHaptics.impact();
        onTap();
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(_branchRowPad),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: colors.borderLight),
          boxShadow: elevationShadows(context, MadarElevation.card),
        ),
        child: Row(
          spacing: Space.md,
          children: [
            Container(
              width: _branchTile,
              height: _branchTile,
              decoration: BoxDecoration(
                color: colors.accentBg,
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              alignment: Alignment.center,
              child: MadarIcon('building.2', tint: colors.accent),
            ),
            Expanded(
              child: Text(
                branch.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.title.copyWith(color: colors.textPrimary),
              ),
            ),
            MadarIcon(
              'chevron.right',
              tint: colors.textMuted,
              size: IconSize.xs,
            ),
          ],
        ),
      ),
    );
  }
}
