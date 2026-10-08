/// The tills unit's mock backend (`/tills`, SELL-TIL rows), behaving like
/// MadarRust's `src/tills/handlers.rs`, `reconcile.rs`, `spot_views.rs` and
/// the till report reads in `src/reports/handlers.rs`:
///
/// - `GET /tills/branches/{branchId}/current` — the caller's till state here
///   (`TillPreFill`; `teller_id` only for `till.read.branch`);
/// - `GET /tills/branches/{branchId}/open` — every open till, newest first;
/// - `GET /tills/branches/{branchId}/open-bills-notice` — `tickets.read`;
/// - `GET /tills/branches/{branchId}` — the list (nil id = the whole org),
///   `status` (400 on an unknown one), `teller_id`, `device_id`, `flagged`,
///   `from`, `to`, and paging only when `page`/`per_page` is sent;
/// - `POST /tills/branches/{branchId}/open` — `till.open`; one open till per
///   person (409 `TILL_OPEN_AT_OTHER_BRANCH`, resume at this branch), the
///   carryover rule (400 without an `edit_reason` when the float differs
///   from the last declared close);
/// - `GET /tills/{tillId}/report`, `GET /reports/tills/{tillId}/summary`,
///   `GET /reports/tills/{tillId}/deductions` (`inventory.read`),
///   `GET /tills/{tillId}/spot-views`;
/// - `GET /tills/{tillId}/close-preview` and `POST /tills/{tillId}/close`
///   (`till.operate`; someone else's till only with `till.force_close`; the
///   per-method check with the coded 400s);
/// - `POST /tills/{tillId}/cash-movements` (`till.operate`, own till, open
///   only, non-zero, a note);
/// - `POST /tills/{tillId}/force-close` (`till.operate` + `till.force_close`);
/// - `DELETE /tills/{tillId}` (`till.delete`; 409 for an open till or one
///   with recorded sales).
///
/// Capability refusals are the backend's uncoded 403 envelope
/// (SELL-ALL-017). The tills are the core seed's (two a day per branch for
/// 30 days, today's morning ones open); [loadTillsScenario] adds what the
/// page needs to show every state: cash movements, spot views, the payment
/// checks of yesterday's closes, a flagged second till, an unverified one,
/// an edited float with a card mismatch, and an empty till that may be
/// deleted.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        CashMovement,
        CashMovementRequest,
        CashMovementSummaryRow,
        CloseTillMethod,
        CloseTillPreview,
        CloseTillRequest,
        CloseTillResponse,
        DeductionLogRow,
        ForceCloseRequest,
        LastTillWarning,
        OpenBillsNotice,
        OpenTillRequest,
        OrderNumberRange,
        PaymentSummaryRow,
        ReconciliationInput,
        ShiftSummary,
        Till,
        TillBrief,
        TillPreFill,
        TillReconciliationLine,
        TillReportResponse,
        TillSpotView,
        TillStatus,
        TillVerification;
import 'package:dashboard_api/mock.dart';

import '../area_seed.dart' show SellTables;

/// The [MockDb] tables this unit reads and writes.
abstract final class TillTables {
  /// [Till] rows (the core seed's, plus the scenario's and new opens).
  static const String tills = 'tills';

  /// [CashMovement] rows.
  static const String movements = 'till_cash_movements';

  /// [TillReconciliationLine] rows with a `till_id` (id `<till>:<method>`).
  static const String reconciliations = 'till_reconciliations';

  /// [TillSpotView] rows.
  static const String spotViews = 'till_spot_views';

  static const String _scenario = '_sell_tills_scenario';
}

/// The backend's "every branch in my org" id.
const String _allBranches = '00000000-0000-0000-0000-000000000000';

/// Stable ids of the tills the scenario names.
abstract final class TillIds {
  static String _day(int daysAgo) =>
      MockClock.cairoDate(MockSeed.now.subtract(Duration(days: daysAgo)));

  /// A core seed till: [branchKey]'s [shift] (`morning`/`evening`)
  /// [daysAgo] days before today.
  static String seeded(String branchKey, int daysAgo, String shift) =>
      MockSeed.tillId(branchKey, _day(daysAgo), shift);

  /// Ali Hassan's open till on Heliopolis' Counter 1 (cash movements, spot
  /// views).
  static final String helioMorning = seeded('heliopolis', 0, 'morning');

  /// Ali Hassan's second till, on Counter 2, opened while his first was open
  /// (flagged, verified on the LAN, no sales yet).
  static final String helioSecond = mockUuid('till:heliopolis:second');

  /// Hana Mostafa's open till at Maadi (the limited persona's own till).
  static final String maadiMorning = seeded('maadi', 0, 'morning');

  /// Mariam Fathy's open till at Zamalek.
  static final String zamalekMorning = seeded('zamalek', 0, 'morning');

  /// Salma Nabil's open till at New Cairo.
  static final String newCairoMorning = seeded('new-cairo', 0, 'morning');

  /// Youssef Samir's close last night at Zamalek: an edited float, a safe
  /// drop, a card slip that did not match, a held order left open.
  static final String zamalekLastEvening = seeded('zamalek', 1, 'evening');

  /// Salma Nabil's till yesterday morning, opened offline (not verified).
  static final String newCairoLastMorning = seeded('new-cairo', 1, 'morning');

  /// Omar Khaled's till opened by mistake three days ago and closed with no
  /// sale: the one till a Delete goes through for.
  static final String emptyTill = mockUuid('till:new-cairo:empty');

  /// The force-closed till of the core seed (Maadi, twelve days ago).
  static final String maadiForced = seeded('maadi', 12, 'evening');
}

String _staffName(String key) =>
    sabahStaff.firstWhere((p) => p.key == key).name;

/// Cairo wall-clock [hour]:[minute] [daysAgo] days before the seed's now.
DateTime _at(int daysAgo, int hour, int minute) {
  final w = MockClock.wall(MockSeed.now.subtract(Duration(days: daysAgo)));
  return MockClock.fromCairo(w.year, w.month, w.day, hour, minute);
}

