/// The handoff after an issue or a rotation (`handoff-dialog.tsx` +
/// `use-credential-handoff.ts`, SET-INT-020..026, 032).
///
/// One dialog is one passphrase: it is drawn once when the dialog opens and
/// never again (a retry rebuilds the archive with the same one). The
/// partner's password is never rendered, never copied and never cached: it
/// lives in this state and inside the encrypted archive. It is not scrubbed
/// from memory; nothing here claims more.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show CredentialWithSecret;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'credential_util.dart';
import 'handoff_content.dart';
import 'handoff_zip.dart';
import 'secure_random.dart';

/// The dialog's width (`sm:max-w-[560px]`).
const double handoffDialogWidth = 560;

/// What was just issued: the one-time secret and whether it is new.
typedef IssuedCredential = ({
  CredentialWithSecret credential,
  HandoffMode mode,
});

/// Where the archive is in its life.
enum HandoffStatus { building, ready, failed }

/// Opens the handoff for [issued]; resolves when it closes.
Future<void> showHandoffDialog(BuildContext context, IssuedCredential issued) =>
    showDashDialog<void>(
      context,
      width: handoffDialogWidth,
      builder: (_) => HandoffDialog(issued: issued),
    );

class HandoffDialog extends ConsumerStatefulWidget {
  const HandoffDialog({required this.issued, super.key});

  final IssuedCredential issued;

  /// How long the Copy button shows its check.
  static const Duration copiedFor = Duration(milliseconds: 1500);

  @override
  ConsumerState<HandoffDialog> createState() => _HandoffDialogState();
}

class _HandoffDialogState extends ConsumerState<HandoffDialog> {
  /// Drawn once. A device without a secure source gets none, and the build
  /// reports it through the failed state instead of throwing here.
  final String _passphrase = () {
    try {
      return generatePassphrase();
    } on InsecureRandomError {
      return '';
    }
  }();

  HandoffStatus _status = HandoffStatus.building;
  Object? _error;

  /// 0 = the person has not got the file yet: closing asks first.
  int _downloads = 0;
  List<int>? _bytes;
  String _filename = '';
  bool _copied = false;
  Timer? _copiedReset;
  bool _closing = false;

  CredentialWithSecret get _credential => widget.issued.credential;

  @override
  void initState() {
    super.initState();
    unawaited(_build());
  }

  @override
  void dispose() {
    _copiedReset?.cancel();
    super.dispose();
  }

  /// Builds the archive and saves it (the web's automatic download).
  Future<void> _build() async {
    if (_status != HandoffStatus.building) {
      setState(() {
        _status = HandoffStatus.building;
        _error = null;
      });
    }
    final files = ref.read(fileGatewayProvider);
    final now = ref.read(clockProvider);
    try {
      if (_passphrase.isEmpty) throw const InsecureRandomError();
      final issuedAt = now();
      final bytes = await HandoffZipBuilder.run(
        buildHandoffFiles(
          HandoffInput(
            label: _credential.name,
            username: _credential.username,
            secret: _credential.secret,
            branchName: _credential.branchName,
            issuedAt: issuedAt,
            mode: widget.issued.mode,
          ),
        ),
        _passphrase,
      );
      _bytes = bytes;
      _filename = handoffFilename(_credential.username, issuedAt);
      final saved = await files.saveBytes(
        bytes,
        filename: _filename,
        mimeType: zipMimeType,
      );
      if (!mounted) return;
      setState(() {
        if (saved != null) _downloads++;
        _status = HandoffStatus.ready;
      });
    } on Object catch (e) {
      // Recoverable: the secret is still here, so Try again can rebuild.
      if (!mounted) return;
      setState(() {
        _error = e;
        _status = HandoffStatus.failed;
      });
    }
  }

  Future<void> _downloadAgain() async {
    final bytes = _bytes;
    if (bytes == null) return;
    final t = ref.read(tProvider);
    try {
      final saved = await ref
          .read(fileGatewayProvider)
          .saveBytes(bytes, filename: _filename, mimeType: zipMimeType);
      if (saved != null && mounted) setState(() => _downloads++);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    }
  }

