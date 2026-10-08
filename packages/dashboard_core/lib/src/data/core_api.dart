/// The calls dashboard_core makes for itself, through the generated client
/// (package:dashboard_api's `DashboardApi`), the same operations the web's
/// shell asks for.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/src/data/models.dart';

class CoreApi {
  CoreApi(ApiTransport transport) : api = DashboardApi(transport);

  final DashboardApi api;

  /// `POST /auth/login` (email + password).
  Future<SessionInfo> login({
    required String email,
    required String password,
    String? orgId,
  }) async {
    final r = await api.auth.login(
      body: LoginRequest(email: email, password: password, orgId: orgId),
    );
    return SessionInfo.fromJson(r.toJson());
  }

  /// `GET /auth/me`.
  Future<SessionInfo> me({String? token}) async =>
      SessionInfo.fromJson((await api.auth.me()).toJson(), token: token);

  /// `GET /authz/me`.
  Future<MyAuthz> getMyAuthz() => api.authz.getMyAuthz();

  /// `GET /orgs/{id}/modules`.
  Future<List<String>> getOrgModules(String orgId) async =>
      (await api.orgs.getOrgModules(id: orgId)).modules;

  /// `GET /orgs/{id}`.
  Future<Org> getOrg(String orgId) => api.orgs.getOrg(id: orgId);

  /// `GET /orgs`.
  Future<List<Org>> listOrgs() => api.orgs.listOrgs();

  /// `GET /branches?org_id=`.
  Future<List<Branch>> listBranches(String orgId) =>
      api.branches.listBranches(orgId: orgId);

  /// `GET /orgs/{id}/onboarding`: `completed`.
  Future<bool> getOnboardingCompleted(String orgId) async =>
      (await api.orgs.getOnboarding(id: orgId)).completed;

  /// `GET /staff/employees?employment_status=active`: each one's status.
  Future<List<String>> listActiveEmployeeStatuses() async => [
    for (final e in await api.staff.listEmployees(employmentStatus: 'active'))
      e.employmentStatus,
  ];

  /// `GET /staff/work-shifts`: each shift's `is_active`.
  Future<List<bool>> listWorkShiftActive() async => [
    for (final s in await api.staff.listWorkShifts()) s.isActive,
  ];

  /// `GET /staff/attendance/settings`: `rules_saved_at`.
  Future<DateTime?> getAttendanceRulesSavedAt() async =>
      (await api.staff.getAttendanceSettings()).rulesSavedAt;
}
