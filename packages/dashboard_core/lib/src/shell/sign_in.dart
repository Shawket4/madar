/// Sign-in (`routes/login.tsx`, `features/auth/login-page.tsx`, web main):
/// the split screen — on a wide window the brand panel in the chrome's ink
/// (the shop's name and tagline, the welcome, Madar's family on its orbit,
/// the copyright) beside the form; on a narrower one the form alone. The
/// form: email and password (required, a valid email), the eye that shows the
/// password, Sign in with its spinner, a refusal as an error toast; the
/// theme and language toggles in the corner and the legal links under it.
library;

import 'dart:math' as math;

import 'package:dashboard_api/dashboard_api.dart' show ApiException;
import 'package:dashboard_core/src/authz/gates.dart' show errorMessage;
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/session/session.dart';
import 'package:dashboard_core/src/shell/brand_mark.dart';
import 'package:dashboard_core/src/shell/footer.dart';
import 'package:dashboard_core/src/shell/header.dart';
import 'package:dashboard_core/src/shell/router.dart';
import 'package:dashboard_core/src/shell/sidebar.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// zod's `.email()` in spirit: something@something.tld, no spaces.
final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// The sign-in page's sizes, from the web's classes.
abstract final class SignInMetrics {
  /// The form's column (`max-w-sm`).
  static const double form = DashMetrics.prose;

  /// The panel's welcome (`max-w-md`).
  static const double welcome = 448;

  /// The orbit stage's cap (`28rem`).
  static const double orbit = 448;

  /// The wordmark above the form (`h-9`).
  static const double wordmark = Space.xxl + Space.xs;

  /// The panel's mark tile (`size-11`).
  static const double tile = DashMetrics.target;
}

class DashSignInPage extends ConsumerStatefulWidget {
  const DashSignInPage({super.key});

  @override
  ConsumerState<DashSignInPage> createState() => _SignInState();
}

