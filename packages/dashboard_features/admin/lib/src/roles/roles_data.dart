/// The Roles & Permissions unit's reads, invalidation and the rules the web
/// computes in the browser (`features/access/{roles-page,role-dialog,
/// ask-manager-card,catalog}.ts(x)`).
///
/// The roles list is the Users unit's [accessRolesProvider]: one endpoint,
/// one cache entry (the web's single `['/authz/roles']` key).
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart' show PolicyEntry, RoleView;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/capability_catalog.dart' show bilingual;
import '../users/users_data.dart' show accessRolesProvider;

export '../users/users_data.dart' show accessRolesProvider;

/// `GET /authz/policy` (getPolicy): "Hidden" or "Ask a manager" per approval
/// capability, business-wide (ADM-ROL-019..022).
final rolesPolicyProvider = FutureProvider.autoDispose<List<PolicyEntry>>((
  ref,
) {
  ref.webCache();
  ref.watch(realtimeEpochProvider('/authz/policy'));
  return ref.watch(apiProvider).authz.getPolicy();
});

/// The web's `getListRolesQueryKey()` invalidation.
const List<String> rolesKey = ['/authz/roles'];

/// The web's `getGetPolicyQueryKey()` invalidation.
const List<String> policyKey = ['/authz/policy'];

/// The web's `prefetchRoute('/access/roles')`, warming what the page reads
/// on mount: the roles, and the policy card under the selected role (see the
/// divergence log: the web warms the Users list here).
void prefetchRoles(DashPrefetcher warm, Scope s) {
  if (s.orgId == null) return;
  warm(accessRolesProvider);
  warm(rolesPolicyProvider);
}

/// The kinds a new role may work like (`KINDS`), in the web's order.
const List<String> creatableKinds = [
  RoleKind.branchManager,
  RoleKind.teller,
  RoleKind.waiter,
  RoleKind.kitchen,
];

/// A role kind in words (`ROLE_KIND_LABELS`); an unknown kind reads raw.
String kindLabel(String kind, String lang) {
  final l = roleKindLabels[kind];
  return l == null ? kind : bilingual(l.en, l.ar, lang);
}

/// A role's name in the active language.
String roleName(RoleView r, String lang) => bilingual(r.nameEn, r.nameAr, lang);

/// The role on show (ADM-ROL-008): the `?role` match, else the first branch
/// manager role, else the first role.
RoleView? selectedRole(List<RoleView> roles, String? id) =>
    roles.firstWhereOrNull((r) => r.id == id) ??
    roles.firstWhereOrNull((r) => r.kind == RoleKind.branchManager) ??
    roles.firstOrNull;

/// The role dialog's name rule (zod `string().trim().min(1).max(80)`): the
/// key of the problem, or null.
String? roleNameProblem(String value) {
  final v = value.trim();
  if (v.isEmpty) return 'access.roleNameMin';
  if (v.length > 80) return 'access.roleNameMax';
  return null;
}
