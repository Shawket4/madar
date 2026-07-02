import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/widgets.dart';
import 'package:flutter/material.dart';
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

/// Device-setup is two steps: a manager authenticates, then picks the branch.
enum _SetupPhase { credentials, pickBranch }

/// The manager device-setup form — CREDENTIALS (org email + password →
/// `login`) then PICK_BRANCH (`listBranches` → `setDeviceBranch`). Mirror of
/// the natives' `DeviceSetupForm` in LoginScreen.kt; shared by
/// `DeviceSetupScreen` and the reconfigure path of `LoginScreen`.
class DeviceSetupForm extends StatefulWidget {
  /// Creates the setup form.
  const DeviceSetupForm({
    required this.core,
    required this.onStateChanged,
    required this.showLogo,
    super.key,
  });

  /// The core handle.
  final MadarCore core;

  /// Notifies the shell after any bridge call that can move the route.
  final void Function() onStateChanged;

  /// Show the brand mark above the form (narrow/stacked layout only).
  final bool showLogo;

  @override
  State<DeviceSetupForm> createState() => _DeviceSetupFormState();
}

class _DeviceSetupFormState extends State<DeviceSetupForm> {
  final TextEditingController _email = TextEditingController();
  final TextEditingController _password = TextEditingController();
  _SetupPhase _phase = _SetupPhase.credentials;
  List<BranchView> _branches = const [];
  bool _busy = false;
  String? _error;

  MadarBridge get _bridge => widget.core.bridge;

  String _t(String key) => _bridge.tr(key: key);

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Best-effort logout — setup auth failures must never strand a session.
  Future<void> _quietLogout() async {
    try {
      await _bridge.logout(wipeOutbox: false);
    } on Exception catch (_) {}
  }

  /// Manager credentials → branch list (natives' `authenticateManager`).
  Future<void> _authenticate() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    String? failure;
    var branches = const <BranchView>[];
    try {
      await _bridge.login(
        req: LoginRequest(
          mode: LoginMode.email,
          email: _email.text.trim(),
          password: _password.text,
        ),
      );
      branches = await _bridge.listBranches();
    } on MadarError catch (e) {
      failure = _bridge.humanMessage(e);
      await _quietLogout();
    } on Exception catch (_) {
      failure = _t('err.generic');
      await _quietLogout();
    }
    widget.onStateChanged();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failure;
      if (failure == null) {
        _branches = branches;
        _phase = _SetupPhase.pickBranch;
      }
    });
  }

  /// Bind the till to [branch], then sign the manager out so tellers sign in
  /// (natives' `bindBranch`).
  Future<void> _bindBranch(BranchView branch) async {
    try {
      await _bridge.setDeviceBranch(
        branchId: branch.id,
        branchName: branch.name,
      );
    } on Exception catch (_) {}
    await _quietLogout();
    if (mounted) {
      setState(() {
        _phase = _SetupPhase.credentials;
        _branches = const [];
        _error = null;
      });
    }
    widget.onStateChanged();
  }

  /// Re-confirm the existing branch to drop the reconfigure flag (natives'
  /// `cancelReconfigure`).
  Future<void> _cancelReconfigure() async {
    final config = _bridge.deviceConfig();
    final branchId = config.branchId;
    if (branchId != null && branchId.isNotEmpty) {
      try {
        await _bridge.setDeviceBranch(
          branchId: branchId,
          branchName: config.branchName,
        );
      } on Exception catch (_) {}
    }
    await _quietLogout();
    if (mounted) {
      setState(() {
        _phase = _SetupPhase.credentials;
        _branches = const [];
        _error = null;
      });
    }
    widget.onStateChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final picking = _phase == _SetupPhase.pickBranch;
    final config = _bridge.deviceConfig();
    final isBranchConfigured = (config.branchId ?? '').isNotEmpty;
    final error = _error;

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
                picking ? _t('setup.choose_branch') : _t('setup.title'),
                textAlign: TextAlign.center,
                style: MadarType.h2.copyWith(
                  fontSize: _titleSize,
                  fontWeight: FontWeight.w800,
                  letterSpacing: _titleTracking,
                  color: colors.textPrimary,
                ),
              ),
              Text(
                picking ? _t('setup.choose_branch_desc') : _t('setup.desc'),
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
          for (final branch in _branches)
            _BranchRow(
              branch: branch,
              onTap: () => unawaited(_bindBranch(branch)),
            )
        else ...[
          MadarTextField(
            controller: _email,
            placeholder: _t('setup.email'),
            icon: 'envelope',
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
          ),
          MadarTextField(
            controller: _password,
            placeholder: _t('setup.password'),
            icon: 'lock',
            secure: true,
            enabled: !_busy,
            onSubmitted: (_) => unawaited(_authenticate()),
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
            label: _t('setup.continue'),
            onPressed: () => unawaited(_authenticate()),
            loading: _busy,
            icon: 'arrow.right.circle',
          ),
        if (picking || isBranchConfigured)
          MadarButton(
            label: _t('setup.cancel'),
            onPressed: () => unawaited(_cancelReconfigure()),
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
