/// The floor unit's mock backend: `/floor`: GET/POST /floor/sections,
/// PATCH/DELETE /floor/sections/{id}, GET/POST /floor/tables, PATCH/DELETE
/// /floor/tables/{id}, PUT /floor/layout, GET /floor/transfers, POST
/// /floor/transfers/{id}/fulfill|cancel, GET /floor/tables/{id}/history,
/// GET /open-tickets.
///
/// Handlers behave like the backend (`MadarRust src/reservations/floor.rs`,
/// `src/floor_ops/handlers.rs`, `src/tickets/handlers.rs`): the capability
/// refusals as a 403 envelope WITHOUT a code (SELL-ALL-017), the branch
/// gate, the 400/404/409 refusals with the backend's sentences (and the
/// floor's `code`s), the layout save's all-or-nothing `expected_updated_at`
/// guard, and state (a write shows in the next read). Rows are the area
/// seed's (`../area_seed.dart`); a table's `next_booking` is derived from the
/// bookings at read time, as the backend's `attach_next_bookings` does, and a
/// table's history from the core seed's dine-in sales.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

void registerFloorMocks(MockServer server, MockDb db) {
  final h = FloorMockHandlers(db);
  server
    ..on('GET', '/floor/sections', h.listSections)
    ..on('POST', '/floor/sections', h.createSection)
    ..on('PATCH', '/floor/sections/{id}', h.updateSection)
    ..on('DELETE', '/floor/sections/{id}', h.deleteSection)
    ..on('GET', '/floor/tables', h.listTables)
    ..on('POST', '/floor/tables', h.createTable)
    ..on('PATCH', '/floor/tables/{id}', h.updateTable)
    ..on('DELETE', '/floor/tables/{id}', h.deleteTable)
    ..on('PUT', '/floor/layout', h.saveLayout)
    ..on('GET', '/floor/transfers', h.listTransfers)
    ..on('POST', '/floor/transfers/{id}/cancel', h.cancelTransfer)
    ..on('POST', '/floor/transfers/{id}/fulfill', h.fulfillTransfer)
    ..on('GET', '/floor/tables/{id}/history', h.tableHistory)
    ..on('GET', '/open-tickets', h.listOpenTickets);
}

/// A live bill (the seed still marks a ready one `ready`).
bool _liveTicket(MockRow r) => r['status'] == 'open' || r['status'] == 'ready';

class FloorMockHandlers {
  FloorMockHandlers(this.db);

  final MockDb db;

  MockTable get _sections => db[SellTables.floorSections];
  MockTable get _tables => db[SellTables.floorTables];
  MockTable get _transfers => db[SellTables.floorTransfers];
  MockTable get _tickets => db[SellTables.openTickets];

  /// `branch_id` from the query (actix's 400 when missing), then the gate.
  String _branchQuery(MockRequest req) {
    final b = req.q('branch_id');
    if (b == null || b.isEmpty) {
      req.badRequest('Query deserialize error: missing field `branch_id`');
    }
    req.requireBranch(b);
    return b;
  }

  String _branchBody(MockRequest req) {
    final b = req.json['branch_id'];
    if (b is! String) req.badRequest('Json deserialize error: branch_id');
    req.requireBranch(b);
    return b;
  }

  static int _byName(MockRow a, MockRow b) =>
      '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase());

  static int _byLabel(MockRow a, MockRow b) =>
      '${a['label']}'.toLowerCase().compareTo('${b['label']}'.toLowerCase());

  // ── Sections ──────────────────────────────────────────────────────────

  MockResponse listSections(MockRequest req) {
    req.requireCap('floor.layout.read');
    final b = _branchQuery(req);
    final rows = _sections.where((r) => r['branch_id'] == b)
      ..sort((a, c) {
        final o = (a['ordering']! as num).compareTo(c['ordering']! as num);
        return o != 0 ? o : _byName(a, c);
      });
    return MockResponse.ok(rows);
  }

