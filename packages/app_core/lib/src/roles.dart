/// Who a signed-in person is, as far as the screens need to branch on it.
library;

/// Roles that manage a branch. The wire enum is super_admin | org_admin |
/// branch_manager | teller | waiter | kitchen; written positively so an
/// unknown future role is NOT a manager by accident.
const Set<String> _managerRoles = {'super_admin', 'org_admin', 'branch_manager'};

/// Whether [role] manages the branch (sees every till, force-closes one,
/// downloads everything again).
bool isManagerRole(String? role) =>
    role != null && _managerRoles.contains(role);

/// Whether [role] never opens a till (a waiter has no drawer; a kitchen
/// display takes no money).
bool neverOpensTill(String? role) => role == 'waiter' || role == 'kitchen';
