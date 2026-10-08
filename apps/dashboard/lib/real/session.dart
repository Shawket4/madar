/// Real mode's session over the core (the core holds the token, refreshes it
/// and sends the org and branch headers): sign-in, restore, sign-out and the
/// scope, as dashboard_core's [SessionGateway].
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, ApiTransport;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart' as rb;

/// The core's snapshot as dashboard_core's session (the token stays in the
/// core).
SessionInfo sessionInfoOf(rb.SessionSnapshot s) => SessionInfo(
  user: SessionUser(
    id: s.userId,
    name: s.displayName,
    role: s.role,
    orgId: s.orgId,
    branchId: s.branchId,
  ),
  currencyCode: s.currencyCode,
  taxRate: s.taxRate,
  taxInclusive: s.taxInclusive,
  serviceChargeRate: s.serviceChargeRate,
  serviceChargeTaxable: s.serviceChargeTaxable,
  requireTableForOrders: s.requireTableForOrders,
);

/// A core error as the seam's [ApiException], worded by the core.
ApiException apiExceptionOfCore(rb.MadarBridge bridge, Object e) {
  if (e is ApiException) return e;
  if (e is! rb.MadarError) {
    return ApiException(status: 0, message: '$e');
  }
  final words = bridge.humanMessage(e);
  return switch (e) {
    rb.MadarError_Unauthenticated() => ApiException(
      status: 401,
      message: words,
    ),
    rb.MadarError_Forbidden() => ApiException(status: 403, message: words),
    rb.MadarError_Validation() => ApiException(
      status: 422,
      code: 'validation',
      message: words,
    ),
    rb.MadarError_Server(:final status, :final code) => ApiException(
      status: status,
      code: code.isEmpty ? null : code,
      message: words,
    ),
    _ => ApiException(status: 0, message: words),
  };
}

class CoreSessionGateway implements SessionGateway {
  CoreSessionGateway(this.bridge, this.transport);

  final rb.MadarBridge bridge;

  /// For `GET /auth/me` (the email the snapshot does not carry).
  final ApiTransport transport;

  /// The snapshot plus the person's email and active flag from `/auth/me`
  /// when the server answers in time; the snapshot alone otherwise.
  Future<SessionInfo> _enrich(SessionInfo info) async {
    try {
      return await CoreApi(transport).me().timeout(const Duration(seconds: 5));
    } on Object {
      return info;
    }
  }

  @override
  Future<SessionInfo?> restore() async {
    final snap = bridge.restoreSessionCached() ?? bridge.currentSession();
    if (snap == null) return null;
    return _enrich(sessionInfoOf(snap));
  }

  @override
  Future<SessionInfo> signIn({
    required String email,
    required String password,
    String? orgId,
  }) async {
    final rb.SessionSnapshot snap;
    try {
      snap = await bridge.dashboardSignIn(
        email: email,
        password: password,
        orgId: orgId,
      );
    } on Object catch (e) {
      throw apiExceptionOfCore(bridge, e);
    }
    return _enrich(sessionInfoOf(snap));
  }

  @override
  Future<void> signOut() => bridge.logout(wipeOutbox: false);

  @override
  Future<void> applyScope({
    required String? orgId,
    required String? branchId,
  }) async {
    bridge.setActiveScope(orgId: orgId, branchId: branchId);
  }
}
