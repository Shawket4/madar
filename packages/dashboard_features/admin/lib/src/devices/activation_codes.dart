/// Device activation codes (web `features/devices/activation-codes.tsx`,
/// ADM-DEV-014..019): an owner issues an 8-digit, single-use code for the
/// branch; a tablet types it to bind itself. Only for `branches.edit`: the
/// section is absent and its list never read otherwise.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        ActivationCode,
        ActivationCodeState,
        CreateActivationCodeRequest,
        DeviceKind;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'devices_data.dart';
import 'devices_table.dart';

/// `STATE_TONE`.
DashTone activationStateTone(ActivationCodeState s) => switch (s.value) {
  'free' => DashTone.success,
  'used' => DashTone.neutral,
  'expired' => DashTone.warning,
  'revoked' => DashTone.danger,
  _ => DashTone.neutral,
};

String activationStateLabel(Translator t, ActivationCodeState s) {
  final key = 'devices.activation.states.${s.value}';
  return t.exists(key) ? t(key) : s.value;
}

class ActivationCodesSection extends ConsumerWidget {
  const ActivationCodesSection({required this.branchId, super.key});

  final String branchId;

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    ActivationCode code,
  ) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('devices.activation.revokeTitle'),
      description: t('devices.activation.revokeBody'),
      confirmLabel: t('devices.activation.revoke'),
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final api = ref.read(apiProvider);
    final invalidate = ref.devicesInvalidate;
    try {
      await api.devices.revokeCode(id: code.id);
      invalidate.codesChanged();
    } on Object catch (e) {
      if (context.mounted) DashToast.error(context, devicesErrorText(e, t));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canIssue = ref.watch(
      authzProvider.select((a) => a.can(Cap.branchesEdit)),
    );
    if (!canIssue) return const SizedBox.shrink();
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final q = ref.watch(activationCodesProvider(branchId));
    final error = q.shownError;
    return Semantics(
      container: true,
      label: t('devices.activation.title'),
      child: Column(
        key: const ValueKey('activation-codes'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          DashSectionHeader(
            title: t('devices.activation.title'),
            description: t('devices.activation.subtitle'),
            icon: 'key-round',
            trailing: DashButton(
              key: const ValueKey('issue-code'),
              label: t('devices.activation.issue'),
              icon: 'plus',
              size: DashButtonSize.compact,
              onPressed: () => showIssueCodeDialog(context, branchId),
            ),
          ),
          DashDataTable<ActivationCode>(
            key: const ValueKey('codes-table'),
            rows: q.value ?? const [],
            rowKey: (r) => r.id,
            loading: q.firstLoad,
            errorMessage: error == null ? null : devicesErrorText(error, t),
            onRetry: () => ref.invalidate(activationCodesProvider(branchId)),
            hideViewOptions: true,
            pageSize: 10,
            rowActionsWidth: DashMetrics.target * 2 + Space.xl,
            rowActions: (context, r) => r.state == ActivationCodeState.free
                ? DashButton(
                    key: ValueKey('revoke-${r.id}'),
                    label: t('devices.activation.revoke'),
                    variant: DashButtonVariant.ghost,
                    size: DashButtonSize.compact,
                    onPressed: () => _revoke(context, ref, r),
                  )
                : const SizedBox.shrink(),
            empty: DashEmptyState(
              icon: 'key-round',
              title: t('devices.activation.empty'),
              description: t('devices.activation.emptyHint'),
            ),
            columns: [
              DashColumn<ActivationCode>(
                id: 'code',
                label: t('devices.activation.code'),
                text: (r) => r.code,
                phone: DashPhoneRole.title,
                cell: (context, r) {
                  final free = r.state == ActivationCodeState.free;
                  return Text(
                    groupActivationCode(r.code),
                    key: ValueKey('activation-code-${r.id}'),
                    textDirection: TextDirection.ltr,
                    style: free
                        ? DashType.monoStrong.copyWith(
                            color: c.textPrimary,
                            fontSize: DashType.sectionTitle.fontSize,
                          )
                        : DashType.mono.copyWith(
                            color: c.textSecondary,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: c.textSecondary,
                          ),
                  );
                },
              ),
              DashColumn<ActivationCode>(
                id: 'label',
                label: t('devices.label'),
                text: (r) => r.label ?? '',
                cell: (context, r) => r.label == null
                    ? const DevicesDash()
                    : MadarClippedText(
                        r.label!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashType.body.copyWith(color: c.textPrimary),
                      ),
              ),
              DashColumn<ActivationCode>(
                id: 'kind',
                label: t('devices.kind'),
                text: (r) => deviceKindLabel(t, r.kind),
              ),
              DashColumn<ActivationCode>(
                id: 'state',
                label: t('common.status'),
                text: (r) => activationStateLabel(t, r.state),
                cell: (context, r) => Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: DashStatusPill(
                    label: activationStateLabel(t, r.state),
                    tone: activationStateTone(r.state),
                    small: true,
                  ),
                ),
              ),
              DashColumn<ActivationCode>(
                id: 'when',
                label: t('devices.activation.when'),
                numeric: true,
                text: (r) =>
                    fmt.fmtStamp(r.usedAt ?? r.revokedAt ?? r.expiresAt),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens the New code dialog for [branchId].
Future<void> showIssueCodeDialog(BuildContext host, String branchId) =>
    showDashDialog<void>(
      host,
      builder: (_) => IssueCodeDialog(branchId: branchId, host: host),
    );

/// The New activation code dialog: a name and a type, then the issued code
/// itself, large, with Done.
class IssueCodeDialog extends ConsumerStatefulWidget {
  const IssueCodeDialog({required this.branchId, this.host, super.key});

  final String branchId;
  final BuildContext? host;

  @override
  ConsumerState<IssueCodeDialog> createState() => _IssueCodeDialogState();
}

class _IssueCodeDialogState extends ConsumerState<IssueCodeDialog> {
  String _label = '';
  DeviceKind _kind = DeviceKind.pos;
  bool _busy = false;
  ActivationCode? _issued;

  Future<void> _issue() async {
    if (_busy) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final invalidate = ref.devicesInvalidate;
    final label = _label.trim();
    setState(() => _busy = true);
    try {
      final code = await api.devices.createCode(
        body: CreateActivationCodeRequest(
          branchId: widget.branchId,
          label: label.isEmpty ? null : label,
          kind: _kind,
          explicitNulls: label.isEmpty ? const {'label'} : const {},
        ),
      );
      invalidate.codesChanged();
      if (mounted) {
        setState(() {
          _busy = false;
          _issued = code;
        });
      }
    } on Object catch (e) {
      final at = mounted ? context : widget.host;
      if (at != null && at.mounted) {
        DashToast.error(at, devicesErrorText(e, t));
      }
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final issued = _issued;
    final close = DashButton(
      key: const ValueKey('issue-cancel'),
      label: t('common.cancel'),
      variant: DashButtonVariant.outline,
      onPressed: () => Navigator.of(context).maybePop(),
    );
    return DashSurface(
      title: t('devices.activation.issueTitle'),
      description: t('devices.activation.issueHint'),
      body: issued != null
          ? Container(
              key: const ValueKey('issued-code'),
              padding: const EdgeInsets.symmetric(vertical: Space.card),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: c.border),
              ),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  groupActivationCode(issued.code),
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.center,
                  style: DashType.statFigure(DashType.pageTitle.fontSize!)
                      .copyWith(
                        color: c.textPrimary,
                        letterSpacing: DashType.pageTitle.fontSize! * 0.2,
                      ),
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.lg,
              children: [
                DashTextField(
                  key: const ValueKey('code-label'),
                  label: t('devices.activation.labelField'),
                  placeholder: t('devices.activation.labelPlaceholder'),
                  value: _label,
                  maxLength: 120,
                  autofocus: true,
                  onChanged: (v) => setState(() => _label = v),
                  onSubmitted: (_) => _issue(),
                ),
                DashSelectField<DeviceKind>(
                  key: const ValueKey('code-kind'),
                  label: t('devices.kind'),
                  value: _kind,
                  options: [
                    for (final k in DeviceKind.values)
                      DashOption(value: k, label: deviceKindLabel(t, k)),
                  ],
                  onChanged: (k) => setState(() => _kind = k),
                ),
              ],
            ),
      actions: issued != null
          ? [
              DashButton(
                key: const ValueKey('issue-done'),
                label: t('common.done'),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ]
          : [
              close,
              DashButton(
                key: const ValueKey('issue-submit'),
                label: t('devices.activation.issue'),
                loading: _busy,
                onPressed: _issue,
              ),
            ],
    );
  }
}
