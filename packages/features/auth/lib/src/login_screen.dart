import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/auth_layout.dart';
import 'package:feature_auth/src/device_setup_form.dart';
import 'package:feature_auth/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Greeting metrics (natives: 28.sp Black, −0.5 tracking).
const double _greetingSize = 28;
const double _greetingTracking = -0.5;

/// Logo size on the narrow (stacked) layout (natives: 56.dp).
const double _logoSize = 56;

/// Sign-in CTA height (natives pass 52.dp, below Metric.buttonHeight).
const double _signInHeight = 52;

/// PIN length window: auto-submit at 6, reject below 4 (natives' maxPin /
/// submit guard).
const int _maxPin = 6;
const int _minPin = 4;

/// Shake step duration ×5 keyframes (natives: five 60 ms tweens).
const Duration _shakeDuration = Duration(milliseconds: 300);

/// Shake keyframes (natives: −8, 8, −6, 6, 0 dp).
const List<double> _shakeKeyframes = [-8, 8, -6, 6, 0];

/// Characters of the branch id shown when no branch name is known
/// (natives: `branchId.take(8)`).
const int _branchIdPreview = 8;

/// Login — branch-gated brand moment. Manager device-setup until the till is
/// bound to a branch, then teller PIN with a reconfigure link. Wide screens
/// (tablet / desktop) split into a brand panel + form. Mirror of the natives'
/// LoginScreen.kt.
class LoginScreen extends StatelessWidget {
  /// Creates the login screen.
  const LoginScreen({
    required this.core,
    required this.onStateChanged,
    super.key,
  });

  /// The core handle.
  final MadarCore core;

  /// Notifies the shell after any bridge call that can move the route.
  final void Function() onStateChanged;

  @override
  Widget build(BuildContext context) {
    return AuthSplitScaffold(
      core: core,
      formBuilder: (context, {required showLogo}) {
        final config = core.bridge.deviceConfig();
        final configured = (config.branchId ?? '').isNotEmpty;
        if (configured && !config.reconfiguring) {
          return _TellerForm(
            core: core,
            onStateChanged: onStateChanged,
            showLogo: showLogo,
          );
        }
        return DeviceSetupForm(
          core: core,
          onStateChanged: onStateChanged,
          showLogo: showLogo,
        );
      },
    );
  }
}

/// Daily teller PIN sign-in — name + 6-digit PIN pad, auto-submit, shake on
/// failure. Offline-capable: `signIn` falls back to the core's offline PIN
/// unlock. Mirror of the natives' `TellerForm`.
class _TellerForm extends StatefulWidget {
  const _TellerForm({
    required this.core,
    required this.onStateChanged,
    required this.showLogo,
  });

  final MadarCore core;
  final void Function() onStateChanged;
  final bool showLogo;

  @override
  State<_TellerForm> createState() => _TellerFormState();
}

