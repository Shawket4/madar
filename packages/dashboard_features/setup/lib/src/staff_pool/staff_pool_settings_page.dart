/// `/settings/staff-pool` Staff drinks (SET-SPL-001 … 022; web
/// `features/staff-pool/staff-pool-settings-page.tsx`): how many drinks a
/// branch may give its own people in a day, and which items count, for the
/// organisation ("All branches") or the header branch's own override.
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane. It refuses in place without
/// `org.settings.read`/`.edit` and asks nothing (SET-SPL-001); a reader sees
/// every control disabled and no Save (SET-SPL-005).
library;

import 'package:dashboard_api/dashboard_api.dart' show StaffPoolSettings;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/scope.dart';
import '../shared/setup_note.dart';
import 'eligible_items_control.dart';
import 'staff_pool_data.dart';

/// No web `prefetchRoute` case: resting on the settings rail row warms the
/// page's reads for the header scope (SET-SPL intent).
void prefetchStaffPool(DashPrefetcher warm, Scope s) =>
    warm(staffPoolWarmProvider((orgId: s.orgId, branchId: s.branchId)));

class StaffPoolSettingsPage extends ConsumerWidget {
  const StaffPoolSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    final title = t('staffPool.settingsTitle');
    final canRead =
        authz.can(Cap.orgSettingsRead) || authz.can(Cap.orgSettingsEdit);
    if (authz.ready && !canRead) {
      return SetupRefusalPane(
        key: const ValueKey('spl-restricted'),
        title: title,
        stateTitle: t('common.restrictedTitle'),
        message: t('staffPool.noAccess'),
      );
    }
    if (!authz.ready && authz.error != null) return const AuthzLoadError();
    final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
    return DashPageScaffold(
      title: title,
      subtitle: t('staffPool.settingsSubtitle'),
      width: DashPageWidth.reading,
      // Keyed by branch: switching it reloads the form rather than leave the
      // previous branch's numbers on screen (SET-SPL-020).
      body: StaffPoolSettingsForm(
        key: ValueKey('spl-form-$branchId'),
        branchId: branchId,
      ),
    );
  }
}

/// The skeleton cards' heights (`h-28`, `h-48`).
const double _skeletonTop = Space.xxl * 3.5;
const double _skeletonBottom = Space.xxl * 6;

/// The pricing rule's measure (`max-w-[70ch]` at 12 px).
const double _ruleMeasure = Space.xxl * 15;

class StaffPoolSettingsForm extends ConsumerStatefulWidget {
  const StaffPoolSettingsForm({required this.branchId, super.key});

  final String? branchId;

  @override
  ConsumerState<StaffPoolSettingsForm> createState() =>
      _StaffPoolSettingsFormState();
}

class _StaffPoolSettingsFormState extends ConsumerState<StaffPoolSettingsForm> {
  /// The answer [_base] was filled from; [_form] is what is on screen.
  /// Until the person changes it, a refreshed answer refills both.
  StaffPoolSettings? _from;
  StaffPoolForm? _base;
  StaffPoolForm? _form;

  /// A Save was attempted: errors show, and follow each change after.
  bool _submitted = false;
  bool _saving = false;

  /// Retry with no organisation in scope asks anyway (TanStack's `refetch`
  /// runs a disabled query), and the server says why it cannot answer.
  bool _forced = false;

  bool get _dirty => _form != _base;

  void _follow(StaffPoolSettings s) {
    if (identical(s, _from)) return;
    _from = s;
    if (_form != null && _dirty) return;
    _base = _form = StaffPoolForm.from(s);
  }

  void _edit(StaffPoolForm next) => setState(() => _form = next);

