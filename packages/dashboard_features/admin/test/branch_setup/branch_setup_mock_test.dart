// The branch-plan mock against hand-worked answers: what GET assembles and
// reads, what PUT checks and writes (the branch's printer columns, the
// stations, the activation codes, the version), the gates.
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_admin/src/branch_setup/plan.dart';
import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final String _bar = BranchPlanSeed.stationId('heliopolis', 'bar');
final String _kitchen = BranchPlanSeed.stationId('heliopolis', 'kitchen');

Future<ApiException> refused(Future<Object?> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

SavePlanRequest save(String branch, int version, BuilderPlan plan) =>
    SavePlanRequest(
      branchId: branch,
      expectedVersion: version,
      plan: toWire(plan),
    );

void main() {
  test('ADM-BSU-005 a never-saved branch, assembled: Zamalek', () async {
    final b = PlanBackend();
    final view = await b.api.branchPlan.getPlan(branchId: SeedIds.zamalek);
    expect(view.saved, isFalse);
    expect(view.version, 0);
    // Stations on auto with an active one: kds.
    expect(view.routingMode, 'kds');
    final plan = fromWire(view.plan);
    // Registered devices by kind then code: K1, T1, T2, W1, W2.
    expect(
      [for (final d in plan.devices) (d.kind, d.name)],
      [
        ('kitchen', 'Kitchen screen'),
        ('pos', 'Counter 1'),
        ('pos', 'Counter 2'),
        ('waiter', 'Floor tablet'),
        ('waiter', 'Terrace tablet'),
      ],
    );
    final receipt = plan.printers.first;
    expect(receipt.name, 'Receipt printer');
    expect(receipt.ip, '192.168.1.43');
    expect(receipt.brand, 'epson');
    // Every POS and waiter slot prints receipts there; the screen does not.
    expect(
      [for (final d in plan.devices) d.receiptPrinterId == receipt.id],
      [false, true, true, true, true],
    );
    // Front column 0, 120, 240, 360; the receipt printer under them.
    expect([for (final d in plan.devices) d.y], [0, 0, 120, 240, 360]);
    expect(receipt.y, 4 * 120 + 60);
    expect(
      [for (final p in plan.printers.skip(1)) (p.name, p.ip, p.brand)],
      [
        ('Bar printer', '192.168.10.21', 'epson'),
        ('Kitchen printer', '192.168.10.22', 'star'),
      ],
    );
    expect([for (final s in plan.sections) s.name], ['Bar', 'Kitchen']);
    expect(plan.sections.first.isDefault, isTrue);
    expect(plan.sections.first.categoryIds, [
      MockSeed.categoryId('hot'),
      MockSeed.categoryId('iced'),
      MockSeed.categoryId('tea'),
      MockSeed.categoryId('juice'),
    ]);
    expect(plan.tillPrintsKitchen, isTrue, reason: 'mode unset');
    expect([for (final c in view.openItems) c.count], [2]);
    // The croissant routed to the kitchen; the cookie's Pastry is closed.
    expect(
      {
        for (final c in view.itemOverrides) c.sectionId: c.count,
      }[BranchPlanSeed.stationId('zamalek', 'kitchen')],
      1,
    );
    expect(view.categories, hasLength(7));
    expect(view.devices, hasLength(5));
  });

  test('ADM-BSU-005 New Cairo is switched off: no chits; the retired iPad '
      'is left out at Maadi', () async {
    final b = PlanBackend();
    final nc = await b.api.branchPlan.getPlan(branchId: SeedIds.newCairo);
    expect(nc.routingMode, 'off');
    expect(fromWire(nc.plan).tillPrintsKitchen, isFalse);
    final maadi = await b.api.branchPlan.getPlan(branchId: SeedIds.maadi);
    expect([for (final d in maadi.devices) d.code], ['T1']);
  });

  test('ADM-BSU-006 a saved branch keeps a printer changed elsewhere: the '
      'station\'s and the branch\'s', () async {
    final b = PlanBackend();
    var plan = fromWire(
      (await b.api.branchPlan.getPlan(branchId: SeedIds.heliopolis)).plan,
    );
    expect(plan.section(_bar)!.printerIds, [BranchPlanSeed.barPrinter]);
    // The kitchen-stations page moved the bar's printer; the branch dialog
    // the receipt printer.
    b.table(BranchPlanTables.stations).find(_bar)!['printer_ip'] =
        '192.168.1.70';
    b.db['branches'].find(SeedIds.heliopolis)!['printer_ip'] = '192.168.1.99';
    plan = fromWire(
      (await b.api.branchPlan.getPlan(branchId: SeedIds.heliopolis)).plan,
    );
    final first = plan.printer(plan.section(_bar)!.printerIds.first)!;
    expect(first.ip, '192.168.1.70');
    expect(first.name, 'Bar printer');
    expect(plan.section(_bar)!.printerIds, hasLength(2));
    final receipt = plan.printer(
      plan.device(BranchPlanSeed.counter)!.receiptPrinterId,
    )!;
    expect(receipt.ip, '192.168.1.99');
    expect(receipt.name, 'Receipt printer');
    // A printer cleared there is not mirrored.
    b.table(BranchPlanTables.stations).find(_kitchen)!['printer_ip'] = null;
    plan = fromWire(
      (await b.api.branchPlan.getPlan(branchId: SeedIds.heliopolis)).plan,
    );
    expect(plan.section(_kitchen)!.printerIds, [BranchPlanSeed.kitchenPrinter]);
  });

  test('ADM-BSU-024 versions: newest first, with the saver', () async {
    final b = PlanBackend();
    final v = await b.api.branchPlan.listVersions(branchId: SeedIds.heliopolis);
    expect([for (final x in v) x.version], [2, 1]);
    expect(v.first.savedByName, 'Nour El-Sayed');
    expect(v.last.plan.devices, hasLength(1));
  });

  test('ADM-BSU-078/079 a save writes the branch, the stations, the codes and '
      'the version', () async {
    final b = PlanBackend();
    // A code issued for the kitchen screen's slot, then the slot removed.
    await b.api.devices.createCode(
      body: CreateActivationCodeRequest(
        branchId: SeedIds.heliopolis,
        slotId: BranchPlanSeed.screen,
      ),
    );
    expect(
      b.codes.rows.where((c) => c['slot_id'] == BranchPlanSeed.screen),
      hasLength(1),
    );
    final view = await b.api.branchPlan.getPlan(branchId: SeedIds.heliopolis);
    var plan = removePieces(fromWire(view.plan), {
      pieceKey(PieceKind.device, BranchPlanSeed.screen),
    });
    // The till's receipts go to a new network printer, Star, at .50; the
    // kitchen loses its printer to a new one; the routing moves to the till.
    plan = plan
        .mapPrinters(
          (p) => p.id == BranchPlanSeed.receipt
              ? p.copyWith(ip: () => ' 192.168.1.50 ', brand: () => null)
              : p.id == BranchPlanSeed.kitchenPrinter
              ? p.copyWith(brand: () => 'epson', port: () => 9200)
              : p,
        )
        .copyWith(tillPrintsKitchen: false);
    final out = await b.api.branchPlan.savePlan(
      body: save(SeedIds.heliopolis, 2, plan),
    );
    expect(out.version, 3);
    expect(out.saved, isTrue);
    final branch = b.db['branches'].find(SeedIds.heliopolis)!;
    expect(branch['printer_ip'], '192.168.1.50');
    expect(branch['printer_port'], 9100);
    // Brand Other keeps the branch's own (Epson).
    expect(branch['printer_brand'], 'epson');
    expect(branch['till_prints_kitchen'], isFalse);
    expect(branch['hardware_plan_version'], 3);
    expect(
      b
          .table(BranchPlanTables.modes)
          .firstWhere((r) => r['branch_id'] == SeedIds.heliopolis)!['mode'],
      'till',
    );
    final kitchen = b.table(BranchPlanTables.stations).find(_kitchen)!;
    expect(
      (
        kitchen['printer_ip'],
        kitchen['printer_port'],
        kitchen['printer_brand'],
      ),
      ('192.168.1.61', 9200, 'epson'),
    );
    // The removed slot took its code with it.
    expect(
      b.codes.rows.where((c) => c['slot_id'] == BranchPlanSeed.screen),
      isEmpty,
    );
    expect(b.table(BranchPlanTables.slots).find(BranchPlanSeed.screen), isNull);
    final versions = await b.api.branchPlan.listVersions(
      branchId: SeedIds.heliopolis,
    );
    expect(versions.first.version, 3);
    expect(versions.first.plan.devices, hasLength(1));
    // Read back: the same plan.
    final again = await b.api.branchPlan.getPlan(branchId: SeedIds.heliopolis);
    expect(samePlan(fromWire(again.plan), fromWire(out.plan)), isTrue);
    expect(
      fromWire(again.plan).printer(BranchPlanSeed.receipt)!.ip,
      '192.168.1.50',
    );
  });

  test('ADM-BSU-079 a dropped station is soft-deleted with its item routes; '
      'a new section becomes a station', () async {
    final b = PlanBackend();
    final view = await b.api.branchPlan.getPlan(branchId: SeedIds.zamalek);
    var plan = removePieces(fromWire(view.plan), {
      pieceKey(PieceKind.section, BranchPlanSeed.stationId('zamalek', 'bar')),
    });
    // Zamalek's kitchen has items cooking: keep it, drop the bar (idle).
    plan = plan.copyWith(
      sections: [
        ...plan.sections,
        const BuilderSection(
          id: '0b6f3a3e-6c43-4e56-9a0f-7b1d6a5a2e10',
          name: 'Juice bar',
          isDefault: false,
          printerIds: [],
          screenIds: [],
          x: 340,
          y: 360,
        ),
      ],
    );
    plan = addLink(
      plan,
      const PieceRef(PieceKind.section, '0b6f3a3e-6c43-4e56-9a0f-7b1d6a5a2e10'),
      PieceRef(PieceKind.device, plan.devices.first.id),
    );
    await b.api.branchPlan.savePlan(body: save(SeedIds.zamalek, 0, plan));
    final bar = b
        .table(BranchPlanTables.stations)
        .find(BranchPlanSeed.stationId('zamalek', 'bar'))!;
    expect(bar['deleted_at'], isNotNull);
    expect(bar['is_default'], isFalse);
    final juice = b
        .table(BranchPlanTables.stations)
        .find('0b6f3a3e-6c43-4e56-9a0f-7b1d6a5a2e10')!;
    expect(
      (juice['name'], juice['is_active'], juice['sort_order']),
      ('Juice bar', true, 1),
    );
    // The inactive pastry station is left alone, its item route too.
    expect(
      b
          .table(BranchPlanTables.stations)
          .find(BranchPlanSeed.stationId('zamalek', 'pastry'))!['deleted_at'],
      isNull,
    );
    expect(b.table(BranchPlanTables.itemRoutes).rows, hasLength(2));
  });

  test('ADM-BSU-081/082/083 refusals: a stale version, a station still '
      'cooking, every blocking check, unknown references', () async {
    final b = PlanBackend();
    final view = await b.api.branchPlan.getPlan(branchId: SeedIds.heliopolis);
    final plan = fromWire(view.plan);
    var e = await refused(
      b.api.branchPlan.savePlan(body: save(SeedIds.heliopolis, 1, plan)),
    );
    expect((e.status, e.code), (409, 'PLAN_CHANGED'));
    e = await refused(
      b.api.branchPlan.savePlan(
        body: save(
          SeedIds.heliopolis,
          2,
          removePieces(plan, {pieceKey(PieceKind.section, _bar)}),
        ),
      ),
    );
    expect((e.status, e.code), (409, 'SECTION_HAS_OPEN_TICKETS'));
    expect(e.message, contains("'Bar' (3)"));
    // Blocking checks, joined by "; ".
    final broken = plan
        .mapSections((s) => s.copyWith(name: 'Bar'))
        .mapPrinters((p) => p.copyWith(paperMm: 70, port: () => 0));
    e = await refused(
      b.api.branchPlan.savePlan(body: save(SeedIds.heliopolis, 2, broken)),
    );
    expect(e.status, 400);
    expect(e.message, contains("Two sections are called 'Bar'"));
    expect(
      e.message,
      contains("'Receipt printer' must use 58 or 80 mm paper; "),
    );
    expect(e.message, contains("has a port outside 1-65535"));
    // A category deleted since.
    b.db['categories'].removeWhere(
      (c) => c['id'] == MockSeed.categoryId('hot'),
    );
    e = await refused(
      b.api.branchPlan.savePlan(body: save(SeedIds.heliopolis, 2, plan)),
    );
    expect(e.message, contains(BranchPlanRefusals.unknownCategory));
  });

  test('ADM-BSU-086 gates: read and save per capability and branch', () async {
    final limited = PlanBackend(persona: Persona.limited);
    var e = await refused(
      limited.api.branchPlan.getPlan(branchId: SeedIds.maadi),
    );
    expect(e.status, 403);
    expect(e.message, contains('kitchen.stations.read'));
    e = await refused(
      limited.api.branchPlan.listVersions(branchId: SeedIds.maadi),
    );
    expect(e.status, 403);
    e = await refused(
      limited.api.branchPlan.savePlan(
        body: save(SeedIds.maadi, 0, BuilderPlan.empty),
      ),
    );
    expect(e.message, contains('kitchen.stations.edit'));
    final manager = PlanBackend(persona: Persona.manager);
    e = await refused(
      manager.api.branchPlan.getPlan(branchId: SeedIds.heliopolis),
    );
    expect(e.status, 403);
    expect(e.message, contains('Not assigned to this branch'));
    // The manager edits Zamalek (stations create/delete are theirs too).
    final z = await manager.api.branchPlan.getPlan(branchId: SeedIds.zamalek);
    final out = await manager.api.branchPlan.savePlan(
      body: save(SeedIds.zamalek, 0, fromWire(z.plan)),
    );
    expect(out.version, 1);
    // …but issues no setup code (branches.edit).
    e = await refused(
      manager.api.devices.createCode(
        body: CreateActivationCodeRequest(
          branchId: SeedIds.zamalek,
          slotId: fromWire(out.plan).devices.first.id,
        ),
      ),
    );
    expect(e.message, contains('branches.edit'));
  });

  test('ADM-BSU-059/060 a slot code takes the slot\'s kind and name; the '
      'tablet that uses it fills the slot, without a new version', () async {
    final b = PlanBackend();
    final code = await b.api.devices.createCode(
      body: CreateActivationCodeRequest(
        branchId: SeedIds.heliopolis,
        slotId: BranchPlanSeed.screen,
      ),
    );
    expect(code.kind.value, 'kds');
    expect(code.label, 'Kitchen screen');
    expect(code.slotId, BranchPlanSeed.screen);
    // A code with no slot answers as the Devices page's.
    final plain = await b.api.devices.createCode(
      body: CreateActivationCodeRequest(branchId: SeedIds.heliopolis),
    );
    expect((plain.kind.value, plain.label, plain.slotId), ('pos', null, null));
    final k2 = AdminSeed.deviceId('heliopolis', 'T1');
    activateSlotCode(b.db, code.code, k2);
    final view = await b.api.branchPlan.getPlan(branchId: SeedIds.heliopolis);
    expect(view.version, 2);
    final plan = fromWire(view.plan);
    expect(plan.device(BranchPlanSeed.screen)!.deviceId, k2);
    expect(
      plan.device(BranchPlanSeed.counter)!.deviceId,
      isNull,
      reason: 'left',
    );
    final e = await refused(
      b.api.devices.createCode(
        body: CreateActivationCodeRequest(
          branchId: SeedIds.heliopolis,
          slotId: BranchPlanSeed.slotId('zamalek', 'nope'),
        ),
      ),
    );
    expect(e.status, 404);
  });
}
