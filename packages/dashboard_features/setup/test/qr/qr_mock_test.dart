// The QR mock against hand-computed answers: the landing addresses, the
// in-mall query, the tables in the backend's text order, the 404/403/409
// refusals, and stable short codes.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qr_support.dart';

DashboardApi _api([Persona p = Persona.owner]) =>
    DashboardApi(setupMockServer(persona: p).server);

Future<ApiException> _refusal(Future<Object?> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

void main() {
  final org = SeedIds.sabahOrg;
  final helio = SeedIds.heliopolis;

  test(
    'org, branch and booking codes land where the backend sends them',
    () async {
      final qr = _api().qr;
      final o = await qr.orgQr(id: org);
      expect(o.kind, 'org_order');
      expect(o.longUrl, 'https://order.madar-pos.cloud/order/$org');
      expect(o.shortUrl, 'https://s.madar-pos.cloud/${o.shortCode}');
      expect(
        (await qr.orgQr(id: org, card: false, dpi: 150)).shortCode,
        o.shortCode,
        reason: 'one short link per target',
      );
      expect(
        (await qr.orgBookingQr(id: org)).longUrl,
        'https://reservations.madar-pos.cloud/$org',
      );
      expect(
        (await qr.branchQr(id: helio)).longUrl,
        'https://order.madar-pos.cloud/order/$org?branch=$helio',
      );
      expect(
        (await qr.branchBookingQr(id: helio)).longUrl,
        'https://reservations.madar-pos.cloud/$org/$helio',
      );
    },
  );

  test('in-mall: all three fields lock the channel and pre-fill, encoded; '
      'one missing is the plain branch code', () async {
    final qr = _api().qr;
    final m = await qr.branchQr(
      id: helio,
      placeName: 'Sabah Kiosk 3',
      floor: 'Ground Floor',
      unitNumber: '42/B',
    );
    expect(m.kind, 'branch_order_in_mall');
    expect(
      m.longUrl,
      'https://order.madar-pos.cloud/order/$org?branch=$helio'
      '&channel=in_mall&place_name=Sabah%20Kiosk%203'
      '&floor=Ground%20Floor&unit_number=42%2FB',
    );
    final plain = await qr.branchQr(
      id: helio,
      placeName: 'Kiosk',
      floor: '',
      unitNumber: '1',
    );
    expect(plain.kind, 'branch_order');
  });

  test('tables: the branch\'s own, in text order, inactive ones too', () async {
    final qr = _api().qr;
    final nc = await qr.listTables(id: SeedIds.newCairo);
    expect(
      [for (final t in nc) t.label],
      [
        'T1',
        'T10',
        'T11',
        'T12',
        'T2',
        'T3',
        'T4',
        'T5',
        'T6',
        'T7',
        'T8',
        'T9',
      ],
    );
    final h = await qr.listTables(id: helio);
    expect(h.firstWhere((t) => t.label == 'T9').isActive, isFalse);
    expect({for (final t in h) t.branchId}, {helio});
  });

  test(
    'a table code: the table\'s page; another branch\'s table is 404',
    () async {
      final qr = _api().qr;
      final tid = qrTableId('heliopolis', 'T3');
      final c = await qr.tableQr(id: helio, tid: tid, caption: 'T3');
      expect(c.kind, 'table_order');
      expect(c.longUrl, 'https://order.madar-pos.cloud/order/$org?table=$tid');
      final e = await _refusal(qr.tableQr(id: SeedIds.maadi, tid: tid));
      expect(e.status, 404);
    },
  );

  test('bookings switched off: 409 for the branch; for the org only when no '
      'branch takes them', () async {
    final m = setupMockServer();
    final qr = DashboardApi(m.server).qr;
    expect(
      (await _refusal(qr.branchBookingQr(id: SeedIds.zamalek))).status,
      409,
    );
    m.db['booking_settings'].removeWhere(
      (r) => r['branch_id'] == SeedIds.newCairo,
    );
    expect(
      (await _refusal(qr.branchBookingQr(id: SeedIds.newCairo))).status,
      409,
      reason: 'never set up',
    );
    for (final r in m.db['booking_settings'].rows) {
      r['enabled'] = false;
    }
    expect((await _refusal(qr.orgBookingQr(id: org))).status, 409);
  });

  test('refusals: bookings.read for booking codes, the caller\'s org, an '
      'unknown branch', () async {
    final limited = _api(Persona.limited).qr;
    expect(
      (await _refusal(limited.branchBookingQr(id: SeedIds.maadi))).status,
      403,
    );
    expect((await limited.branchQr(id: SeedIds.maadi)).kind, 'branch_order');
    final owner = _api().qr;
    expect((await _refusal(owner.orgQr(id: SeedIds.nakhlaOrg))).status, 403);
    expect((await _refusal(owner.branchQr(id: SeedIds.dokki))).status, 403);
    expect(
      (await _refusal(owner.listTables(id: mockUuid('branch:nowhere')))).status,
      404,
    );
  });
}
