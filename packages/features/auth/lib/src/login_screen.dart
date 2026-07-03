import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/auth_layout.dart';
import 'package:feature_auth/src/device_setup_form.dart';
import 'package:feature_auth/src/providers.dart';
import 'package:feature_auth/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Greeting metrics (natives: 28.sp Black, −0.5 tracking).
const double _greetingSize = 28;
const double _greetingTracking = -0.5;

/// Logo size on the narrow (stacked) layout (natives: 56.dp).
const double _logoSize = 56;

/// Sign-in CTA height (natives pass 52.dp, below Metric.buttonHeight).
const double _signInHeight = 52;

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
class LoginScreen extends ConsumerWidget {
  /// Creates the login screen.
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The form choice derives from `deviceConfig()` — re-read it whenever the
    // route moves or an auth mutation touched the device config.
    ref
      ..watch(shellProvider.select((s) => s.route))
      ..watch(authProvider.select((s) => s.configVersion));
    final bridge = ref.watch(bridgeProvider);
    return AuthSplitScaffold(
      formBuilder: (context, {required showLogo}) {
        final config = bridge.deviceConfig();
        final configured = (config.branchId ?? '').isNotEmpty;
        if (configured && !config.reconfiguring) {
          return _TellerForm(showLogo: showLogo);
        }
        return DeviceSetupForm(showLogo: showLogo);
      },
    );
  }
}

/// Daily teller PIN sign-in — name + 6-digit PIN pad, auto-submit, shake on
/// failure. Offline-capable: `signIn` falls back to the core's offline PIN
/// unlock. Mirror of the natives' `TellerForm`.
class _TellerForm extends ConsumerStatefulWidget {
  const _TellerForm({required this.showLogo});

  final bool showLogo;

  @override
  ConsumerState<_TellerForm> createState() => _TellerFormState();
}

class _TellerFormState extends ConsumerState<_TellerForm>
    with SingleTickerProviderStateMixin {
  final TextEditingController _name = TextEditingController();

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

  void _submit() {
    unawaited(
      ref.read(authProvider.notifier).signInTeller(name: _name.text),
    );
  }

  void _digit(String digit) {
    if (ref.read(authProvider.notifier).pushDigit(digit)) _submit();
  }

  @override
  Widget build(BuildContext context) {
    // Every rejected submit (bad PIN, empty name, bridge failure) bumps the
    // fail counter — shake + warning haptic once per failure.
    ref.listen(authProvider.select((s) => s.failCount), (previous, next) {
      if (previous != null && next > previous) _fail();
    });
    final busy = ref.watch(authProvider.select((s) => s.busy));
    final pin = ref.watch(authProvider.select((s) => s.pin));
    final error = ref.watch(authProvider.select((s) => s.error));

    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    String t(String key) => bridge.tr(key: key);
    final config = bridge.deviceConfig();
    final branchName = config.branchName ?? '';
    final branchId = config.branchId ?? '';
    final branchLabel = branchName.isNotEmpty
        ? branchName
        : '${t('login.branch')} '
              '${branchId.substring(0, branchId.length.clamp(0, _branchIdPreview))}';

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
              t('login.welcome_back'),
              textAlign: TextAlign.center,
              style: MadarType.h1.copyWith(
                fontSize: _greetingSize,
                letterSpacing: _greetingTracking,
                color: colors.textPrimary,
              ),
            ),
            Text(
              t('login.subtitle'),
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
              onTap: () =>
                  unawaited(ref.read(authProvider.notifier).beginReconfigure()),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.xs),
                child: Text(
                  t('login.reconfigure'),
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
          placeholder: t('login.name'),
          icon: 'person',
          enabled: !busy,
        ),
        const SizedBox(height: Space.xl),
        PinPad(
          pin: pin,
          onDigit: _digit,
          onBackspace: ref.read(authProvider.notifier).popDigit,
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
          label: t('login.sign_in'),
          onPressed: _submit,
          loading: busy,
          height: _signInHeight,
          icon: 'arrow.right.circle',
        ),
        const SizedBox(height: Space.sm),
        Text(
          t('login.pin_hint'),
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
