/// The mock backend for QR codes and print cards (`/settings/qr`, SET-QR rows),
/// as MadarRust `qr_card/handlers.rs` answers:
///
/// - `GET /orgs/{id}/qr`, `/branches/{id}/qr` (in-mall when `place_name`,
///   `floor` and `unit_number` are all non-empty), `/branches/{id}/tables`,
///   `/branches/{id}/tables/{tid}/qr`: `branches.read`, the caller's org.
/// - `GET /orgs/{id}/booking-qr`, `/branches/{id}/booking-qr`:
///   `bookings.read`, and a 409 unless bookings are switched on (any branch
///   for the org's code, that branch for the branch's).
///
/// Tables are the floor plan's rows (`floor_tables`, the sell area's): seeded
/// here with the same ids and labels only when no other area has, and only on
/// first use, so the sell area's own seed always wins in the app.
library;

import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import 'support.dart';

/// The public ordering and reservations hosts (`PUBLIC_ORDER_BASE_URL`,
/// `PUBLIC_RESERVATIONS_BASE_URL`; no shop has its own host yet).
const String mockOrderBase = 'https://order.madar-pos.cloud';
const String mockReservationsBase = 'https://reservations.madar-pos.cloud';

/// The floor plan's table rows (shared with the sell area).
const String qrTablesTable = 'floor_tables';

/// The table labels per branch, as the sell area's floor plans have them
/// (Heliopolis's T9 is inactive; the backend lists it all the same).
const Map<String, List<String>> qrSeedTables = {
  'heliopolis': ['T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8', 'T9'],
  'maadi': ['T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8'],
  'new-cairo': [
    'T1', 'T2', 'T3', 'T4', 'T5', 'T6', //
    'T7', 'T8', 'T9', 'T10', 'T11', 'T12',
  ],
  'zamalek': ['T1', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'T8', 'T9', 'Bar 1'],
};

/// A seeded table's id (the sell area's `SellIds.table`).
String qrTableId(String branchKey, String label) =>
    mockUuid('floor-table:$branchKey:$label');

void registerQrMocks(MockServer server, MockDb db) {
  final h = _Qr(db);
  server
    ..on('GET', '/orgs/{id}/qr', h.orgQr)
    ..on('GET', '/orgs/{id}/booking-qr', h.orgBookingQr)
    ..on('GET', '/branches/{id}/qr', h.branchQr)
    ..on('GET', '/branches/{id}/booking-qr', h.branchBookingQr)
    ..on('GET', '/branches/{id}/tables/{tid}/qr', h.tableQr);
  onIfAbsent(server, 'GET', '/branches/{id}/tables', h.listTables);
}

class _Qr {
  _Qr(this.db);

  final MockDb db;

  MockTable get _tables {
    seedTableIfAbsent(db, qrTablesTable, () {
      final branches = {
        'heliopolis': SeedIds.heliopolis,
        'maadi': SeedIds.maadi,
        'new-cairo': SeedIds.newCairo,
        'zamalek': SeedIds.zamalek,
      };
      return [
        for (final MapEntry(key: key, value: labels) in qrSeedTables.entries)
          for (final label in labels)
            {
              'id': qrTableId(key, label),
              'org_id': SeedIds.sabahOrg,
              'branch_id': branches[key],
              'label': label,
              'is_active': !(key == 'heliopolis' && label == 'T9'),
              'created_at': '2026-01-12T08:00:00Z',
              'updated_at': '2026-01-12T08:00:00Z',
            },
      ];
    });
    return db[qrTablesTable];
  }

  /// `load_branch_checked`: 404 for an unknown branch, 403 for another org's.
  String _branch(MockRequest req) {
    final id = req.param('id');
    final b = db['branches'].find(id) ?? req.notFound('Branch not found');
    req.requireSameOrg(b['org_id'] as String?);
    return id;
  }

  bool _bookingsOn(String branchId) =>
      db[SetupSeed.bookingSettingsTable].firstWhere(
        (r) => r['branch_id'] == branchId,
      )?['enabled'] ==
      true;

  MockResponse orgQr(MockRequest req) {
    req.requireCap('branches.read');
    final org = req.param('id');
    req.requireSameOrg(org);
    return MockResponse.ok(
      mockQrResponse(
        kind: 'org_order',
        longUrl: '$mockOrderBase/order/$org',
        key: 'org_order:$org',
      ),
    );
  }

  MockResponse orgBookingQr(MockRequest req) {
    req.requireCap('bookings.read');
    final org = req.param('id');
    req.requireSameOrg(org);
    final any = db['branches'].rows.any(
      (b) => b['org_id'] == org && _bookingsOn(b['id']! as String),
    );
    if (!any) req.conflict('No branch in this organisation takes bookings yet');
    return MockResponse.ok(
      mockQrResponse(
        kind: 'org_booking',
        longUrl: '$mockReservationsBase/$org',
        key: 'org_booking:$org',
      ),
    );
  }

  MockResponse branchQr(MockRequest req) {
    req.requireCap('branches.read');
    final id = _branch(req);
    final org = db['branches'].find(id)!['org_id'];
    final place = req.q('place_name') ?? '';
    final floor = req.q('floor') ?? '';
    final unit = req.q('unit_number') ?? '';
    if (place.isNotEmpty && floor.isNotEmpty && unit.isNotEmpty) {
      final e = Uri.encodeComponent;
      return MockResponse.ok(
        mockQrResponse(
          kind: 'branch_order_in_mall',
          longUrl:
              '$mockOrderBase/order/$org?branch=$id&channel=in_mall'
              '&place_name=${e(place)}&floor=${e(floor)}'
              '&unit_number=${e(unit)}',
          key: 'in_mall:$id:$place:$floor:$unit',
        ),
      );
    }
    return MockResponse.ok(
      mockQrResponse(
        kind: 'branch_order',
        longUrl: '$mockOrderBase/order/$org?branch=$id',
        key: 'branch_order:$id',
      ),
    );
  }

  MockResponse branchBookingQr(MockRequest req) {
    req.requireCap('bookings.read');
    final id = _branch(req);
    final org = db['branches'].find(id)!['org_id'];
    if (!_bookingsOn(id)) {
      req.conflict('Bookings are switched off for this branch');
    }
    return MockResponse.ok(
      mockQrResponse(
        kind: 'branch_booking',
        longUrl: '$mockReservationsBase/$org/$id',
        key: 'branch_booking:$id',
      ),
    );
  }

  MockResponse listTables(MockRequest req) {
    req.requireCap('branches.read');
    final id = _branch(req);
    // `ORDER BY label`: text order (T1, T10, T11, T12, T2, …).
    final rows = _tables.where((r) => r['branch_id'] == id)
      ..sort((a, b) => (a['label']! as String).compareTo(b['label']! as String));
    return MockResponse.ok([
      for (final r in rows)
        {
          for (final k in const [
            'id',
            'org_id',
            'branch_id',
            'label',
            'is_active',
            'created_at',
            'updated_at',
          ])
            k: r[k],
        },
    ]);
  }

  MockResponse tableQr(MockRequest req) {
    req.requireCap('branches.read');
    final id = _branch(req);
    final org = db['branches'].find(id)!['org_id'];
    final tid = req.param('tid');
    final table = _tables.find(tid);
    if (table == null || table['branch_id'] != id) {
      req.notFound('Table not found');
    }
    return MockResponse.ok(
      mockQrResponse(
        kind: 'table_order',
        longUrl: '$mockOrderBase/order/$org?table=$tid',
        key: 'table_order:$tid',
      ),
    );
  }
}
