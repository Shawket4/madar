/// "New integration credential" (`credential-dialog.tsx`, SET-INT-015..019):
/// a label, the one branch the partner may read, and a generated username.
/// Issuing hands the one-time secret back to the pane, which opens the
/// handoff; nothing here ever shows it.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'credential_util.dart';
import 'integrations_data.dart';
import 'secure_random.dart';

/// The dialog's width (`sm:max-w-[480px]`).
const double credentialDialogWidth = 480;

/// The label's longest form (`z.string().trim().max(120)`).
const int credentialLabelMax = 120;

/// Opens the issue dialog; resolves with the created credential (secret
/// included) or null when it was closed without issuing.
Future<CredentialWithSecret?> showCredentialDialog(BuildContext context) =>
    showDashDialog<CredentialWithSecret>(
      context,
      width: credentialDialogWidth,
      builder: (_) => const CredentialDialog(),
    );

class CredentialDialog extends ConsumerStatefulWidget {
  const CredentialDialog({super.key});

  @override
  ConsumerState<CredentialDialog> createState() => _CredentialDialogState();
}

class _CredentialDialogState extends ConsumerState<CredentialDialog> {
  final _form = GlobalKey<FormState>();
  String _name = '';
  String? _branchId;
  bool _busy = false;

  /// Only the random tail is state: typing re-slugs the readable prefix
  /// without churning it, and Regenerate stays a deliberate act. Each open
  /// is a fresh dialog, so a fresh suffix (SET-INT-015).
  late String _suffix = _newSuffix();

  /// A device without a secure source still opens the dialog; Issue then
  /// refuses with the reason (SET-INT-019).
  static String _newSuffix() {
    try {
      return randomUsernameSuffix();
    } on InsecureRandomError {
      return '';
    }
  }

  String get _username => buildUsername(_name, _suffix);

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final t = ref.read(tProvider);
    // Refuse before creating anything: a credential that cannot be handed
    // off exists server-side with a lost password.
    if (!IntegrationsRandom.available) {
      DashToast.error(context, t('integrations.handoff.noSecureRandom'));
      return;
    }
    final name = _name.trim();
    final branchId = _branchId!;
    final api = ref.read(apiProvider);
    setState(() => _busy = true);
    try {
      var attempt = _username;
      for (var tries = 0; ; tries++) {
        try {
          final created = await api.integrations.createCredential(
            body: CreateCredentialRequest(
              branchId: branchId,
              name: name,
              username: attempt,
            ),
          );
          invalidateCredentials(ref);
          if (mounted) Navigator.of(context).pop(created);
          return;
        } on ApiException catch (e) {
          // The suffix is random, so a 409 is a vanishingly rare collision:
          // draw another and retry once, silently.
          if (e.status != 409 || tries >= 1) rethrow;
          final next = randomUsernameSuffix();
          if (mounted) setState(() => _suffix = next);
          attempt = buildUsername(name, next);
        }
      }
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final branches = [
      for (final b in ref.watch(branchesProvider).value ?? const <Branch>[])
        if (b.isActive) b,
    ];
    final wide = DashSurfaceScope.maybeOf(context) != DashSurfaceMode.fullScreen;
    return DashSurface(
      title: t('integrations.newTitle'),
      description: t('integrations.newHint'),
      onClose: _busy ? () {} : null,
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
        ),
        DashButton(
          label: t('integrations.issue'),
          onPressed: _busy ? null : _submit,
        ),
      ],
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            DashTextField(
              key: const ValueKey('integrations.label'),
              label: t('integrations.label'),
              placeholder: t('integrations.labelPlaceholder'),
              description: t('integrations.labelHint'),
              value: _name,
              autofocus: wide,
              onChanged: (v) => setState(() => _name = v),
              onSubmitted: (_) => _submit(),
              validator: (v) {
                final s = v.trim();
                if (s.isEmpty) return t('common.requiredField');
                if (s.length > credentialLabelMax) {
                  return t(
                    'common.atMostChars',
                    args: {'n': credentialLabelMax},
                  );
                }
                return null;
              },
            ),
            DashSelectField<String>(
              key: const ValueKey('integrations.branch'),
              label: t('integrations.branch'),
              placeholder: t('integrations.branchPlaceholder'),
              description: t('integrations.branchHint'),
              value: _branchId,
              options: [
                for (final b in branches)
                  DashOption(value: b.id, label: b.name),
              ],
              onChanged: (v) => setState(() => _branchId = v),
              validator: (v) =>
                  v == null ? t('integrations.branchRequired') : null,
            ),
            DashFormField<String>(
              label: t('integrations.username'),
              description: t('integrations.usernameHint'),
              builder: (context, invalid) => Row(
                spacing: Space.sm,
                children: [
                  Expanded(child: _ReadOnlyMono(_username)),
                  DashIconButton(
                    icon: 'refresh-cw',
                    semanticLabel: t('integrations.regenerate'),
                    variant: DashButtonVariant.outline,
                    onPressed: () => setState(() => _suffix = _newSuffix()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The generated username: a read-only field, left to right, mono
/// (`<Input readOnly dir="ltr" className="font-mono text-xs">`).
class _ReadOnlyMono extends StatelessWidget {
  const _ReadOnlyMono(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashFieldShell(
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.centerLeft,
          child: SelectableText(
            text,
            maxLines: 1,
            style: DashType.mono.copyWith(
              fontSize: DashType.small.fontSize,
              color: c.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