  Future<void> _save(String orgId) async {
    final f = _form!;
    setState(() => _submitted = true);
    if (!allowanceOk(f.allowance)) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).staffPool;
    // Captured before the await: the pane may close mid-save, and the
    // re-read still runs (the web's query refetches regardless).
    final container = ProviderScope.containerOf(context, listen: false);
    final key = staffPoolSettingsProvider(widget.branchId);
    setState(() => _saving = true);
    final StaffPoolSettings saved;
    try {
      saved = await api.putStaffPoolSettings(
        body: f.toWire(orgId: orgId, branchId: widget.branchId),
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        DashToast.error(context, errorMessage(e, t));
      }
      return;
    }
    container.invalidate(key);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _base = _form = StaffPoolForm.from(saved);
    });
    DashToast.success(context, t('staffPool.saved'));
  }

  Future<void> _revert() async {
    final branchId = widget.branchId;
    if (branchId == null) return;
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('staffPool.revertTitle'),
      description: t('staffPool.revertBody'),
      confirmLabel: t('staffPool.revert'),
      cancelLabel: t('common.cancel'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = ref.read(apiProvider).staffPool;
    final container = ProviderScope.containerOf(context, listen: false);
    try {
      await api.deleteStaffPoolSettings(branchId: branchId);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
      return;
    }
    container.invalidate(staffPoolSettingsProvider(branchId));
    if (!mounted) return;
    // The organisation's settings replace the form, edits or not.
    setState(() => _form = _base);
    DashToast.success(context, t('staffPool.reverted'));
  }

  Widget _skeleton(Translator t) => Semantics(
    key: const ValueKey('spl-loading'),
    label: t('common.loading'),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        DashSkeleton(height: _skeletonTop, radius: Radii.card),
        DashSkeleton(height: _skeletonBottom, radius: Radii.card),
      ],
    ),
  );

  Widget _failed(Translator t, {String? message, bool retrying = false}) =>
      DashErrorState(
        key: const ValueKey('spl-failed'),
        title: t('staffPool.loadFailed'),
        message: message,
        retryLabel: t('common.retry'),
        retrying: retrying,
        onRetry: () {
          if (!_forced) setState(() => _forced = true);
          ref.invalidate(staffPoolSettingsProvider(widget.branchId));
        },
      );

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    final orgId = ref.watch(orgIdProvider);
    // Grants still loading: the web's disabled query reads as a failure
    // here; it is a wait (divergence SET-SPL-021).
    if (!authz.ready) return _skeleton(t);
    if (orgId == null && !_forced) return _failed(t);
    final q = ref.watch(staffPoolSettingsProvider(widget.branchId));
    if (q.awaitingFirst) return _skeleton(t);
    if (q.failedFirst || !q.hasValue) {
      return _failed(
        t,
        message: errorMessage(q.error, t),
        retrying: q.isLoading,
      );
    }
    final settings = q.requireValue;
    _follow(settings);
    final f = _form!;
    final canEdit = authz.can(Cap.orgSettingsEdit);
    final inherited = isInheritedScope(
      scopeBranchId: widget.branchId,
      rowBranchId: settings.branchId,
    );
    final allowanceError = _submitted && !allowanceOk(f.allowance)
        ? t('staffPool.errors.allowance')
        : null;
    final c = context.madarColors;
    final wide = !DashBreakpoints.isPhone(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.lg,
      children: [
        if (!canEdit)
          SetupNote(t('staffPool.readOnly'), key: const ValueKey('spl-ro')),
        if (inherited)
          SetupNote(
            t('staffPool.inheritedHint'),
            key: const ValueKey('spl-inherited'),
          ),
        DashCard(
          key: const ValueKey('spl-card'),
          padding: EdgeInsets.all(wide ? Space.card : Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.card,
            children: [
              DashSwitchField(
                key: const ValueKey('spl-enabled'),
                label: t('staffPool.enabled'),
                description: t('staffPool.enabledHint'),
                value: f.enabled,
                enabled: canEdit,
                onChanged: (v) => _edit(f.copyWith(enabled: v)),
              ),
              DashTextField(
                key: const ValueKey('spl-allowance'),
                label: t('staffPool.allowance'),
                description: t('staffPool.allowanceHint'),
                errorText: allowanceError,
                value: f.allowance,
                mono: true,
                keyboardType: TextInputType.number,
                enabled: canEdit,
                onChanged: (v) => _edit(f.copyWith(allowance: v)),
              ),
              Column(
                key: const ValueKey('spl-items'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.sm,
                children: [
                  Text(
                    t('staffPool.items'),
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  EligibleItemsControl(
                    orgId: orgId,
                    value: f.itemIds,
                    enabled: canEdit,
                    // Read at call time: the phone sheet keeps the closure it opened with.
                    onChanged: (ids) => _edit(_form!.copyWith(itemIds: ids)),
                  ),
                  // The server's rule, said where the items are chosen.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: _ruleMeasure),
                    child: Text(
                      t('staffPool.pricingRule'),
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                  ),
                ],
              ),
              if (poolIsOff(enabled: f.enabled, itemIds: f.itemIds))
                _OffNotice(
                  t(
                    f.itemIds.isEmpty
                        ? 'staffPool.offNoItems'
                        : 'staffPool.offDisabled',
                  ),
                ),
            ],
          ),
        ),
        if (canEdit)
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DashButton(
                key: const ValueKey('spl-save'),
                label: t('common.save'),
                loading: _saving,
                onPressed: (_dirty || inherited) && orgId != null
                    ? () => _save(orgId)
                    : null,
              ),
              if (widget.branchId != null && !inherited)
                DashButton(
                  key: const ValueKey('spl-revert'),
                  label: t('staffPool.revert'),
                  icon: 'rotate-ccw',
                  variant: DashButtonVariant.outline,
                  onPressed: _revert,
                ),
              if (allowanceError != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    t('staffPool.fixErrors'),
                    key: const ValueKey('spl-fix-errors'),
                    style: DashType.small.copyWith(color: c.errorText),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

/// "The pool is off" (`role=status`, the warning wash).
class _OffNotice extends StatelessWidget {
  const _OffNotice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Semantics(
      key: const ValueKey('spl-off'),
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: DashTone.warning.wash(c),
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Text(
          text,
          style: DashType.body.copyWith(color: DashTone.warning.foreground(c)),
        ),
      ),
    );
  }
}
