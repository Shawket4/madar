import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Setup title metrics (natives: 24.sp Black, −0.4 tracking).
const double _titleSize = 24;
const double _titleTracking = -0.4;

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
  final TextEditingController _code = TextEditingController();

  /// Where the email field's return key goes.
  final FocusNode _passwordFocus = FocusNode();

  /// An activation code from the dashboard is the primary way to bind a
  /// device (POS_SIGNIN_OVERHAUL §4); the manager login stays for now.
  bool _useCode = true;

  @override
  void dispose() {
    _code.dispose();
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _authenticate() {
    unawaited(
      ref
          .read(authProvider.notifier)
          .authenticateManager(email: _email.text, password: _password.text),
    );
  }

  void _activate() {
    unawaited(ref.read(authProvider.notifier).activateDevice(_code.text));
  }

  void _switchMode() {
    setState(() => _useCode = !_useCode);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final phase = ref.watch(authProvider.select((s) => s.phase));
    final busy = ref.watch(authProvider.select((s) => s.busy));
    final error = ref.watch(authProvider.select((s) => s.error));
    final branches = ref.watch(authProvider.select((s) => s.branches));

    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final picking = phase == SetupPhase.pickBranch;
    final byCode = _useCode && !picking;
    final isBranchConfigured =
        (bridge.deviceConfig().branchId ?? '').isNotEmpty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      // Fields and the button share one width — a hugging button under
      // full-width fields reads as a different form.
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        if (widget.showLogo) const Center(child: MadarSymbol(size: _logoSize)),
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Column(
            spacing: Space.xs,
            children: [
              Text(
                picking
                    ? t('setup.choose_branch')
                    : byCode
                    ? t('setup.activate_title')
                    : t('setup.title'),
                textAlign: TextAlign.center,
                style: MadarType.h2.copyWith(
                  fontSize: _titleSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: _titleTracking,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                picking
                    ? t('setup.choose_branch_desc')
                    : byCode
                    ? t('setup.activate_desc')
                    : t('setup.desc'),
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
          MadarCard.column(
            flush: true,
            children: [
              for (final (i, branch) in branches.indexed) ...[
                if (i > 0) const MadarHairline.row(),
                MadarListRow.nav(
                  title: branch.name,
                  glyph: MadarGlyph.tag,
                  onTap: () {
                    MadarHaptics.impact();
                    unawaited(
                      ref.read(authProvider.notifier).bindBranch(branch),
                    );
                  },
                ),
              ],
            ],
          )
        else if (byCode)
          MadarField(
            controller: _code,
            placeholder: t('setup.activation_code'),
            kind: MadarFieldKind.code,
            icon: 'lock.open',
            enabled: !busy,
            autofocus: true,
            onSubmitted: (_) => _activate(),
          )
        else ...[
          // Email then password: the return key moves on instead of putting
          // the keyboard away halfway through the form — the same order a
          // hardware keyboard's Tab follows.
          MadarField(
            controller: _email,
            placeholder: t('setup.email'),
            kind: MadarFieldKind.email,
            icon: 'envelope',
            enabled: !busy,
            nextFocus: _passwordFocus,
          ),
          MadarField(
            controller: _password,
            placeholder: t('setup.password'),
            kind: MadarFieldKind.password,
            icon: 'lock',
            enabled: !busy,
            focusNode: _passwordFocus,
            onSubmitted: (_) => _authenticate(),
          ),
        ],
        if (error != null)
          NoticeBanner(
            text: error.of(ref.bridge),
            tone: ChipTone.danger,
            icon: 'exclamationmark.circle',
          ),
        if (byCode)
          MadarButton(
            label: t('setup.activate'),
            onTap: _activate,
            loading: busy,
            icon: 'arrow.right.circle',
          )
        else if (!picking)
          MadarButton(
            label: t('setup.continue'),
            onTap: _authenticate,
            loading: busy,
            icon: 'arrow.right.circle',
          ),
        if (!picking)
          MadarButton(
            label: byCode ? t('setup.use_manager_login') : t('setup.use_code'),
            onTap: _switchMode,
            enabled: !busy,
            variant: MadarButtonVariant.ghost,
            size: MadarButtonSize.compact,
          ),
        if (picking || isBranchConfigured)
          MadarButton(
            label: t('setup.cancel'),
            onTap: () =>
                unawaited(ref.read(authProvider.notifier).cancelReconfigure()),
            variant: MadarButtonVariant.ghost,
          ),
      ],
    );
  }
}
