// The owner's rule (2026-10-11): a report's tab and filters carry through
// navigation — away to another page and back, they are as they were
// (`DashListMemory`, `DashRememberedState`).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../financial/support.dart' as fin;
import 'support.dart';

void main() {
  testWidgets('Operations: the tab comes back from another page', (
    tester,
  ) async {
    final h = await pumpOps(tester, branchId: SeedIds.heliopolis);
    await openTab(h, 'Tellers');
    expect(
      inPage(find.byKey(const ValueKey('ops-tellers-table'))),
      findsOneWidget,
    );
    await h.go('/reports/financial');
    await h.go(opsPath);
    expect(
      inPage(find.byKey(const ValueKey('ops-tellers-table'))),
      findsOneWidget,
    );
  });

  testWidgets('Operations › Tables: the section filter comes back; another '
      'branch drops it', (tester) async {
    final h = await pumpOps(tester, branchId: SeedIds.heliopolis);
    final select = inPage(find.byKey(const ValueKey('ops-section-filter')));
    await pickOption(h, select, 'Terrace');
    await h.go('/reports/loyalty');
    await h.go(opsPath);
    expect(
      tester
          .widget<DashSelect<String>>(
            inPage(find.byKey(const ValueKey('ops-section-filter'))),
          )
          .value,
      'Terrace',
    );
    await h.go('/reports/loyalty');
    await h.container.read(scopeProvider.notifier).setBranch(SeedIds.maadi);
    await h.settle();
    expect(
      h.container
          .read(dashListMemoryProvider)
          .recall('reports.operations.tables')
          .sameBranch,
      isFalse,
    );
  });

  testWidgets('Financial › Profitability: the class filter and flagged-only '
      'come back from another page', (tester) async {
    final h = await fin.pumpFin(tester);
    await h.tap(find.byKey(const ValueKey('fin-flagged-only')));
    await h.tap(find.byKey(const ValueKey('fin-class-filter')));
    await h.tap(
      find.descendant(
        of: find.byType(DashOptionList<String>),
        matching: find.text('Star'),
      ),
    );
    await h.go(opsPath);
    await h.go(fin.finPath);
    expect(
      tester
          .widget<DashSelect<String>>(
            find.byKey(const ValueKey('fin-class-filter')),
          )
          .value,
      'star',
    );
    expect(
      tester
          .widget<DashSwitch>(find.byKey(const ValueKey('fin-flagged-only')))
          .value,
      isTrue,
    );
  });
}
