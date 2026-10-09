/// The mock backend of the Approvals (`/staff/approvals`, TEAM-APR rows) unit: the
/// endpoints this unit OWNS (register them here and nowhere else):
///
/// - `GET /staff/swaps`
/// - `PATCH /staff/swaps/{id}/decision`
/// - `PATCH /staff/open-shifts/{id}/decision`
/// - `PATCH /staff/attendance/{id}/cover`
/// - `PATCH /staff/attendance/{id}/overtime`
///
/// Each follows MadarRust `src/staff/dawam/roster.rs` (`list_swaps`,
/// `decide_swap`, `decide_claim`) and `presence.rs` (`decide_cover`,
/// `decide_overtime`): the capability, the branch it is decided at, "not
/// your own", one decision only (a second is `ALREADY_DECIDED {status}`,
/// nothing waiting is the coded 404), and a closed payroll month refusing an
/// approval (`PERIOD_CLOSED {date, paid}`) but never a rejection.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'team_reads_mock.dart';

/// `already_decided`: 409 `ALREADY_DECIDED {status}`.
Never _alreadyDecided(MockRequest req, String status) => req.fail(
  MockResponse.error(
    409,
    'This was already decided ($status).',
    code: 'ALREADY_DECIDED',
    vars: {'status': status},
  ),
);

/// `staff::coded(404, code, …)`.
Never _nothingWaiting(MockRequest req, String code, String words) =>
    req.fail(MockResponse.error(404, words, code: code));

/// A coded 403 (`OWN_SWAP`, `OWN_CLAIM`, `OWN_COVER`, `OWN_OVERTIME`).
Never _own(MockRequest req, String code, String words) =>
    req.fail(MockResponse.error(403, words, code: code));

/// The employee records linked to the caller.
Set<String> _mine(MockRequest req, MockDb db) => {
  for (final e in db['employees'].rows)
    if (e['user_id'] == req.persona.userId) e['id']! as String,
};

/// `period_lock::assert_open`: an approved, paid or closed month refuses.
void _assertOpen(MockRequest req, MockDb db, String org, String day) {
  for (final p in db[TeamTables.payrollPeriods].rows) {
    if (p['org_id'] != org) continue;
    final status = p['status'];
    if (status != 'generated' && status != 'paid' && status != 'closed') {
      continue;
    }
    final from = p['start_date']! as String;
    final to = p['end_date']! as String;
    if (from.compareTo(day) > 0 || to.compareTo(day) < 0) continue;
    final paid = status == 'paid' || status == 'closed';
    req.fail(
      MockResponse.error(
        409,
        paid
            ? 'That month is paid — this dated $day can\'t change it. '
                  'Add it to the next open month instead.'
            : 'That month\'s payroll is approved — this dated $day can\'t '
                  'change it. Reopen it first, or add it to the next open month.',
        code: 'PERIOD_CLOSED',
        vars: {'date': day, 'paid': paid},
      ),
    );
  }
}

