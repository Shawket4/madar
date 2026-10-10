/// The session as dashboard_core holds it: what `SessionGateway` hands back
/// (real mode builds it from the core's snapshot, the mock from
/// `LoginResponse` / `MeResponse`). Everything else is the generated models
/// of package:dashboard_api (`MyAuthz`, `Branch`, `Org`, …).
library;

import 'package:dashboard_api/dashboard_api.dart' show Branch;

Map<String, Object?> _map(Object? v) =>
    v is Map ? v.map((k, v) => MapEntry('$k', v)) : const {};

String? _str(Object? v) => v?.toString();

double? _double(Object? v) => v is num ? v.toDouble() : null;

/// The signed-in person (`UserPublic`).
class SessionUser {
  const SessionUser({
    required this.id,
    required this.name,
    required this.role,
    this.email,
    this.phone,
    this.orgId,
    this.branchId,
    this.isActive = true,
  });

  factory SessionUser.fromJson(Object? json) {
    final m = _map(json);
    return SessionUser(
      id: '${m['id']}',
      name: _str(m['name']) ?? '',
      role: _str(m['role']) ?? '',
      email: _str(m['email']),
      phone: _str(m['phone']),
      orgId: _str(m['org_id']),
      branchId: _str(m['branch_id']),
      isActive: m['is_active'] != false,
    );
  }

  final String id;
  final String name;

  /// `super_admin`, `org_admin`, `branch_manager`, `teller`, `waiter`,
  /// `kitchen`. Never gate on it (ask `Authz`); the scope rules read it the
  /// way the web does.
  final String role;
  final String? email;
  final String? phone;
  final String? orgId;
  final String? branchId;
  final bool isActive;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'role': role,
    'email': email,
    'phone': phone,
    'org_id': orgId,
    'branch_id': branchId,
    'is_active': isActive,
  };
}

/// A signed-in session (`LoginResponse` / `MeResponse`, plus the token when
/// the gateway exposes one).
class SessionInfo {
  const SessionInfo({
    required this.user,
    this.token,
    this.currencyCode = 'EGP',
    this.taxRate = 0,
    this.taxInclusive = false,
    this.serviceChargeRate = 0,
    this.serviceChargeTaxable = false,
    this.requireTableForOrders = false,
  });

  /// From a `LoginResponse` or `MeResponse` body.
  factory SessionInfo.fromJson(Object? json, {String? token}) {
    final m = _map(json);
    final policy = _map(m['tax_policy']);
    return SessionInfo(
      user: SessionUser.fromJson(m['user']),
      token: token ?? _str(m['token']),
      currencyCode: _str(m['currency_code']) ?? 'EGP',
      taxRate: _double(m['tax_rate']) ?? 0,
      taxInclusive: policy['tax_inclusive'] == true,
      serviceChargeRate: _double(policy['service_charge_rate']) ?? 0,
      serviceChargeTaxable: policy['service_charge_taxable'] == true,
      requireTableForOrders: m['require_table_for_orders'] == true,
    );
  }

  final SessionUser user;

  /// The bearer token, when the gateway holds one in Dart (the mock does;
  /// real mode keeps it in the core and leaves this null).
  final String? token;
  final String currencyCode;
  final double taxRate;
  final bool taxInclusive;
  final double serviceChargeRate;
  final bool serviceChargeTaxable;
  final bool requireTableForOrders;

  /// A platform (super) admin: every capability, picks the org to look at.
  bool get isPlatform => user.role == 'super_admin';
}

/// A branch a phone can be checked against: a pin and a radius
/// (`branchPinned`).
bool branchPinned(Branch b) =>
    b.latitude != null && b.longitude != null && (b.geoRadiusMeters ?? 0) > 0;