/// Adds the scenario rows to [db] (once; safe to call again).
void loadTillsScenario(MockDb db) {
  final mark = db.table(TillTables._scenario);
  if (mark.find('loaded') != null) return;
  mark.insert({'id': 'loaded'}, timestamps: false);
  final tills = db[TillTables.tills];
  final helio = MockSeed.branchIdOf('heliopolis');

  void move(
    String tillId,
    int amount,
    String kind,
    String note,
    String byKey,
    DateTime at,
  ) {
    final n = db[TillTables.movements].length + 1;
    db[TillTables.movements].insert(
      CashMovement(
        id: mockUuid('till-movement:$tillId:$n'),
        tillId: tillId,
        shiftId: tillId,
        amount: amount,
        kind: kind,
        note: note,
        movedBy: SeedIds.user(byKey),
        movedByName: _staffName(byKey),
        createdAt: at,
      ).toJson(),
      timestamps: false,
    );
  }

  void spot(
    String tillId,
    String viewerKey,
    DateTime at, {
    bool printed = false,
    String? approverKey,
  }) {
    final till = tills.get(tillId);
    final n = db[TillTables.spotViews].length + 1;
    db[TillTables.spotViews].insert(
      TillSpotView(
        id: mockUuid('till-spot-view:$tillId:$n'),
        tillId: tillId,
        branchId: till['branch_id']! as String,
        viewedBy: SeedIds.user(viewerKey),
        viewedByName: _staffName(viewerKey),
        viewedAt: at,
        createdAt: at,
        printed: printed,
        printedAt: printed ? at.add(const Duration(seconds: 20)) : null,
        approvalId: approverKey == null
            ? null
            : mockUuid('approval:$tillId:$n'),
        approvedBy: approverKey == null ? null : SeedIds.user(approverKey),
        approvedByName: approverKey == null ? null : _staffName(approverKey),
        deviceId: till['device_id'] as String?,
      ).toJson(),
      timestamps: false,
    );
  }

  // Heliopolis, this morning: Ali's drawer took change from the safe and
  // paid for milk; the manager looked at the spot report and printed it,
  // then unlocked one look for Ali.
  move(
    TillIds.helioMorning,
    20000,
    'pay_in',
    'Change float from the safe',
    'rana',
    _at(0, 7, 35),
  );
  move(
    TillIds.helioMorning,
    -8500,
    'pay_out',
    'Milk top-up from the corner shop',
    'ali',
    _at(0, 8, 40),
  );
  spot(TillIds.helioMorning, 'rana', _at(0, 8, 30), printed: true);
  spot(TillIds.helioMorning, 'ali', _at(0, 9, 40), approverKey: 'rana');

  // Ali's second till on Counter 2, replayed from the LAN while his first
  // was open.
  final first = tills.get(TillIds.helioMorning);
  tills.insert(
    Till(
      id: TillIds.helioSecond,
      branchId: helio,
      branchName: first['branch_name'] as String?,
      tellerId: first['teller_id']! as String,
      tellerName: first['teller_name']! as String,
      deviceId: mockUuid('device:heliopolis:T2'),
      deviceCode: 'T2',
      deviceLabel: 'Counter 2',
      openedAt: _at(0, 8, 12),
      openingCash: 50000,
      openingCashWasEdited: false,
      openedWhileAnotherOpen: true,
      otherTillId: TillIds.helioMorning,
      flaggedAt: _at(0, 8, 14),
      disagreementCount: 0,
      status: TillStatus.open,
      verification: TillVerification.lan,
      timezone: MockClock.timezone,
    ).toJson(),
    timestamps: false,
  );

  // Zamalek, last night: the float was edited at open, a safe drop went to
  // the back office, and one card slip was missing at close.
  final z = tills.get(TillIds.zamalekLastEvening);
  move(
    TillIds.zamalekLastEvening,
    -100000,
    'safe_drop',
    'Safe drop before closing',
    'karim',
    _at(1, 21, 30),
  );
  const edit = 5000;
  const drop = -100000;
  z.addAll({
    'opening_cash': (z['opening_cash']! as int) + edit,
    'opening_cash_original': z['opening_cash'],
    'opening_cash_was_edited': true,
    'opening_cash_edit_reason':
        'Found EGP 50 left in the drawer from the morning till.',
    'closing_cash_system': (z['closing_cash_system']! as int) + edit + drop,
    'closing_cash_declared': (z['closing_cash_declared']! as int) + edit + drop,
    'held_orders_left_open': 1,
    'held_orders_left_open_total': 8500,
  });
  spot(TillIds.zamalekLastEvening, 'karim', _at(1, 22, 50), printed: true);

  // New Cairo, yesterday morning: opened while the tablet was offline.
  tills.get(TillIds.newCairoLastMorning)['verification'] = 'unverified';

  // New Cairo, three days ago: opened by mistake, closed with no sale.
  final empty = Till(
    id: TillIds.emptyTill,
    branchId: MockSeed.branchIdOf('new-cairo'),
    branchName: 'New Cairo',
    tellerId: SeedIds.user('omar'),
    tellerName: _staffName('omar'),
    deviceId: mockUuid('device:new-cairo:T2'),
    deviceCode: 'T2',
    deviceLabel: 'Counter 2',
    openedAt: _at(3, 13, 58),
    openingCash: 100000,
    openingCashWasEdited: false,
    openedWhileAnotherOpen: false,
    disagreementCount: 0,
    status: TillStatus.closed,
    verification: TillVerification.server,
    closedAt: _at(3, 14, 3),
    closedBy: SeedIds.user('omar'),
    closingCashSystem: 100000,
    closingCashDeclared: 100000,
    cashDiscrepancy: 0,
    openBillsAtClose: 0,
    oldBillsAtClose: 0,
    timezone: MockClock.timezone,
  ).toJson();
  tills.insert(empty, timestamps: false);

  // Yesterday's closes went through the payment check.
  final yesterday = TillIds._day(1);
  for (final t in [...tills.rows]) {
    final closedAt = t['closed_at'] as String?;
    if (t['status'] != 'closed' || closedAt == null) continue;
    if (MockClock.cairoDate(DateTime.parse(closedAt)) != yesterday) continue;
    final id = t['id']! as String;
    final declared = t['closing_cash_declared']! as int;
    final system = t['closing_cash_system']! as int;
    final inputs = [
      for (final m in _closeMethods(db, t, system))
        if (!m.isCash)
          id == TillIds.zamalekLastEvening && m.method == 'card'
              ? ReconciliationInput(
                  method: m.method,
                  status: 'disagreed',
                  declaredAmount: m.systemTotal - 15000,
                  note: 'One card slip is missing from the batch.',
                )
              : ReconciliationInput(method: m.method, status: 'checked'),
    ];
    final lines = _planLines(
      db,
      t,
      declared: declared,
      system: system,
      cashNote: t['notes'] as String?,
      inputs: inputs,
      by: t['closed_by'] as String?,
      at: DateTime.parse(closedAt),
    );
    _storeLines(db, id, lines);
  }
}

// ── Reads over the rows ──────────────────────────────────────────────────

List<MockRow> _ordersOf(MockDb db, String tillId) =>
    db['orders'].where((o) => o['till_id'] == tillId);

