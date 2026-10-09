/// `/settings/integrations` Integrations (`features/integrations/
/// integrations-page.tsx`, SET-INT rows): the partner credentials that read
/// one branch's order analytics.
///
/// A shop may AUDIT the list (`integrations.read`); issuing, rotating and
/// revoking are Madar's (platform admins), and the backend refuses them for
/// anyone else, so nobody else is shown a button that will only fail.
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane: a section heading, no page gutter.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart'
    show CredentialSummary, CredentialWithSecret;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/scope.dart';
import 'credential_dialog.dart';
import 'handoff_content.dart' show HandoffMode;
import 'handoff_dialog.dart';
import 'integrations_data.dart';
import 'secure_random.dart';

class IntegrationsPage extends ConsumerStatefulWidget {
  const IntegrationsPage({this.edit, super.key});

  /// `?edit=new` (SET-SHL-012, SET-INT-014): the issue dialog, platform
  /// admins only.
  final String? edit;

  @override
  ConsumerState<IntegrationsPage> createState() => _IntegrationsPageState();
}

class _IntegrationsPageState extends ConsumerState<IntegrationsPage> {
  /// The issue dialog is up (opened from `?edit=new`).
  bool _dialogOpen = false;

  /// `usePageSearch().update({edit})`: the param replaced in place, the
  /// scope params kept.
  void _setEdit(String? value) {
    final uri = GoRouterState.of(context).uri;
    final q = Map<String, String>.of(uri.queryParameters)..remove('edit');
    if (value != null) q['edit'] = value;
    context.go(
      Uri(path: uri.path, queryParameters: q.isEmpty ? null : q).toString(),
    );
  }

