/// A person's access (ADM-USR-037..051, 056..058; web
/// `features/access/person-access-sheet.tsx`): their roles and branches,
/// and allow / deny per capability at All branches or one branch, with a
/// "Why?" for each. A side panel from the end edge (full screen on a phone).
///
/// Shared with the Roles & Permissions unit: [showPersonAccessSheet] takes
/// only the person, so any page can open it.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show
        AssignmentInput,
        Branch,
        CapabilityAccess,
        Explanation,
        ExplainStep,
        LimitsView,
        SetAssignmentsRequest,
        SetOverrideRequest,
        UserAccess,
        UserPublic;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../branches/branches_data.dart' show adminBranchesProvider;
import '../orgs/org_errors.dart' show orgErrorWords;
import '../shared/capability_catalog.dart' show bilingual;
import '../shared/capability_groups.dart';
import '../shared/limits_button.dart';
import 'users_data.dart';

/// Opens [user]'s access; resolves when it closes.
Future<void> showPersonAccessSheet(
  BuildContext context, {
  required UserPublic user,
}) => showDashSidePanel<void>(
  context,
  width: DashMetrics.dialogWide,
  builder: (_) => PersonAccessSheet(user: user),
);

/// The "Where" select's All branches value.
const String _all = 'all';

class PersonAccessSheet extends ConsumerStatefulWidget {
  const PersonAccessSheet({required this.user, super.key});

  final UserPublic user;

  @override
  ConsumerState<PersonAccessSheet> createState() => _PersonAccessState();
}

class _PersonAccessState extends ConsumerState<PersonAccessSheet> {
  /// Where: null = All branches. Reset only by closing the sheet.
  String? _branch;

  /// Rides every change until edited (ADM-USR-058).
  String _reason = '';

  /// The capability whose change is in flight.
  String? _busy;

  /// Kept for after a call: the sheet may have closed while it ran.
  late final _bus = ref.read(realtimeBusProvider);

  UserAccessKey get _key => (id: widget.user.id, branchId: _branch);

  @override
  void initState() {
    super.initState();
    _bus;
  }

  /// `invalidateQueries`: asks again and waits for the answer. A failed
  /// refetch never fails the write that caused it (the web's never throws);
  /// the sheet keeps the last answer.
  Future<void> _refresh() async {
    _bus.invalidate(['/authz/users/${widget.user.id}']);
    if (!mounted) return;
    try {
      await ref.read(userAccessProvider(_key).future);
    } on Object {
      // The read shows its own state.
    }
  }