void registerApprovalsMocks(MockServer server, MockDb db) {
  // The last decision on each open shift's claim (`staff_open_shift_claims`).
  final lastClaim = <String, String>{};

  // ── swaps ─────────────────────────────────────────────────────────────
  server.on('GET', '/staff/swaps', (req) {
    req.requireCap('hr.schedule.edit');
    final status = req.q('status');
    final rows = db[TeamTables.swaps].query(
      filters: {'status': status},
      where: (s) {
        final a = s['requester_id'] as String?;
        if (teamOrgOfEmployee(db, a) != req.orgId) return false;
        // Either side at the caller's branches (`in_scope` OR).
        return teamSeesEmployee(req, db, a) ||
            teamSeesEmployee(req, db, s['peer_id'] as String?);
      },
      sort: '-created_at',
    );
    return MockResponse.ok(rows);
  });

  server.on('PATCH', '/staff/swaps/{id}/decision', (req) {
    req.requireCap('hr.schedule.edit');
    final approve = req.json['approve'] == true;
    final row = db[TeamTables.swaps].find(req.param('id'));
    final org = teamOrgOfEmployee(db, row?['requester_id'] as String?);
    if (row == null || org != req.orgId) {
      _nothingWaiting(req, 'NO_SWAP_WAITING', 'No swap waiting here.');
    }
    final a = row['requester_id']! as String;
    final b = row['peer_id']! as String;
    // Both rosters change, so both sides' rights count (RO-6).
    for (final who in [a, b]) {
      if (!teamSeesEmployee(req, db, who)) {
        req.fail(MockResponse.denied('hr.schedule.edit'));
      }
    }
    final status = row['status']! as String;
    if (status != 'pending') {
      if (const {'approved', 'rejected', 'cancelled'}.contains(status)) {
        _alreadyDecided(req, status);
      }
      _nothingWaiting(req, 'NO_SWAP_WAITING', 'No swap waiting here.');
    }
    final mine = _mine(req, db);
    if (mine.contains(a) || mine.contains(b)) {
      _own(req, 'OWN_SWAP', "You can't approve a swap you're part of.");
    }
    // ponytail: the roster move itself (`apply_swap`) and the started /
    // unpublished re-checks are the Schedule unit's; only the swap's state
    // is kept here.
    db[TeamTables.swaps].update(row['id']! as String, {
      'status': approve ? 'approved' : 'rejected',
    });
    return MockResponse.empty();
  });

  // ── open-shift claims ─────────────────────────────────────────────────
  server.on('PATCH', '/staff/open-shifts/{id}/decision', (req) {
    req.requireCap('hr.schedule.edit');
    final approve = req.json['approve'] == true;
    final row = db[TeamTables.openShifts].find(req.param('id'));
    final branch = row?['branch_id'] as String?;
    if (row == null || teamOrgOfBranch(db, branch) != req.orgId) {
      _nothingWaiting(req, 'NO_CLAIM_WAITING', 'No claim waiting here.');
    }
    if (row['status'] != 'claimed' || row['claimed_by'] == null) {
      // `no_claim_waiting`: the last claim's decision, else nothing.
      final last = lastClaim[row['id']];
      if (last == 'approved' || last == 'declined') {
        req.requireBranch(branch!);
        _alreadyDecided(req, last!);
      }
      _nothingWaiting(req, 'NO_CLAIM_WAITING', 'No claim waiting here.');
    }
    req.requireBranch(branch!);
    final claimer = row['claimed_by']! as String;
    if (_mine(req, db).contains(claimer)) {
      _own(req, 'OWN_CLAIM', "You can't approve your own claim.");
    }
    final id = row['id']! as String;
    if (approve) {
      db[TeamTables.openShifts].update(id, {'status': 'filled'});
      lastClaim[id] = 'approved';
    } else {
      // The shift reopens; the claimer's declined claim stays theirs.
      db[TeamTables.openShifts].update(id, {
        'status': 'open',
        'claimed_by': null,
        'claimed_by_name': null,
        'claimed_at': null,
      });
      lastClaim[id] = 'declined';
    }
    // ponytail: the labour-limit warnings of the claimer's new day
    // (`day_view(...).warnings`) are not computed; a test answers them.
    return MockResponse.ok({
      'status': approve ? 'approved' : 'rejected',
      'warnings': <Object?>[],
    });
  });

  // ── covers ────────────────────────────────────────────────────────────
  server.on('PATCH', '/staff/attendance/{id}/cover', (req) {
    req.requireCap('hr.shift_cover.confirm');
    final approve = req.json['approve'] == true;
    final table = db[TeamTables.attendance];
    final row = table.find(req.param('id'));
    if (row == null ||
        row['org_id'] != req.orgId ||
        row['cover_status'] != 'pending') {
      // Pending only: a decided one reads as nothing waiting (CV-5).
      _nothingWaiting(req, 'NO_COVER_WAITING', 'No cover waiting here.');
    }
    req.requireCap(
      'hr.shift_cover.confirm',
      branchId: row['branch_id']! as String,
    );
    final mine = _mine(req, db);
    if (mine.contains(row['employee_id']) ||
        mine.contains(row['covered_employee_id'])) {
      _own(req, 'OWN_COVER', "You can't confirm a cover you're part of.");
    }
    // Confirming pays it: never into a closed month; rejecting may.
    if (approve) {
      _assertOpen(req, db, req.orgId!, row['business_date']! as String);
    }
    final status = approve ? 'confirmed' : 'rejected';
    final id = row['id']! as String;
    final updated = table.update(id, {
      'cover_status': status,
      'edited_by': req.persona.userId,
    });
    // The cover's flag says what was decided (CV-3).
    for (final f in db[TeamTables.flags].rows) {
      if (f['attendance_record_id'] == id &&
          f['kind'] == 'cover' &&
          f['resolution'] == null) {
        db[TeamTables.flags].update(f['id']! as String, {
          'resolution': status,
          'resolved_at': db.nowIso,
        });
      }
    }
    return MockResponse.ok(updated);
  });

  // ── overtime ──────────────────────────────────────────────────────────
  server.on('PATCH', '/staff/attendance/{id}/overtime', (req) {
    req.requireCap('hr.overtime.approve');
    final approve = req.json['approve'] == true;
    final table = db[TeamTables.attendance];
    final row = table.find(req.param('id'));
    if (row == null ||
        row['org_id'] != req.orgId ||
        row['overtime_status'] == null) {
      _nothingWaiting(req, 'NO_OVERTIME_WAITING', 'No overtime waiting here.');
    }
    final status = row['overtime_status']! as String;
    if (status != 'pending') _alreadyDecided(req, status);
    if (_mine(req, db).contains(row['employee_id'])) {
      _own(req, 'OWN_OVERTIME', "You can't approve your own overtime.");
    }
    req.requireCap(
      'hr.overtime.approve',
      branchId: row['branch_id']! as String,
    );
    // ponytail: the approver's money limit on the priced overtime
    // (`authz::require::settle`) is not modelled; every persona here
    // either holds the right outright or lacks it.
    if (approve) {
      _assertOpen(req, db, req.orgId!, row['business_date']! as String);
    }
    final updated = table.update(row['id']! as String, {
      'overtime_status': approve ? 'approved' : 'rejected',
      'edited_by': req.persona.userId,
    });
    return MockResponse.ok(updated);
  });
}
