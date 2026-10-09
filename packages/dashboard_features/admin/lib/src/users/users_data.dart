/// The Users unit's reads, its invalidation rules and the rules its screens
/// compute in the browser (web `features/users/{users-page,user-dialog,
/// branch-assign-dialog,util}.tsx`, `features/access/person-access-sheet.tsx`).
///
/// Reads shared with other admin pages keep the web's one cache key: the
/// org's branches are `adminBranchesProvider` (`/branches?org_id=`), the org
/// list is `orgsListProvider` (`/orgs`).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        CapabilityAccess,
        LinkableUser,
        RoleView,
        UserAccess,
        UserBranch,
        UserPublic,
        UserRole;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `GET /users?org_id=<org>` (listUsers): every account of the org,
/// unpaginated (ADM-USR-005). The web's `prefetchRoute('/access/users')`
/// warms exactly this key.
final usersListProvider = FutureProvider.autoDispose
    .family<List<UserPublic>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/users?org_id=$orgId'));
      return ref.watch(apiProvider).users.listUsers(orgId: orgId);
    });

/// `GET /users/{id}/branches` (listUserBranches): the branches a person is
/// assigned to (ADM-USR-034).
final userBranchesProvider = FutureProvider.autoDispose
    .family<List<UserBranch>, String>((ref, userId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/users/$userId/branches'));
      return ref.watch(apiProvider).users.listUserBranches(id: userId);
    });

/// The access read's key: the person and the branch it reads at (null = All
/// branches), the web's `useUserAccess(id, branchId ? {branch_id} : undefined)`.
typedef UserAccessKey = ({String id, String? branchId});

/// `GET /authz/users/{id}[?branch_id=]` (userAccess) (ADM-USR-038, 043).
final userAccessProvider = FutureProvider.autoDispose
    .family<UserAccess, UserAccessKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/authz/users/${k.id}'));
      return ref
          .watch(apiProvider)
          .authz
          .userAccess(id: k.id, branchId: k.branchId);
    });

/// `GET /authz/roles` (listRoles): the roles the access sheet's Roles editor
/// offers (ADM-USR-041).
final accessRolesProvider = FutureProvider.autoDispose<List<RoleView>>((ref) {
  ref.webCache();
  ref.watch(realtimeEpochProvider('/authz/roles'));
  return ref.watch(apiProvider).authz.listRoles();
});

/// `GET /staff/employees/linkable` (linkableUsers): the accounts that are
/// not employees yet, read only when Make employee can show (ADM-USR-014).
/// The team dialog reads the same list through its own provider (warmed by
/// `AddEmployeeOpener.warm`): admin cannot import team, so the web's one
/// shared query is two here (logged in docs/fdash/divergences/admin-users.md).
final linkableUsersProvider = FutureProvider.autoDispose<List<LinkableUser>>((
  ref,
) {
  ref.webCache();
  ref.watch(realtimeEpochProvider('/staff/employees/linkable'));
  return ref.watch(apiProvider).staff.linkableUsers();
});

/// The web's `invalidateUsers()`: every read whose key starts with `/users`
/// (the list, every person's branch assignments). Takes the bus read before
/// the write's await, so a page closed mid-save still refreshes.
void invalidateUsers(RealtimeBus bus) => bus.invalidate(const ['/users']);

// ── rules the browser computes ─────────────────────────────────────────────

/// Every role, in the web's `ALL_ROLES` order.
const List<UserRole> allUserRoles = [
  UserRole.superAdmin,
  UserRole.orgAdmin,
  UserRole.branchManager,
  UserRole.teller,
  UserRole.waiter,
  UserRole.kitchen,
];

/// A till role (`POS_ROLES`): the PIN is what they need; email and password
/// are optional.
bool isTillRole(UserRole role) =>
    role == UserRole.teller ||
    role == UserRole.waiter ||
    role == UserRole.kitchen;

/// The Role select's options by the viewer's role (ADM-USR-022): a super
/// admin every role, a branch manager the till roles, anyone else all but
/// Super Admin.
List<UserRole> roleOptionsFor(String? viewerRole) => switch (viewerRole) {
  'super_admin' => allUserRoles,
  'branch_manager' => const [
    UserRole.teller,
    UserRole.waiter,
    UserRole.kitchen,
  ],
  _ => [
    for (final r in allUserRoles)
      if (r != UserRole.superAdmin) r,
  ],
};

/// Whether the Assign branches row action shows for [user] (ADM-USR-013):
/// by the row's role only.
bool assignableRole(UserRole role) =>
    role == UserRole.branchManager || isTillRole(role);

/// How many accounts hold [role] (the stat cards, ADM-USR-006).
int roleCount(List<UserPublic> users, UserRole role) =>
    users.where((u) => u.role == role).length;

/// A person's override effect at the chosen branch (`effectOf`): their
/// override there, else "inherit".
String effectAt(CapabilityAccess row, String? branchId) {
  for (final o in row.overrides) {
    if (o.branchId == branchId) return o.effect;
  }
  return 'inherit';
}

/// The machine codes `locked_reason` carries (ADM-USR-039).
const Set<String> lockedReasonCodes = {
  'self',
  'owner',
  'not_dominant',
  'not_above',
  'missing_authority',
};

/// The locked note's words: the code worded (see the divergence log; the web
/// prints the raw code), else the generic sentence.
String lockedReasonText(String? reason, Translator t) =>
    reason != null && lockedReasonCodes.contains(reason)
    ? t('access.lockedReasons.$reason')
    : t('access.locked');

/// The web's `prefetchRoute('/access/users')` (also `/users`, `/access`,
/// `/permissions`, `/access/roles`): the org's users, the key the page reads.
void prefetchUsers(DashPrefetcher warm, Scope s) {
  if (s.orgId case final orgId?) warm(usersListProvider(orgId));
}