  Future<void> _write(
    CapabilityMeta meta,
    String effect, [
    LimitsView? limits,
  ]) async {
    final t = ref.read(tProvider);
    setState(() => _busy = meta.key);
    try {
      final reason = _reason.trim();
      await ref
          .read(apiProvider)
          .authz
          .setOverride(
            id: widget.user.id,
            body: SetOverrideRequest(
              capability: meta.key,
              effect: effect,
              branchId: _branch,
              reason: reason.isEmpty ? null : reason,
              limits: limits,
              explicitNulls: const {'branch_id', 'reason', 'limits'},
            ),
          );
      await _refresh();
    } on Object catch (e) {
      if (mounted) DashToast.error(context, orgErrorWords(e, t));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Widget _control(
    BuildContext context,
    CapabilityMeta meta,
    UserAccess access,
    Map<String, CapabilityAccess> byKey,
  ) {
    final t = ref.read(tProvider);
    final row = byKey[meta.key];
    if (row == null) return const SizedBox.shrink();
    final why = WhyButton(
      userId: widget.user.id,
      capability: meta.key,
      branchId: _branch,
    );
    if (row.source == 'core') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [const AlwaysOnBadge(), why],
      );
    }
    if (row.source == 'owner') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          Text(
            t('access.owner'),
            style: DashType.small.copyWith(
              color: context.madarColors.textSecondary,
            ),
          ),
          why,
        ],
      );
    }
    final disabled = !access.canEdit || !row.editable || _busy == meta.key;
    final inherited = row.fromRoles.isNotEmpty;
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Space.sm,
      runSpacing: Space.xs,
      children: [
        DashSegmentedControl<String>(
          key: ValueKey('effect-${meta.key}'),
          semanticLabel: meta.label(ref.read(localeProvider)),
          value: effectAt(row, _branch),
          enabled: !disabled,
          options: [
            DashOption(
              value: 'inherit',
              label: t(inherited ? 'access.inheritOn' : 'access.inheritOff'),
            ),
            DashOption(value: 'allow', label: t('access.allow')),
            DashOption(value: 'deny', label: t('access.deny')),
          ],
          onChanged: (v) {
            if (!disabled) _write(meta, v);
          },
        ),
        if (meta.limits.isNotEmpty && row.effective)
          LimitsButton(
            key: ValueKey('limits-${meta.key}'),
            meta: meta,
            value: row.limits,
            disabled: disabled,
            onSave: (l) => _write(meta, 'allow', l),
          ),
        why,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final orgId = widget.user.orgId;
    final branches = orgId == null
        ? const <Branch>[]
        : ref.watch(adminBranchesProvider(orgId)).value ?? const <Branch>[];
    final q = ref.watch(userAccessProvider(_key));
    final access = q.value;
    final ready = ref.watch(authzProvider.select((a) => a.ready));
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;

    final Widget body;
    if (q.awaitingFirst) {
      body = Column(
        spacing: Space.sm,
        children: [
          for (var i = 0; i < 6; i++)
            const DashSkeleton(height: DashMetrics.control),
        ],
      );
    } else if (access == null) {
      // The web leaves the body empty; a failed read says so here (see the
      // divergence log).
      body = DashErrorState(
        framed: false,
        title: t('common.loadFailed'),
        message: orgErrorWords(q.error, t),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(userAccessProvider(_key)),
      );
    } else {
      final byKey = {for (final r in access.capabilities) r.capability: r};
      final where = DashSelectField<String>(
        key: const ValueKey('access-where'),
        label: t('access.where'),
        value: _branch ?? _all,
        options: [
          DashOption(value: _all, label: t('access.allBranches')),
          for (final b in branches) DashOption(value: b.id, label: b.name),
        ],
        onOptionIntent: (v) => ref.warm(
          userAccessProvider((id: widget.user.id, branchId: v == _all ? null : v)),
        ),
        onChanged: (v) => setState(() => _branch = v == _all ? null : v),
      );
      final reason = DashTextField(
        key: const ValueKey('access-reason'),
        label: t('access.reason'),
        description: t('access.reasonHint'),
        value: _reason,
        maxLength: 200,
        onChanged: (v) => setState(() => _reason = v),
      );
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          if (!access.canEdit)
            Container(
              key: const ValueKey('access-locked'),
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                color: c.muted,
                borderRadius: BorderRadius.circular(Radii.control),
                border: Border.all(color: c.hairline),
              ),
              child: Row(
                spacing: Space.sm,
                children: [
                  DashIcon('lock', size: IconSize.sm, color: c.textSecondary),
                  Expanded(
                    child: Text(
                      lockedReasonText(access.lockedReason, t),
                      style: DashType.body.copyWith(color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          _AssignmentsEditor(
            userId: widget.user.id,
            access: access,
            branches: branches,
            disabled: !access.canEdit,
            onSaved: _refresh,
          ),
          if (wide)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Expanded(child: where),
                Expanded(child: reason),
              ],
            )
          else ...[
            where,
            reason,
          ],
          if (ready)
            CapabilityGroupsList(
              stacked: !wide,
              control: (context, meta) =>
                  _control(context, meta, access, byKey),
            ),
        ],
      );
    }

    return DashSurface(
      title: t('access.personTitle', args: {'name': widget.user.name}),
      description: t('access.personHint'),
      body: body,
    );
  }
}

/// The Roles card: what the person holds and where; Edit opens the role
/// checkboxes (ADM-USR-040..042).
class _AssignmentsEditor extends ConsumerStatefulWidget {
  const _AssignmentsEditor({
    required this.userId,
    required this.access,
    required this.branches,
    required this.disabled,
    required this.onSaved,
  });

