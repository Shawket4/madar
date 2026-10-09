/// `/access/users` Users (ADM-USR-001..058): the org's accounts with the
/// Access section tabs, stats, search, Excel export, the user dialog
/// (`?edit=<id>|new`), branch access (`?branches=<id>`) and the person's
/// access sheet (`?access=<id>`). A platform admin with no shop picked sees
/// "Select an organization" (ADM-USR-004). Web: `features/users/*`,
/// `features/access/{person-access-sheet,capability-groups,limits-button}.tsx`.
///
/// Nothing on the page is wrapped in `<Restricted>`: the list asks the
/// server (which refuses without `staff.users.read`), New is not gated, a
/// row opens the editor for everyone, and only the row actions check
/// capabilities (ADM-USR-011..016).
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart' show UserPublic, UserRole;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../orgs/org_errors.dart' show orgErrorWords;
import '../shared/access_tabs.dart';
import '../shared/pick_org_state.dart';
import '../shared/row_action.dart';
import '../shared/url_params.dart';
import 'branch_access_dialog.dart';
import 'person_access_sheet.dart';
import 'user_dialog.dart';
import 'users_data.dart';

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key});

  static const String path = AccessPaths.users;

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  /// The URL param whose dialog / sheet is up, so each opens once.
  final Set<String> _open = {};
  bool _exporting = false;

  /// Opens what `?<param>=<id>` names once the list has the person (`?edit`
  /// also takes `new`); closing it removes the param (ADM-USR-019).
  void _sync(
    String param,
    List<UserPublic>? users,
    Future<void> Function(UserPublic? user) show,
  ) {
    final id = context.queryParam(param);
    if (id == null || _open.contains(param)) return;
    UserPublic? user;
    if (!(param == 'edit' && id == 'new')) {
      user = users?.firstWhereOrNull((u) => u.id == id);
      if (user == null) return;
    }
    _open.add(param);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _open.remove(param);
        return;
      }
      await show(user);
      _open.remove(param);
      if (mounted && context.queryParam(param) != null) {
        context.setQueryParams({param: null});
      }
    });
  }

  Future<void> _remove(UserPublic u) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('users.deleteTitle', args: {'name': u.name}),
      description: t('users.deleteDescription'),
      confirmLabel: t('common.delete'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(apiProvider).users.deleteUser(id: u.id);
      invalidateUsers(ref);
      if (mounted) DashToast.success(context, t('users.deletedToast'));
    } on Object catch (e) {
      if (mounted) DashToast.error(context, orgErrorWords(e, t));
    }
  }

  Future<void> _export(List<UserPublic> users) async {
    final t = ref.read(tProvider);
    final brand = ref.read(publicBrandProvider).value;
    setState(() => _exporting = true);
    final toast = DashToast.loading(context, t('excel.generating'));
    String dash(String? s) => s ?? '—';
    final outcome = await ref
        .read(exporterProvider)
        .exportToExcel(
          ExcelConfig(
            filename: 'Madar-Users',
            logoUrl: brand?.customBranding == true ? brand?.logoUrl : null,
            sheets: [
              ExcelSheet<UserPublic>(
                name: t('users.title'),
                title: t('users.title'),
                rows: users,
                columns: [
                  ExcelColumn(
                    header: t('common.name'),
                    accessor: (u) => u.name,
                    type: ExcelColumnType.text,
                    width: 28,
                  ),
                  ExcelColumn(
                    header: t('auth.email'),
                    accessor: (u) => dash(u.email),
                    type: ExcelColumnType.text,
                    width: 30,
                  ),
                  ExcelColumn(
                    header: t('users.phone'),
                    accessor: (u) => dash(u.phone),
                    type: ExcelColumnType.text,
                    width: 18,
                  ),
                  ExcelColumn(
                    header: t('users.role'),
                    accessor: (u) => roleLabel(u.role, t),
                    type: ExcelColumnType.text,
                    width: 18,
                  ),
                  ExcelColumn(
                    header: t('common.status'),
                    accessor: (u) =>
                        t(u.isActive ? 'common.active' : 'common.inactive'),
                    type: ExcelColumnType.text,
                    width: 12,
                  ),
                ],
              ),
            ],
          ),
        );
    toast.update(
      outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
      outcome.message(t),
    );
    if (mounted) setState(() => _exporting = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final title = t('users.title');
    final orgId = ref.watch(orgIdProvider);
    if (orgId == null) {
      return PickOrgPage(
        title: title,
        icon: 'users',
        message: t('users.pickOrg'),
        tabs: const AccessSectionTabs(),
      );
    }
    // The export's logo (the shop's own on the branding tier).
    ref.watch(publicBrandProvider);
    final authz = ref.watch(authzProvider);
    final dawam = ref.watch(
      orgModulesProvider.select((m) => m.has(OrgModule.dawam)),
    );
    // "Make employee" (Phase A): offered where Dawam is on, to someone who
    // may add staff, for accounts that are not employees yet. The dialog is
    // the team area's, which the app wires; unwired, no button.
    final makeEmployee = ref.watch(areaOpenersProvider).addEmployee;
    final canMakeEmployee =
        makeEmployee != null && dawam && authz.can(Cap.hrStaffCreate);
    final linkable = canMakeEmployee
        ? ref.watch(linkableUsersProvider).value
        : null;
    final linkableIds = {for (final l in linkable ?? const []) l.userId};

    final list = ref.watch(usersListProvider(orgId));
    final users = list.value ?? const <UserPublic>[];
    final loading = list.isLoading && !list.hasValue;
    final error = !loading && list.hasError ? list.error : null;

    _sync('edit', list.value, (u) => showUserDialog(context, user: u));
    _sync(
      'branches',
      list.value,
      (u) => showBranchAccessDialog(context, user: u!),
    );
    _sync(
      'access',
      list.value,
      (u) => showPersonAccessSheet(context, user: u!),
    );

    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg;
    final stats = [
      DashStatCard(
        label: t('users.totalUsers'),
        value: users.length,
        loading: loading,
      ),
      DashStatCard(
        label: t('users.orgAdmins'),
        value: roleCount(users, UserRole.orgAdmin),
        loading: loading,
      ),
      DashStatCard(
        label: t('users.branchManagers'),
        value: roleCount(users, UserRole.branchManager),
        loading: loading,
      ),
      DashStatCard(
        label: t('users.tellers'),
        value: roleCount(users, UserRole.teller),
        loading: loading,
      ),
    ];

    return DashPageScaffold(
      title: title,
      subtitle: t('users.subtitle'),
      tabs: const AccessSectionTabs(),
      actions: [
        DashExportButton(
          onExport: () => _export(users),
          loading: _exporting,
          enabled: users.isNotEmpty,
        ),
        DashButton(
          key: const ValueKey('users-new'),
          label: t('common.new'),
          icon: 'plus',
          onPressed: () => context.setQueryParams({'edit': 'new'}),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          _StatGrid(columns: wide ? 4 : 2, children: stats),
          _UsersTable(
            users: users,
            loading: loading,
            errorText: error == null ? null : orgErrorWords(error, t),
            onRetry: () => ref.invalidate(usersListProvider(orgId)),
            canAccess: authz.can(Cap.staffPermissionsRead),
            canEdit: authz.can(Cap.staffUsersEdit),
            canDelete: authz.can(Cap.staffUsersDelete),
            canMakeEmployee: (u) =>
                canMakeEmployee && linkableIds.contains(u.id),
            onOpen: (u) => context.setQueryParams({'edit': u.id}),
            onAccess: (u) => context.setQueryParams({'access': u.id}),
            onBranches: (u) => context.setQueryParams({'branches': u.id}),
            onMakeEmployee: (u) async {
              await makeEmployee?.open(context, userId: u.id);
            },
            onMakeEmployeeIntent: () => makeEmployee?.warm(ref),
            onDelete: _remove,
          ),
        ],
      ),
    );
  }
}