bool _sold(MockRow o) => o['status'] != 'voided' && o['status'] != 'refunded';

List<({String method, int amount, bool isCash})> _legs(MockRow o) {
  final legs = o['payment_legs'];
  if (legs is List && legs.isNotEmpty) {
    return [
      for (final l in legs.cast<Map<String, Object?>>())
        (
          method: l['method']! as String,
          amount: l['amount']! as int,
          isCash: (l['is_cash'] as bool?) ?? l['method'] == 'cash',
        ),
    ];
  }
  final m = (o['payment_method'] as String?) ?? 'cash';
  return [
    (method: m, amount: (o['total_amount'] as int?) ?? 0, isCash: m == 'cash'),
  ];
}

List<MockRow> _movesOf(MockDb db, String tillId) =>
    db[TillTables.movements]
        .where((m) => m['till_id'] == tillId)
        .toList()
      ..sort(
        (a, b) => (a['created_at']! as String).compareTo(
          b['created_at']! as String,
        ),
      );

/// The drawer: float + cash tenders of sold orders + cash movements.
int _systemCash(MockDb db, MockRow till) {
  final id = till['id']! as String;
  var cash = till['opening_cash']! as int;
  for (final o in _ordersOf(db, id)) {
    if (!_sold(o)) continue;
    for (final l in _legs(o)) {
      if (l.isCash) cash += l.amount;
    }
  }
  for (final m in _movesOf(db, id)) {
    cash += m['amount']! as int;
  }
  return cash;
}

/// The frozen close figure, else the live drawer.
int _expectedCash(MockDb db, MockRow till) =>
    (till['closing_cash_system'] as int?) ?? _systemCash(db, till);

String? _paymentMethodId(MockDb db, String name) =>
    db['payment_methods'].firstWhere((m) => m['name'] == name)?['id']
        as String?;

/// What a close reconciles: the cash line (the expected drawer) first, then
/// every non-cash method the till took, by name.
List<CloseTillMethod> _closeMethods(
  MockDb db,
  MockRow till,
  int expectedCash,
) {
  final byMethod = <String, ({bool cash, int total, Set<String> orders})>{};
  for (final o in _ordersOf(db, till['id']! as String)) {
    if (!_sold(o)) continue;
    for (final l in _legs(o)) {
      final cur = byMethod[l.method];
      byMethod[l.method] = (
        cash: (cur?.cash ?? false) || l.isCash,
        total: (cur?.total ?? 0) + l.amount,
        orders: {...?cur?.orders, o['id']! as String},
      );
    }
  }
  final cashOrders = byMethod.entries
      .where((e) => e.value.cash)
      .fold<int>(0, (s, e) => s + e.value.orders.length);
  final names = byMethod.keys.toList()..sort();
  return [
    CloseTillMethod(
      method: 'cash',
      paymentMethodId: _paymentMethodId(db, 'cash'),
      isCash: true,
      systemTotal: expectedCash,
      orderCount: cashOrders,
    ),
    for (final m in names)
      if (!byMethod[m]!.cash)
        CloseTillMethod(
          method: m,
          paymentMethodId: _paymentMethodId(db, m),
          isCash: false,
          systemTotal: byMethod[m]!.total,
          orderCount: byMethod[m]!.orders.length,
        ),
  ];
}

/// The close's lines (`madar_till::reconcile::plan_lines`): the cash line's
/// status from the count, each non-cash method from its input (unreviewed
/// when none), a disagreement needing an amount and a note.
List<TillReconciliationLine> _planLines(
  MockDb db,
  MockRow till, {
  required int declared,
  required int system,
  required String? cashNote,
  required List<ReconciliationInput> inputs,
  required String? by,
  required DateTime at,
}) {
  final methods = _closeMethods(db, till, system);
  final cash = methods.first;
  String? blank(String? s) => s == null || s.trim().isEmpty ? null : s.trim();
  final lines = <TillReconciliationLine>[
    TillReconciliationLine(
      method: cash.method,
      paymentMethodId: cash.paymentMethodId,
      isCash: true,
      systemTotal: system,
      currentSystemTotal: system,
      orderCount: cash.orderCount,
      status: declared == system ? 'checked' : 'disagreed',
      declaredAmount: declared,
      note: blank(cashNote),
      reconciledBy: by,
      reconciledAt: at,
      changedAfterClose: false,
    ),
  ];
  ReconciliationInput? inputFor(String method) {
    for (final i in inputs) {
      if (i.method.trim() == method) return i;
    }
    return null;
  }

  TillReconciliationLine line(
    CloseTillMethod m,
    ReconciliationInput? input,
  ) {
    final base = TillReconciliationLine(
      method: m.method,
      paymentMethodId: m.paymentMethodId,
      isCash: false,
      systemTotal: m.systemTotal,
      currentSystemTotal: m.systemTotal,
      orderCount: m.orderCount,
      status: 'unreviewed',
      reconciledBy: by,
      reconciledAt: at,
      changedAfterClose: false,
    );
    if (input == null) return base;
    switch (input.status.trim()) {
      case 'checked':
        return TillReconciliationLine.fromJson({
          ...base.toJson(),
          'status': 'checked',
          'note': ?blank(input.note),
        });
      case 'disagreed':
        final amount = input.declaredAmount;
        if (amount == null) {
          throw MockHttpError(
            MockResponse.error(
              400,
              'RECONCILIATION_AMOUNT_REQUIRED: enter the amount you see for '
              '${m.method}',
              code: 'RECONCILIATION_AMOUNT_REQUIRED',
            ),
          );
        }
        final note = blank(input.note);
        if (note == null) {
          throw MockHttpError(
            MockResponse.error(
              400,
              'RECONCILIATION_NOTE_REQUIRED: add a note for the difference on '
              '${m.method}',
              code: 'RECONCILIATION_NOTE_REQUIRED',
            ),
          );
        }
        return TillReconciliationLine.fromJson({
          ...base.toJson(),
          'status': 'disagreed',
          'declared_amount': amount,
          'note': note,
        });
      default:
        throw MockHttpError(
          MockResponse.badRequest(
            "Invalid reconciliation status '${input.status}' for ${m.method}",
          ),
        );
    }
  }

  for (final m in methods.skip(1)) {
    lines.add(line(m, inputFor(m.method)));
  }
  // An input naming a method the till never took: system total 0.
  for (final i in inputs) {
    final name = i.method.trim();
    if (name.isEmpty || name == cash.method) continue;
    if (methods.any((m) => m.method == name)) continue;
    lines.add(
      line(
        CloseTillMethod(
          method: name,
          isCash: false,
          systemTotal: 0,
          orderCount: 0,
        ),
        i,
      ),
    );
  }
  return lines;
}