  MockResponse createSection(MockRequest req) {
    req.requireCap('floor.layout.create');
    final b = _branchBody(req);
    final body = req.bodyAs(CreateSectionRequest.fromJson);
    final name = body.name.trim();
    if (name.isEmpty) req.badRequest('Section name is required');
    final row = _sections.insert({
      'id': db.newId(SellTables.floorSections),
      'org_id': SeedIds.sabahOrg,
      'branch_id': b,
      'name': name,
      'ordering': body.ordering ?? 0,
      'canvas_w': body.canvasW ?? 1000,
      'canvas_h': body.canvasH ?? 700,
      'created_at': db.nowIso,
      'updated_at': db.nowIso,
    });
    return MockResponse.created(row);
  }

  MockResponse updateSection(MockRequest req) {
    req.requireCap('floor.layout.edit');
    final row = _sections.get(req.param('id'), what: 'Section not found');
    req.requireBranch('${row['branch_id']}');
    final body = req.bodyAs(UpdateSectionRequest.fromJson);
    final name = body.name;
    if (name != null && name.trim().isEmpty) {
      req.badRequest('Section name cannot be empty');
    }
    return MockResponse.ok(
      _sections.update('${row['id']}', {
        'name': ?name?.trim(),
        'ordering': ?body.ordering,
        'canvas_w': ?body.canvasW,
        'canvas_h': ?body.canvasH,
      }),
    );
  }

  MockResponse deleteSection(MockRequest req) {
    req.requireCap('floor.layout.delete');
    final id = req.param('id');
    final row = _sections.get(id, what: 'Section not found');
    req.requireBranch('${row['branch_id']}');
    // Its tables stay: the FK sets their section to NULL (Unassigned).
    for (final t in _tables.where((t) => t['section_id'] == id)) {
      t['section_id'] = null;
    }
    _sections.delete(id);
    return MockResponse.empty();
  }

  // ── Tables ────────────────────────────────────────────────────────────

  /// A table as the list answers it: with its next active booking within
  /// the day ahead (ends after now, starts within 24 h, earliest first).
  MockRow _withBooking(MockRow t, DateTime now) {
    final limit = now.add(const Duration(hours: 24));
    MockRow? next;
    for (final b in db[SellTables.bookings].rows) {
      final status = b['status'];
      if (status != 'confirmed' && status != 'seated') continue;
      if (!((b['table_ids'] as List?) ?? const []).contains(t['id'])) continue;
      final starts = DateTime.parse('${b['starts_at']}');
      final ends = DateTime.parse('${b['ends_at']}');
      if (!ends.isAfter(now) || !starts.isBefore(limit)) continue;
      if (next == null ||
          starts.isBefore(DateTime.parse('${next['starts_at']}'))) {
        next = b;
      }
    }
    final out = MockRow.of(t);
    out['next_booking'] = next == null
        ? null
        : {
            'booking_id': next['id'],
            'status': next['status'],
            'guest_name': next['guest_name'],
            'party_size': next['party_size'],
            'starts_at': next['starts_at'],
            'ends_at': next['ends_at'],
            'held_from': next['held_from'],
          };
    return out;
  }

  List<MockRow> _branchTables(String branchId) =>
      _tables.where((r) => r['branch_id'] == branchId)..sort(_byLabel);

  MockResponse listTables(MockRequest req) {
    req.requireCap('floor.layout.read');
    final b = _branchQuery(req);
    return MockResponse.ok([
      for (final t in _branchTables(b)) _withBooking(t, req.now),
    ]);
  }

  static void _validShape(MockRequest req, String shape) {
    if (shape != 'rect' && shape != 'circle') {
      req.badRequest("shape must be 'rect' or 'circle'");
    }
  }

  MockResponse createTable(MockRequest req) {
    req.requireCap('floor.layout.create');
    final b = _branchBody(req);
    final body = req.bodyAs(CreateFloorTableRequest.fromJson);
    final label = body.label.trim();
    if (label.isEmpty) req.badRequest('Table label is required');
    final shape = body.shape ?? 'rect';
    _validShape(req, shape);
    final row = _tables.insert({
      'id': db.newId(SellTables.floorTables),
      'org_id': SeedIds.sabahOrg,
      'branch_id': b,
      'section_id': body.sectionId,
      'label': label,
      'seats': body.seats ?? 2,
      'shape': shape,
      'pos_x': body.posX ?? 0,
      'pos_y': body.posY ?? 0,
      'width': body.width ?? 80,
      'height': body.height ?? 80,
      'rotation': body.rotation ?? 0,
      'is_active': true,
      'status': 'free',
      'created_at': db.nowIso,
      'updated_at': db.nowIso,
    });
    return MockResponse.created(row);
  }