/// `t('roles.<role>', role)`: the role's words, the raw value when unknown.
String roleLabel(UserRole role, Translator t) {
  final raw = role.toJson();
  return t.exists('roles.$raw') ? t('roles.$raw') : raw;
}

/// The stats in a grid of equal cells (`grid-cols-2 lg:grid-cols-4 gap-3`).
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.columns, required this.children});

  final int columns;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.md,
    children: [
      for (var i = 0; i < children.length; i += columns)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.md,
          children: [
            for (var j = i; j < i + columns; j++)
              Expanded(
                child: j < children.length
                    ? children[j]
                    : const SizedBox.shrink(),
              ),
          ],
        ),
    ],
  );
}

/// The users table (phone: one card per person).
class _UsersTable extends ConsumerWidget {
  const _UsersTable({
    required this.users,
    required this.loading,
    required this.errorText,
    required this.onRetry,
    required this.canAccess,
    required this.canEdit,
    required this.canDelete,
    required this.canMakeEmployee,
    required this.onOpen,
    required this.onAccess,
    required this.onBranches,
    required this.onMakeEmployee,
    required this.onMakeEmployeeIntent,
    required this.onDelete,
  });

  final List<UserPublic> users;
  final bool loading;
  final String? errorText;
  final VoidCallback onRetry;
  final bool canAccess;
  final bool canEdit;
  final bool canDelete;
  final bool Function(UserPublic u) canMakeEmployee;
  final ValueChanged<UserPublic> onOpen;
  final ValueChanged<UserPublic> onAccess;
  final ValueChanged<UserPublic> onBranches;
  final ValueChanged<UserPublic> onMakeEmployee;
  final VoidCallback onMakeEmployeeIntent;
  final ValueChanged<UserPublic> onDelete;

