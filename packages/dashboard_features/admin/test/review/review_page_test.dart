// Driven tests for `/access/review` (ADM-REV-001..017), one or more per
// inventory row, through the real shell on the mock server.
import 'package:dashboard_admin/src/review/review_data.dart';
import 'package:dashboard_admin/src/shared/access_tabs.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Seeded open flags, newest first (AdminSeed.flags).
const _open = [
  'Hana Mostafa',
  'Mariam Fathy',
  'Youssef Samir',
  'Ziad Amr',
  'Ali Hassan',
  'Omar Khaled',
];
const _reviewed = ['Farida Wael', 'Salma Nabil'];

Finder _tab(String label) => find.descendant(
  of: find.byType(AccessSectionTabs),
  matching: find.text(label),
);

DashButton _button(WidgetTester tester, Finder f) => tester.widget<DashButton>(f);

void main() {
  testWidgets('ADM-REV-001 the Review tab shows only with approvals.review', (
    tester,
  ) async {
    await pumpReview(tester);
    expect(_tab('Review'), findsOneWidget);
    expect(_tab('Users'), findsOneWidget);
    expect(_tab('Roles & Permissions'), findsOneWidget);
  });

  testWidgets('ADM-REV-001 a manager (no approvals.review) sees no Review tab',
      (tester) async {
    final h = await pumpReview(tester, persona: Persona.manager);
    expect(_tab('Users'), findsOneWidget);
    expect(_tab('Review'), findsNothing);
    expect(h.location.path, reviewPath);
  });

  testWidgets('ADM-REV-002 header title and description', (tester) async {
    final h = await pumpReview(tester);
    expect(onPage('Review'), findsWidgets);
    expect(onPage(h.t('access.review.subtitle')), findsOneWidget);
  });

  testWidgets('ADM-REV-003 loads the open flags only, newest first', (
    tester,
  ) async {
    final h = await pumpReview(tester);
    final reads = flagReads(h);
    expect(reads, hasLength(1));
    expect(reads.single.query, isEmpty, reason: 'no include_reviewed');
    for (final n in _open) {
      expect(onPage(n), findsOneWidget, reason: n);
    }
    for (final n in _reviewed) {
      expect(onPage(n), findsNothing, reason: n);
    }
    final ys = [for (final n in _open) tester.getTopLeft(onPage(n)).dy];
    expect(ys, [...ys]..sort(), reason: 'newest first');
  });

  group('ADM-REV-004 refusal', () {
    testWidgets('without approvals.review the read is refused: error + Retry',
        (tester) async {
      final h = await pumpReview(tester, persona: Persona.manager);
      expect(
        onPage(shown(h, MockResponse.denied('approvals.review'))),
        findsOneWidget,
      );
      expect(onPage(h.t('errors.unauthorized')), findsOneWidget);
      expect(selectAll, findsNothing);
      expect(onPage('Mark reviewed'), findsNothing);
      await h.tap(onPage('Retry'));
      expect(flagReads(h), hasLength(2), reason: 'Retry asks again');
    });

    testWidgets('a list read without the grant shows no picks, no bulk bar, '
        'no Mark reviewed', (tester) async {
      final s = reviewServer();
      signedInWithout(s.server, {'approvals.review'});
      final h = await pumpReview(tester, server: s.server, db: s.db);
      expect(onPage('Hana Mostafa'), findsOneWidget);
      expect(pick(1), findsNothing);
      expect(selectAll, findsNothing);
      expect(bulkBar, findsNothing);
      expect(onPage('Mark reviewed'), findsNothing);
      expect(h.server.callsTo(reviewRoute), isEmpty);
    });
  });

  testWidgets('ADM-REV-005 Show reviewed adds include_reviewed=true and the '
      'reviewed flags join', (tester) async {
    final h = await pumpReview(tester);
    expect(tester.widget<DashSwitch>(showReviewed).value, isFalse);
    await h.tap(showReviewed);
    final reads = flagReads(h);
    expect(reads.last.query, {
      'include_reviewed': ['true'],
    });
    for (final n in [..._open, ..._reviewed]) {
      expect(onPage(n), findsOneWidget, reason: n);
    }
    // The words press it too (the web's <Label>).
    await h.tap(onPage('Show reviewed'));
    expect(onPage('Farida Wael'), findsNothing);
  });

  testWidgets('ADM-REV-006 columns, When as fmtStamp, 20 per page', (
    tester,
  ) async {
    final s = reviewServer();
    addFlags(s.db, 19); // 25 open
    final h = await pumpReview(tester, server: s.server, db: s.db);
    for (final c in ['PERSON', 'WHAT HAPPENED', 'PERMISSION', 'WHEN']) {
      expect(onPage(c), findsOneWidget, reason: c);
    }
    final fmt = h.container.read(formatProvider);
    // The first row (Teller 101) happened 10 minutes ago: today, time only.
    final first = s.db.clock.now.subtract(const Duration(minutes: 10));
    expect(onPage(dashFigure(fmt.fmtStamp(first))), findsOneWidget);
    expect(fmt.fmtStamp(first), isNot(contains(' · ')));
    // 20 on the first page: the last of the 25 rows is on page 2.
    expect(onPage('Teller 101'), findsOneWidget);
    expect(onPage('Omar Khaled'), findsNothing);
    expect(find.descendant(of: page, matching: find.byType(DashCheckbox)),
        findsNWidgets(21), reason: '20 rows + select all');
    await h.tap(find.bySemanticsLabel(h.t('common.next')).last);
    expect(onPage('Omar Khaled'), findsOneWidget);
  });

  testWidgets('ADM-REV-007 a plain flag says its reason; an unknown reason '
      'shows raw', (tester) async {
    final s = reviewServer();
    flagRows(s.db).rows.first['reason'] = 'brand_new_reason';
    final h = await pumpReview(tester, server: s.server, db: s.db);
    expect(onPage('brand_new_reason'), findsOneWidget);
    expect(onPage('Done offline before a permission change reached the till'),
        findsOneWidget); // Youssef
    expect(onPage("Correct PIN at a branch they don't work at"),
        findsOneWidget);
    expect(onPage('Done offline without the permission'), findsOneWidget);
  });

  testWidgets('ADM-REV-008 a staff-drink detail says what happened; another '
      'detail keeps the plain reason', (tester) async {
    final s = reviewServer();
    flagRows(s.db).rows.firstWhere((r) => r['id'] == 6)['capability'] =
        'orders.discount.preset:inactive';
    final h = await pumpReview(tester, server: s.server, db: s.db);
    expect(
      onPage('Staff drink: the till gave a different amount free than the '
          'server priced'),
      findsOneWidget,
    );
    expect(onPage(h.t('access.review.details.orders_staff_drink_record'
        '.overspent')), findsOneWidget);
    expect(onPage('orders.discount.preset:inactive'), findsOneWidget);
    expect(onPage('Done offline without the permission'), findsNWidgets(2));
    // No key leaks.
    expect(find.descendant(of: page, matching: find.textContaining(
        'access.review')), findsNothing);
    expect(find.descendant(of: page, matching: find.textContaining(
        'orders.staff_drink')), findsNothing);
  });

  testWidgets('ADM-REV-009 a known detail names its capability (key on '
      'hover); others show the raw key', (tester) async {
    await pumpReview(tester);
    expect(onPage('Record a staff drink'), findsNWidgets(2));
    expect(
      find.descendant(
        of: page,
        matching: find.byWidgetPredicate((w) =>
            w is Tooltip &&
            w.message == 'orders.staff_drink.record:comp_mismatch'),
      ),
      findsOneWidget,
    );
    expect(onPage('orders.void'), findsNWidgets(2));
    expect(onPage('pos:sign_in'), findsOneWidget);
  });

  testWidgets('ADM-REV-009 Arabic names the capability in Arabic', (
    tester,
  ) async {
    await pumpReview(tester, locale: 'ar');
    expect(onPage('تسجيل مشروب موظفين'), findsNWidgets(2));
    expect(
      onPage('مشروب موظفين: المبلغ المجاني الذي سجّله الكاشير يختلف عمّا '
          'حسبه الخادم'),
      findsOneWidget,
    );
  });

  testWidgets('ADM-REV-010 Reviewed pill on reviewed flags, Mark reviewed on '
      'open ones, spinner on that row only', (tester) async {
    final s = reviewServer();
    final gate = s.server.hold('POST', reviewRoute);
    final h = await pumpReview(tester, server: s.server, db: s.db);
    await h.tap(showReviewed);
    expect(onPage('Reviewed'), findsNWidgets(2));
    expect(mark(7), findsNothing);
    expect(mark(1), findsOneWidget);
    await h.tap(mark(1));
    expect(_button(tester, mark(1)).loading, isTrue);
    expect(_button(tester, mark(3)).loading, isFalse);
    expect(_button(tester, mark(3)).onPressed, isNotNull);
    gate.release();
    await h.settle();
  });

  testWidgets('ADM-REV-011 Mark reviewed: the row leaves the open list, no '
      'toast', (tester) async {
    final h = await pumpReview(tester);
    final before = flagReads(h).length;
    await h.tap(mark(1));
    expect(h.server.callsTo(reviewRoute).single.path, '/authz/flags/1/review');
    expect(flagReads(h).length, before + 1, reason: 'refetched');
    expect(onPage('Hana Mostafa'), findsNothing);
    expect(_toasts, findsNothing);
    expect(onPage('Unexpected server data for review_flag.'), findsNothing);
  });

  testWidgets('ADM-REV-011 a refused Mark reviewed toasts the words and '
      'keeps the row', (tester) async {
    final s = reviewServer();
    final denied = MockResponse.denied('approvals.review');
    s.server.fail('POST', reviewRoute, denied);
    final h = await pumpReview(tester, server: s.server, db: s.db);
    final before = flagReads(h).length;
    await h.tap(mark(1));
    await h.expectToast(shown(h, denied));
    expect(flagReads(h).length, before, reason: 'no refetch on failure');
    expect(onPage('Hana Mostafa'), findsOneWidget);
  });

  testWidgets('ADM-REV-012 a checkbox only on open flags, named "Select this '
      'action"', (tester) async {
    final h = await pumpReview(tester);
    await h.tap(showReviewed);
    expect(pick(1), findsOneWidget);
    expect(pick(7), findsNothing);
    expect(pick(8), findsNothing);
    expect(tester.widget<DashCheckbox>(pick(1)).semanticLabel,
        'Select this action');
    await h.tap(pick(1));
    expect(tester.widget<DashCheckbox>(pick(1)).value, isTrue);
  });

  testWidgets('ADM-REV-013 Select all shown takes every open flag, never a '
      'reviewed one; unticking clears', (tester) async {
    final h = await pumpReview(tester);
    await h.tap(showReviewed);
    expect(tester.widget<DashCheckbox>(selectAll).semanticLabel,
        'Select all shown');
    await h.tap(selectAll);
    expect(tester.widget<DashCheckbox>(selectAll).value, isTrue);
    expect(find.descendant(of: bulkBar, matching: find.text('6 selected')),
        findsOneWidget);
    await h.tap(pick(1));
    expect(tester.widget<DashCheckbox>(selectAll).value, isFalse);
    await h.tap(pick(1));
    expect(tester.widget<DashCheckbox>(selectAll).value, isTrue);
    await h.tap(selectAll);
    expect(bulkBar, findsNothing);
  });

  testWidgets('ADM-REV-013 Select all is disabled with no open flags', (
    tester,
  ) async {
    final s = reviewServer();
    flagRows(s.db).removeWhere((r) => r['reviewed_at'] == null);
    final h = await pumpReview(tester, server: s.server, db: s.db);
    await h.tap(showReviewed);
    expect(onPage('Farida Wael'), findsOneWidget);
    expect(tester.widget<DashCheckbox>(selectAll).enabled, isFalse);
  });

  testWidgets('ADM-REV-014 the bulk bar: count, note, Mark N reviewed, Clear',
      (tester) async {
    final h = await pumpReview(tester);
    expect(bulkBar, findsNothing);
    await h.tap(pick(1));
    await h.tap(pick(2));
    Finder inBar(String t) => find.descendant(of: bulkBar, matching: find.text(t));
    expect(inBar('2 selected'), findsOneWidget);
    expect(inBar('Mark 2 reviewed'), findsOneWidget);
    expect(tester.widget<DashTextInput>(bulkNote).placeholder,
        'Note (optional)');
    await h.tap(inBar('Clear'));
    expect(bulkBar, findsNothing);
    expect(tester.widget<DashCheckbox>(pick(1)).value, isFalse);
  });

  testWidgets('ADM-REV-014 Arabic: "تمييز 1 كمراجَع"', (tester) async {
    await pumpReview(tester, locale: 'ar');
    await tester.tap(pick(1));
    await tester.pumpAndSettle();
    expect(find.descendant(of: bulkResolve, matching: find.text('تمييز 1 كمراجَع')),
        findsOneWidget);
  });

  group('ADM-REV-015 bulk resolve', () {
    testWidgets('sends the picks and the trimmed note; success toast, cleared, '
        'refetched', (tester) async {
      final h = await pumpReview(tester);
      await h.tap(pick(1));
      await h.tap(pick(2));
      await h.enterText(bulkNote, '  checked with the manager ');
      final before = flagReads(h).length;
      await h.tap(bulkResolve);
      expect(h.server.callsTo(bulkRoute).single.body, {
        'flag_ids': [1, 2],
        'note': 'checked with the manager',
      });
      await h.expectToast('Resolved 2');
      expect(bulkBar, findsNothing);
      expect(flagReads(h).length, before + 1);
      expect(onPage('Hana Mostafa'), findsNothing);
      expect(onPage('Mariam Fathy'), findsNothing);
      // The note is gone with the selection.
      await h.tap(pick(3));
      expect(tester.widget<DashTextInput>(bulkNote).value, isEmpty);
    });

    testWidgets('no note: the field is absent', (tester) async {
      final h = await pumpReview(tester);
      await h.tap(selectAll);
      await h.tap(bulkResolve);
      expect(h.server.callsTo(bulkRoute).single.body, {
        'flag_ids': [1, 2, 3, 4, 5, 6],
      });
      await h.expectToast('Resolved 6');
    });

    testWidgets('a partial result names every refused id and why', (
      tester,
    ) async {
      final s = reviewServer();
      final h = await pumpReview(tester, server: s.server, db: s.db);
      await h.tap(pick(1));
      await h.tap(pick(2));
      flagRows(s.db).removeWhere((r) => r['id'] == 2); // gone meanwhile
      await h.tap(bulkResolve);
      expect(find.text('Resolved 1, 1 could not be resolved'), findsOneWidget);
      expect(find.text('#2: no such open flag in this org'), findsOneWidget);
      await h.flushTimers();
      expect(bulkBar, findsNothing);
    });

    testWidgets('(divergence) Arabic: the refused reason is not the server '
        'English', (tester) async {
      final s = reviewServer();
      final h = await pumpReview(tester, server: s.server, db: s.db,
          locale: 'ar');
      await h.tap(pick(2));
      flagRows(s.db).removeWhere((r) => r['id'] == 2);
      await h.tap(bulkResolve);
      expect(find.text('#2: ${h.t('access.review.pendingNotOpen')}'),
          findsOneWidget);
      await h.flushTimers();
    });

    testWidgets('a failed call toasts the words and keeps the picks', (
      tester,
    ) async {
      final s = reviewServer();
      final boom = MockResponse.error(500, 'boom');
      s.server.fail('POST', bulkRoute, boom);
      final h = await pumpReview(tester, server: s.server, db: s.db);
      await h.tap(pick(1));
      await h.tap(bulkResolve);
      await h.expectToast(shown(h, boom), keep: true);
      expect(bulkBar, findsOneWidget);
      await h.flushTimers();
    });
  });

  group('ADM-REV-016 states', () {
    testWidgets('empty: shield and the hint', (tester) async {
      final s = reviewServer();
      flagRows(s.db).removeWhere((r) => r['reviewed_at'] == null);
      final h = await pumpReview(tester, server: s.server, db: s.db);
      expect(onPage('Nothing to review'), findsOneWidget);
      expect(onPage(h.t('access.review.emptyHint')), findsOneWidget);
    });

    testWidgets('loading: a skeleton, never the empty words', (tester) async {
      final s = reviewServer();
      final gate = s.server.hold('GET', flagsRoute);
      final h = await pumpReview(tester, server: s.server, db: s.db);
      expect(find.descendant(of: page, matching: find.byType(DashSkeleton)),
          findsWidgets);
      expect(onPage('Nothing to review'), findsNothing);
      gate.release();
      await h.settle();
      expect(onPage('Hana Mostafa'), findsOneWidget);
    });

    testWidgets('error: the words and a Retry that asks only this read', (
      tester,
    ) async {
      final s = reviewServer();
      final boom = MockResponse.error(500, 'boom');
      s.server.fail('GET', flagsRoute, boom);
      final h = await pumpReview(tester, server: s.server, db: s.db);
      expect(onPage(shown(h, boom)), findsOneWidget);
      expect(onPage('Nothing to review'), findsNothing);
      final others = h.server.calls.length - flagReads(h).length;
      await h.tap(onPage('Retry'));
      expect(onPage('Hana Mostafa'), findsOneWidget);
      expect(h.server.calls.length - flagReads(h).length, others);
    });

    testWidgets('phone: cards without checkboxes, Mark reviewed kept', (
      tester,
    ) async {
      await pumpReview(tester, size: DashSize.phone);
      expect(onPage('Hana Mostafa'), findsOneWidget);
      expect(pick(1), findsNothing);
      expect(selectAll, findsNothing);
      expect(mark(1), findsOneWidget);
    });
  });

  group('ADM-REV-017 selection details', () {
    testWidgets('picks survive Show reviewed', (tester) async {
      final h = await pumpReview(tester);
      await h.tap(pick(1));
      await h.tap(showReviewed);
      expect(tester.widget<DashCheckbox>(pick(1)).value, isTrue);
      expect(find.descendant(of: bulkBar, matching: find.text('1 selected')),
          findsOneWidget);
    });

    testWidgets('Select all takes every page; picks survive paging', (
      tester,
    ) async {
      final s = reviewServer();
      addFlags(s.db, 19); // 25 open over two pages
      final h = await pumpReview(tester, server: s.server, db: s.db);
      await h.tap(selectAll);
      expect(find.descendant(of: bulkBar, matching: find.text('25 selected')),
          findsOneWidget);
      await h.tap(find.bySemanticsLabel(h.t('common.next')).last);
      expect(tester.widget<DashCheckbox>(pick(6)).value, isTrue);
      await h.tap(pick(6));
      await h.tap(find.bySemanticsLabel(h.t('common.previous')).last);
      expect(find.descendant(of: bulkBar, matching: find.text('24 selected')),
          findsOneWidget);
    });

    testWidgets('the count keeps only picks still open; a single Mark '
        'reviewed shows no toast', (tester) async {
      final h = await pumpReview(tester);
      await h.tap(pick(1));
      await h.tap(pick(2));
      await h.tap(mark(1));
      expect(_toasts, findsNothing);
      expect(find.descendant(of: bulkBar, matching: find.text('1 selected')),
          findsOneWidget);
      await h.tap(bulkResolve);
      expect(h.server.callsTo(bulkRoute).single.body, {
        'flag_ids': [2],
      });
      await h.flushTimers();
    });
  });

  testWidgets('intent: resting on Show reviewed warms that list; pressing '
      'asks nothing more', (tester) async {
    final h = await pumpReview(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    bool all(MockCall c) => c.query.containsKey('include_reviewed');
    expect(flagReads(h).where(all), isEmpty);
    await mouse.moveTo(tester.getCenter(showReviewed));
    await h.settle();
    expect(flagReads(h).where(all), hasLength(1), reason: 'warmed');
    await h.tap(showReviewed);
    expect(flagReads(h).where(all), hasLength(1), reason: 'from the cache');
    expect(onPage('Farida Wael'), findsOneWidget);
    expect(h.container.exists(reviewFlagsProvider(true)), isTrue);
  });
}

/// Every toast on screen.
Finder get _toasts =>
    find.byWidgetPredicate((w) => w.runtimeType.toString() == '_ToastCard');