/// `madar_till::reconcile::rollup_status`.
String _rollup(Iterable<TillReconciliationLine> lines) {
  var unreviewed = false;
  for (final l in lines) {
    if (l.status == 'disagreed') return 'disagreed';
    if (l.status == 'unreviewed') unreviewed = true;
  }
  return unreviewed ? 'unreviewed' : 'clean';
}

void _storeLines(
  MockDb db,
  String tillId,
  List<TillReconciliationLine> lines,
) {
  final table = db[TillTables.reconciliations];
  for (final l in lines) {
    table.put({'id': '$tillId:${l.method}', 'till_id': tillId, ...l.toJson()});
  }
  final till = db[TillTables.tills].get(tillId, what: 'Till not found');
  till['reconciliation_status'] = _rollup(lines);
  till['disagreement_count'] = lines
      .where((l) => l.status == 'disagreed')
      .length;
}

List<TillReconciliationLine> _linesOf(MockDb db, String tillId) {
  final rows = db[TillTables.reconciliations].where(
    (r) => r['till_id'] == tillId,
  );
  final lines = [
    for (final r in rows)
      TillReconciliationLine.fromJson({...r}..remove('till_id')),
  ];
  // Cash first, then by method (`ORDER BY is_cash DESC, method`).
  lines.sort((a, b) {
    if (a.isCash != b.isCash) return a.isCash ? -1 : 1;
    return a.method.compareTo(b.method);
  });
  return lines;
}

/// `open_bills_notice`: the branch's open bills (and the old ones), its
/// seated tables, and since when (its last close).
OpenBillsNotice _notice(MockDb db, String branchId, DateTime now) {
  final branch = db['branches'].find(branchId);
  final hours = (branch?['old_bill_hours'] as int?) ?? 3;
  final open = db[SellTables.openTickets].where(
    (k) =>
        k['branch_id'] == branchId &&
        (k['status'] == 'open' || k['status'] == 'ready') &&
        k['settled_at'] == null &&
        k['voided_at'] == null,
  );
  final cutoff = now.subtract(Duration(hours: hours));
  DateTime? oldest;
  var old = 0;
  var amount = 0;
  for (final k in open) {
    final at = DateTime.parse(k['opened_at']! as String);
    if (oldest == null || at.isBefore(oldest)) oldest = at;
    if (at.isBefore(cutoff)) old++;
    amount += (k['subtotal'] as int?) ?? 0;
  }
  final seated = {
    for (final t in db[SellTables.floorTables].where(
      (t) => t['branch_id'] == branchId && t['status'] == 'seated',
    ))
      t['id'],
  }.length;
  DateTime? since;
  for (final t in db[TillTables.tills].where(
    (t) =>
        t['branch_id'] == branchId &&
        (t['status'] == 'closed' || t['status'] == 'force_closed'),
  )) {
    final c = t['closed_at'] as String?;
    if (c == null) continue;
    final at = DateTime.parse(c);
    if (since == null || at.isAfter(since)) since = at;
  }
  return OpenBillsNotice(
    openBillsCount: open.length,
    openBillsAmount: amount,
    oldestOpenedAt: oldest,
    oldBillsCount: old,
    oldBillHours: hours,
    seatedTablesCount: seated,
    since: since,
  );
}

LastTillWarning? _lastTillWarning(
  OpenBillsNotice notice, {
  required bool otherOpen,
}) => !otherOpen && (notice.openBillsCount > 0 || notice.seatedTablesCount > 0)
    ? LastTillWarning(
        isLastOpenTill: true,
        openBillsCount: notice.openBillsCount,
        openBillsAmount: notice.openBillsAmount,
        seatedTablesCount: notice.seatedTablesCount,
      )
    : null;

bool _otherOpen(MockDb db, String branchId, String tillId) =>
    db[TillTables.tills].firstWhere(
      (t) =>
          t['branch_id'] == branchId &&
          t['status'] == 'open' &&
          t['id'] != tillId,
    ) !=
    null;

/// The branch's latest declared close (`last_close_declared`, no device).
int? _lastCloseDeclared(MockDb db, String branchId) {
  MockRow? best;
  for (final t in db[TillTables.tills].rows) {
    if (t['branch_id'] != branchId) continue;
    if (t['status'] != 'closed' && t['status'] != 'force_closed') continue;
    if (t['closing_cash_declared'] == null) continue;
    if (best == null ||
        (t['opened_at']! as String).compareTo(best['opened_at']! as String) >
            0) {
      best = t;
    }
  }
  return best?['closing_cash_declared'] as int?;
}

TillBrief _brief(MockRow t) => TillBrief(
  id: t['id']! as String,
  branchId: t['branch_id']! as String,
  tellerId: t['teller_id']! as String,
  tellerName: t['teller_name']! as String,
  deviceId: t['device_id'] as String?,
  deviceCode: t['device_code'] as String?,
  deviceLabel: t['device_label'] as String?,
  openedAt: DateTime.parse(t['opened_at']! as String),
  openedWhileAnotherOpen: (t['opened_while_another_open'] as bool?) ?? false,
  status: TillStatus.fromJson(t['status']! as String),
  verification: TillVerification.fromJson(t['verification']! as String),
);

List<MockRow> _newestFirst(Iterable<MockRow> rows) =>
    queryRows(rows, sort: '-opened_at');

/// One stock item a menu item (or an add-on) takes, per unit sold.
typedef _Use = ({String key, String name, String unit, double qty});

_Use _use(String key, String name, String unit, double qty) =>
    (key: key, name: name, unit: unit, qty: qty);

final _Use _beans = _use('beans', 'Espresso beans', 'g', 18);
final _Use _milk = _use('milk', 'Full-cream milk', 'ml', 180);

