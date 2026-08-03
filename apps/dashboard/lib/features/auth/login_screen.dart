import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart';

import '../../app/providers.dart';

/// Email/password sign-in for the dashboard. On success the router redirect
/// carries the user into the app; errors surface inline (core-localized).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .signIn(_email.text.trim(), _password.text);
      // Router redirect handles navigation on the session change.
    } on MadarError catch (e) {
      final msg = ref.read(coreProvider).bridge.humanMessage(e);
      if (mounted) setState(() => _error = msg);
    } on Object catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = ref.watch(tProvider);
    return Scaffold(
      backgroundColor: c.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Responsive.formMaxWidth,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: MadarSymbol(size: 56)),
                const SizedBox(height: Space.xl),
                Text(
                  t('login.title'),
                  style: MadarType.h1.copyWith(color: c.textPrimary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.xs),
                Text(
                  t('login.subtitle'),
                  style: MadarType.body.copyWith(color: c.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: Space.xl),
                _Field(
                  controller: _email,
                  label: t('login.email'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                ),
                const SizedBox(height: Space.md),
                _Field(
                  controller: _password,
                  label: t('login.password'),
                  obscure: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => _submit(),
                ),
                if (_error case final error?) ...[
                  const SizedBox(height: Space.md),
                  Text(
                    error,
                    style: MadarType.bodySm.copyWith(color: c.danger),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: Space.xl),
                SizedBox(
                  height: Metrics.buttonHeight,
                  child: FilledButton(
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: c.textOnAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            t('login.submit'),
                            style: MadarType.title.copyWith(
                              color: c.textOnAccent,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<String>? autofillHints;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      onSubmitted: onSubmitted,
      style: MadarType.body.copyWith(color: c.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: MadarType.body.copyWith(color: c.textMuted),
        filled: true,
        fillColor: c.surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.md),
          borderSide: BorderSide(color: c.accent, width: 2),
        ),
      ),
    );
  }
}
