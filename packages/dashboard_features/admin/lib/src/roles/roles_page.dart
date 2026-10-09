/// `/access/roles` Roles & Permissions (ADM-ROL-001..024): the roles list
/// beside the selected role (`?role=<id>`; `?user=` from old links accepted
/// and ignored), its capability grants and limits, the role dialog and the
/// ask-a-manager policy card. Web: `features/access/{roles-page,role-dialog,
/// ask-manager-card}.tsx`.
///
/// The page gates itself, as the web's does: once the person's permissions
/// are known and hold neither `staff.permissions.read` nor
/// `staff.roles.manage`, it shows the Access tabs over "Not available on this
/// account" (ADM-ROL-001) and reads nothing. Changing anything takes
/// `staff.roles.manage`.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show LimitsView, RoleView, SetGrantRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../orgs/org_errors.dart' show orgErrorWords;
import '../shared/access_tabs.dart';
import '../shared/capability_catalog.dart' show isCoreFor, roleHolds;
import '../shared/capability_groups.dart';
import '../shared/limits_button.dart';
import '../shared/url_params.dart';
import 'ask_manager_card.dart';
import 'role_dialog.dart';
import 'roles_data.dart';

/// What opens the page (`canRead` on the web).
const List<String> rolesReadCaps = [
  Cap.staffPermissionsRead,
  Cap.staffRolesManage,
];

/// The roles list's width beside the selected role (`lg:grid-cols-[280px_1fr]`).
const double _listWidth = Space.xxl * 8 + Space.xl;

class RolesPage extends ConsumerStatefulWidget {
  const RolesPage({super.key});

  static const String path = AccessPaths.roles;

  @override
  ConsumerState<RolesPage> createState() => _RolesPageState();
}

class _RolesPageState extends ConsumerState<RolesPage> {
  /// The capability whose grant is being saved.
  String? _busy;

  void _select(String? id) => context.setQueryParams({'role': id});

  /// `await refresh()`: the new list, a failed refetch kept quiet (the web's
  /// `invalidateQueries` never throws).
  Future<void> _settled() async {
    if (!mounted) return;
    try {
      await ref.read(accessRolesProvider.future);
    } on Object {
      // The list shows its own state.
    }
  }

  Future<void> _toggle(
    RoleView role,
    CapabilityMeta meta,
    bool granted, [
    LimitsView? limits,
  ]) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    setState(() => _busy = meta.key);
    try {
      await api.authz.setRoleGrant(
        id: role.id,
        body: SetGrantRequest(
          capability: meta.key,
          granted: granted,
          limits: limits,
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(context, orgErrorWords(e, t));
        setState(() => _busy = null);
      }
      return;
    }
    bus.invalidate(rolesKey);
    await _settled();
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _remove(RoleView role) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('access.deleteRoleTitle'),
      description: t('access.deleteRoleBody'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = ref.read(apiProvider);
    final bus = ref.read(realtimeBusProvider);
    try {
      await api.authz.deleteRole(id: role.id);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, orgErrorWords(e, t));
      return;
    }
    if (mounted && context.queryParam('role') != null) _select(null);
    bus.invalidate(rolesKey);
  }

  void _openDialog([RoleView? role]) => showRoleDialog(
    context,
    role: role,
    onSaved: (r) {
      if (mounted) _select(r.id);
    },
  );