  MockResponse updateTable(MockRequest req) {
    req.requireCap('floor.layout.edit');
    final row = _tables.get(req.param('id'), what: 'Table not found');
    req.requireBranch('${row['branch_id']}');
    final body = req.bodyAs(UpdateFloorTableRequest.fromJson);
    if (body.shape case final s?) _validShape(req, s);
    final label = body.label;
    if (label != null && label.trim().isEmpty) {
      req.badRequest('Table label cannot be empty');
    }
    // Every field COALESCEs: an absent (or null) one keeps its value.
    return MockResponse.ok(
      _tables.update('${row['id']}', {
        'label': ?label?.trim(),
        'section_id': ?body.sectionId,
        'seats': ?body.seats,
        'shape': ?body.shape,
        'pos_x': ?body.posX,
        'pos_y': ?body.posY,
        'width': ?body.width,
        'height': ?body.height,
        'rotation': ?body.rotation,
        'is_active': ?body.isActive,
        'updated_at': db.nowIso,
      }),
    );
  }

  MockResponse deleteTable(MockRequest req) {
    req.requireCap('floor.layout.delete');
    final id = req.param('id');
    final row = _tables.get(id, what: 'Table not found');
    req.requireBranch('${row['branch_id']}');
    if (_tickets.rows.any((k) => k['table_id'] == id && _liveTicket(k))) {
      req.conflict(
        'Cannot delete a table with a live open ticket — settle or move it '
        'first.',
      );
    }
    _tables.delete(id);
    return MockResponse.empty();
  }

  MockResponse saveLayout(MockRequest req) {
    req.requireCap('floor.layout.edit');
    final b = _branchBody(req);
    final body = req.bodyAs(SaveLayoutRequest.fromJson);
    // All or nothing: a guard that does not match names the table and
    // writes none of them.
    final stale = <MockRow>[];
    for (final p in body.tables) {
      final row = _tables.find(p.id);
      if (row == null || row['branch_id'] != b) continue;
      final expected = p.expectedUpdatedAt;
      if (expected != null &&
          !DateTime.parse('${row['updated_at']}').isAtSameMomentAs(expected)) {
        stale.add(row);
      }
    }
    if (stale.isNotEmpty) {
      final labels = (stale..sort(_byLabel)).map((r) => r['label']).join(', ');
      req.conflict(
        'The layout changed while you were editing: $labels. Nothing was '
        'saved. Reload the floor to pick up the current positions, then '
        'reapply your changes.',
      );
    }
    for (final p in body.tables) {
      final row = _tables.find(p.id);
      if (row == null || row['branch_id'] != b) continue;
      _tables.update(p.id, {
        'section_id': p.sectionId,
        'pos_x': p.posX,
        'pos_y': p.posY,
        'width': p.width,
        'height': p.height,
        'rotation': p.rotation,
        'updated_at': db.nowIso,
      });
    }
    // The rows as stored (no `next_booking`: the backend attaches none here).
    return MockResponse.ok([
      for (final t in _branchTables(b)) {...t}..remove('next_booking'),
    ]);
  }

  // ── Transfers ─────────────────────────────────────────────────────────

  MockResponse listTransfers(MockRequest req) {
    req.requireCap('floor.transfers.read');
    final b = _branchQuery(req);
    final since = req.qDateTime('since');
    final rows =
        _transfers.where(
          (r) =>
              r['branch_id'] == b &&
              (since == null
                  ? r['status'] == 'waiting'
                  : DateTime.parse('${r['updated_at']}').isAfter(since)),
        )..sort(
          (a, c) => DateTime.parse(
            '${a['created_at']}',
          ).compareTo(DateTime.parse('${c['created_at']}')),
        );
    return MockResponse.ok({'server_time': db.nowIso, 'transfers': rows});
  }

