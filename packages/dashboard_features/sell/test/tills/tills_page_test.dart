// Tills (SELL-TIL rows): the page, its reads, filters, KPIs, "Open now" and
// the list, driven through the real shell on the mock server.
import 'dart:async';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/tills/tills_data.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tills_support.dart';

String get _helio => SeedIds.heliopolis;

/// Texts of [finder]'s RichTexts, joined.
String textsOf(WidgetTester tester, Finder finder) => [
  for (final e
      in find
          .descendant(of: finder, matching: find.byType(RichText))
          .evaluate())
    (e.widget as RichText).text.toPlainText(),
].join(' | ');

void main() {
  testWidgets('SELL-TIL-001 header: title, subtitle, Export, Open till and '
      'the filters row', (tester) async {
    await pumpTills(tester);
    expect(inPage(find.text('Tills')), findsOneWidget);
    expect(
      inPage(find.text("Each teller's sales session and cash drawer")),
      findsOneWidget,
    );
    expect(inPage(find.text('Export Excel')), findsOneWidget);
    expect(inPage(find.text('Open till')), findsOneWidget);
    for (final w in [
      'All statuses',
      'All tellers',
      'All devices',
      'Today',
      'Flagged only',
    ]) {
      expect(inKey('tills-filters', find.text(w)), findsOneWidget, reason: w);
    }
  });

  testWidgets('SELL-TIL-002 with a branch: my till, open tills, the bills '
      'notice and the list (no params)', (tester) async {
    final h = await pumpTills(tester);
    expect(
      h.server.callsTo(tillsCurrent).single.path,
      '/tills/branches/$_helio/current',
    );
    expect(
      h.server.callsTo(tillsOpen).single.path,
      '/tills/branches/$_helio/open',
    );
    expect(
      h.server.callsTo(tillsNotice).single.path,
      '/tills/branches/$_helio/open-bills-notice',
    );
    // The table's first server page, never the unpaged full history.
    final list = pageReads(h).single;
    expect(list.path, '/tills/branches/$_helio');
    expect(list.query, pageQuery());
    // Plus the Flagged KPI's count and the filter menus' window: three reads.
    expect([
      for (final c in h.server.callsTo(tillsList)) c.query,
    ], unorderedEquals([pageQuery(), flaggedQuery(), optionsQuery]));
  });

  testWidgets('SELL-TIL-003 Status filter → ?status= → status', (tester) async {
    final h = await pumpTills(tester);
    expect(
      filterOptions(h, 'filter-status'),
      containsAllInOrder(['All statuses', 'Open', 'Closed', 'Force Closed']),
    );
    await pickFilter(h, 'filter-status', 'Closed');
    expect(h.location.queryParameters['status'], 'closed');
    expect(
      pageReads(h).last.query,
      pageQuery({
        'status': ['closed'],
      }),
    );
    expect(inKey('tills-table', find.text('Open')), findsNothing);
    await pickFilter(h, 'filter-status', 'All statuses');
    expect(h.location.queryParameters.containsKey('status'), isFalse);
  });

  testWidgets('SELL-TIL-004/064 Teller filter: the tellers of the latest '
      'tills; picking one leaves only that teller', (tester) async {
    final h = await pumpTills(tester);
    final options = filterOptions(h, 'filter-teller');
    expect(options.first, 'All tellers');
    expect(options, containsAll(['Ali Hassan', 'Farida Wael']));
    await pickFilter(h, 'filter-teller', 'Farida Wael');
    expect(h.location.queryParameters['teller'], SeedIds.user('farida'));
    expect(
      pageReads(h).last.query,
      pageQuery({
        'teller_id': [SeedIds.user('farida')],
      }),
    );
    // The menu comes from the latest tills, not the page on screen: the
    // other tellers stay pickable.
    expect(
      filterOptions(h, 'filter-teller'),
      containsAll(['All tellers', 'Ali Hassan', 'Farida Wael']),
    );
  });

  testWidgets('SELL-TIL-005 Device filter: label, else code → device_id', (
    tester,
  ) async {
    final h = await pumpTills(tester);
    final options = filterOptions(h, 'filter-device');
    // Newest first: Ali's second till (Counter 3), the second teller's
    // (Counter 2), Ali's first (Counter 1).
    expect(options, ['All devices', 'Counter 3', 'Counter 2', 'Counter 1']);
    await pickFilter(h, 'filter-device', 'Counter 3');
    final id = mockUuid('device:heliopolis:T3');
    expect(h.location.queryParameters['device'], id);
    expect(
      pageReads(h).last.query,
      pageQuery({
        'device_id': [id],
      }),
    );
    expect(inKey('tills-table', find.text('Farida Wael')), findsNothing);
  });

  testWidgets('SELL-TIL-006 Today → ?today=true → from = local midnight', (
    tester,
  ) async {
    final h = await pumpTills(tester);
    await h.tap(inKey('filter-today', find.text('Today')));
    expect(h.location.queryParameters['today'], 'true');
    final now = h.container.read(clockProvider)().toLocal();
    final midnight = DateTime(now.year, now.month, now.day).toUtc();
    final from = pageReads(h).last.query['from']!.single;
    expect(DateTime.parse(from), midnight);
    // Only the tills opened since then.
    final today = [
      for (final t in tillsAt(h.db!, _helio))
        if (!DateTime.parse(t['opened_at']! as String).isBefore(midnight)) t,
    ];
    expect(today, isNotEmpty);
    expect(inKey('all-tills', find.text('${today.length}')), findsOneWidget);
  });

  testWidgets('SELL-TIL-007 Flagged only → flagged=true; unchecking drops it', (
    tester,
  ) async {
    final h = await pumpTills(tester);
    await h.tap(inKey('filter-flagged', find.text('Flagged only')));
    expect(h.location.queryParameters['flagged'], 'true');
    expect(
      pageReads(h).last.query,
      pageQuery({
        'flagged': ['true'],
      }),
    );
    expect(inPage(find.text('All tills')), findsOneWidget);
    expect(inKey('all-tills', find.text('1')), findsOneWidget);
    await h.tap(inKey('filter-flagged', find.text('Flagged only')));
    expect(h.location.queryParameters.containsKey('flagged'), isFalse);
    // The unfiltered list is still fresh in the cache: no request.
    expect(pageReads(h), hasLength(2));
    expect(
      inKey('all-tills', find.text('${tillsAt(h.db!, _helio).length}')),
      findsOneWidget,
    );
  });

  testWidgets('SELL-TIL-008 filters come from the URL; an unknown status is '
      'ignored, empty and false params are dropped', (tester) async {
    final farida = SeedIds.user('farida');
    final h = await pumpTills(
      tester,
      query: 'status=nope&flagged=1&teller=$farida&device=&today=false',
    );
    expect(
      pageReads(h).single.query,
      pageQuery({
        'teller_id': [farida],
        'flagged': ['true'],
      }),
    );
    expect(TillsSearch.fromQuery({'page': '3'}).page, 3);
    for (final junk in ['1', '0', '-2', 'x', '']) {
      expect(TillsSearch.fromQuery({'page': junk}).page, 1, reason: junk);
    }
    expect(TillsSearch.fromQuery({'status': 'open'}).status, 'open');
    expect(TillsSearch.fromQuery({'flagged': 'true'}).flagged, isTrue);
    expect(TillsSearch.fromQuery({'today': '0'}).today, isFalse);
  });

  testWidgets('SELL-TIL-009 KPIs: open now, open bills (+ amount), older than '
      'the branch hours, flagged in list', (tester) async {
    final h = await pumpTills(tester);
    final kpis = find.byKey(const ValueKey('tills-kpis'));
    Finder card(String key) =>
        find.descendant(of: kpis, matching: find.byKey(ValueKey(key)));
    String text(String key) => textsOf(tester, card(key));
    final open = openAt(h.db!, _helio).length;
    expect(text('open'), allOf(contains('Open now'), contains('$open')));
    expect(
      text('bills'),
      allOf(contains('Open bills'), contains('2'), contains('EGP 820.00')),
    );
    expect(text('old'), allOf(contains('Older than 3h'), contains('1')));
    expect(text('flagged'), allOf(contains('Flagged in list'), contains('1')));
    // Counted by the server across every page (a one-row flagged read's
    // total), never from the page on screen.
    expect(
      h.server
          .callsTo(tillsList)
          .where((c) => c.query['per_page']?.single == '1')
          .single
          .query,
      flaggedQuery(),
    );
    expect(tester.widget<DashStatCard>(card('open')).tone, DashTone.success);
    expect(tester.widget<DashStatCard>(card('old')).tone, DashTone.warning);
    expect(tester.widget<DashStatCard>(card('flagged')).tone, DashTone.warning);
  });

  testWidgets('SELL-TIL-010 the bills line: count since the last close, the '
      'amount, and the old-bill pill', (tester) async {
    final h = await pumpTills(tester);
    final line = find.byKey(const ValueKey('open-bills-notice'));
    expect(
      textsOf(tester, line),
      allOf(
        contains('2 bills left open since 07 Oct, 11:05 PM'),
        contains('EGP 820.00'),
        contains('1 older than 3h'),
      ),
    );
    expect(h.server.callsTo(tillsNotice), hasLength(1));
  });

  testWidgets('SELL-TIL-011 Open now rows: teller, device · label · open for, '
      'badges without the link, the float; a tap opens the report', (
    tester,
  ) async {
    final h = await pumpTills(tester);
    final row = find.byKey(ValueKey('open-now-${TillIds.helioSecond}'));
    expect(
      textsOf(tester, row),
      allOf(
        contains('Ali Hassan'),
        contains('T3 · Counter 3 · 1h 48m'),
        contains('Verified on LAN'),
        contains('Opened while another till was open'),
        contains('EGP 500.00'),
      ),
    );
    expect(
      find.descendant(of: row, matching: find.text('See the other till')),
      findsNothing,
    );
    await h.tap(row);
    expect(h.location.queryParameters['report'], TillIds.helioSecond);
    expect(
      h.server.callsTo(tillReport).last.path,
      '/tills/${TillIds.helioSecond}/report',
    );
    expect(find.text('Till Report'), findsOneWidget);
  });

  testWidgets('SELL-TIL-012 Open now empty: No open till', (tester) async {
    final s = tillsServer();
    for (final t in s.db['tills'].rows) {
      if (t['branch_id'] == _helio && t['status'] == 'open') {
        t['status'] = 'closed';
      }
    }
    await pumpTills(tester, server: s.server, db: s.db);
    final empty = find.byKey(const ValueKey('open-now-empty'));
    expect(
      find.descendant(of: empty, matching: find.text('No open till')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: empty,
        matching: find.text(
          'A till opens when a teller starts selling on a POS.',
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SELL-TIL-013 "All tills" counts the server total', (
    tester,
  ) async {
    final h = await pumpTills(tester);
    final head = find.byKey(const ValueKey('all-tills'));
    expect(
      find.descendant(of: head, matching: find.text('All tills')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: head,
        matching: find.text('${tillsAt(h.db!, _helio).length}'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('SELL-TIL-014/016/017/021 columns: teller with opened → closed, '
      'device code + label, status pill, opening and discrepancy', (
    tester,
  ) async {
    final s = tillsServer();
    final short = TillIds.seeded('heliopolis', 1, 'evening');
    final over = TillIds.seeded('heliopolis', 1, 'morning');
    final even = TillIds.seeded('heliopolis', 2, 'evening');
    s.db['tills'].get(short)['cash_discrepancy'] = -1200;
    s.db['tills'].get(over)['cash_discrepancy'] = 2000;
    s.db['tills'].get(even)['cash_discrepancy'] = 0;
    await pumpTills(tester, server: s.server, db: s.db);
    final text = textsOf(tester, tillsTable);
    for (final h in [
      'TELLER',
      'DEVICE',
      'STATUS',
      'OPENING CASH',
      'DISCREPANCY',
    ]) {
      expect(text, contains(h));
    }
    expect(text, isNot(contains('BRANCH')));
    expect(text, contains('07 Oct, 02:57 PM\u2069 → \u206807 Oct, 11:05 PM'));
    expect(text, contains('T1  Counter 1'));
    Text cell(String id) =>
        tester.widget<Text>(find.byKey(ValueKey('discrepancy-$id')));
    // Open: none; balanced: muted zero; short / over: signed, danger, bold.
    expect(cell(TillIds.helioMorning).data, '—');
    expect(cell(short).data, contains('−EGP 12.00'));
    expect(cell(over).data, contains('+EGP 20.00'));
    expect(cell(even).data, contains('EGP 0.00'));
    expect(cell(even).data, isNot(contains('+')));
    expect(cell(even).style!.fontWeight, isNot(cell(short).style!.fontWeight));
    expect(cell(over).style!.color, cell(short).style!.color);
  });

  testWidgets('SELL-TIL-015/056 All branches: the Branch column, no KPIs, no '
      'Open now, no Open till; only the list is read', (tester) async {
    final h = await pumpTills(tester, allBranches: true);
    // Only the list endpoint: the page of 20 and the menus' window of 200.
    // No flagged count (there are no KPIs to feed).
    final reads = h.server.callsTo(tillsList);
    expect(reads, hasLength(2));
    expect(reads.map((c) => c.path).toSet(), {
      '/tills/branches/$allBranchesId',
    });
    expect(reads.map((c) => c.query['per_page']!.single).toList()..sort(), [
      '20',
      '200',
    ]);
    expect(reads.any((c) => c.query.containsKey('flagged')), isFalse);
    expect(h.server.callsTo(tillsCurrent), isEmpty);
    expect(h.server.callsTo(tillsOpen), isEmpty);
    expect(h.server.callsTo(tillsNotice), isEmpty);
    expect(find.byKey(const ValueKey('tills-kpis')), findsNothing);
    expect(find.byKey(const ValueKey('open-now')), findsNothing);
    expect(inPage(find.text('Open till')), findsNothing);
    final text = textsOf(tester, tillsTable);
    expect(text, contains('BRANCH'));
    expect(text, contains('Heliopolis'));
    expect(text, contains('Zamalek'));
  });

  testWidgets('SELL-TIL-017/018 status pills and verification badges', (
    tester,
  ) async {
    final h = await pumpTills(tester, branchId: SeedIds.newCairo);
    final unverified = find.byKey(
      ValueKey('till-badges-${TillIds.newCairoLastMorning}'),
    );
    expect(
      textsOf(tester, unverified),
      allOf(contains('Closed'), contains('Not verified')),
    );
    expect(
      find.descendant(
        of: inKey('tills-table', find.byType(Wrap)),
        matching: find.byKey(const ValueKey('verification-badge')),
      ),
      findsOneWidget,
    );
    // A server-verified till earns none.
    final open = find.byKey(ValueKey('till-badges-${TillIds.newCairoMorning}'));
    expect(textsOf(tester, open), contains('Open'));
    expect(textsOf(tester, open), isNot(contains('verified')));
    // Force closed reads in the warning tone (Maadi has one).
    await h.go('/tills?status=force_closed');
    expect(h.server.callsTo(tillsList).last.query['status'], ['force_closed']);
  });

  testWidgets('SELL-TIL-017 force closed pill', (tester) async {
    await pumpTills(
      tester,
      branchId: SeedIds.maadi,
      query: 'status=force_closed',
    );
    final badges = find.byKey(ValueKey('till-badges-${TillIds.maadiForced}'));
    final pill = tester.widget<DashStatusPill>(
      find.descendant(of: badges, matching: find.byType(DashStatusPill)).first,
    );
    expect(pill.label, 'Force Closed');
    expect(pill.tone, DashTone.warning);
  });

  testWidgets('SELL-TIL-019 the flag badge links to the other till without '
      'opening the row', (tester) async {
    final h = await pumpTills(tester);
    final badges = find.byKey(ValueKey('till-badges-${TillIds.helioSecond}'));
    await h.tap(
      find.descendant(of: badges, matching: find.text('See the other till')),
    );
    expect(h.location.queryParameters['report'], TillIds.helioMorning);
    // The finger going down on the row also warms the row's own report
    // (its intent); only the other till's report is shown.
    expect(
      h.server
          .callsTo(tillReport)
          .where((c) => c.path == '/tills/${TillIds.helioMorning}/report'),
      hasLength(1),
    );
  });

  testWidgets('SELL-TIL-020 the mismatch badge counts disagreements', (
    tester,
  ) async {
    await pumpTills(tester, branchId: SeedIds.zamalek);
    final badges = find.byKey(
      ValueKey('till-badges-${TillIds.zamalekLastEvening}'),
    );
    expect(textsOf(tester, badges), contains('1 mismatches'));
    final pill = tester.widget<DashStatusPill>(
      find.descendant(
        of: badges,
        matching: find.byKey(const ValueKey('disagreement-badge')),
      ),
    );
    expect(pill.tone, DashTone.danger);
  });

  testWidgets('SELL-TIL-022 a row opens its report; pointing at it warms the '
      'report first', (tester) async {
    final h = await pumpTills(tester);
    final id = TillIds.seeded('heliopolis', 1, 'evening');
    final cell = find.byKey(ValueKey('till-badges-$id'));
    await tester.ensureVisible(cell);
    await h.settle();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(cell));
    await h.settle();
    expect(h.server.callsTo(tillReport).single.path, '/tills/$id/report');
    await h.tap(cell);
    expect(h.location.queryParameters['report'], id);
    // Served from the warmed read.
    expect(h.server.callsTo(tillReport), hasLength(1));
    expect(find.text('Till Report'), findsOneWidget);
  });

  testWidgets('SELL-TIL-024 server paging: 20 a page from the server, '
      '?page= in the URL, a filter change is page 1, no Columns menu', (
    tester,
  ) async {
    final h = await pumpTills(tester);
    final pages = (tillsAt(h.db!, _helio).length / 20).ceil();
    expect(pages, greaterThan(1), reason: 'the seed needs a second page');
    expect(inKey('tills-table', find.text('Page 1 of $pages')), findsOneWidget);
    expect(inKey('tills-table', find.text('Columns')), findsNothing);
    final next = find.descendant(
      of: find.byType(DashPagination),
      matching: find.bySemanticsLabel('Next'),
    );
    await h.tap(next);
    expect(h.location.queryParameters['page'], '2');
    expect(pageReads(h).last.query, pageQuery({}, 2));
    expect(inKey('tills-table', find.text('Page 2 of $pages')), findsOneWidget);
    expect(pageReads(h), hasLength(2));
    // The total and the Flagged KPI are the server's, whatever the page.
    expect(
      inKey('all-tills', find.text('${tillsAt(h.db!, _helio).length}')),
      findsOneWidget,
    );
    await pickFilter(h, 'filter-status', 'Closed');
    expect(h.location.queryParameters.containsKey('page'), isFalse);
    expect(
      pageReads(h).last.query,
      pageQuery({
        'status': ['closed'],
      }),
    );
  });

  testWidgets('SELL-TIL-024 a page past the end goes to the last page', (
    tester,
  ) async {
    final h = await pumpTills(tester, query: 'page=999');
    final pages = (tillsAt(h.db!, _helio).length / 20).ceil();
    await h.settle();
    expect(h.location.queryParameters['page'], '$pages');
  });

  testWidgets('SELL-TIL-025 list loading: skeleton rows', (tester) async {
    final s = tillsServer();
    final gate = s.server.hold('GET', tillsList);
    final h = await pumpTills(tester, server: s.server, db: s.db);
    expect(
      find.descendant(of: tillsTable, matching: find.byType(DashSkeleton)),
      findsWidgets,
    );
    expect(inPage(find.text('No tills yet')), findsNothing);
    gate.release();
    await h.settle();
    expect(inKey('tills-table', find.text('Farida Wael')), findsWidgets);
  });

  testWidgets('SELL-TIL-025 list error: the server words and Retry, which '
      'reads the list again only', (tester) async {
    final s = tillsServer();
    s.server.fail(
      'GET',
      tillsList,
      MockResponse.error(500, 'Database error: connection reset'),
      times: null,
    );
    final h = await pumpTills(tester, server: s.server, db: s.db);
    expect(
      inKey('tills-table', find.text("Couldn't load this")),
      findsOneWidget,
    );
    expect(inKey('tills-table', find.text('connection reset')), findsOneWidget);
    s.server.clearFailures();
    final before = h.server.calls.length;
    final gate = s.server.hold('GET', tillsList);
    await h.tap(inKey('tills-table', find.text('Retry')));
    // While the retry is out the failure stays; never "No tills yet".
    expect(inPage(find.text('No tills yet')), findsNothing);
    expect(
      inKey('tills-table', find.text("Couldn't load this")),
      findsOneWidget,
    );
    gate.release();
    await h.settle();
    expect(h.server.calls.skip(before).map((c) => c.template).toSet(), {
      tillsList,
    });
    expect(inKey('tills-table', find.text('Farida Wael')), findsWidgets);
  });

  testWidgets('SELL-TIL-025 list empty: No tills yet', (tester) async {
    final s = tillsServer();
    s.db['tills'].removeWhere((t) => t['branch_id'] == _helio);
    final h = await pumpTills(tester, server: s.server, db: s.db);
    expect(inPage(find.text('No tills yet')), findsOneWidget);
    expect(
      inPage(
        find.text(
          'Tills appear here once a teller opens one, and stay for the record '
          'after they close.',
        ),
      ),
      findsOneWidget,
    );
    // Nothing to export.
    final export = tester.widget<DashExportButton>(
      find.byKey(const ValueKey('tills-export')),
    );
    expect(export.enabled, isFalse);
    // The page, the Flagged KPI's count and the menus' window: nothing else.
    final reads = h.server.callsTo(tillsList);
    expect(reads, hasLength(3));
    expect(reads.map((c) => c.query['per_page']!.single).toList()..sort(), [
      '1',
      '20',
      '200',
    ]);
    expect(reads.where((c) => c.query.containsKey('flagged')), hasLength(1));
  });

  testWidgets('SELL-TIL-026 phone: till cards with Device, Status, Opening, '
      'Discrepancy', (tester) async {
    final h = await pumpTills(tester, size: DashSize.phone);
    final card = find.ancestor(
      of: find.byKey(ValueKey('till-badges-${TillIds.helioMorning}')),
      matching: find.byType(DashCard),
    );
    final text = textsOf(tester, card);
    for (final w in [
      'Ali Hassan',
      'Device',
      'Status',
      'Opening Cash',
      'Discrepancy',
    ]) {
      expect(text, contains(w));
    }
    await h.tap(card.first);
    expect(h.location.queryParameters['report'], TillIds.helioMorning);
    expect(find.text('Till Report'), findsOneWidget);
  });

  testWidgets('SELL-TIL-057 a till.* event refreshes the KPIs, Open now, the '
      'list and the open report', (tester) async {
    final h = await pumpTills(tester, query: 'report=${TillIds.helioMorning}');
    int count(String t) => h.server.callsTo(t).length;
    // The list endpoint serves three reads (page, Flagged count, menus).
    final listReads = tillsList;
    final before = {
      for (final t in [
        tillsOpen,
        tillsNotice,
        tillsList,
        tillsCurrent,
        tillReport,
      ])
        t: count(t),
    };
    h.realtime.current!.emit('till.cash_moved', data: '{}');
    await h.settle();
    for (final e in before.entries) {
      // Each of the list's three reads runs once more.
      final reads = e.key == listReads ? 3 : 1;
      expect(count(e.key), e.value + reads, reason: e.key);
    }
  });

  testWidgets('SELL-TIL-058/059 Export: every till under the filters, one '
      'sheet "Tills", the web columns', (tester) async {
    final h = await pumpTills(tester, query: 'flagged=true');
    await h.tap(find.byKey(const ValueKey('tills-export')));
    await h.expectToast('Exported 1 row');
    final wb = h.exports.built.single;
    final sheet = wb.sheets.single;
    expect(sheet.name, 'Tills');
    expect(sheet.title, 'Tills');
    expect(
      [for (final c in sheet.columns) c.header],
      [
        'Opened',
        'Teller',
        'Device',
        'Status',
        'Opening Cash',
        'Cash counted in drawer',
        'Discrepancy',
        'Opened while another till was open',
        'Payment check',
      ],
    );
    expect(sheet.rows.single.sublist(1, 4), ['Ali Hassan', 'T3', 'Open']);
    expect(sheet.rows.single[7], '✓');
    expect(h.files.saved.single.filename, startsWith('Madar-Tills-'));
    expect(h.files.saved.single.filename, endsWith('.xlsx'));
    // The file walks the server's pages under the same filters.
    expect(
      h.server
          .callsTo(tillsList)
          .where(
            (c) =>
                c.query['per_page']?.single == '200' &&
                c.query['flagged']?.single == 'true',
          )
          .map((c) => c.query),
      [
        {
          'flagged': ['true'],
          'page': ['1'],
          'per_page': ['200'],
        },
      ],
    );
  });

  testWidgets('SELL-TIL-058 Export failure toasts', (tester) async {
    final h = await pumpTills(tester);
    final gate = Completer<void>();
    h.exports
      ..hold = gate.future
      ..failNext = StateError('disk full');
    await h.tap(find.byKey(const ValueKey('tills-export')));
    expect(
      tester
          .widget<DashExportButton>(find.byKey(const ValueKey('tills-export')))
          .loading,
      isTrue,
    );
    gate.complete();
    await h.settle();
    await h.expectToast('Export failed');
  });

  testWidgets('SELL-TIL-060 (divergence) Open now while loading: a '
      'skeleton, never "No open till"; Open till shows until my till is '
      'known', (tester) async {
    final s = tillsServer();
    final open = s.server.hold('GET', tillsOpen);
    final current = s.server.hold('GET', tillsCurrent);
    final h = await pumpTills(tester, server: s.server, db: s.db);
    expect(find.byKey(const ValueKey('open-now-loading')), findsOneWidget);
    expect(find.byKey(const ValueKey('open-now-empty')), findsNothing);
    expect(inPage(find.text('Open till')), findsOneWidget);
    current.release();
    open.release();
    await h.settle();
    expect(
      find.byKey(ValueKey('open-now-${TillIds.helioMorning}')),
      findsOneWidget,
    );
  });

  testWidgets('SELL-TIL-060 (divergence) Open now failed: an error with '
      'Retry (reading only the open tills), never "No open till"', (
    tester,
  ) async {
    final s = tillsServer();
    s.server.fail(
      'GET',
      tillsOpen,
      MockResponse.error(500, 'boom'),
      times: null,
    );
    final h = await pumpTills(tester, server: s.server, db: s.db);
    final error = find.byKey(const ValueKey('open-now-error'));
    expect(error, findsOneWidget);
    expect(find.byKey(const ValueKey('open-now-empty')), findsNothing);
    s.server.clearFailures();
    final before = h.server.calls.length;
    await h.tap(find.descendant(of: error, matching: find.text('Retry')));
    expect(h.server.calls.skip(before).map((c) => c.template).toSet(), {
      tillsOpen,
    });
    expect(
      find.byKey(ValueKey('open-now-${TillIds.helioMorning}')),
      findsOneWidget,
    );
  });

  testWidgets('SELL-TIL-055 ?report= opens that report on load; closing it '
      'clears the param', (tester) async {
    final h = await pumpTills(tester, query: 'report=${TillIds.helioMorning}');
    expect(find.text('Till Report'), findsOneWidget);
    expect(inSurface(find.text('Ali Hassan')), findsWidgets);
    await h.tap(inSurface(find.bySemanticsLabel('Close')));
    expect(find.text('Till Report'), findsNothing);
    expect(h.location.queryParameters.containsKey('report'), isFalse);
  });
}