  /// The end side of a capability row (`control`).
  Widget _control(RoleView role, CapabilityMeta meta, bool canManage) {
    if (isCoreFor(meta, role.kind)) return const AlwaysOnBadge();
    final lang = ref.read(localeProvider);
    final on = roleHolds([for (final g in role.grants) g.capability], role.kind)
        .contains(meta.key);
    final grant = role.grants.firstWhereOrNull((g) => g.capability == meta.key);
    final disabled = !canManage || !role.editable || _busy == meta.key;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        if (on && meta.limits.isNotEmpty)
          LimitsButton(
            key: ValueKey('limits-${meta.key}'),
            meta: meta,
            value: grant?.limits,
            disabled: disabled,
            onSave: (l) => _toggle(role, meta, true, l),
          ),
        DashSwitch(
          key: ValueKey('grant-${meta.key}'),
          value: on,
          // The web names it by its key; a screen reader gets its words.
          semanticLabel: meta.label(lang),
          onChanged: disabled ? null : (v) => _toggle(role, meta, v),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    final title = t('nav.rolesPermissions');
    final canRead = authz.canAny(rolesReadCaps);
    if (authz.ready && !canRead) {
      return DashPageScaffold(
        title: title,
        tabs: const AccessSectionTabs(),
        body: DashEmptyState(
          icon: 'lock',
          title: t('common.restrictedTitle'),
          description: t('access.noAccess'),
        ),
      );
    }
    final canManage = authz.can(Cap.staffRolesManage);
    // Not asked until the person's permissions say they may read it.
    final q = canRead ? ref.watch(accessRolesProvider) : null;
    final roles = q?.value ?? const <RoleView>[];
    final selected = selectedRole(roles, context.queryParam('role'));

    final list = _RolesList(
      q: q,
      selectedId: selected?.id,
      onSelect: _select,
      onRetry: () => ref.invalidate(accessRolesProvider),
    );
    final detail = selected == null
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.lg,
            children: [
              _RoleHeader(
                role: selected,
                canManage: canManage,
                onRename: () => _openDialog(selected),
                onDelete: () => _remove(selected),
              ),
              if (selected.editable)
                CapabilityGroupsList(
                  key: ValueKey('caps-${selected.id}'),
                  control: (context, meta) =>
                      _control(selected, meta, canManage),
                ),
              if (canManage) const AskManagerCard(),
            ],
          );
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;

    return DashPageScaffold(
      title: title,
      subtitle: t('access.rolesSubtitle'),
      tabs: const AccessSectionTabs(),
      actions: [
        if (canManage)
          DashButton(
            key: const ValueKey('roles-new'),
            label: t('access.newRole'),
            icon: 'plus',
            // The dialog's read ("Start from"): the page's own list.
            onIntent: () => ref.warm(accessRolesProvider),
            onPressed: _openDialog,
          ),
      ],
      body: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.lg,
              children: [
                SizedBox(width: _listWidth, child: list),
                Expanded(child: detail ?? const SizedBox.shrink()),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.lg,
              children: [list, ?detail],
            ),
    );
  }
}

/// The roles, with their loading, failed and empty states (ADM-ROL-004..007).
class _RolesList extends ConsumerWidget {
  const _RolesList({
    required this.q,
    required this.selectedId,
    required this.onSelect,
    required this.onRetry,
  });

  /// Null while the person's permissions are not known yet.
  final AsyncValue<List<RoleView>>? q;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final q = this.q;
    final roles = q?.value;
    final Widget child;
    if (q != null && q.failedFirst) {
      child = Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xl),
        child: DashErrorState(
          framed: false,
          title: t('access.rolesLoadError'),
          retryLabel: t('common.retry'),
          retrying: q.isLoading,
          onRetry: onRetry,
        ),
      );
    } else if (q == null || q.awaitingFirst || roles == null) {
      // Also while permissions load: the web shows "No roles yet" then (see
      // the divergence log).
      child = Padding(
        key: const ValueKey('roles-loading'),
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          spacing: Space.sm,
          children: [
            for (var i = 0; i < 5; i++)
              const DashSkeleton(height: DashMetrics.control),
          ],
        ),
      );
    } else if (roles.isEmpty) {
      child = Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.xl),
        child: DashEmptyState(
          framed: false,
          icon: 'shield',
          title: t('access.noRoles'),
        ),
      );
    } else {
      return DashListCard(
        children: [
          for (final r in roles)
            DashListRow(
              key: ValueKey('role-${r.id}'),
              variant: DashListRowVariant.nav,
              title: roleName(r, lang),
              meta:
                  '${kindLabel(r.kind, lang)} · '
                  '${t('access.members', count: r.members)}',
              selected: r.id == selectedId,
              onTap: () => onSelect(r.id),
            ),
        ],
      );
    }
    return DashListCard(children: [child]);
  }
}

/// The selected role's card: its name, what it works like (or that the
/// owner holds everything), "Built in", Rename and Delete (ADM-ROL-009..011).
class _RoleHeader extends ConsumerWidget {
  const _RoleHeader({
    required this.role,
    required this.canManage,
    required this.onRename,
    required this.onDelete,
  });

  final RoleView role;
  final bool canManage;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    return Container(
      key: const ValueKey('role-header'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.md,
        runSpacing: Space.md,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                roleName(role, lang),
                style: DashType.bodyStrong.copyWith(
                  color: c.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                role.editable
                    ? t(
                        'access.behavesLike',
                        args: {'kind': kindLabel(role.kind, lang)},
                      )
                    : t('access.ownerHoldsAll'),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ],
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              if (role.isSystem) DashBadge(t('access.builtIn')),
              if (canManage)
                DashButton(
                  key: const ValueKey('role-rename'),
                  label: t('access.rename'),
                  icon: 'pencil',
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onIntent: () => ref.warm(accessRolesProvider),
                  onPressed: onRename,
                ),
              if (canManage && !role.isSystem)
                DashButton(
                  key: const ValueKey('role-delete'),
                  label: t('common.delete'),
                  icon: 'trash-2',
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  // Only a role nobody holds can go.
                  onPressed: role.members > 0 ? null : onDelete,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