class _SignInState extends ConsumerState<DashSignInPage> {
  final _form = GlobalKey<FormState>();
  String _email = '';
  String _password = '';
  bool _showPw = false;
  bool _busy = false;

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final t = ref.read(tProvider);
    final target =
        safeReturnPath(
          GoRouterState.of(context).uri.queryParameters['redirect'],
        ) ??
        '/';
    final router = GoRouter.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(sessionProvider.notifier)
          .signIn(email: _email, password: _password);
      if (!mounted) return;
      router.go(target);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // A refused sign-in in the reader's language (the web shows the
      // server's English sentence even in Arabic).
      final words = e is ApiException && e.status == 401
          ? t('auth.errors.invalid', defaultValue: 'Invalid credentials')
          : errorMessage(e, t);
      DashToast.error(context, words);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= DashBreakpoints.lg;
    return Material(
      color: c.bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            SizedBox(
              width: width * (width >= DashBreakpoints.xl ? 0.55 : 0.5),
              child: const _BrandPanel(),
            ),
          Expanded(child: _formPanel(context, wide)),
        ],
      ),
    );
  }

  Widget _formPanel(BuildContext context, bool wide) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final align = wide ? CrossAxisAlignment.start : CrossAxisAlignment.center;
    final textAlign = wide ? TextAlign.start : TextAlign.center;
    return SafeArea(
      child: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.xxl + Space.sm,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: SignInMetrics.form),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        crossAxisAlignment: align,
                        children: [
                          const ShellWordmark(height: SignInMetrics.wordmark),
                          const SizedBox(height: Space.xl),
                          Semantics(
                            header: true,
                            child: Text(
                              t('auth.welcome', defaultValue: 'Welcome back'),
                              textAlign: textAlign,
                              style: MadarType.h2.copyWith(
                                color: c.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            t(
                              'auth.signInSubtitle',
                              defaultValue:
                                  'Sign in to your account to continue',
                            ),
                            textAlign: textAlign,
                            style: DashType.body.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.xxl),
                      DashTextField(
                        key: const ValueKey('signin-email'),
                        value: _email,
                        onChanged: (v) => setState(() => _email = v),
                        label: t('auth.email', defaultValue: 'Email address'),
                        placeholder: t(
                          'auth.emailPlaceholder',
                          defaultValue: 'you@madar.com',
                        ),
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v.isEmpty) {
                            return t(
                              'common.requiredField',
                              defaultValue: 'This field is required',
                            );
                          }
                          if (!_emailPattern.hasMatch(v)) {
                            return t(
                              'auth.errors.invalidEmail',
                              defaultValue: 'Enter a valid email',
                            );
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: Space.lg),
                      DashFormField<String>(
                        label: t('auth.password', defaultValue: 'Password'),
                        value: _password,
                        validator: (v) => v.isEmpty
                            ? t(
                                'common.requiredField',
                                defaultValue: 'This field is required',
                              )
                            : null,
                        builder: (context, invalid) => DashTextInput(
                          key: const ValueKey('signin-password'),
                          value: _password,
                          obscure: !_showPw,
                          invalid: invalid,
                          placeholder: '••••••••',
                          semanticLabel: t(
                            'auth.password',
                            defaultValue: 'Password',
                          ),
                          onChanged: (v) => setState(() => _password = v),
                          onSubmitted: (_) => _submit(),
                          trailing: DashIconButton(
                            icon: _showPw ? 'eye-off' : 'eye',
                            semanticLabel: _showPw
                                ? t(
                                    'auth.hidePassword',
                                    defaultValue: 'Hide password',
                                  )
                                : t(
                                    'auth.showPassword',
                                    defaultValue: 'Show password',
                                  ),
                            color: c.textSecondary,
                            onPressed: () => setState(() => _showPw = !_showPw),
                          ),
                        ),
                      ),
                      const SizedBox(height: Space.xl),
                      DashButton(
                        key: const ValueKey('signin-submit'),
                        label: t('auth.signIn', defaultValue: 'Sign in'),
                        icon: 'log-in',
                        loading: _busy,
                        expand: true,
                        onPressed: _submit,
                      ),
                      if (!wide) ...[
                        const SizedBox(height: Space.xxl),
                        Text(
                          copyrightLine(ref),
                          textAlign: TextAlign.center,
                          style: DashType.small.copyWith(color: c.textMuted),
                        ),
                      ],
                      SizedBox(height: wide ? Space.xxl : Space.xs),
                      const DashLegalLinks(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          PositionedDirectional(
            top: Space.lg,
            end: Space.lg,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ThemeMenu(color: c.textSecondary),
                LanguageToggle(color: c.textSecondary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The brand panel: the chrome's ink in both themes, set apart by a
/// hairline.
class _BrandPanel extends ConsumerWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final xl = MediaQuery.sizeOf(context).width >= DashBreakpoints.xl;
    final pad = xl ? Space.xxl * 2 : Space.xxl + Space.lg;
    return Container(
      decoration: BoxDecoration(
        color: c.chrome,
        border: BorderDirectional(end: BorderSide(color: c.sidebarBorder)),
      ),
      padding: EdgeInsets.all(pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: Space.md,
            children: [
              Container(
                width: SignInMetrics.tile,
                height: SignInMetrics.tile,
                padding: const EdgeInsets.all(Space.xs + DashMetrics.hair),
                decoration: BoxDecoration(
                  color: c.chromeAlt,
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: Border.all(color: c.sidebarBorder),
                ),
                child: const MadarSymbol(reversed: true),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('app.name', defaultValue: 'Madar'),
                      style: MadarType.h3.copyWith(color: c.onChrome),
                    ),
                    Text(
                      t('app.tagline', defaultValue: 'Coffee Shop Management'),
                      style: DashType.body.copyWith(color: c.onChromeMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: SignInMetrics.welcome),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t('auth.welcome', defaultValue: 'Welcome back'),
                  style: MadarType.display.copyWith(
                    color: c.onChrome,
                    fontSize: xl ? Space.xxl + Space.lg : Space.xxl + Space.xs,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: Space.lg),
                Text(
                  t(
                    'auth.signInSubtitle',
                    defaultValue: 'Sign in to your account to continue',
                  ),
                  style: MadarType.title.copyWith(
                    color: c.onChromeMuted,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.xxl),
          const Expanded(flex: 6, child: BrandOrbit()),
          const SizedBox(height: Space.xxl),
          Text(
            copyrightLine(ref),
            style: DashType.small.copyWith(color: c.onChromeMuted),
          ),
        ],
      ),
    );
  }
}

/// One part of the family on the orbit: ring radius (% of the stage), angle
/// (degrees, 0 = east).
class _Body {
  const _Body(this.key, this.fallback, this.r, this.deg, [this.icon]);
  final String key;
  final String fallback;
  final double r;
  final double deg;
  final String? icon;
}

const List<_Body> _bodies = [
  _Body('till', 'Till', 25, -70, 'receipt'),
  _Body('kitchen', 'Kitchen', 25, 110, 'chef-hat'),
  _Body('dashboard', 'Dashboard', 37, -160, 'layout-dashboard'),
  _Body('ordering', 'Ordering', 37, 20, 'shopping-bag'),
  _Body('rewards', 'Rewards', 48, -25, 'gift'),
  _Body('dawam', 'Dawam', 48, 155),
];

/// Madar means orbit (`orbit-2d.tsx`): Madar's mark at the centre, the
/// family's parts on hairline rings around it, Dawam among them with its own
/// mark. The rings turn once every 160 s and the labels counter-turn so they
/// stay upright; under reduced motion everything holds still. Decorative:
/// the words on the panel carry the meaning. The web draws this where its 3D
/// showcase cannot run; the app always draws it.
class BrandOrbit extends ConsumerStatefulWidget {
  const BrandOrbit({super.key});

  @override
  ConsumerState<BrandOrbit> createState() => _BrandOrbitState();
}

class _BrandOrbitState extends ConsumerState<BrandOrbit>
    with SingleTickerProviderStateMixin {
  late final AnimationController _turn = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 160),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (DashMotion.reduced(context)) {
      _turn.stop();
    } else if (!_turn.isAnimating) {
      _turn.repeat();
    }
  }

  @override
  void dispose() {
    _turn.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, box) {
          final side = math.min(
            SignInMetrics.orbit,
            math.min(box.maxWidth, MediaQuery.sizeOf(context).height * 0.5),
          );
          final s = box.hasBoundedHeight ? math.min(side, box.maxHeight) : side;
          return Center(
            child: SizedBox.square(
              dimension: s,
              child: AnimatedBuilder(
                animation: _turn,
                builder: (context, _) {
                  final a = _turn.value * 2 * math.pi;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Transform.rotate(
                          angle: a,
                          child: CustomPaint(
                            painter: _RingsPainter(
                              ring: c.onChrome.withValues(alpha: 0.1),
                              dot: c.brand,
                            ),
                          ),
                        ),
                      ),
                      for (final b in _bodies)
                        _place(
                          context,
                          b,
                          s,
                          a,
                          t('auth.orbit.${b.key}', defaultValue: b.fallback),
                        ),
                      Center(
                        child: MadarSymbol(size: Space.xxl * 2, reversed: true),
                      ),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _place(
    BuildContext context,
    _Body b,
    double side,
    double turn,
    String label,
  ) {
    final c = context.madarColors;
    // Physical geometry: the orbit is a picture, never mirrored.
    final a = b.deg * math.pi / 180 + turn;
    final x = side / 2 + side * b.r / 100 * math.cos(a);
    final y = side / 2 + side * b.r / 100 * math.sin(a);
    return Positioned(
      left: x,
      top: y,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Container(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.sm,
            Space.xs + DashMetrics.hair,
            Space.md,
            Space.xs + DashMetrics.hair,
          ),
          decoration: BoxDecoration(
            color: c.chromeAlt,
            borderRadius: BorderRadius.circular(Radii.pill),
            border: Border.all(color: c.sidebarBorder),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs + DashMetrics.hair,
            children: [
              if (b.icon != null)
                DashIcon(b.icon!, size: IconSize.xs, color: c.onChromeMuted)
              else
                const DawamSymbol(size: IconSize.xs, reversed: true),
              Text(
                label,
                style: DashType.smallMedium.copyWith(color: c.onChrome),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  const _RingsPainter({required this.ring, required this.dot});

  final Color ring;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / 200;
    final centre = size.center(Offset.zero);
    final stroke = Paint()
      ..color = ring
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, 0.5 * unit);
    for (final r in const [50.0, 74.0, 96.0]) {
      canvas.drawCircle(centre, r * unit, stroke);
    }
    canvas.drawCircle(
      Offset(centre.dx, 4 * unit),
      2.2 * unit,
      Paint()..color = dot,
    );
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.ring != ring || old.dot != dot;
}