  /// Opens the issue dialog `?edit=new` asks for, once, for a platform admin
  /// only (anyone else typing it sees nothing, and the param stays, as on
  /// the web). Closing it removes the param; issuing opens the handoff.
  void _syncDialog({required bool platform}) {
    if (_dialogOpen || widget.edit != 'new' || !platform) return;
    _dialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final created = await showCredentialDialog(context);
      _dialogOpen = false;
      if (!mounted) return;
      if (GoRouterState.of(context).uri.queryParameters['edit'] != null) {
        _setEdit(null);
      }
      if (created != null) {
        await showHandoffDialog(context, (
          credential: created,
          mode: HandoffMode.created,
        ));
      }
    });
  }

  Future<void> _rotate(CredentialSummary c) async {
    final t = ref.read(tProvider);
    // Never mint a password that cannot be packaged into a handoff file.
    if (!IntegrationsRandom.available) {
      DashToast.error(context, t('integrations.handoff.noSecureRandom'));
      return;
    }
    final ok = await showDashConfirm(
      context,
      title: t('integrations.rotateTitle'),
      description: t('integrations.rotateHint', args: {'name': c.name}),
      confirmLabel: t('integrations.rotate'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    final CredentialWithSecret next;
    try {
      next = await api.integrations.rotateCredential(id: c.id);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
      return;
    }
    invalidateCredentials(bus);
    if (mounted) {
      await showHandoffDialog(context, (
        credential: next,
        mode: HandoffMode.rotated,
      ));
    }
  }

  Future<void> _revoke(CredentialSummary c) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('integrations.revokeTitle'),
      description: t('integrations.revokeHint', args: {'name': c.name}),
      confirmLabel: t('integrations.revoke'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    try {
      await api.integrations.revokeCredential(id: c.id);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
      return;
    }
    invalidateCredentials(bus);
    if (mounted) DashToast.success(context, t('integrations.revoked'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final title = t('integrations.title');
    final authz = ref.watch(authzProvider);
    // The grants decide what shows: nothing (or the access error) until
    // they are known, never a lock flashing first (SET-INT-031).
    if (!authz.ready) {
      return authz.error == null
          ? const SizedBox.shrink()
          : const AuthzLoadError();
    }
    if (!authz.can(Cap.integrationsRead)) {
      return SetupRefusalPane(
        key: const ValueKey('integrations-restricted'),
        title: title,
        stateTitle: t('common.restrictedTitle'),
        message: t('common.restrictedBody'),
      );
    }
    if (ref.watch(orgIdProvider) == null) {
      return DashPageScaffold(
        title: title,
        width: DashPageWidth.reading,
        body: DashEmptyState(
          key: const ValueKey('integrations-pick-org'),
          icon: 'plug',
          title: t('users.pickOrg'),
        ),
      );
    }
    final platform = authz.platform;
    _syncDialog(platform: platform);
    final q = ref.watch(integrationCredentialsProvider);
    final rows = q.value ?? const <CredentialSummary>[];
    return DashPageScaffold(
      title: title,
      subtitle: t(platform ? 'integrations.hint' : 'integrations.hintReadOnly'),
      width: DashPageWidth.reading,
      actions: [
        if (platform)
          DashButton(
            key: const ValueKey('integrations-issue'),
            label: t('integrations.issue'),
            icon: 'plus',
            // The dialog lists the org's branches.
            onIntent: () => ref.warm(branchesProvider),
            onPressed: () => _setEdit('new'),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          if (!q.failedFirst) _Stats(rows: rows, loading: q.awaitingFirst),
          _CredentialsTable(
            rows: rows,
            loading: q.awaitingFirst,
            errorText: q.failedFirst ? errorMessage(q.error, t) : null,
            retrying: q.isLoading,
            onRetry: () => ref.invalidate(integrationCredentialsProvider),
            onRotate: platform ? _rotate : null,
            onRevoke: platform ? _revoke : null,
          ),
        ],
      ),
    );
  }
}

/// Total, Active, Revoked: three columns at every width.
class _Stats extends ConsumerWidget {
  const _Stats({required this.rows, required this.loading});

  final List<CredentialSummary> rows;
  final bool loading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final active = rows.where((c) => !isRevoked(c)).length;
    final cards = [
      DashStatCard(
        key: const ValueKey('integrations-total'),
        label: t('common.total'),
        value: rows.length,
        loading: loading,
      ),
      DashStatCard(
        key: const ValueKey('integrations-active'),
        label: t('common.active'),
        value: active,
        loading: loading,
      ),
      DashStatCard(
        key: const ValueKey('integrations-revoked'),
        label: t('integrations.revokedStatus'),
        value: rows.length - active,
        loading: loading,
      ),
    ];
    // ponytail: the kit's stat skeleton has fixed widths that overflow a
    // phone's third of a row; a fluid one stands in there until the kit's
    // fits (kit candidate).
    return LayoutBuilder(
      builder: (context, box) {
        final narrow =
            loading &&
            (box.maxWidth - Space.md * 2) / cards.length < _statSkeletonFits;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              for (final c in cards)
                Expanded(child: narrow ? const _NarrowStatSkeleton() : c),
            ],
          ),
        );
      },
    );
  }
}

/// The narrowest card the kit's stat skeleton fits (its 96-wide figure
/// bar inside the card's padding).
const double _statSkeletonFits = 96 + Space.card * 2;

/// A loading stat card whose bars follow the card's width.
class _NarrowStatSkeleton extends StatelessWidget {
  const _NarrowStatSkeleton();

  @override
  Widget build(BuildContext context) => const DashCard(
    key: ValueKey('integrations-stat-skeleton'),
    padding: EdgeInsets.all(Space.lg),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        DashSkeleton(height: Space.card),
        DashSkeleton(height: Space.xxl),
      ],
    ),
  );
}

class _CredentialsTable extends ConsumerWidget {
  const _CredentialsTable({
    required this.rows,
    required this.loading,
    required this.errorText,
    required this.retrying,
    required this.onRetry,
    required this.onRotate,
    required this.onRevoke,
  });

