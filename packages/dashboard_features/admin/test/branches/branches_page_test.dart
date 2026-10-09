// `/branches` driven tests (ADM-BRA-001..019, 039): the list, its stats,
// columns, search, export, delete and the `?edit` deep links, through the
// real shell on the mock server.
import 'dart:convert';

import 'package:dashboard_admin/src/branches/branch_dialog.dart';
import 'package:dashboard_admin/src/branches/branches_page.dart';
import 'package:dashboard_api/dashboard_api.dart' show BranchKind;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show ScopePrefKeys;
import 'package:dashboard_core/shell.dart' show DashSidebar;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder _inPage(Finder f) =>
    find.descendant(of: find.byType(BranchesPage), matching: f);

Finder _pageText(String s) => _inPage(find.text(s));

List<MockCall> _lists(DashHarness h) =>
    h.server.callsTo(listRoute, method: 'GET');

void main() {
  testWidgets('ADM-BRA-001 the sidebar offers Branches', (tester) async {
    final h = await pumpBranches(tester);
    expect(
      find.descendant(
        of: find.byType(DashSidebar),
        matching: find.text('Branches'),
      ),
      findsWidgets,
    );
    expect(h.location.path, branchesPath);
  });

  testWidgets('ADM-BRA-002 a platform admin with no shop picked: "Select an '
      'organization", nothing fetched', (tester) async {
    final h = await pumpBranches(tester, persona: Persona.platform);
    expect(_pageText('Branches'), findsWidgets);
    expect(_pageText('Select an organization'), findsOneWidget);
    expect(
      _pageText(
        'Choose an organization from the sidebar to view and manage its '
        'branches.',
      ),
      findsOneWidget,
    );
    expect(_lists(h), isEmpty);
    expect(_inPage(find.byType(DashDataTable<Never>)), findsNothing);
  });

  testWidgets('ADM-BRA-003 the header: title, subtitle, Export, New '
      'warehouse (outline) and New', (tester) async {
    await pumpBranches(tester);
    expect(_pageText('Branches'), findsWidgets);
    expect(
      _pageText('Manage your branch locations and printer config'),
      findsOneWidget,
    );
    expect(_pageText('Export Excel'), findsOneWidget);
    final warehouse = button(tester, 'New warehouse');
    expect(warehouse.variant, DashButtonVariant.outline);
    expect(warehouse.icon, 'warehouse');
    expect(button(tester, 'New').icon, 'plus');
  });

  testWidgets('ADM-BRA-004/039 one unpaginated read with the warehouses, '
      'inactive included', (tester) async {
    final s = branchesServer();
    addLocation(s.db);
    addLocation(s.db, name: 'Dokki Kiosk', kind: 'branch', active: false);
    final h = await pumpBranches(tester, server: s.server, db: s.db);
    // The page reads the scope bar's own list (core's branchesProvider):
    // one request between them.
    final calls = _lists(h);
    expect(calls, hasLength(1));
    for (final c in calls) {
      expect(c.query, {
        'org_id': [SeedIds.sabahOrg],
        'include_warehouses': ['true'],
      });
    }
    expect(_pageText('Obour Warehouse'), findsOneWidget);
    expect(_pageText('Dokki Kiosk'), findsOneWidget);
  });

  testWidgets('ADM-BRA-005 the stats: Total, Active, Warehouses, Inactive', (
    tester,
  ) async {
    final s = branchesServer();
    addLocation(s.db);
    addLocation(s.db, name: 'Dokki Kiosk', kind: 'branch', active: false);
    await pumpBranches(tester, server: s.server, db: s.db);
    expect(stat(tester, 'Total').value, 6);
    expect(stat(tester, 'Active').value, 5);
    expect(stat(tester, 'Warehouses').value, 1);
    expect(stat(tester, 'Inactive').value, 1);
    expect(
      find.byWidgetPredicate(
        (w) => w is DashStatCard && w.label == 'With Printer',
      ),
      findsNothing,
    );
  });

  testWidgets('ADM-BRA-006 the Name column: a branch tile, the address with a '
      'pin; a warehouse tile and its pill', (tester) async {
    final s = branchesServer();
    addLocation(s.db);
    await pumpBranches(tester, server: s.server, db: s.db);
    final zamalek = rowOf('Zamalek');
    final address = branchNamed(s.db, 'Zamalek')['address']! as String;
    expect(
      find.descendant(of: zamalek, matching: find.text(address)),
      findsOneWidget,
    );
    bool hasIcon(Finder row, String name) => find
        .descendant(
          of: row,
          matching: find.byWidgetPredicate((w) => w is DashIcon && w.name == name),
        )
        .evaluate()
        .isNotEmpty;
    expect(hasIcon(zamalek, 'git-branch'), isTrue);
    expect(hasIcon(zamalek, 'map-pin'), isTrue);
    final obour = rowOf('Obour Warehouse');
    expect(hasIcon(obour, 'warehouse'), isTrue);
    final pill = tester.widget<DashStatusPill>(
      find.descendant(of: obour, matching: find.byType(DashStatusPill)).first,
    );
    expect(pill.label, 'Warehouse');
    expect(pill.tone, DashTone.info);
    expect(
      find.descendant(of: zamalek, matching: find.text('Warehouse')),
      findsNothing,
    );
  });

  testWidgets('ADM-BRA-007/008/009 Phone (LTR or —), Printer (brand, ip:port '
      'or "No printer") and Status', (tester) async {
    final s = branchesServer();
    addLocation(s.db, active: false);
    await pumpBranches(tester, server: s.server, db: s.db);
    final zamalek = rowOf('Zamalek');
    final phone = branchNamed(s.db, 'Zamalek')['phone']! as String;
    final phoneText = tester.widget<Text>(
      find.descendant(of: zamalek, matching: find.text(phone)),
    );
    expect(phoneText.textDirection, TextDirection.ltr);
    expect(
      find.descendant(of: zamalek, matching: find.text('Epson')),
      findsOneWidget,
    );
    final ip = branchNamed(s.db, 'Zamalek')['printer_ip'];
    expect(
      find.descendant(of: zamalek, matching: find.text('$ip:9100')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: zamalek, matching: find.text('Active')),
      findsOneWidget,
    );
    final obour = rowOf('Obour Warehouse');
    expect(
      find.descendant(of: obour, matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: obour, matching: find.text('No printer')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: obour, matching: find.text('Inactive')),
      findsOneWidget,
    );
  });

  testWidgets('ADM-BRA-010 search reads the name, the phone and the printer '
      'brand, never the address', (tester) async {
    final s = branchesServer();
    final h = await pumpBranches(tester, server: s.server, db: s.db);
    final search = find.byType(DashSearchInput);
    await h.enterText(search, 'zama');
    expect(rowOf('Zamalek'), findsOneWidget);
    expect(rowOf('Maadi'), findsNothing);
    final phone = branchNamed(s.db, 'Maadi')['phone']! as String;
    await h.enterText(search, phone.substring(phone.length - 4));
    expect(rowOf('Maadi'), findsOneWidget);
    expect(rowOf('Zamalek'), findsNothing);
    await h.enterText(search, 'epson');
    expect(rowOf('Heliopolis'), findsOneWidget);
    expect(rowOf('Zamalek'), findsOneWidget);
    final address = branchNamed(s.db, 'Zamalek')['address']! as String;
    await h.enterText(search, address.split(',').first);
    expect(rowOf('Zamalek'), findsNothing);
  });

  testWidgets('ADM-BRA-011 the Columns menu, ten rows a page', (tester) async {
    final s = branchesServer();
    for (var i = 1; i <= 8; i++) {
      addLocation(s.db, name: 'Kiosk Number $i', kind: 'branch');
    }
    final h = await pumpBranches(tester, server: s.server, db: s.db);
    final table = tester.widget<DashDataTable<Object?>>(
      _inPage(find.byWidgetPredicate((w) => w is DashDataTable)),
    );
    expect(table.pageSize, 10);
    expect(
      [for (final c in table.columns) c.label],
      ['Name', 'Phone', 'Printer', 'Status'],
    );
    expect(_inPage(find.textContaining('Page 1')), findsOneWidget);
    await h.tapText('Columns');
    expect(find.text('Printer').hitTestable(), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
  });

  testWidgets('ADM-BRA-011 the phone layout: one card per branch', (
    tester,
  ) async {
    await pumpBranches(tester, size: DashSize.phone);
    expect(_pageText('Zamalek'), findsOneWidget);
    expect(_pageText('Heliopolis'), findsOneWidget);
    expect(_inPage(find.text('New warehouse')), findsOneWidget);
  });

  testWidgets('ADM-BRA-011 loading: skeletons, never the empty words', (
    tester,
  ) async {
    final s = branchesServer();
    final gate = s.server.hold('GET', listRoute);
    final h = await pumpBranches(tester, server: s.server, db: s.db);
    expect(_pageText('Branches you add appear here'), findsNothing);
    expect(stat(tester, 'Total').loading, isTrue);
    expect(
      tester
          .widget<DashDataTable<Object?>>(
            _inPage(find.byWidgetPredicate((w) => w is DashDataTable)),
          )
          .loading,
      isTrue,
    );
    gate.release();
    await h.settle();
    expect(stat(tester, 'Total').loading, isFalse);
    expect(_pageText('Zamalek'), findsOneWidget);
  });

  testWidgets('ADM-BRA-012 a failed read: the error and Retry, which asks '
      'again', (tester) async {
    final s = branchesServer();
    // The one read the page and the scope bar share fails.
    s.server.fail('GET', listRoute, MockResponse.error(500, 'boom'));
    final h = await pumpBranches(tester, server: s.server, db: s.db);
    expect(_pageText('Retry'), findsOneWidget);
    expect(_pageText('Branches you add appear here'), findsNothing);
    final before = _lists(h).length;
    await h.tap(_pageText('Retry'));
    expect(_lists(h), hasLength(before + 1), reason: 'only its own read');
    expect(_pageText('Zamalek'), findsOneWidget);
  });

  testWidgets('ADM-BRA-009/012 branch.settings_changed asks for the list '
      'again and shows the new value', (tester) async {
    final s = branchesServer();
    // The realtime stream follows the picked branch.
    final h = await pumpBranches(
      tester,
      server: s.server,
      db: s.db,
      prefs: {
        ScopePrefKeys.branch: jsonEncode({
          'org': SeedIds.sabahOrg,
          'branch': SeedIds.maadi,
        }),
      },
    );
    final before = _lists(h).length;
    branchRow(s.db, SeedIds.zamalek)['name'] = 'Zamalek Nile';
    h.realtime.current!.emit('branch.settings_changed', data: '{}');
    await h.settle();
    expect(_lists(h), hasLength(before + 1));
    expect(_pageText('Zamalek Nile'), findsOneWidget);
    expect(_pageText('Zamalek'), findsNothing);
  });

  testWidgets('ADM-BRA-013 empty: "Branches you add appear here"; Export '
      'off', (tester) async {
    final s = branchesServer();
    s.db['branches'].removeWhere((r) => r['org_id'] == SeedIds.sabahOrg);
    await pumpBranches(tester, server: s.server, db: s.db);
    expect(_pageText('Branches you add appear here'), findsOneWidget);
    expect(
      tester.widget<DashExportButton>(find.byType(DashExportButton)).enabled,
      isFalse,
    );
  });

  testWidgets('ADM-BRA-014 a row, Enter and the Edit action open the editor '
      '(?edit=<id>)', (tester) async {
    final h = await pumpBranches(tester);
    await h.tap(rowOf('Zamalek'));
    expect(h.location.queryParameters['edit'], SeedIds.zamalek);
    expect(find.text('Edit Branch'), findsOneWidget);
    await h.tapText('Cancel');
    expect(h.location.queryParameters.containsKey('edit'), isFalse);
    await h.tap(
      labelled('Edit', within: rowOf('Maadi')).first,
    );
    expect(h.location.queryParameters['edit'], SeedIds.maadi);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(h.location.queryParameters.containsKey('edit'), isFalse);
    // Keyboard: focus the row, Enter.
    Focus.of(tester.element(_pageText('Heliopolis'))).requestFocus();
    await h.settle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await h.settle();
    expect(h.location.queryParameters['edit'], isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
  });

  testWidgets('ADM-BRA-015/016 Delete: the confirm, then the branch is gone, '
      'the list asked again, "Branch deleted"', (tester) async {
    final s = branchesServer();
    final row = addLocation(s.db);
    final h = await pumpBranches(tester, server: s.server, db: s.db);
    await h.tap(labelled('Delete', within: rowOf('Obour Warehouse')).first);
    expect(inConfirm('Delete Obour Warehouse?'), findsOneWidget);
    expect(
      inConfirm(
        'Its tills, printer settings and stock levels go with it. Past '
        'orders stay in reports.',
      ),
      findsOneWidget,
    );
    final before = _lists(h).length;
    await h.tap(inConfirm('Delete'));
    expect(
      h.server.callsTo(itemRoute, method: 'DELETE').single.path,
      '/branches/${row['id']}',
    );
    await h.expectToast('Branch deleted');
    expect(_lists(h).length, greaterThan(before), reason: '/branches asked');
    expect(rowOf('Obour Warehouse'), findsNothing);
  });

  testWidgets('ADM-BRA-016 a refused delete: the server\'s sentence, the '
      'branch stays', (tester) async {
    final s = branchesServer();
    final refusal = MockResponse.conflict(
      'This branch still has 1 open shift. Close or clear them first — or '
      'switch the branch off instead, which keeps its history and stops it '
      'being used.',
    );
    s.server.fail('DELETE', itemRoute, refusal);
    final h = await pumpBranches(tester, server: s.server, db: s.db);
    await h.tap(labelled('Delete', within: rowOf('Zamalek')).first);
    await h.tap(inConfirm('Delete'));
    await h.expectToast(
      h.refusalWords(refusal).replaceFirst('Conflict: ', ''),
    );
    expect(rowOf('Zamalek'), findsOneWidget);
  });

  testWidgets('ADM-BRA-017 a person who may only read: New, Edit and Delete '
      'show, the server refuses with "You don\'t have permission"', (
    tester,
  ) async {
    final h = await pumpBranches(tester, persona: Persona.limited);
    expect(rowOf('Maadi'), findsOneWidget);
    expect(rowOf('Zamalek'), findsNothing, reason: 'only her own branch');
    expect(button(tester, 'New').onPressed, isNotNull);
    await h.tap(labelled('Delete', within: rowOf('Maadi')).first);
    await h.tap(inConfirm('Delete'));
    await h.expectToast(h.t('errors.unauthorized'));
    await h.tap(rowOf('Maadi'));
    await h.tapKey(const ValueKey('branch-submit'));
    await h.expectToast(h.t('errors.unauthorized'));
    expect(find.text('Edit Branch'), findsOneWidget, reason: 'stays open');
  });

  testWidgets('ADM-BRA-018 Export: one sheet, six columns, every branch, the '
      'engine\'s toasts', (tester) async {
    final s = branchesServer();
    addLocation(s.db);
    branchNamed(s.db, 'Obour Warehouse')['printer_brand'] = 'star';
    final h = await pumpBranches(tester, server: s.server, db: s.db);
    await h.enterText(find.byType(DashSearchInput), 'zama');
    await h.tapText('Export Excel');
    await h.expectToast('Exported 5 rows');
    final sheet = h.exports.built.single.sheets.single;
    expect(sheet.name, 'Branches');
    expect(sheet.title, 'Branches');
    expect(
      [for (final c in sheet.columns) c.header],
      ['Name', 'Address', 'Phone', 'Timezone', 'Printer', 'Status'],
    );
    expect([for (final c in sheet.columns) c.width], [28, 32, 18, 18, 26, 12]);
    final obour = sheet.rows.firstWhere((r) => r.first == 'Obour Warehouse');
    expect(obour, [
      'Obour Warehouse',
      'Industrial Zone A, Obour City',
      '—',
      'Africa/Cairo',
      'star @ :',
      'Active',
    ]);
    final zamalek = branchNamed(s.db, 'Zamalek');
    expect(
      sheet.rows.firstWhere((r) => r.first == 'Zamalek')[4],
      'epson @ ${zamalek['printer_ip']}:9100',
    );
    expect(
      h.files.saved.single.filename,
      matches(RegExp(r'^Madar-Branches-\d{4}-\d{2}-\d{2}\.xlsx$')),
    );
  });

  testWidgets('ADM-BRA-018 a failed export: "Export failed"', (tester) async {
    final h = await pumpBranches(tester);
    h.exports.failNext = StateError('disk full');
    await h.tapText('Export Excel');
    await h.expectToast(h.t('excel.failed'));
  });

  group('ADM-BRA-019 the ?edit deep links', () {
    testWidgets('New → ?edit=new, a Branch', (tester) async {
      final h = await pumpBranches(tester);
      await h.tapKey(const ValueKey('branches-new'));
      expect(h.location.queryParameters['edit'], 'new');
      expect(find.text('New Branch'), findsOneWidget);
      expect(
        tester.widget<BranchDialog>(find.byType(BranchDialog)).kind,
        BranchKind.branch,
      );
      await h.tapText('Cancel');
      expect(h.location.queryParameters.containsKey('edit'), isFalse);
    });

    testWidgets('New warehouse → ?edit=new-warehouse, a Warehouse', (
      tester,
    ) async {
      final h = await pumpBranches(tester);
      await h.tapKey(const ValueKey('branches-new-warehouse'));
      expect(h.location.queryParameters['edit'], 'new-warehouse');
      expect(find.text('New warehouse'), findsWidgets);
      expect(find.text('Warehouse name'), findsOneWidget);
      await h.tapText('Cancel');
      expect(h.location.queryParameters.containsKey('edit'), isFalse);
    });

    testWidgets('a link to a branch opens it once the list is in; an unknown '
        'id opens nothing', (tester) async {
      final s = branchesServer();
      final gate = s.server.hold('GET', listRoute);
      final h = await pumpBranches(
        tester,
        path: '$branchesPath?edit=${SeedIds.maadi}',
        server: s.server,
        db: s.db,
      );
      expect(find.byType(BranchDialog), findsNothing);
      gate.release();
      await h.settle();
      expect(find.text('Edit Branch'), findsOneWidget);
      expect(fieldText(tester, 'branch-name'), 'Maadi');
      await h.tapText('Cancel');
      await h.go('$branchesPath?edit=nope');
      expect(find.byType(BranchDialog), findsNothing);
    });
  });
}
