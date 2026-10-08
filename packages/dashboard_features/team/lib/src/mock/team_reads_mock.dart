/// The area's shared READ handlers: the lists more than one team unit reads,
/// over the area seed's tables, so a unit's page can be built and tested
/// before the unit that owns the list has landed. Registered before every
/// unit's mocks: the owning unit (see `register.dart`) may register the same
/// route again with richer behaviour, and the later registration wins.
///
/// Each handler checks the backend's capability (`MadarRust src/staff/**`),
/// stays inside the caller's org and, for a branch-scoped persona, inside
/// the people of their branches, and orders rows as the backend does.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

/// The employee row of [employeeId], or null.
MockRow? teamEmployeeRow(MockDb db, String? employeeId) =>
    employeeId == null ? null : db['employees'].find(employeeId);

/// The org of [employeeId] (rows without an `org_id` belong to their
/// employee's org).
String? teamOrgOfEmployee(MockDb db, String? employeeId) =>
    teamEmployeeRow(db, employeeId)?['org_id'] as String?;

/// Whether the caller sees [employeeId]: same org, and for a branch-scoped
/// persona someone working one of their branches (`access::in_scope`).
bool teamSeesEmployee(MockRequest req, MockDb db, String? employeeId) {
  final e = teamEmployeeRow(db, employeeId);
  if (e == null || e['org_id'] != req.orgId) return false;
  final scoped = req.persona.branchIds;
  if (scoped == null) return true;
  final ids = (e['branch_ids'] as List?)?.cast<String>() ?? const [];
  return ids.any(scoped.contains);
}

/// The org of [branchId].
String? teamOrgOfBranch(MockDb db, String? branchId) => branchId == null
    ? null
    : db['branches'].find(branchId)?['org_id'] as String?;

int _desc(Object? a, Object? b) => compareJson(b, a);

void registerTeamReadMocks(MockServer server, MockDb db) {
  // ── attendance (Attendance, Team, Approvals, Requests) ───────────────
  server.on('GET', '/staff/attendance', (req) {
    final branchId = req.q('branch_id');
    req.requireCap('hr.attendance.read', branchId: branchId);
    final from = req.q('from');
    final to = req.q('to');
    final rows =
        db[TeamTables.attendance].query(
          filters: {
            'org_id': req.orgId,
            'branch_id': branchId,
            'employee_id': req.q('employee_id'),
            'status': req.q('status'),
            'cover_status': req.q('cover_status'),
            'overtime_status': req.q('overtime_status'),
          },
          where: (r) {
            final d = r['business_date']! as String;
            if (from != null && d.compareTo(from) < 0) return false;
            if (to != null && d.compareTo(to) > 0) return false;
            final scoped = req.persona.branchIds;
            return scoped == null || scoped.contains(r['branch_id']);
          },
        )..sort((a, b) {
          final c = _desc(a['business_date'], b['business_date']);
          if (c != 0) return c;
          return compareJson(a['employee_name'], b['employee_name']);
        });
    return MockResponse.ok(rows);
  });

  // ── departments (Employees, the employee profile) ─────────────────────
  server.on('GET', '/staff/departments', (req) {
    req.requireCap('hr.staff.read');
    final staff = db['employees'].rows;
    final rows = [
      for (final d in db[TeamTables.departments].query(
        filters: {'org_id': req.orgId},
        sort: 'name',
      ))
        {
          ...d,
          'employee_count': staff
              .where(
                (e) =>
                    e['department_id'] == d['id'] &&
                    e['employment_status'] == 'active',
              )
              .length,
        },
    ];
    return MockResponse.ok(rows);
  });

  // ── requests (Requests, Approvals) ────────────────────────────────────
  server.on('GET', '/staff/requests', (req) {
    req.requireCap('hr.leave.read');
    final from = req.q('from');
    final to = req.q('to');
    final rows = db[TeamTables.requests].query(
      filters: {
        'org_id': req.orgId,
        'employee_id': req.q('employee_id'),
        'kind': req.q('kind'),
        'status': req.q('status'),
      },
      where: (r) {
        final d = r['on_date']! as String;
        if (from != null && d.compareTo(from) < 0) return false;
        if (to != null && d.compareTo(to) > 0) return false;
        return teamSeesEmployee(req, db, r['employee_id'] as String?);
      },
      sort: '-created_at',
    );
    return MockResponse.ok(rows);
  });

  // ── salary advances (Approvals, Payroll) ──────────────────────────────
  server.on('GET', '/staff/payroll/advances', (req) {
    req.requireAnyCap(const ['hr.payroll.read', 'hr.advances.decide']);
    final from = req.q('from');
    final to = req.q('to');
    final rows = db[TeamTables.advances].query(
      filters: {'org_id': req.orgId, 'employee_id': req.q('employee_id')},
      where: (r) {
        final d = (r['created_at']! as String).substring(0, 10);
        if (from != null && d.compareTo(from) < 0) return false;
        if (to != null && d.compareTo(to) > 0) return false;
        return teamSeesEmployee(req, db, r['employee_id'] as String?);
      },
      sort: '-created_at',
    );
    return MockResponse.ok(rows);
  });

  // ── bonuses and deductions (Approvals, Payroll) ───────────────────────
  server.on('GET', '/staff/adjustments', (req) {
    req.requireAnyCap(const [
      'hr.payroll.read',
      'hr.adjustments.create',
      'hr.deductions.create',
    ]);
    final rows = db[TeamTables.adjustments].query(
      filters: {'employee_id': req.q('employee_id'), 'status': req.q('status')},
      where: (r) => teamSeesEmployee(req, db, r['employee_id'] as String?),
      sort: '-created_at',
    );
    return MockResponse.ok(rows);
  });

  // ── open shifts (Schedule, Approvals) ─────────────────────────────────
  server.on('GET', '/staff/open-shifts', (req) {
    req.requireCap('hr.schedule.edit');
    final from = req.q('from');
    final to = req.q('to');
    if (from == null || to == null) {
      req.badRequest('Query deserialize error: missing field `from`');
    }
    final rows = db[TeamTables.openShifts].query(
      where: (r) {
        final branch = r['branch_id'] as String?;
        if (teamOrgOfBranch(db, branch) != req.orgId) return false;
        if (branch != null && !req.persona.seesBranch(branch)) return false;
        final d = r['on_date']! as String;
        return d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
      },
      sort: 'on_date',
    );
    return MockResponse.ok(rows);
  });
}