class _TellerFormState extends State<_TellerForm>
    with SingleTickerProviderStateMixin {
  final TextEditingController _name = TextEditingController();
  String _pin = '';
  bool _busy = false;
  String? _error;

  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: _shakeDuration,
  );
  late final Animation<double> _shakeOffset = _shake.drive(
    TweenSequence<double>([
      for (var i = 0; i < _shakeKeyframes.length; i++)
        TweenSequenceItem(
          tween: Tween(
            begin: i == 0 ? 0.0 : _shakeKeyframes[i - 1],
            end: _shakeKeyframes[i],
          ),
          weight: 1,
        ),
    ]),
  );

  MadarBridge get _bridge => widget.core.bridge;

  String _t(String key) => _bridge.tr(key: key);

  @override
  void dispose() {
    _name.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _fail() {
    MadarHaptics.warning();
    unawaited(_shake.forward(from: 0));
  }

  Future<void> _submit() async {
    if (_name.text.trim().isEmpty || _pin.length < _minPin) {
      _fail();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    String? failure;
    try {
      await _bridge.signIn(
        req: LoginRequest(
          mode: LoginMode.pin,
          name: _name.text.trim(),
          pin: _pin,
          branchId: _bridge.deviceConfig().branchId,
        ),
      );
    } on MadarError catch (e) {
      failure = _bridge.humanMessage(e);
    } on Exception catch (_) {
      failure = _t('err.generic');
    }
    widget.onStateChanged();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = failure;
      if (failure != null) _pin = '';
    });
    if (failure != null) _fail();
  }

  void _digit(String digit) {
    if (_busy || _pin.length >= _maxPin) return;
    setState(() {
      _error = null;
      _pin += digit;
    });
    if (_pin.length == _maxPin) unawaited(_submit());
  }

  void _backspace() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  /// Re-enter device setup (natives' `beginReconfigure`) — the route/form
  /// recomputes to the manager setup flow.
  Future<void> _beginReconfigure() async {
    try {
      await _bridge.startReconfigure();
    } on Exception catch (_) {}
    widget.onStateChanged();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final config = _bridge.deviceConfig();
    final branchName = config.branchName ?? '';
    final branchId = config.branchId ?? '';
    final branchLabel = branchName.isNotEmpty
        ? branchName
        : '${_t('login.branch')} '
              '${branchId.substring(0, branchId.length.clamp(0, _branchIdPreview))}';
    final error = _error;

    // Spacing mirrors the natives' deliberate rhythm (not a flat stack): xs
    // between title/subtitle, md before the branch chip block, xxl after the
    // header block, xl around the PIN pad, sm between button and hint.
    final form = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showLogo) ...[
          const MadarSymbol(size: _logoSize),
          const SizedBox(height: Space.xxl),
        ],
        // The greeting is the hero — heavy, tightly tracked; the subtitle
        // sits beneath as a quiet eyebrow.
        Column(
          spacing: Space.xs,
          children: [
            Text(
              _t('login.welcome_back'),
              textAlign: TextAlign.center,
              style: MadarType.h1.copyWith(
                fontSize: _greetingSize,
                letterSpacing: _greetingTracking,
                color: colors.textPrimary,
              ),
            ),
            Text(
              _t('login.subtitle'),
              textAlign: TextAlign.center,
              style: MadarType.body.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: Space.md),
        // Identity moment — the bound branch as a tinted teal pill with a
        // quiet reconfigure link beneath.
        Column(
          spacing: Space.xs,
          children: [
            StatusChip(
              label: branchLabel,
              tone: ChipTone.accent,
              icon: 'building.2',
            ),
            GestureDetector(
              onTap: () => unawaited(_beginReconfigure()),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Text(
                  _t('login.reconfigure'),
                  style: MadarType.label.copyWith(
                    fontWeight: FontWeight.w500,
                    color: colors.textMuted,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.xxl),
        MadarTextField(
          controller: _name,
          placeholder: _t('login.name'),
          icon: 'person',
          enabled: !_busy,
        ),
        const SizedBox(height: Space.xl),
        PinPad(
          pin: _pin,
          onDigit: _digit,
          onBackspace: _backspace,
        ),
        if (error != null) ...[
          const SizedBox(height: Space.sm),
          NoticeBanner(
            text: error,
            tone: ChipTone.danger,
            icon: 'exclamationmark.circle',
          ),
        ],
        const SizedBox(height: Space.xl),
        MadarButton(
          label: _t('login.sign_in'),
          onPressed: () => unawaited(_submit()),
          loading: _busy,
          height: _signInHeight,
          icon: 'arrow.right.circle',
        ),
        const SizedBox(height: Space.sm),
        Text(
          _t('login.pin_hint'),
          textAlign: TextAlign.center,
          style: MadarType.label.copyWith(
            fontWeight: FontWeight.w500,
            color: colors.textMuted,
          ),
        ),
      ],
    );

    return AnimatedBuilder(
      animation: _shakeOffset,
      builder: (context, child) => Transform.translate(
        offset: Offset(_shakeOffset.value, 0),
        child: child,
      ),
      child: form,
    );
  }
}