  MockRow _transfer(MockRequest req) {
    final row = _transfers.get(
      req.param('id'),
      what: 'Transfer request not found',
    );
    req.requireBranch('${row['branch_id']}');
    return row;
  }

  MockResponse cancelTransfer(MockRequest req) {
    req.requireCap('floor.transfers.edit');
    final row = _transfer(req);
    switch (row['status']) {
      case 'cancelled':
        break; // idempotent
      case 'fulfilled':
        req.conflict(
          'Transfer is already fulfilled',
          code: 'TRANSFER_FULFILLED',
        );
      default:
        _transfers.update('${row['id']}', {
          'status': 'cancelled',
          'resolved_at': db.nowIso,
        });
    }
    return MockResponse.ok(row);
  }

  MockResponse fulfillTransfer(MockRequest req) {
    req.requireCap('floor.transfers.edit');
    final row = _transfer(req);
    final body = req.bodyAs(FulfillTransferRequest.fromJson);
    switch (row['status']) {
      case 'fulfilled':
        return MockResponse.ok(row); // a replayed fulfil
      case 'cancelled':
        req.conflict(
          'Transfer is already cancelled',
          code: 'TRANSFER_CANCELLED',
        );
    }
    final target = row['target_table_id'];
    if (target != null && target != body.tableId) {
      req.badRequest('The party asked for a different table');
    }
    final table = _tables.find(body.tableId);
    if (table == null || table['branch_id'] != row['branch_id']) {
      req.badRequest('Table is not in this branch');
    }
    final section = row['target_section_id'];
    if (target == null && section != null && table['section_id'] != section) {
      req.badRequest('Table is not in the section the party asked for');
    }
    final ticket = _tickets.find('${row['occupant_id']}');
    if (ticket == null || !_liveTicket(ticket)) {
      req.conflict(
        "The party's order is no longer live",
        code: 'TICKET_NOT_LIVE',
      );
    }
    req.requireCap('tickets.edit');
    final occupied =
        table['status'] == 'seated' ||
        _tickets.rows.any(
          (k) =>
              k['table_id'] == table['id'] &&
              k['id'] != ticket['id'] &&
              _liveTicket(k),
        );
    if (occupied) {
      req.conflict('Table is already occupied', code: 'TABLE_OCCUPIED');
    }
    // The old table frees up; the party lands on the new one.
    final old = ticket['table_id'];
    if (old is String && old != table['id'] && _tables.find(old) != null) {
      _tables.update(old, {
        'status': 'free',
        'seated_at': null,
        'party_size': null,
      });
    }
    ticket['table_id'] = table['id'];
    _tables.update('${table['id']}', {
      'status': 'seated',
      'seated_at': ticket['opened_at'],
      'party_size': ticket['guest_count'],
    });
    return MockResponse.ok(
      _transfers.update('${row['id']}', {
        'status': 'fulfilled',
        'fulfilled_table_id': table['id'],
        'resolved_at': db.nowIso,
      }),
    );
  }

  // ── A table's history ─────────────────────────────────────────────────

  MockResponse tableHistory(MockRequest req) {
    req.requireCap('tickets.read');
    final to = req.qDateTime('to') ?? req.now;
    final from = req.qDateTime('from') ?? to.subtract(const Duration(days: 30));
    if (!from.isBefore(to)) req.badRequest('`from` must be before `to`');
    final table = _tables.find(req.param('id'));
    if (table == null) req.notFound('table not found');
    req.requireBranch('${table['branch_id']}');
    return MockResponse.ok(
      floorTableHistory(db, '${table['id']}', from: from, to: to, now: req.now),
    );
  }

  // ── Open tickets ──────────────────────────────────────────────────────