  final String userId;
  final UserAccess access;
  final List<Branch> branches;
  final bool disabled;
  final Future<void> Function() onSaved;

  @override
  ConsumerState<_AssignmentsEditor> createState() => _AssignmentsState();
}

class _AssignmentsState extends ConsumerState<_AssignmentsEditor> {
  bool _editing = false;
  bool _saving = false;

  /// role id → (all branches, the chosen branches), in the order ticked.
  Map<String, ({bool all, List<String> branches})> _draft = {};

  void _start() => setState(() {
    _draft = {
      for (final a in widget.access.assignments)
        a.roleId: (all: a.allBranches, branches: [...a.branchIds]),
    };
    _editing = true;
  });

  Future<void> _save() async {
    final t = ref.read(tProvider);
    setState(() => _saving = true);
    try {
      await ref
          .read(apiProvider)
          .authz
          .setAssignments(
            id: widget.userId,
            body: SetAssignmentsRequest(
              assignments: [
                for (final e in _draft.entries)
                  AssignmentInput(
                    roleId: e.key,
                    allBranches: e.value.all,
                    branchIds: e.value.all ? const [] : e.value.branches,
                  ),
              ],
            ),
          );
      if (mounted) setState(() => _editing = false);
      await widget.onSaved();
    } on Object catch (e) {
      if (mounted) DashToast.error(context, orgErrorWords(e, t));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _branchName(String id) =>
      widget.branches.firstWhereOrNull((b) => b.id == id)?.name ?? '—';

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    // The web's `useListRoles()` runs with the card, editing or not.
    final roles = ref.watch(accessRolesProvider).value ?? const [];
    final assignments = widget.access.assignments;

    final header = Container(
      color: c.muted,
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.lg,
        Space.sm,
        Space.sm,
        Space.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                t('access.roles'),
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
            ),
          ),
          if (!widget.disabled && !_editing)
            DashButton(
              key: const ValueKey('access-roles-edit'),
              label: t('common.edit'),
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              onPressed: _start,
            )
          else
            const SizedBox(height: DashMetrics.target),
        ],
      ),
    );

    final Widget content;
    if (!_editing) {
      content = assignments.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.md,
              ),
              child: Text(
                t('access.noRolesHeld'),
                style: DashType.body.copyWith(color: c.textSecondary),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, a) in assignments.indexed) ...[
                  if (i > 0) const MadarHairline(light: true),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.lg,
                      vertical: Space.md,
                    ),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: Space.sm,
                      runSpacing: Space.xs,
                      children: [
                        Text(
                          bilingual(a.roleNameEn, a.roleNameAr, lang),
                          style: DashType.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          a.allBranches
                              ? t('access.allBranches')
                              : a.branchIds.map(_branchName).join('، '),
                          style: DashType.body.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
    } else {
      content = Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            for (final r in roles.where((r) => r.kind != 'org_admin'))
              _RoleChoice(
                name: bilingual(r.nameEn, r.nameAr, lang),
                draft: _draft[r.id],
                branches: widget.branches,
                allLabel: t('access.allBranches'),
                onRole: (on) => setState(() {
                  if (on) {
                    _draft[r.id] = (all: false, branches: const []);
                  } else {
                    _draft.remove(r.id);
                  }
                }),
                onAll: (on) => setState(
                  () => _draft[r.id] = (
                    all: on,
                    branches: _draft[r.id]?.branches ?? const [],
                  ),
                ),
                onBranch: (id, on) => setState(() {
                  final d = _draft[r.id]!;
                  _draft[r.id] = (
                    all: d.all,
                    branches: on
                        ? [...d.branches, id]
                        : [
                            for (final b in d.branches)
                              if (b != id) b,
                          ],
                  );
                }),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              spacing: Space.sm,
              children: [
                DashButton(
                  label: t('common.cancel'),
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onPressed: () => setState(() => _editing = false),
                ),
                DashButton(
                  key: const ValueKey('access-roles-save'),
                  label: t('common.save'),
                  size: DashButtonSize.compact,
                  onPressed: _saving ? null : _save,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('access-roles'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, const MadarHairline(), content],
      ),
    );
  }
}

/// One role in the Roles editor: its checkbox and, when ticked, "All
/// branches" and (with that off) one checkbox per branch.
class _RoleChoice extends StatelessWidget {
  const _RoleChoice({
    required this.name,
    required this.draft,
    required this.branches,
    required this.allLabel,
    required this.onRole,
    required this.onAll,
    required this.onBranch,
  });

  final String name;
  final ({bool all, List<String> branches})? draft;
  final List<Branch> branches;
  final String allLabel;
  final ValueChanged<bool> onRole;
  final ValueChanged<bool> onAll;
  final void Function(String id, bool on) onBranch;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final d = draft;
    Widget check(String label, bool value, ValueChanged<bool> onChanged) =>
        DashCheckChip(label: label, value: value, onChanged: onChanged);
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          DashCheckboxField(label: name, value: d != null, onChanged: onRole),
          if (d != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: Space.xl),
              child: Wrap(
                spacing: Space.md,
                runSpacing: Space.xs,
                children: [
                  check(allLabel, d.all, onAll),
                  if (!d.all)
                    for (final b in branches)
                      check(
                        b.name,
                        d.branches.contains(b.id),
                        (on) => onBranch(b.id, on),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "Why?": asks `/authz/explain` on every open and words the answer in the
/// viewer's language (ADM-USR-049, 057).
class WhyButton extends ConsumerStatefulWidget {
  const WhyButton({
    required this.userId,
    required this.capability,
    this.branchId,
    super.key,
  });

  final String userId;
  final String capability;
  final String? branchId;

  @override
  ConsumerState<WhyButton> createState() => _WhyButtonState();
}

class _WhyButtonState extends ConsumerState<WhyButton> {
  final _popover = DashPopoverController();
  Explanation? _data;
  bool _loading = false;

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final t = ref.read(tProvider);
    _popover.open();
    setState(() => _loading = true);
    try {
      final data = await ref
          .read(apiProvider)
          .authz
          .explain(
            userId: widget.userId,
            capability: widget.capability,
            branchId: widget.branchId,
          );
      if (mounted) setState(() => _data = data);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, orgErrorWords(e, t));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _step(ExplainStep s, Translator t, String lang) {
    final name = s.roleName;
    final role = name == null ? '' : bilingual(name, s.roleNameAr ?? name, lang);
    return switch (s.kind) {
      'owner' => t('access.whyOwner'),
      'inactive' => t('access.whyInactive'),
      'core' => t('access.whyCore', args: {'role': role}),
      'assignment' when s.appliesHere == false => t(
        'access.whyNotHere',
        args: {'role': role},
      ),
      'assignment' => t(
        s.grants == true ? 'access.whyRoleGrants' : 'access.whyRoleNot',
        args: {'role': role},
      ),
      'override_allow' => t('access.whyAllow'),
      'override_deny' => t('access.whyDeny'),
      'protected' => t('access.whyProtected'),
      'limit' => t('access.whyLimit'),
      'ask_manager' => t('access.whyAsk'),
      'not_held' => t('access.whyNotHeld'),
      _ => s.kind,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    return DashPopover(
      controller: _popover,
      align: DashPopoverAlign.end,
      width: DashMetrics.popover + Space.xxl,
      anchor: (context, _) => DashIconButton(
        icon: 'help-circle',
        semanticLabel: t('access.why'),
        onPressed: _open,
      ),
      content: (context, _) {
        final d = _data;
        return Padding(
          padding: const EdgeInsets.all(Space.md),
          child: _loading || d == null
              ? const DashSkeleton(height: Space.xxl * 2)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.sm,
                  children: [
                    Text(
                      bilingual(d.labelEn, d.labelAr, lang),
                      style: DashType.bodyStrong.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                    Text(
                      t(
                        d.effective
                            ? 'access.resultAllowed'
                            : 'access.resultNotAllowed',
                      ),
                      style: DashType.smallMedium.copyWith(
                        color: c.textPrimary,
                      ),
                    ),
                    for (final s in d.steps)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.xs,
                        children: [
                          Text(
                            '•',
                            style: DashType.small.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              _step(s, t, lang),
                              style: DashType.small.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
        );
      },
    );
  }
}