/// The recipe a line takes, by menu item key (close enough to the menu's for
/// a believable "Stock used").
List<_Use> _recipe(String item, bool iced) {
  final cup = iced
      ? _use('cup-cold', 'Clear cup 16oz', 'pcs', 1)
      : _use('cup-hot', 'Paper cup 12oz', 'pcs', 1);
  List<_Use> milky(double ml) => [_beans, _use('milk', _milk.name, 'ml', ml)];
  final ingredients = switch (item) {
    'espresso' => [_beans],
    'americano' || 'iced_americano' => [_beans],
    'cortado' => milky(60),
    'flatwhite' => milky(120),
    'cappuccino' => milky(150),
    'latte' || 'iced_latte' => milky(200),
    'spanish' || 'iced_spanish' => [
      ...milky(160),
      _use('condensed', 'Condensed milk', 'ml', 30),
    ],
    'mocha' || 'iced_mocha' => [
      ...milky(160),
      _use('chocolate', 'Chocolate sauce', 'ml', 30),
    ],
    'pistachio_latte' => [
      ...milky(170),
      _use('pistachio', 'Pistachio paste', 'g', 20),
    ],
    'frappe' => [
      ...milky(150),
      _use('caramel', 'Caramel syrup', 'ml', 25),
    ],
    'v60' => [_use('single-origin', 'Single-origin beans', 'g', 15)],
    'turkish' => [_use('turkish', 'Turkish coffee', 'g', 10)],
    'cold_brew' => [_use('cold-brew', 'Cold brew concentrate', 'ml', 120)],
    'matcha' || 'iced_matcha' => [
      _use('matcha', 'Matcha powder', 'g', 4),
      _use('milk', _milk.name, 'ml', 200),
    ],
    'chai' => [
      _use('chai', 'Chai concentrate', 'ml', 60),
      _use('milk', _milk.name, 'ml', 180),
    ],
    'hot_choc' => [
      _use('chocolate', 'Chocolate sauce', 'ml', 40),
      _use('milk', _milk.name, 'ml', 200),
    ],
    'mint_lemonade' => [
      _use('lemons', 'Lemons', 'kg', 0.15),
      _use('mint', 'Fresh mint', 'g', 8),
    ],
    'hibiscus' => [_use('hibiscus', 'Dried hibiscus', 'g', 8)],
    'green_tea' => [_use('green-tea', 'Green tea bags', 'pcs', 1)],
    'orange' => [_use('oranges', 'Oranges', 'kg', 0.4)],
    'mango' => [_use('mangoes', 'Mangoes', 'kg', 0.3)],
    'strawberry' => [_use('strawberries', 'Strawberries', 'kg', 0.25)],
    _ => <_Use>[],
  };
  return [...ingredients, cup];
}

/// An add-on's stock (by its English name).
List<_Use> _addonUse(String name) => switch (name) {
  'Extra shot' => [_use('beans', _beans.name, 'g', 9)],
  'Vanilla syrup' => [_use('vanilla', 'Vanilla syrup', 'ml', 15)],
  'Caramel syrup' => [_use('caramel', 'Caramel syrup', 'ml', 15)],
  'Hazelnut syrup' => [_use('hazelnut', 'Hazelnut syrup', 'ml', 15)],
  'Whipped cream' => [_use('cream', 'Whipping cream', 'g', 20)],
  _ => const [],
};

final Map<String, SeedItem> _menuById = {
  for (final m in seedMenu) MockSeed.menuItemId(m.key): m,
};

/// The stock a till's orders moved (`till_deduction_rows`): a sale's rows
/// positive, a void's restock negative.
List<DeductionLogRow> _deductions(MockDb db, String tillId) {
  final out = <DeductionLogRow>[];
  final orders = _ordersOf(db, tillId)
    ..sort(
      (a, b) =>
          (a['created_at']! as String).compareTo(b['created_at']! as String),
    );
  for (final o in orders) {
    final orderId = o['id']! as String;
    final uses = <_Use>[];
    for (final line in MockSeed.instance.orderItems(orderId)) {
      final item = _menuById[line.menuItemId];
      if (item == null) continue;
      final milkSwap = line.addons
          .where(
            (a) =>
                a.addonName.endsWith(' milk') ||
                a.addonName == 'Skimmed' ||
                a.addonName == 'Full cream',
          )
          .map((a) => a.addonName)
          .firstOrNull;
      for (final u in _recipe(item.key, item.category == 'iced')) {
        final swapped = u.key == 'milk' && milkSwap != null
            ? _use(
                'milk-${milkSwap.toLowerCase().replaceAll(' ', '-')}',
                milkSwap == 'Skimmed'
                    ? 'Skimmed milk'
                    : (milkSwap == 'Full cream' ? _milk.name : milkSwap),
                'ml',
                u.qty,
              )
            : u;
        uses.add(_use(swapped.key, swapped.name, swapped.unit, u.qty * line.quantity));
      }
      for (final a in line.addons) {
        for (final u in _addonUse(a.addonName)) {
          uses.add(_use(u.key, u.name, u.unit, u.qty * line.quantity));
        }
      }
    }
    final created = DateTime.parse(o['created_at']! as String);
    final voidedAt = o['voided_at'] as String?;
    for (final (i, u) in uses.indexed) {
      out.add(
        DeductionLogRow(
          id: mockUuid('deduction:$orderId:$i:sale'),
          orderId: orderId,
          inventoryItemId: mockUuid('ingredient:${u.key}'),
          itemName: u.name,
          unit: u.unit,
          quantityDeducted: u.qty,
          source: 'sale',
          createdAt: created,
        ),
      );
      if (voidedAt != null) {
        out.add(
          DeductionLogRow(
            id: mockUuid('deduction:$orderId:$i:void'),
            orderId: orderId,
            inventoryItemId: mockUuid('ingredient:${u.key}'),
            itemName: u.name,
            unit: u.unit,
            quantityDeducted: -u.qty,
            source: 'void_restock',
            createdAt: DateTime.parse(voidedAt),
          ),
        );
      }
    }
  }
  return out;
}