  MockResponse listOpenTickets(MockRequest req) {
    req.requireCap('tickets.read');
    final b = _branchQuery(req);
    final status = req.q('status');
    final rows =
        _tickets.where(
          (r) =>
              r['branch_id'] == b &&
              switch (status) {
                null || '' => _liveTicket(r),
                'all' => true,
                _ => r['status'] == status,
              },
        )..sort(
          (a, c) => DateTime.parse(
            '${c['opened_at']}',
          ).compareTo(DateTime.parse('${a['opened_at']}')),
        );
    return MockResponse.ok(rows);
  }
}

/// What a table has done between [from] and [to] (the backend's
/// `table_history`): the live bill on it, and the core seed's sittings of
/// its branch's dine-in sales at this table ([MockSeed.sittings], shared
/// with the reports' tables dataset). Money, covers and the averages count
/// SETTLED bills only.
TableHistory floorTableHistory(
  MockDb db,
  String tableId, {
  required DateTime from,
  required DateTime to,
  required DateTime now,
}) {
  final table = db[SellTables.floorTables].get(tableId);
  final branch = table['branch_id'];
  final sittings = <TableSitting>[];
  for (final k in db[SellTables.openTickets].rows) {
    if (k['table_id'] != tableId) continue;
    final opened = DateTime.parse('${k['opened_at']}');
    if (opened.isBefore(from) || !opened.isBefore(to)) continue;
    final live = _liveTicket(k);
    sittings.add(
      TableSitting(
        openTicketId: '${k['id']}',
        ticketRef: k['ticket_ref'] as String?,
        openedAt: opened,
        seatedAt: opened,
        minutes: live ? now.difference(opened).inMinutes : 0,
        status: live ? 'open' : '${k['status']}',
        customerId: k['customer_id'] as String?,
        customerName: k['customer_name'] as String?,
        guestCount: k['guest_count'] as int?,
      ),
    );
  }
  // The core seed's sittings (`MockSeed.sittings`): the model the reports'
  // tables dataset reads too, so a table's history matches its ledger.
  for (final o in db['orders'].rows) {
    if (o['branch_id'] != branch || o['order_type'] != 'dine_in') continue;
    final sitting = MockSeed.instance.sittingOf('${o['id']}');
    if (sitting == null || sitting.tableId != tableId) continue;
    final at = DateTime.parse('${o['created_at']}');
    final opened = sitting.seatedAt;
    if (opened.isBefore(from) || !opened.isBefore(to)) continue;
    final voided = o['status'] == 'voided';
    final closed = voided && o['voided_at'] != null
        ? DateTime.parse('${o['voided_at']}')
        : at;
    sittings.add(
      TableSitting(
        openTicketId: mockUuid('sitting-ticket:${o['id']}'),
        ticketRef: 'T-${o['order_ref']}',
        openedAt: opened,
        seatedAt: opened,
        closedAt: closed,
        minutes: closed.difference(opened).inMinutes,
        status: voided ? 'voided' : 'settled',
        customerId: o['customer_id'] as String?,
        customerName: o['customer_name'] as String?,
        guestCount: sitting.covers,
        orderId: '${o['id']}',
        orderNumber: (o['order_number'] as num?)?.toInt(),
        totalAmount: voided ? null : (o['total_amount']! as num).toInt(),
      ),
    );
  }
  sittings.sort((a, b) => b.openedAt.compareTo(a.openedAt));
  final settled = sittings.where((s) => s.totalAmount != null).toList();
  final n = settled.length;
  final total = settled.fold<int>(0, (s, x) => s + x.totalAmount!);
  final covers = settled.fold<int>(0, (s, x) => s + (x.guestCount ?? 0));
  final mins = settled.fold<int>(0, (s, x) => s + x.minutes);
  final days = to.difference(from).inMinutes / (24 * 60);
  return TableHistory(
    tableId: tableId,
    label: '${table['label']}',
    from: from,
    to: to,
    sittings: sittings,
    covers: covers,
    settledCount: n,
    totalMinor: total,
    averageBillMinor: n == 0 ? 0 : total ~/ n,
    averageMinutes: n == 0 ? 0 : mins ~/ n,
    turnsPerDayX100: (n / (days < 1 / 24 ? 1 / 24 : days) * 100).round(),
  );
}
