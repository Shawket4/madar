// The customers unit's mock handlers against the backend's rules
// (MadarRust src/customers/handlers.rs, src/loyalty): gates, refusals,
// windows, the merge chain, state, the export throttle, and figures that
// agree with the seed.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_sell/src/mock/customers_mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

({MockServer server, MockDb db, DashboardApi api}) _setup([
  Persona p = Persona.owner,
]) {
  final s = customersServer(persona: p);
  return (server: s.server, db: s.db, api: DashboardApi(s.server));
}

Future<int> _status(Future<Object?> call) async {
  try {
    await call;
    return 200;
  } on ApiException catch (e) {
    return e.status;
  }
}

Future<String?> _code(Future<Object?> call) async {
  try {
    await call;
    return null;
  } on ApiException catch (e) {
    return e.code;
  }
}

void main() {
  test('list: window, order, search by name and by phone digits', () async {
    final s = _setup();
    final all = await s.api.customers.listCustomers(limit: 500);
    expect(all, hasLength(200));
    // Most recent visit first.
    for (var i = 1; i < all.length; i++) {
      final a = all[i - 1].lastOrderAt ?? all[i - 1].createdAt;
      final b = all[i].lastOrderAt ?? all[i].createdAt;
      expect(a.isBefore(b), isFalse);
    }
    final window = await s.api.customers.listCustomers(limit: 50, offset: 50);
    expect(
      [for (final c in window) c.id],
      [for (final c in all.skip(50).take(50)) c.id],
    );
    // The server clamps the window to 500.
    expect(await s.api.customers.listCustomers(limit: 9999), hasLength(200));
    final byName = await s.api.customers.listCustomers(q: 'nada kam');
    expect(byName.first.name, 'Nada Kamal');
    // Typed digits, Arabic ones and the leading 0 included.
    for (final q in ['0100 123 4567', '٠١٠٠١٢٣٤٥٦٧', '1001234']) {
      final hit = await s.api.customers.listCustomers(q: q);
      expect([for (final c in hit) c.id], contains(nadaId), reason: q);
    }
  });

  test('list: member and source filters; an unknown source is a 400', () async {
    final s = _setup();
    final members = await s.api.customers.listCustomers(
      member: true,
      limit: 500,
    );
    expect(members.every((c) => c.isMember == true), isTrue);
    expect(
      members.length,
      s.db['customers'].rows.where((c) => c['is_member'] == true).length,
    );
    final booking = await s.api.customers.listCustomers(source: 'booking');
    expect(booking, isNotEmpty);
    expect(booking.every((c) => c.source == 'booking'), isTrue);
    expect(await _status(s.api.customers.listCustomers(source: 'fax')), 400);
  });

  test('every read and write refuses without its capability (403, no '
      'code)', () async {
    final s = _setup(Persona.limited);
    // limited holds customers.view only.
    expect(await _status(s.api.customers.listCustomers()), 200);
    expect(await _status(s.api.customers.getCustomer(id: nadaId)), 200);
    expect(
      await _status(s.api.customers.listCustomerBookings(id: nadaId)),
      200,
    );
    expect(
      await _status(s.api.customers.listCustomerAddresses(id: nadaId)),
      403,
    );
    expect(
      await _status(
        s.api.customers.createCustomer(
          body: CreateCustomerRequest(name: 'Mona Hafez'),
        ),
      ),
      403,
    );
    expect(
      await _status(
        s.api.customers.updateCustomer(
          id: nadaId,
          body: UpdateCustomerRequest(name: 'Nada'),
        ),
      ),
      403,
    );
    expect(
      await _status(
        s.api.customers.mergeCustomer(
          id: nadaId,
          body: MergeCustomerRequest(into: MockSeed.customerId(1)),
        ),
      ),
      403,
    );
    expect(await _status(s.api.customers.eraseCustomer(id: nadaId)), 403);
    expect(await _status(s.api.loyalty.getLoyaltySettings()), 403);
    expect(await _status(s.api.loyalty.getLoyaltyMember(id: nadaId)), 403);
    expect(await _code(s.api.loyalty.getLoyaltyMember(id: nadaId)), isNull);
    final m = _setup(Persona.manager);
    expect(await _status(m.api.customers.eraseCustomer(id: nadaId)), 403);
    expect(await _status(m.api.loyalty.deleteLoyaltyMember(id: nadaId)), 403);
    expect(await _status(m.api.loyalty.getLoyaltyMember(id: nadaId)), 200);
    final o = _setup();
    expect(
      await _status(o.api.loyalty.getLoyaltyGoogleObject(id: nadaId)),
      403,
    );
  });

  test(
    'create: trims, clears blanks, refuses a used phone, shows next',
    () async {
      final s = _setup();
      expect(
        await _status(
          s.api.customers.createCustomer(
            body: CreateCustomerRequest(name: '   '),
          ),
        ),
        400,
      );
      expect(
        await _code(
          s.api.customers.createCustomer(
            body: CreateCustomerRequest(name: 'Nada 2', phone: '+201001234567'),
          ),
        ),
        'CUSTOMER_PHONE_EXISTS',
      );
      final made = await s.api.customers.createCustomer(
        body: CreateCustomerRequest(
          name: '  Mona Hafez ',
          phone: '01009876543',
        ),
      );
      expect(made.customer.name, 'Mona Hafez');
      expect(made.customer.source, 'dashboard');
      expect(made.customer.ordersCount, 0);
      final found = await s.api.customers.listCustomers(q: 'Mona Hafez');
      expect(found.single.id, made.customer.id);
    },
  );

  test('update: "" clears phone and notes; a member keeps a phone', () async {
    final s = _setup();
    final c = nonMember(s.db)..['notes'] = 'Likes the window table.';
    final id = c['id']! as String;
    final saved = await s.api.customers.updateCustomer(
      id: id,
      body: UpdateCustomerRequest(name: 'Salma Hafez', phone: '', notes: ''),
    );
    expect(saved.customer.name, 'Salma Hafez');
    expect(saved.customer.phone, isNull);
    expect(saved.customer.notes, isNull);
    expect(
      await _status(
        s.api.customers.updateCustomer(
          id: nadaId,
          body: UpdateCustomerRequest(phone: ''),
        ),
      ),
      400,
    );
  });

  test(
    'merge: the member must stay; orders move; the old id resolves',
    () async {
      final s = _setup();
      final x = nonMember(s.db);
      final xId = x['id']! as String;
      final xOrders = (x['orders_count']! as num).toInt();
      final nada = customerNamed(s.db, 'Nada Kamal');
      final before = (nada['orders_count']! as num).toInt();
      expect(
        await _code(
          s.api.customers.mergeCustomer(
            id: nadaId,
            body: MergeCustomerRequest(into: xId),
          ),
        ),
        'CUSTOMER_MERGE_MEMBER_SURVIVES',
      );
      expect(
        await _status(
          s.api.customers.mergeCustomer(
            id: xId,
            body: MergeCustomerRequest(into: xId),
          ),
        ),
        400,
      );
      final kept = await s.api.customers.mergeCustomer(
        id: xId,
        body: MergeCustomerRequest(into: nadaId),
      );
      expect(kept.customer.id, nadaId);
      expect(kept.customer.ordersCount, before + xOrders);
      expect(kept.mergedFrom, [xId]);
      expect(
        s.db['orders'].rows.where((o) => o['customer_id'] == xId),
        isEmpty,
      );
      final resolved = await s.api.customers.getCustomer(id: xId);
      expect(resolved.customer.id, nadaId);
      expect(resolved.resolvedFrom, xId);
      expect([
        for (final c in await s.api.customers.listCustomers(limit: 500)) c.id,
      ], isNot(contains(xId)));
    },
  );

  test('erase: gone from the list, its addresses and its card', () async {
    final s = _setup();
    await s.api.customers.eraseCustomer(id: nadaId);
    expect(await _status(s.api.customers.getCustomer(id: nadaId)), 404);
    expect(
      s.db[CustomerTables.addresses].rows.where(
        (a) => a['customer_id'] == nadaId,
      ),
      isEmpty,
    );
    expect(
      s.db['orders'].rows.where(
        (o) => o['customer_id'] == nadaId && o['customer_name'] != null,
      ),
      isEmpty,
    );
    expect(await _status(s.api.customers.eraseCustomer(id: nadaId)), 404);
  });

  test('addresses newest first; bookings windowed newest first', () async {
    final s = _setup();
    final a = await s.api.customers.listCustomerAddresses(id: nadaId);
    expect([for (final x in a) x.label ?? x.channel], ['Home', 'in_mall']);
    expect(a.first.useCount, 9);
    final counts = <String, int>{};
    for (final b in s.db['bookings'].rows) {
      final id = b['customer_id'];
      if (id is String) counts[id] = (counts[id] ?? 0) + 1;
    }
    final id = counts.entries.reduce((x, y) => x.value >= y.value ? x : y).key;
    final page = await s.api.customers.listCustomerBookings(id: id, limit: 1);
    expect(page, hasLength(1));
    final all = await s.api.customers.listCustomerBookings(id: id, limit: 200);
    expect(all, hasLength(counts[id]));
    expect(all.first.id, page.first.id);
    for (var i = 1; i < all.length; i++) {
      expect(all[i - 1].startsAt.isBefore(all[i].startsAt), isFalse);
    }
  });

  test(
    'the ledger sums to the balance; the card agrees with the list',
    () async {
      final s = _setup();
      for (final c in s.db['customers'].rows) {
        if (c['is_member'] != true) continue;
        final id = c['id']! as String;
        final sum = s.db[CustomerTables.ledger].rows
            .where((e) => e['customer_id'] == id)
            .fold<int>(0, (n, e) => n + (e['points']! as num).toInt());
        expect(sum, (c['visits_balance'] as num?)?.toInt() ?? 0, reason: id);
      }
      final card = await s.api.loyalty.getLoyaltyMember(id: nadaId);
      expect(card.member.mode, 'visits');
      expect(card.member.balance, 6);
      expect(card.member.rewardsReady, 1);
      expect(card.member.pointsToNextReward, 6);
      // Newest first.
      for (var i = 1; i < card.ledger.length; i++) {
        expect(
          card.ledger[i - 1].createdAt.isBefore(card.ledger[i].createdAt),
          isFalse,
        );
      }
      // A non-member has no card.
      final x = nonMember(s.db)['id']! as String;
      expect(await _status(s.api.loyalty.getLoyaltyMember(id: x)), 404);
    },
  );

  test('adjust: note required, no overdraw, the balance moves', () async {
    final s = _setup();
    Future<Object?> adjust(int pts, String note) => s.api.loyalty.loyaltyAdjust(
      body: AdjustRequest(
        branchId: SeedIds.heliopolis,
        customerId: nadaId,
        points: pts,
        note: note,
      ),
    );
    expect(await _status(adjust(1, '  ')), 400);
    expect(await _status(adjust(-7, 'Card returned')), 400);
    expect(await _status(adjust(0, 'Nothing')), 400);
    await adjust(2, 'Stamps missed');
    final card = await s.api.loyalty.getLoyaltyMember(id: nadaId);
    expect(card.member.balance, 8);
    expect(card.ledger.first.note, 'Stamps missed');
    expect(card.ledger.first.points, 2);
  });

  test('leaving the programme keeps the customer', () async {
    final s = _setup();
    await s.api.loyalty.deleteLoyaltyMember(id: nadaId);
    final c = await s.api.customers.getCustomer(id: nadaId);
    expect(c.customer.isMember, isFalse);
    expect(await _status(s.api.loyalty.getLoyaltyMember(id: nadaId)), 404);
    // Twice is not a failure.
    expect(await _status(s.api.loyalty.deleteLoyaltyMember(id: nadaId)), 200);
  });

  test('the export throttle: ten export reads a minute, then 429', () async {
    final s = _setup();
    final api = DashboardApi(_Headers(s.server, const {'X-Madar-Export': '1'}));
    for (var i = 0; i < mockExportsPerMinute; i++) {
      await api.customers.listCustomers(limit: 500, offset: 0);
    }
    expect(
      await _code(api.customers.listCustomers(limit: 500, offset: 0)),
      'EXPORT_RATE_LIMITED',
    );
    // A plain read is not counted.
    expect(await _status(s.api.customers.listCustomers()), 200);
  });
}

class _Headers implements ApiTransport {
  _Headers(this.inner, this.headers);

  final ApiTransport inner;
  final Map<String, String> headers;

  ApiRequest _with(ApiRequest r) => ApiRequest(
    method: r.method,
    path: r.path,
    query: r.query,
    body: r.body,
    files: r.files,
    headers: {...r.headers, ...headers},
  );

  @override
  Future<ApiResponse> send(ApiRequest request) => inner.send(_with(request));

  @override
  Stream<String> stream(ApiRequest request) => inner.stream(_with(request));
}
