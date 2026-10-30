// The Branches handlers against hand-worked answers (ADM-BRA-039 and the
// backend rules they mirror): kinds, the warehouse limit, the still-selling
// refusal, and every row carrying `kind`.
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<ApiException> _refused(Future<Object?> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

CreateBranchRequest _new(String name, [BranchKind? kind]) =>
    CreateBranchRequest(orgId: SeedIds.sabahOrg, name: name, kind: kind);

void main() {
  late MockDb db;
  late DashboardApi api;
  setUp(() {
    final s = branchesServer();
    db = s.db;
    api = DashboardApi(s.server);
  });

  test('ADM-BRA-039 GET: selling branches by default, the warehouses with '
      'include_warehouses, one kind with kind=', () async {
    addLocation(db);
    final selling = await api.branches.listBranches(orgId: SeedIds.sabahOrg);
    expect(selling.map((b) => b.name), [
      'Heliopolis',
      'Maadi',
      'New Cairo',
      'Zamalek',
    ]);
    final all = await api.branches.listBranches(
      orgId: SeedIds.sabahOrg,
      includeWarehouses: true,
    );
    expect(all, hasLength(5));
    final only = await api.branches.listBranches(
      orgId: SeedIds.sabahOrg,
      kind: BranchKind.warehouse,
    );
    expect(only.single.name, 'Obour Warehouse');
  });

  test('ADM-BRA-039 a create carries kind: branch by default, warehouse when '
      'asked; the row decodes as a Branch', () async {
    final b = await api.branches.createBranch(body: _new('Sheikh Zayed'));
    expect(b.kind, BranchKind.branch);
    expect(db['branches'].get(b.id)['kind'], 'branch');
    final w = await api.branches.createBranch(
      body: _new('Badr Warehouse', BranchKind.warehouse),
    );
    expect(w.kind, BranchKind.warehouse);
    expect(w.printerPort, 9100);
    expect(w.oldBillHours, 3);
  });

  test('ADM-BRA-039 max_warehouses: null is no limit; at the limit a create '
      'or a switch is 409 WAREHOUSE_LIMIT', () async {
    addLocation(db);
    addLocation(db, name: 'Badr Warehouse');
    final kiosk = addLocation(db, name: 'Abbasiya Kiosk', kind: 'branch');
    maxWarehouses(db, 2);
    final e = await _refused(
      api.branches.createBranch(body: _new('Ain Sokhna', BranchKind.warehouse)),
    );
    expect(e.status, 409);
    expect(e.code, 'WAREHOUSE_LIMIT');
    expect(e.message, contains('can have 2 warehouse(s), and has 2.'));
    final s = await _refused(
      api.branches.patchBranch(
        id: kiosk['id']! as String,
        body: const UpdateBranchRequest(kind: BranchKind.warehouse),
      ),
    );
    expect(s.code, 'WAREHOUSE_LIMIT');
    expect(db['branches'].get(kiosk['id']! as String)['kind'], 'branch');
    // A selling branch is not counted, and is still allowed.
    expect(
      (await api.branches.createBranch(body: _new('Ain Sokhna'))).kind,
      BranchKind.branch,
    );
    maxWarehouses(db, null);
    await api.branches.createBranch(
      body: _new('Ain Sokhna Store', BranchKind.warehouse),
    );
  });

  test('ADM-BRA-039 a switch while selling: 409 BRANCH_STILL_SELLING naming '
      'each step; a retired device does not count', () async {
    final kiosk = addLocation(db, name: 'Abbasiya Kiosk', kind: 'branch');
    final id = kiosk['id']! as String;
    db['tills'].insert({
      'id': db.newId('tills'),
      'branch_id': id,
      'status': 'open',
    }, timestamps: false);
    db[AdminTables.devices].insert({
      'id': db.newId('devices'),
      'branch_id': id,
      'retired_at': null,
    }, timestamps: false);
    db[AdminTables.devices].insert({
      'id': db.newId('devices'),
      'branch_id': id,
      'retired_at': db.nowIso,
    }, timestamps: false);
    final e = await _refused(
      api.branches.patchBranch(
        id: id,
        body: const UpdateBranchRequest(kind: BranchKind.warehouse),
      ),
    );
    expect(e.status, 409);
    expect(e.code, 'BRANCH_STILL_SELLING');
    expect(
      e.message,
      contains(
        'To make this a warehouse, first close its open tills, unpair its '
        'devices.',
      ),
    );
    expect(db['branches'].get(id)['kind'], 'branch');

    for (final r in db['tills'].where((r) => r['branch_id'] == id)) {
      r['status'] = 'closed';
    }
    for (final r in db[AdminTables.devices].where(
      (r) => r['branch_id'] == id,
    )) {
      r['retired_at'] = db.nowIso;
    }
    final done = await api.branches.patchBranch(
      id: id,
      body: const UpdateBranchRequest(kind: BranchKind.warehouse),
    );
    expect(done.kind, BranchKind.warehouse);
    // Back to a branch: no checks.
    final back = await api.branches.patchBranch(
      id: id,
      body: const UpdateBranchRequest(kind: BranchKind.branch),
    );
    expect(back.kind, BranchKind.branch);
  });

  test(
    'ADM-BRA-039 a seed branch still sells (its tills and devices)',
    () async {
      final e = await _refused(
        api.branches.patchBranch(
          id: SeedIds.zamalek,
          body: const UpdateBranchRequest(kind: BranchKind.warehouse),
        ),
      );
      expect(e.code, 'BRANCH_STILL_SELLING');
      expect(e.message, contains('unpair its devices'));
    },
  );

  test('ADM-BRA-033 a PATCH without kind leaves it; a same-kind PATCH runs '
      'no checks', () async {
    final w = addLocation(db);
    maxWarehouses(db, 0);
    final id = w['id']! as String;
    final b = await api.branches.patchBranch(
      id: id,
      body: const UpdateBranchRequest(
        name: 'Obour Depot',
        kind: BranchKind.warehouse,
      ),
    );
    expect(b.name, 'Obour Depot');
    expect(b.kind, BranchKind.warehouse);
  });

  test(
    'ADM-BRA-024 old_bill_hours out of 1..168 is the backend\'s 400',
    () async {
      final e = await _refused(
        api.branches.patchBranch(
          id: SeedIds.zamalek,
          body: const UpdateBranchRequest(oldBillHours: 200),
        ),
      );
      expect(e.status, 400);
    },
  );

  test('teller pick: a PATCH stores pick_teller_at_checkout; absent or null '
      'keeps it; a new branch starts off', () async {
    final on = await api.branches.patchBranch(
      id: SeedIds.zamalek,
      body: const UpdateBranchRequest(pickTellerAtCheckout: true),
    );
    expect(on.pickTellerAtCheckout, isTrue);
    final kept = await api.branches.patchBranch(
      id: SeedIds.zamalek,
      body: const UpdateBranchRequest(
        name: 'Zamalek Nile',
        explicitNulls: {'pick_teller_at_checkout'},
      ),
    );
    expect(kept.pickTellerAtCheckout, isTrue);
    final off = await api.branches.patchBranch(
      id: SeedIds.zamalek,
      body: const UpdateBranchRequest(pickTellerAtCheckout: false),
    );
    expect(off.pickTellerAtCheckout, isFalse);
    final made = await api.branches.createBranch(body: _new('Sheikh Zayed'));
    expect(made.pickTellerAtCheckout, isFalse);
  });

  test(
    'ADM-BRA-017 a reader may not write: 403 on create, edit, delete',
    () async {
      final s = branchesServer(persona: Persona.limited);
      final reader = DashboardApi(s.server);
      for (final call in <Future<Object?> Function()>[
        () => reader.branches.createBranch(body: _new('Sheikh Zayed')),
        () => reader.branches.patchBranch(
          id: SeedIds.maadi,
          body: const UpdateBranchRequest(name: 'Maadi Degla'),
        ),
        () => reader.branches.deleteBranch(id: SeedIds.maadi),
      ]) {
        expect((await _refused(call())).status, 403);
      }
    },
  );
}
