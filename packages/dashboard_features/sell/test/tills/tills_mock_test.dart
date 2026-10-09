// The tills mock handlers against hand-computed expectations: the backend's
// gates, filters, carryover rule, close reconciliation, cash movement rules
// and delete guard (MadarRust `src/tills/handlers.rs`, `reconcile.rs`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tills_support.dart';

({DashboardApi api, MockServer server, MockDb db}) _api({
  Persona persona = Persona.owner,
}) {
  final s = tillsServer(persona: persona);
  return (api: DashboardApi(s.server), server: s.server, db: s.db);
}

Matcher _status(int status) =>
    isA<ApiException>().having((e) => e.status, 'status', status);

void main() {
  final helio = SeedIds.heliopolis;

  test('the list is newest first, filters by status / teller / device / '
      'flagged / from, and spans the org with the nil id', () async {
    final m = _api();
    final all = await m.api.tills.listTills(branchId: helio);
    expect(all.total, all.data.length);
    final opened = [for (final t in all.data) t.openedAt];
    expect(opened, [...opened]..sort((a, b) => b.compareTo(a)));
    final open = await m.api.tills.listTills(branchId: helio, status: 'open');
    expect({for (final t in open.data) t.id}, openAt(m.db, helio));
    expect(
      openAt(m.db, helio),
      containsAll([TillIds.helioMorning, TillIds.helioSecond]),
    );
    final flagged = await m.api.tills.listTills(branchId: helio, flagged: true);
    expect([for (final t in flagged.data) t.id], [TillIds.helioSecond]);
    final t2 = await m.api.tills.listTills(
      branchId: helio,
      deviceId: mockUuid('device:heliopolis:T3'),
    );
    expect([for (final t in t2.data) t.id], [TillIds.helioSecond]);
    final org = await m.api.tills.listTills(
      branchId: '00000000-0000-0000-0000-000000000000',
    );
    expect(org.total, m.db['tills'].length);
    await expectLater(
      m.api.tills.listTills(branchId: helio, status: 'nope'),
      throwsA(_status(400)),
    );
  });

  test('the bills notice needs tickets.read; the list only till.read', () async {
    final m = _api(persona: Persona.limited);
    await expectLater(
      m.api.tills.getOpenBillsNotice(branchId: SeedIds.maadi),
      throwsA(_status(403)),
    );
    final mine = await m.api.tills.getCurrentTill(branchId: SeedIds.maadi);
    expect(mine.hasOpenTill, isTrue);
    expect(mine.openTill!.id, TillIds.maadiMorning);
    // A branch the persona is not assigned to.
    await expectLater(
      m.api.tills.listTills(branchId: helio),
      throwsA(_status(403)),
    );
  });

  test('open: the suggested float passes; another amount needs a reason; '
      'one open till per person', () async {
    final m = _api();
    final pre = await m.api.tills.getCurrentTill(branchId: helio);
    expect(pre.hasOpenTill, isFalse);
    await expectLater(
      m.api.tills.openTill(
        branchId: helio,
        body: OpenTillRequest(openingCash: pre.suggestedOpeningCash + 100),
      ),
      throwsA(_status(400)),
    );
    final till = await m.api.tills.openTill(
      branchId: helio,
      body: OpenTillRequest(openingCash: pre.suggestedOpeningCash),
    );
    expect(till.tellerId, SeedIds.owner);
    expect((await m.api.tills.getCurrentTill(branchId: helio)).openTill!.id,
        till.id);
    await expectLater(
      m.api.tills.openTill(
        branchId: SeedIds.maadi,
        body: const OpenTillRequest(openingCash: 0),
      ),
      throwsA(_status(409)),
    );
  });

  test('open needs till.open (the limited persona has it not)', () async {
    final m = _api(persona: Persona.limited);
    m.db['tills'].get(TillIds.maadiMorning)['teller_id'] = SeedIds.user('ali');
    await expectLater(
      m.api.tills.openTill(
        branchId: SeedIds.maadi,
        body: const OpenTillRequest(openingCash: 0),
      ),
      throwsA(_status(403)),
    );
  });

  test('cash movements: non-zero, a note, own open till; they move the '
      'expected drawer', () async {
    final m = _api();
    m.db['tills'].get(TillIds.helioMorning)['teller_id'] = SeedIds.owner;
    final before = await m.api.tills.closePreview(tillId: TillIds.helioMorning);
    await expectLater(
      m.api.tills.addCashMovement(
        tillId: TillIds.helioMorning,
        body: const CashMovementRequest(amount: 0, note: 'x'),
      ),
      throwsA(_status(400)),
    );
    await expectLater(
      m.api.tills.addCashMovement(
        tillId: TillIds.helioMorning,
        body: const CashMovementRequest(amount: 500, note: '  '),
      ),
      throwsA(_status(400)),
    );
    await m.api.tills.addCashMovement(
      tillId: TillIds.helioMorning,
      body: const CashMovementRequest(amount: -2500, note: 'Bank run'),
    );
    final after = await m.api.tills.closePreview(tillId: TillIds.helioMorning);
    expect(after.expectedCash, before.expectedCash - 2500);
    final report = await m.api.tills.getTillReport(tillId: TillIds.helioMorning);
    expect(report.cashMovements.last.note, 'Bank run');
    expect(report.cashMovementsOut, 8500 + 2500);
    expect(report.cashMovementsIn, 20000);
  });

  test('close: the count against the drawer, each method checked or '
      'disagreed (a disagreement needs an amount and a note), the rollup', () async {
    final m = _api();
    m.db['tills'].get(TillIds.helioMorning)['teller_id'] = SeedIds.owner;
    final preview = await m.api.tills.closePreview(tillId: TillIds.helioMorning);
    final cards = [for (final x in preview.methods) if (!x.isCash) x];
    expect(cards, isNotEmpty);
    await expectLater(
      m.api.tills.closeTill(
        tillId: TillIds.helioMorning,
        body: CloseTillRequest(
          closingCashDeclared: preview.expectedCash,
          reconciliation: [
            ReconciliationInput(method: cards.first.method, status: 'disagreed'),
          ],
        ),
      ),
      throwsA(_status(400)),
    );
    final res = await m.api.tills.closeTill(
      tillId: TillIds.helioMorning,
      body: CloseTillRequest(
        closingCashDeclared: preview.expectedCash - 5000,
        reconciliation: [
          ReconciliationInput(
            method: cards.first.method,
            status: 'disagreed',
            declaredAmount: cards.first.systemTotal - 1000,
            note: 'Slip missing',
          ),
        ],
      ),
    );
    expect(res.till.status.value, 'closed');
    expect(res.till.cashDiscrepancy, -5000);
    expect(res.till.reconciliationStatus, 'disagreed');
    expect(res.till.disagreementCount, 2); // the short count and the card
    // Another till is still open at the branch: no last-till warning.
    expect(res.lastTillWarning, isNull);
  });

  test('close the last open till with bills open: the warning', () async {
    final m = _api();
    m.db['tills'].get(TillIds.helioMorning)['teller_id'] = SeedIds.owner;
    closeOthers(m.db, helio, TillIds.helioMorning);
    final res = await m.api.tills.closeTill(
      tillId: TillIds.helioMorning,
      body: const CloseTillRequest(closingCashDeclared: 100000),
    );
    expect(res.lastTillWarning, isNotNull);
    expect(res.lastTillWarning!.openBillsCount, 2);
    expect(res.lastTillWarning!.openBillsAmount, 82000);
  });

  test('force close needs till.force_close; delete refuses an open till or '
      'one with sales, and removes an empty one', () async {
    final limited = _api(persona: Persona.limited);
    await expectLater(
      limited.api.tills.forceCloseTill(
        tillId: TillIds.maadiMorning,
        body: const ForceCloseRequest(),
      ),
      throwsA(_status(403)),
    );
    final m = _api();
    final forced = await m.api.tills.forceCloseTill(
      tillId: TillIds.helioSecond,
      body: const ForceCloseRequest(explicitNulls: {'reason'}),
    );
    expect(forced.status.value, 'force_closed');
    await expectLater(
      m.api.tills.deleteTill(tillId: TillIds.helioMorning),
      throwsA(_status(409)),
    );
    await expectLater(
      m.api.tills.deleteTill(
        tillId: TillIds.seeded('heliopolis', 1, 'evening'),
      ),
      throwsA(_status(409)),
    );
    await m.api.tills.deleteTill(tillId: TillIds.emptyTill);
    expect(m.db['tills'].find(TillIds.emptyTill), isNull);
  });

  test('the report: payments sum to net, the summary agrees, stock moves '
      'with the orders', () async {
    final m = _api();
    final id = TillIds.seeded('heliopolis', 1, 'evening');
    final report = await m.api.tills.getTillReport(tillId: id);
    final sum = report.paymentSummary.fold<int>(0, (s, p) => s + p.total);
    expect(report.netPayments, sum);
    final summary = await m.api.reports.tillSummary(tillId: id);
    expect(summary.totalRevenue, sum);
    final stock = await m.api.reports.tillDeductions(tillId: id);
    expect(stock, isNotEmpty);
    final spot = await m.api.tills.listSpotViews(tillId: TillIds.helioMorning);
    expect(spot, hasLength(2));
    expect(spot.last.approvedByName, isNotNull);
  });
}