  Future<void> _copy() async {
    final t = ref.read(tProvider);
    try {
      await Clipboard.setData(ClipboardData(text: _passphrase));
    } on Object {
      if (mounted) {
        DashToast.error(context, t('integrations.handoff.copyFailed'));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedReset?.cancel();
    _copiedReset = Timer(HandoffDialog.copiedFor, () {
      if (mounted) setState(() => _copied = false);
    });
  }

  /// Done, Escape, ×, a tap outside: closing destroys the only copy of the
  /// password, so it is deliberate while the file was never saved.
  Future<void> _requestClose() async {
    if (_closing) return;
    _closing = true;
    try {
      if (_downloads == 0) {
        final t = ref.read(tProvider);
        final ok = await showDashConfirm(
          context,
          title: t('integrations.handoff.closeTitle'),
          description: t('integrations.handoff.closeHint'),
          confirmLabel: t('integrations.handoff.closeAnyway'),
          destructive: true,
        );
        if (!ok) return;
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      _closing = false;
    }
  }

  /// The failure's words: a missing secure source says why in the active
  /// language; anything else is the error's own words.
  String _failureText(Translator t) => _error is InsecureRandomError
      ? t('integrations.handoff.noSecureRandom')
      : errorMessage(_error, t);

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final rotated = widget.issued.mode == HandoffMode.rotated;
    final name = {'name': _credential.name};
    final building = _status == HandoffStatus.building;
    final ready = _status == HandoffStatus.ready;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose());
      },
      child: DashSurface(
        key: const ValueKey('handoff-dialog'),
        title: rotated
            ? t('integrations.handoff.rotatedTitle', args: name)
            : t('integrations.handoff.createdTitle', args: name),
        description: rotated
            ? t('integrations.handoff.rotatedHint')
            : t('integrations.handoff.createdHint'),
        onClose: _requestClose,
        actions: [
          DashButton(
            key: const ValueKey('handoff-download'),
            label: t('integrations.handoff.downloadAgain'),
            icon: 'download',
            variant: DashButtonVariant.outline,
            loading: building,
            onPressed: ready ? _downloadAgain : null,
          ),
          DashButton(
            key: const ValueKey('handoff-done'),
            label: t('common.done'),
            onPressed: _requestClose,
          ),
        ],
        body: _status == HandoffStatus.failed
            ? _Failed(text: _failureText(t), onRetry: () => unawaited(_build()))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.lg,
                children: [
                  _Passphrase(
                    text: building
                        ? t('integrations.handoff.building')
                        : _passphrase,
                    copied: _copied,
                    onCopy: ready ? _copy : null,
                  ),
                  _Steps(
                    steps: [
                      t('integrations.handoff.step1'),
                      t('integrations.handoff.step2'),
                      t('integrations.handoff.step3'),
                    ],
                  ),
                  HandoffPanel(
                    tone: DashTone.warning,
                    children: [Text(t('integrations.handoff.warning'))],
                  ),
                ],
              ),
      ),
    );
  }
}

/// "Password for the file", the passphrase (or "Preparing…") and Copy.
class _Passphrase extends ConsumerWidget {
  const _Passphrase({
    required this.text,
    required this.copied,
    required this.onCopy,
  });

  final String text;
  final bool copied;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xs,
      children: [
        Text(
          t('integrations.handoff.passphrase'),
          style: DashType.smallStrong.copyWith(color: c.textSecondary),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.sm,
          children: [
            Expanded(
              child: Container(
                key: const ValueKey('handoff-passphrase'),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.md,
                ),
                decoration: BoxDecoration(
                  color: c.muted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(Radii.control),
                  border: Border.all(color: c.hairline),
                ),
                // A code read aloud: left to right in both languages.
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: SelectableText(
                    text,
                    style: DashType.monoMedium.copyWith(
                      color: c.textPrimary,
                      // `tracking-widest`: 0.1em.
                      letterSpacing: DashType.monoMedium.fontSize! * 0.1,
                    ),
                  ),
                ),
              ),
            ),
            DashIconButton(
              key: const ValueKey('handoff-copy'),
              icon: copied ? 'check' : 'copy',
              color: copied ? DashTone.success.foreground(c) : null,
              semanticLabel: t('common.copy'),
              variant: DashButtonVariant.outline,
              onPressed: onCopy,
            ),
          ],
        ),
      ],
    );
  }
}

/// The numbered steps (`<ol class="list-decimal">`).
class _Steps extends StatelessWidget {
  const _Steps({required this.steps});

  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final style = DashType.small.copyWith(color: c.textPrimary, height: 1.6);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          for (var i = 0; i < steps.length; i++)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.xs,
              children: [
                Text(ltr('${i + 1}.'), style: style),
                Expanded(child: Text(steps[i], style: style)),
              ],
            ),
        ],
      ),
    );
  }
}

/// The red "could not build the file" panel and its Try again.
class _Failed extends ConsumerWidget {
  const _Failed({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        HandoffPanel(
          key: const ValueKey('handoff-failed'),
          tone: DashTone.danger,
          children: [
            Text(
              t('integrations.handoff.failedTitle'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(t('integrations.handoff.failedHint')),
            Text(text, style: DashType.small.copyWith(color: c.textSecondary)),
          ],
        ),
        DashButton(
          key: const ValueKey('handoff-retry'),
          label: t('integrations.handoff.retry'),
          expand: true,
          onPressed: onRetry,
        ),
      ],
    );
  }
}

/// A tone-washed notice with a warning glyph (`border-x/30 bg-x/10`).
class HandoffPanel extends StatelessWidget {
  const HandoffPanel({required this.tone, required this.children, super.key});

  final DashTone tone;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: tone.wash(c),
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: tone.solid(c).withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          DashIcon(
            'triangle-alert',
            size: IconSize.sm,
            color: tone.foreground(c),
          ),
          Expanded(
            child: DefaultTextStyle.merge(
              style: DashType.small.copyWith(color: c.textPrimary, height: 1.6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: Space.xs,
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
