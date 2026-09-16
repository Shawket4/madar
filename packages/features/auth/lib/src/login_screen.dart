import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_auth/src/auth_layout.dart';
import 'package:feature_auth/src/device_setup_form.dart';
import 'package:feature_auth/src/providers.dart';
import 'package:feature_auth/src/reconfigure_sheet.dart';
import 'package:feature_auth/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Greeting metrics (natives: 28.sp Black, −0.5 tracking).
const double _greetingSize = 28;
const double _greetingTracking = -0.5;

/// Logo size on the narrow (stacked) layout (natives: 56.dp).
const double _logoSize = 56;

/// Shake step duration ×5 keyframes (natives: five 60 ms tweens).
const Duration _shakeDuration = Duration(milliseconds: 300);

/// Shake keyframes (natives: −8, 8, −6, 6, 0 dp).
const List<double> _shakeKeyframes = [-8, 8, -6, 6, 0];

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
    final bridge = ref.bridge;
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

/// Daily PIN sign-in — the PIN alone (POS_SIGNIN_OVERHAUL §8.5), 6-digit
/// pad, auto-submit, shake on failure. Offline-capable: `signIn` falls back to the core's offline PIN
/// unlock. Mirror of the natives' `TellerForm`.
class _TellerForm extends ConsumerStatefulWidget {
  const _TellerForm({required this.showLogo});

  final bool showLogo;

  @override
  ConsumerState<_TellerForm> createState() => _TellerFormState();
}

class _TellerFormState extends ConsumerState<_TellerForm>
    with SingleTickerProviderStateMixin {
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

  /// Ticks the wrong-PIN countdown. Cheap: one synchronous core read a second.
  Timer? _waitTicker;

  @override
  void initState() {
    super.initState();
    // A delay owed from before a restart shows at once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(authProvider.notifier).tickPinWait();
    });
    _waitTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final notifier = ref.read(authProvider.notifier);
      if (ref.read(authProvider).pinWaitSeconds > 0) notifier.tickPinWait();
    });
  }

  @override
  void dispose() {
    _waitTicker?.cancel();
    _shake.dispose();
    super.dispose();
  }

  void _fail() {
    MadarHaptics.warning();
    _shake.forward(from: 0);
  }

  void _submit() {
    unawaited(ref.read(authProvider.notifier).signInTeller());
  }

  void _digit(String digit) {
    if (ref.read(authProvider.notifier).pushDigit(digit)) _submit();
  }

  /// A hardware keyboard types the PIN too: digits (row or numpad), delete,
  /// and Enter to sign in with a 4–5 digit PIN that does not auto-submit.
  /// While a text field has focus (the name) the keys are its own.
  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      ref.read(authProvider.notifier).popDigit();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) _submit();
      return KeyEventResult.handled;
    }
    final char = event.character;
    if (char != null && char.length == 1 && '0123456789'.contains(char)) {
      _digit(char);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Reconfigure is a gated fresh install: the sheet shows what blocks it
  /// and only wipes once the core allows it.
  Future<void> _reconfigure() => showReconfigureSheet(context);

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
    final wait = ref.watch(authProvider.select((s) => s.pinWaitSeconds));

    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final config = bridge.deviceConfig();
    final branchName = config.branchName?.trim() ?? '';
    // Never the raw id: a UUID fragment is not a place anybody works.
    final branchLabel = branchName.isNotEmpty ? branchName : t('login.branch');

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
            // A real 44pt target, behind a confirm.
            MadarButton(
              label: t('login.reconfigure'),
              variant: MadarButtonVariant.ghost,
              size: MadarButtonSize.compact,
              enabled: !busy,
              onTap: () => unawaited(_reconfigure()),
            ),
          ],
        ),
        const SizedBox(height: Space.xxl),
        PinPad(
          pin: pin,
          onDigit: _digit,
          onBackspace: ref.read(authProvider.notifier).popDigit,
          enabled: wait <= 0 && !busy,
        ),
        if (wait > 0) ...[
          const SizedBox(height: Space.sm),
          NoticeBanner(
            text: t('login.pin_wait').replaceAll('{seconds}', '$wait'),
            icon: 'clock',
          ),
        ] else if (error != null) ...[
          const SizedBox(height: Space.sm),
          NoticeBanner(
            text: error.of(ref.bridge),
            tone: ChipTone.danger,
            icon: 'exclamationmark.circle',
          ),
        ],
        const SizedBox(height: Space.xl),
        MadarButton(
          label: t('login.sign_in'),
          onTap: _submit,
          enabled: wait <= 0,
          loading: busy,
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

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: AnimatedBuilder(
        animation: _shakeOffset,
        builder: (context, child) => Transform.translate(
          offset: Offset(_shakeOffset.value, 0),
          child: child,
        ),
        child: form,
      ),
    );
  }
}
