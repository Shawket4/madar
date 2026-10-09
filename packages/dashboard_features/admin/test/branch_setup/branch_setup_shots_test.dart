// The Branch setup screenshots (SPEC 6.2): the default state at phone /
// tablet / desktop in English light and Arabic dark, and every dialog,
// menu and state at desktop-en-light and phone-ar-light. Written only with
// FDASH_SHOTS set; each also checks the state it pictures.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _matrix = [
  (DashSize.phone, 'en', false),
  (DashSize.tablet, 'en', false),
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', true),
  (DashSize.tablet, 'ar', true),
  (DashSize.desktop, 'ar', true),
];

const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

String _name(DashSize s, String l, bool d) =>
    '${s.name}-$l-${d ? 'dark' : 'light'}';

Future<void> _scrollTo(DashHarness h, Finder f) async {
  await h.tester.ensureVisible(f.first);
  await h.settle();
}

void main() {
  for (final (size, lang, dark) in _matrix) {
    testWidgets('default ${_name(size, lang, dark)}', (tester) async {
      final h = await pumpBuilder(
        tester,
        branchId: SeedIds.heliopolis,
        size: size,
        locale: lang,
        dark: dark,
      );
      expect(find.byKey(const ValueKey('bb-canvas')), findsOneWidget);
      await h.shot('branch-setup/default');
      await _scrollTo(h, find.byKey(const ValueKey('bb-inspector')));
      await h.shot('branch-setup/default-summary');
    });
  }

  for (final (size, lang, dark) in _states) {
    final n = _name(size, lang, dark);

    testWidgets('editing a section $n', (tester) async {
      final h = await pumpBuilder(
        tester,
        branchId: SeedIds.zamalek,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(find.byKey(const ValueKey('bb-lock')));
      final bar = cardTitled(lang == 'ar' ? 'Bar' : 'Bar');
      await h.tap(bar);
      expect(find.byKey(const ValueKey('bb-toolbar')), findsOneWidget);
      await h.shot('branch-setup/section-selected');
      await _scrollTo(h, find.byKey(const ValueKey('bb-select-all')));
      await h.shot('branch-setup/section-inspector');
    });

    testWidgets('a device and its setup code $n', (tester) async {
      final h = await pumpBuilder(
        tester,
        branchId: SeedIds.heliopolis,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(cardTitled('Counter 1'));
      await _scrollTo(h, find.byKey(const ValueKey('bb-get-code')));
      await h.tap(find.byKey(const ValueKey('bb-get-code')));
      expect(find.byKey(const ValueKey('bb-slot-code')), findsOneWidget);
      await h.shot('branch-setup/device-code');
    });

    testWidgets('a printer $n', (tester) async {
      final h = await pumpBuilder(
        tester,
        branchId: SeedIds.heliopolis,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(find.byKey(const ValueKey('bb-lock')));
      await h.tap(
        cardTitled(lang == 'ar' ? 'طابعة الإيصالات' : 'Receipt printer'),
      );
      await _scrollTo(h, find.byKey(const ValueKey('bb-paper')));
      await h.shot('branch-setup/printer');
    });

    testWidgets('the setup picker $n', (tester) async {
      final b = PlanBackend();
      b.db['branches'].find(SeedIds.maadi)!['printer_ip'] = null;
      b.db['devices'].removeWhere((d) => d['branch_id'] == SeedIds.maadi);
      final h = await pumpBuilder(
        tester,
        branchId: SeedIds.maadi,
        size: size,
        locale: lang,
        dark: dark,
        backend: b,
      );
      expect(find.byKey(const ValueKey('bb-setup-till')), findsOneWidget);
      await h.shot('branch-setup/picker');
    });

    testWidgets('the add menu and history menu $n', (tester) async {
      final h = await pumpBuilder(
        tester,
        branchId: SeedIds.heliopolis,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(find.byKey(const ValueKey('bb-history')));
      expect(find.byKey(const ValueKey('bb-history-menu')), findsOneWidget);
      await h.shot('branch-setup/history-menu');
      await h.tap(find.byKey(const ValueKey('bb-version-1')));
      await h.tap(find.byKey(const ValueKey('bb-add')));
      await h.shot('branch-setup/add-menu');
    });

    testWidgets('the review dialog $n', (tester) async {
      final h = await pumpBuilder(
        tester,
        branchId: SeedIds.zamalek,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(find.byKey(const ValueKey('bb-lock')));
      await h.tap(cardTitled('Counter 2'));
      await _scrollTo(h, find.byKey(const ValueKey('bb-remove')));
      await h.tap(find.byKey(const ValueKey('bb-remove')));
      await h.tap(find.byKey(const ValueKey('bb-save')));
      expect(find.byKey(const ValueKey('bb-review-save')), findsOneWidget);
      await h.shot('branch-setup/review');
    });

    testWidgets('loading $n', (tester) async {
      final b = PlanBackend();
      final gate = b.server.hold('GET', BranchPlanRoutes.plan);
      final h = await pumpBuilder(
        tester,
        branchId: SeedIds.heliopolis,
        size: size,
        locale: lang,
        dark: dark,
        backend: b,
      );
      expect(find.byKey(const ValueKey('bb-skeleton')), findsOneWidget);
      await h.shot('branch-setup/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed $n', (tester) async {
      final b = PlanBackend();
      b.server.fail(
        'GET',
        BranchPlanRoutes.plan,
        MockResponse.error(500, 'Database error: boom'),
      );
      final h = await pumpBuilder(
        tester,
        branchId: SeedIds.heliopolis,
        size: size,
        locale: lang,
        dark: dark,
        backend: b,
      );
      expect(find.byKey(const ValueKey('bb-error')), findsOneWidget);
      await h.shot('branch-setup/failed');
    });
  }
}