  List<Widget> _actions(UserPublic u, Translator t) => [
    if (canAccess)
      AdminRowAction(
        icon: 'shield',
        label: t('users.permissions'),
        onPressed: () => onAccess(u),
      ),
    if (assignableRole(u.role))
      AdminRowAction(
        icon: 'git-branch',
        label: t('users.assignBranches'),
        onPressed: () => onBranches(u),
      ),
    if (canMakeEmployee(u))
      DashIntent(
        onIntent: onMakeEmployeeIntent,
        child: AdminRowAction(
          icon: 'briefcase-business',
          label: t('dawam.makeEmployee'),
          onPressed: () => onMakeEmployee(u),
        ),
      ),
    if (canEdit)
      AdminRowAction(
        icon: 'pencil',
        label: t('common.edit'),
        onPressed: () => onOpen(u),
      ),
    if (canDelete)
      AdminRowAction(
        icon: 'trash-2',
        label: t('common.delete'),
        destructive: true,
        onPressed: () => onDelete(u),
      ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    // The table's search reads a column only when the first row has a value
    // there (TanStack's global filter rule).
    final first = users.firstOrNull;
    final most = users.fold<int>(0, (n, u) {
      final k = _actions(u, t).length;
      return k > n ? k : n;
    });
    return DashDataTable<UserPublic>(
      rows: users,
      rowKey: (u) => u.id,
      loading: loading,
      errorMessage: errorText,
      onRetry: onRetry,
      onRowTap: onOpen,
      rowSemanticLabel: (u) => u.name,
      searchPlaceholder: t('common.search'),
      empty: DashEmptyState(icon: 'users', title: t('users.empty')),
      rowActionsWidth: DashMetrics.target * (most < 1 ? 1 : most) + Space.lg,
      rowActions: (context, u) =>
          Row(mainAxisSize: MainAxisSize.min, children: _actions(u, t)),
      columns: [
        DashColumn<UserPublic>(
          id: 'name',
          label: t('common.name'),
          phone: DashPhoneRole.title,
          flex: 3,
          minWidth: 170,
          text: (u) => u.name,
          cell: (context, u) => _NameCell(user: u),
        ),
        DashColumn<UserPublic>(
          id: 'phone',
          label: t('users.phone'),
          numeric: true,
          align: DashAlign.start,
          flex: 2,
          minWidth: 150,
          searchable: first?.phone != null,
          text: (u) => u.phone ?? '',
          cell: (context, u) => u.phone != null
              ? MadarClippedText(
                  u.phone!,
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                )
              : Text('—', style: TextStyle(color: c.textSecondary)),
        ),
        DashColumn<UserPublic>(
          id: 'role',
          label: t('users.role'),
          flex: 2,
          minWidth: 110,
          // The raw value (the web's search) and the words on screen.
          text: (u) => '${u.role.toJson()} ${roleLabel(u.role, t)}',
          cell: (context, u) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashBadge(roleLabel(u.role, t)),
          ),
        ),
        DashColumn<UserPublic>(
          id: 'status',
          label: t('common.status'),
          flex: 1,
          minWidth: 100,
          searchable: false,
          text: (u) => t(u.isActive ? 'common.active' : 'common.inactive'),
          cell: (context, u) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashStatusPill(
              label: t(u.isActive ? 'common.active' : 'common.inactive'),
              tone: u.isActive ? DashTone.success : DashTone.neutral,
            ),
          ),
        ),
      ],
    );
  }
}

/// The Name cell: the initials avatar, the name, the email (or "—") under it.
class _NameCell extends StatelessWidget {
  const _NameCell({required this.user});

  final UserPublic user;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        Container(
          width: Space.xxl,
          height: Space.xxl,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.muted, shape: BoxShape.circle),
          child: ExcludeSemantics(
            child: Text(
              initials(user.name),
              style: DashType.smallMedium.copyWith(color: c.textSecondary),
            ),
          ),
        ),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              MadarClippedText(
                user.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
              MadarClippedText(
                user.email ?? '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