TillReportResponse _report(MockDb db, MockRow till, DateTime now) {
  final id = till['id']! as String;
  final orders = _ordersOf(db, id);
  final sold = orders.where(_sold).toList();
  final byMethod = <String, ({bool cash, int total, Set<String> orders})>{};
  for (final o in sold) {
    for (final l in _legs(o)) {
      final cur = byMethod[l.method];
      byMethod[l.method] = (
        cash: (cur?.cash ?? false) || l.isCash,
        total: (cur?.total ?? 0) + l.amount,
        orders: {...?cur?.orders, o['id']! as String},
      );
    }
  }
  final names = byMethod.keys.toList()..sort();
  final summary = [
    for (final m in names)
      PaymentSummaryRow(
        paymentMethod: m,
        isCash: byMethod[m]!.cash,
        total: byMethod[m]!.total,
        orderCount: byMethod[m]!.orders.length,
      ),
  ];
  final totalPayments = summary.fold<int>(0, (s, p) => s + p.total);
  var tips = 0;
  var cashTips = 0;
  var tax = 0;
  for (final o in sold) {
    final tip = (o['tip_amount'] as int?) ?? 0;
    tips += tip;
    final tipMethod =
        (o['tip_payment_method'] as String?) ?? o['payment_method'];
    if (tip != 0 && tipMethod == 'cash') cashTips += tip;
    tax += (o['tax_amount'] as int?) ?? 0;
  }
  final voided = orders
      .where((o) => o['status'] == 'voided')
      .fold<int>(0, (s, o) => s + ((o['total_amount'] as int?) ?? 0));
  final moves = _movesOf(db, id);
  int bucket(String kind) => moves
      .where((m) => m['kind'] == kind)
      .fold<int>(0, (s, m) => s + (m['amount']! as int));
  final net = moves.fold<int>(0, (s, m) => s + (m['amount']! as int));
  int? first;
  int? last;
  String? code;
  for (final o in orders) {
    final n = o['order_number'] as int?;
    if (n == null) continue;
    if (first == null || n < first) first = n;
    if (last == null || n > last) last = n;
    final c = o['device_code'] as String?;
    if (c != null && (code == null || c.compareTo(code) > 0)) code = c;
  }
  final expected = _expectedCash(db, till);
  final branch = db['branches'].find(till['branch_id']! as String);
  final float = branch?['standard_float'] as int?;
  return TillReportResponse(
    till: Till.fromJson(till),
    paymentSummary: summary,
    totalPayments: totalPayments,
    netPayments: totalPayments,
    voidedAmount: voided,
    totalTips: tips,
    cashTips: cashTips,
    nonCashTips: tips - cashTips,
    totalTax: tax,
    totalServiceCharge: 0,
    cashMovements: [
      for (final m in moves)
        CashMovementSummaryRow(
          id: m['id']! as String,
          amount: m['amount']! as int,
          kind: m['kind']! as String,
          note: m['note']! as String,
          movedByName: m['moved_by_name']! as String,
          createdAt: DateTime.parse(m['created_at']! as String),
          correctsId: m['corrects_id'] as String?,
        ),
    ],
    cashMovementsIn: bucket('pay_in'),
    cashMovementsOut: -bucket('pay_out'),
    safeDrops: -bucket('safe_drop'),
    cashAdjustments: bucket('correction'),
    cashMovementsNet: net,
    refundsIssuedCount: 0,
    refundsIssuedAmount: 0,
    refundsIssuedCash: 0,
    expectedCash: expected,
    standardFloat: float,
    suggestedSafeDrop: till['status'] == 'open' && float != null
        ? (expected - float < 0 ? 0 : expected - float)
        : null,
    printedAt: now,
    timezone: till['timezone'] as String?,
    orderNumberRange: OrderNumberRange(
      deviceCode: code ?? till['device_code'] as String?,
      first: first,
      last: last,
    ),
    openBillsAtClose: till['open_bills_at_close'] as int?,
    oldBillsAtClose: till['old_bills_at_close'] as int?,
    heldOrdersLeftOpen: till['held_orders_left_open'] as int?,
    heldOrdersLeftOpenTotal: till['held_orders_left_open_total'] as int?,
    reconciliation: _linesOf(db, id),
  );
}

ShiftSummary _summary(MockDb db, MockRow till) {
  final id = till['id']! as String;
  final orders = _ordersOf(db, id);
  final sold = orders.where(_sold).toList();
  int sum(String field) =>
      sold.fold<int>(0, (s, o) => s + ((o[field] as int?) ?? 0));
  final byMethod = <String, int>{};
  for (final o in sold) {
    for (final l in _legs(o)) {
      byMethod[l.method] = (byMethod[l.method] ?? 0) + l.amount;
    }
  }
  var cashTips = 0;
  for (final o in sold) {
    final tip = (o['tip_amount'] as int?) ?? 0;
    final m = (o['tip_payment_method'] as String?) ?? o['payment_method'];
    if (tip != 0 && m == 'cash') cashTips += tip;
  }
  return ShiftSummary(
    tillId: id,
    shiftId: id,
    branchId: till['branch_id']! as String,
    branchName: (till['branch_name'] as String?) ?? '',
    tellerId: till['teller_id']! as String,
    tellerName: till['teller_name']! as String,
    status: till['status']! as String,
    deviceCode: till['device_code'] as String?,
    openedAt: DateTime.parse(till['opened_at']! as String),
    closedAt: till['closed_at'] == null
        ? null
        : DateTime.parse(till['closed_at']! as String),
    openedWhileAnotherOpen: (till['opened_while_another_open'] as bool?) ?? false,
    reconciliationStatus: till['reconciliation_status'] as String?,
    openingCash: till['opening_cash']! as int,
    closingCashDeclared: till['closing_cash_declared'] as int?,
    closingCashSystem: till['closing_cash_system'] as int?,
    cashDiscrepancy: till['cash_discrepancy'] as int?,
    totalOrders: sold.length,
    voidedOrders: orders.where((o) => o['status'] == 'voided').length,
    totalRevenue: sum('total_amount'),
    grossSales: sum('total_amount'),
    refundedAmount: 0,
    revenueByMethod: byMethod,
    totalDiscount: sum('discount_amount'),
    totalTax: sum('tax_amount'),
    totalServiceCharge: sum('service_charge_amount'),
    totalDeliveryFees: sum('delivery_fee'),
    totalTips: sum('tip_amount'),
    cashTips: cashTips,
    refundsIssuedCount: 0,
    refundsIssuedAmount: 0,
    refundsIssuedCash: 0,
  );
}

// ── The routes ───────────────────────────────────────────────────────────