  final List<CredentialSummary> rows;
  final bool loading;
  final String? errorText;
  final bool retrying;
  final VoidCallback onRetry;

  /// Null for a viewer who may only audit: no actions at all.
  final ValueChanged<CredentialSummary>? onRotate;
  final ValueChanged<CredentialSummary>? onRevoke;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final rotate = onRotate, revoke = onRevoke;
    return DashDataTable<CredentialSummary>(
      key: const ValueKey('integrations-table'),
      rows: rows,
      rowKey: (r) => r.id,
      loading: loading,
      errorMessage: errorText,
      retrying: retrying,
      onRetry: onRetry,
      hideViewOptions: true,
      searchPlaceholder: t('common.search'),
      rowSemanticLabel: (r) => r.name,
      empty: DashEmptyState(
        icon: 'key-round',
        title: t('integrations.emptyTitle'),
        description: t('integrations.emptyHint'),
      ),
      rowActions: rotate == null || revoke == null
          ? null
          : (context, r) => isRevoked(r)
                // A revoked credential is a permanent audit record.
                ? const SizedBox.shrink()
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DashIconButton(
                        key: ValueKey('integrations-rotate-${r.id}'),
                        icon: 'refresh-cw',
                        semanticLabel: t('integrations.rotate'),
                        onPressed: () => rotate(r),
                      ),
                      DashIconButton(
                        key: ValueKey('integrations-revoke-${r.id}'),
                        icon: 'trash-2',
                        color: DashTone.danger.foreground(c),
                        semanticLabel: t('integrations.revoke'),
                        onPressed: () => revoke(r),
                      ),
                    ],
                  ),
      rowActionsWidth: (DashMetrics.target + Space.xs) * 2,
      columns: [
        DashColumn<CredentialSummary>(
          id: 'name',
          label: t('integrations.label'),
          phone: DashPhoneRole.title,
          flex: 2,
          minWidth: 180,
          // Searched by the label only, not the username under it.
          text: (r) => r.name,
          cell: (context, r) => _LabelCell(credential: r),
        ),
        DashColumn<CredentialSummary>(
          id: 'branch_name',
          label: t('integrations.branch'),
          text: (r) => r.branchName,
        ),
        DashColumn<CredentialSummary>(
          id: 'last_used_at',
          label: t('integrations.lastUsed'),
          minWidth: 190,
          // The raw timestamp, as TanStack searches it (SET-INT-007).
          searchable: lastUsedSearchable(rows),
          text: (r) => r.lastUsedAt == null ? '' : isoString(r.lastUsedAt!),
          cell: (context, r) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: r.lastUsedAt == null
                ? Text(
                    t('integrations.never'),
                    style: DashType.body.copyWith(color: c.textSecondary),
                  )
                : Text(
                    fmt.fmtDateTime(r.lastUsedAt),
                    style: DashType.mono.copyWith(color: c.textPrimary),
                  ),
          ),
        ),
        DashColumn<CredentialSummary>(
          id: 'status',
          label: t('common.status'),
          searchable: false,
          cell: (context, r) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: isRevoked(r)
                ? DashStatusPill(label: t('integrations.revokedStatus'))
                : DashStatusPill(
                    label: t('common.active'),
                    tone: DashTone.success,
                  ),
          ),
        ),
      ],
    );
  }
}

/// The label in bold and, under it, the username (left to right, mono).
class _LabelCell extends StatelessWidget {
  const _LabelCell({required this.credential});

  final CredentialSummary credential;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MadarClippedText(
          credential.name,
          textDirection: dashTextDirectionOf(credential.name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashType.bodyStrong.copyWith(color: c.textPrimary),
        ),
        MadarClippedText(
          credential.username,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textDirection: TextDirection.ltr,
          style: DashType.mono.copyWith(
            fontSize: DashType.small.fontSize,
            color: c.textSecondary,
          ),
        ),
      ],
    );
  }
}