void registerTillsMocks(MockServer server, MockDb db) {
  loadTillsScenario(db);
  final tills = db[TillTables.tills];

  MockRow tillOf(MockRequest req) {
    final t = tills.get(req.param('tillId'), what: 'Till not found');
    req.requireBranch(t['branch_id']! as String);
    return t;
  }

  /// The person's own till, or someone's when they may force-close it.
  void requireOwn(MockRequest req, MockRow t, String refusal) {
    if (t['teller_id'] == req.persona.userId) return;
    if (req.persona.can('till.force_close') &&
        req.persona.seesBranch(t['branch_id']! as String)) {
      return;
    }
    throw MockHttpError(MockResponse.forbidden(refusal));
  }

  // T1 — the caller's till state at the branch.
  server.on('GET', '/tills/branches/{branchId}/current', (req) {
    req.requireCap('till.read');
    final branchId = req.param('branchId');
    req.requireBranch(branchId);
    final wanted = req.q('teller_id');
    final person = wanted != null && req.persona.can('till.read.branch')
        ? wanted
        : req.persona.userId;
    final open = _newestFirst(
      tills.where((t) => t['teller_id'] == person && t['status'] == 'open'),
    );
    final here = open.where((t) => t['branch_id'] == branchId).firstOrNull;
    final float =
        db['branches'].find(branchId)?['standard_float'] as int?;
    final last = _lastCloseDeclared(db, branchId);
    return MockResponse.ok(
      TillPreFill(
        hasOpenTill: here != null,
        openTill: here == null ? null : Till.fromJson(here),
        openElsewhere: [for (final t in open) _brief(t)],
        openAtBranch: [
          for (final t in open)
            if (t['branch_id'] == branchId) _brief(t),
        ],
        suggestedOpeningCash: last ?? float ?? 0,
        lastCloseDeclared: last,
        openBillsNotice: _notice(db, branchId, req.now),
      ),
    );
  });

  // T4 — every open till at the branch, newest first.
  server.on('GET', '/tills/branches/{branchId}/open', (req) {
    req.requireCap('till.read');
    final branchId = req.param('branchId');
    req.requireBranch(branchId);
    return MockResponse.ok(
      _newestFirst(
        tills.where(
          (t) => t['branch_id'] == branchId && t['status'] == 'open',
        ),
      ),
    );
  });

  // T5 — bills left open at the branch.
  server.on('GET', '/tills/branches/{branchId}/open-bills-notice', (req) {
    req.requireCap('tickets.read');
    final branchId = req.param('branchId');
    req.requireBranch(branchId);
    return MockResponse.ok(_notice(db, branchId, req.now));
  });

  // T3 — the list.
  server.on('GET', '/tills/branches/{branchId}', (req) {
    req.requireCap('till.read');
    final branchId = req.param('branchId');
    Set<String> branches;
    if (branchId == _allBranches) {
      final org = req.orgId;
      if (org == null) {
        req.fail(MockResponse.forbidden('No organization in scope'));
      }
      branches = {
        for (final b in db['branches'].where((b) => b['org_id'] == org))
          b['id']! as String,
      };
    } else {
      req.requireBranch(branchId);
      branches = {branchId};
    }
    final status = req.q('status');
    if (status != null &&
        status != 'open' &&
        status != 'closed' &&
        status != 'force_closed') {
      req.badRequest('status must be open, closed or force_closed');
    }
    final teller = req.q('teller_id');
    final device = req.q('device_id');
    final flagged = req.qBool('flagged') ?? false;
    final rows = queryRows(
      tills.rows,
      where: (t) =>
          branches.contains(t['branch_id']) &&
          (status == null || t['status'] == status) &&
          (teller == null || t['teller_id'] == teller) &&
          (device == null || t['device_id'] == device) &&
          (!flagged ||
              t['opened_while_another_open'] == true ||
              t['reconciliation_status'] == 'disagreed'),
      from: req.qDateTime('from'),
      to: req.qDateTime('to'),
      dateField: 'opened_at',
      sort: '-opened_at',
    );
    final paged = req.q('page') != null || req.q('per_page') != null;
    if (paged) return MockResponse.ok(pageOf(rows, req, maxPerPage: 200));
    return MockResponse.ok({
      'data': rows,
      'total': rows.length,
      'page': 1,
      'per_page': rows.isEmpty ? 1 : rows.length,
      'total_pages': rows.isEmpty ? 0 : 1,
    });
  });

  // T2 — open a till.
  server.on('POST', '/tills/branches/{branchId}/open', (req) {
    final branchId = req.param('branchId');
    req.requireCap('till.open', branchId: branchId);
    final body = req.bodyAs(OpenTillRequest.fromJson);
    if (body.openingCash < 0) {
      req.badRequest('Opening cash cannot be negative');
    }
    final mine = _newestFirst(
      tills.where(
        (t) => t['teller_id'] == req.persona.userId && t['status'] == 'open',
      ),
    );
    final elsewhere = mine.where((t) => t['branch_id'] != branchId);
    if (elsewhere.isNotEmpty) {
      req.fail(
        MockResponse.error(
          409,
          'You already have an open till at another branch. Close it before '
          'opening a new one.',
          code: 'TILL_OPEN_AT_OTHER_BRANCH',
          till: _brief(elsewhere.first).toJson(),
        ),
      );
    }
    final here = mine.where((t) => t['device_id'] == null).firstOrNull;
    if (here != null) return MockResponse.ok(here);
    if (mine.isNotEmpty) {
      req.fail(
        MockResponse.error(
          409,
          'You already have an open till on another device. Close it there '
          'first.',
          code: 'TILL_OPEN_ELSEWHERE',
          till: _brief(mine.first).toJson(),
        ),
      );
    }
    final expected = _lastCloseDeclared(db, branchId);
    final edited = expected != null && expected != body.openingCash;
    final reason = body.editReason?.trim();
    if (edited && (reason == null || reason.isEmpty)) {
      req.badRequest(
        'Opening cash differs from your last declared closing cash; '
        'edit_reason is required.',
      );
    }
    final branch = db['branches'].get(branchId, what: 'Branch not found');
    final till = Till(
      id: body.id ?? db.newId(TillTables.tills),
      branchId: branchId,
      branchName: branch['name'] as String?,
      tellerId: req.persona.userId,
      tellerName: req.persona.displayName,
      openedAt: body.openedAt ?? req.now,
      openingCash: body.openingCash,
      openingCashOriginal: expected,
      openingCashWasEdited: edited,
      openingCashEditReason: edited ? reason : null,
      openedWhileAnotherOpen: false,
      disagreementCount: 0,
      status: TillStatus.open,
      verification: TillVerification.server,
      timezone: (branch['timezone'] as String?) ?? MockClock.timezone,
    ).toJson();
    tills.insert(till, timestamps: false);
    return MockResponse.created(till);
  });

  // T7 — the till (Z) report.
  server.on('GET', '/tills/{tillId}/report', (req) {
    req.requireCap('till.read');
    return MockResponse.ok(_report(db, tillOf(req), req.now));
  });

  // T15 — the sales summary.
  server.on('GET', '/reports/tills/{tillId}/summary', (req) {
    req.requireCap('till.read');
    final t = tills.get(req.param('tillId'), what: 'Shift not found');
    req.requireBranch(t['branch_id']! as String);
    return MockResponse.ok(_summary(db, t));
  });

  // T16 — the stock its orders moved.
  server.on('GET', '/reports/tills/{tillId}/deductions', (req) {
    req.requireCap('inventory.read');
    final t = tills.get(req.param('tillId'), what: 'Shift not found');
    req.requireBranch(t['branch_id']! as String);
    return MockResponse.ok(_deductions(db, t['id']! as String));
  });

  // T17 — who looked at the spot report, oldest first.
  server.on('GET', '/tills/{tillId}/spot-views', (req) {
    req.requireCap('till.read');
    final t = tillOf(req);
    final rows = queryRows(
      db[TillTables.spotViews].where((v) => v['till_id'] == t['id']),
      sort: 'viewed_at',
    );
    return MockResponse.ok(rows);
  });

  // T8 — what the close form reconciles.
  server.on('GET', '/tills/{tillId}/close-preview', (req) {
    req.requireCap('till.operate');
    final t = tillOf(req);
    final expected = _expectedCash(db, t);
    final branchId = t['branch_id']! as String;
    return MockResponse.ok(
      CloseTillPreview(
        till: Till.fromJson(t),
        expectedCash: expected,
        methods: _closeMethods(db, t, expected),
        lastTillWarning: _lastTillWarning(
          _notice(db, branchId, req.now),
          otherOpen: _otherOpen(db, branchId, t['id']! as String),
        ),
      ),
    );
  });

  // T9 — close.
  server.on('POST', '/tills/{tillId}/close', (req) {
    req.requireCap('till.operate');
    final t = tillOf(req);
    requireOwn(req, t, 'You can only close your own till');
    final body = req.bodyAs(CloseTillRequest.fromJson);
    final id = t['id']! as String;
    if (t['status'] != 'open') {
      return MockResponse.ok(
        CloseTillResponse(till: Till.fromJson(t), reconciliation: _linesOf(db, id)),
      );
    }
    final closedAt = body.closedAt ?? req.now;
    final system = _systemCash(db, t);
    final branchId = t['branch_id']! as String;
    final notice = _notice(db, branchId, req.now);
    final lines = _planLines(
      db,
      t,
      declared: body.closingCashDeclared,
      system: system,
      cashNote: body.cashNote,
      inputs: body.reconciliation ?? const [],
      by: req.persona.userId,
      at: closedAt,
    );
    t.addAll({
      'status': 'closed',
      'closing_cash_declared': body.closingCashDeclared,
      'closing_cash_system': system,
      'cash_discrepancy': body.closingCashDeclared - system,
      'closed_at': closedAt.toUtc().toIso8601String(),
      'closed_by': req.persona.userId,
      'notes': body.cashNote ?? t['notes'],
      'open_bills_at_close': notice.openBillsCount,
      'old_bills_at_close': notice.oldBillsCount,
      'held_orders_left_open': ?body.heldOrdersLeftOpen,
      'held_orders_left_open_total': ?body.heldOrdersLeftOpenTotal,
    });
    _storeLines(db, id, lines);
    return MockResponse.ok(
      CloseTillResponse(
        till: Till.fromJson(t),
        reconciliation: _linesOf(db, id),
        lastTillWarning: _lastTillWarning(
          notice,
          otherOpen: _otherOpen(db, branchId, id),
        ),
      ),
    );
  });

  // T11 — move cash in or out.
  server.on('POST', '/tills/{tillId}/cash-movements', (req) {
    req.requireCap('till.operate');
    final t = tillOf(req);
    requireOwn(req, t, 'You can only add cash movements to your own till');
    final body = req.bodyAs(CashMovementRequest.fromJson);
    if (body.amount == 0) req.badRequest('Amount cannot be zero');
    if (body.note.trim().isEmpty) {
      req.badRequest('Note is required for cash movements');
    }
    final kind = body.kind?.value ?? (body.amount > 0 ? 'pay_in' : 'pay_out');
    final signOk = switch (kind) {
      'pay_in' => body.amount > 0,
      'pay_out' || 'safe_drop' => body.amount < 0,
      _ => true,
    };
    if (!signOk) {
      req.badRequest(switch (kind) {
        'pay_in' => 'A pay-in must be a positive amount',
        'pay_out' => 'A pay-out must be a negative amount',
        _ => 'A safe drop must be a negative amount',
      });
    }
    if (t['status'] != 'open') {
      req.fail(
        MockResponse.error(
          400,
          'Cash movements can only be added to an open till',
          code: 'TILL_NOT_OPEN',
        ),
      );
    }
    final id = t['id']! as String;
    final movement = CashMovement(
      id: db.newId(TillTables.movements),
      tillId: id,
      shiftId: id,
      amount: body.amount,
      kind: kind,
      note: body.note,
      movedBy: req.persona.userId,
      movedByName: req.persona.displayName,
      createdAt: body.createdAt ?? req.now,
      deviceId: body.deviceId,
      clientRef: body.clientRef,
      correctsId: body.correctsId,
    ).toJson();
    db[TillTables.movements].insert(movement, timestamps: false);
    return MockResponse.created(movement);
  });

  // T10 — force close.
  server.on('POST', '/tills/{tillId}/force-close', (req) {
    req.requireCap('till.operate');
    final t = tillOf(req);
    req.requireCap('till.force_close', branchId: t['branch_id']! as String);
    final body = req.bodyAs(ForceCloseRequest.fromJson);
    if (t['status'] != 'open') return MockResponse.ok(t);
    final id = t['id']! as String;
    final branchId = t['branch_id']! as String;
    final system = _systemCash(db, t);
    final notice = _notice(db, branchId, req.now);
    final now = req.now.toUtc().toIso8601String();
    t.addAll({
      'status': 'force_closed',
      'closing_cash_system': system,
      'closed_at': now,
      'closed_by': req.persona.userId,
      'force_closed_by': req.persona.userId,
      'force_closed_at': now,
      'force_close_reason': body.reason,
      'open_bills_at_close': notice.openBillsCount,
      'old_bills_at_close': notice.oldBillsCount,
    });
    final lines = [
      for (final l in _planLines(
        db,
        t,
        declared: system,
        system: system,
        cashNote: null,
        inputs: const [],
        by: req.persona.userId,
        at: req.now,
      ))
        TillReconciliationLine.fromJson({
          ...l.toJson(),
          'status': 'unreviewed',
          'declared_amount': null,
          'note': null,
        }),
    ];
    _storeLines(db, id, lines);
    return MockResponse.ok(t);
  });

  // T13 — delete a till record.
  server.on('DELETE', '/tills/{tillId}', (req) {
    req.requireCap('till.delete');
    final t = tillOf(req);
    final id = t['id']! as String;
    if (t['status'] == 'open') {
      req.conflict('Cannot delete an open till — force-close it first.');
    }
    final orders = _ordersOf(db, id);
    if (orders.any((o) => o['status'] != 'voided')) {
      req.conflict(
        'Cannot delete a till that has recorded (non-voided) orders — its '
        'sales are part of the financial record.',
      );
    }
    db['orders'].removeWhere((o) => o['till_id'] == id);
    tills.delete(id);
    db[TillTables.movements].removeWhere((m) => m['till_id'] == id);
    db[TillTables.reconciliations].removeWhere((r) => r['till_id'] == id);
    db[TillTables.spotViews].removeWhere((v) => v['till_id'] == id);
    return MockResponse.empty();
  });
}
