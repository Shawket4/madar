// Set-up's dialogs (TEAM-SET-036…038) and the set-up nav leaf (TEAM-ALL-003,
// 004), plus the refresh-failure rule for its one read outside `/staff`
// (TEAM-ALL-022), driven through the real shell on the mock server.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashCommandPalette, DashSidebar;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/employees/add_employee_dialog.dart';
import 'package:dashboard_team/src/employees/import_people_dialog.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'setup_support.dart';

/// The open dialog / sheet.
Finder _inSurface(Finder f) =>
    find.descendant(of: find.byType(DashSurface).last, matching: f);

Finder _surfaceText(String s) => _inSurface(find.text(s));

Finder _inSidebar(String s) =>
    find.descendant(of: find.byType(DashSidebar), matching: find.text(s));

List<Map<String, Object?>> _posts(DashHarness h) => [
  for (final c in h.server.callsTo('/staff/employees', method: 'POST'))
    (c.body! as Map).cast<String, Object?>(),
];

String _progress(DashHarness h, int n) =>
    h.t('dawam.setupProgress', args: {'n': n, 'total': 4});

Future<void> _openPalette(WidgetTester tester, DashHarness h) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await h.settle();
}

void main() {
  // ── Step 2's dialogs ─────────────────────────────────────────────────

  testWidgets('TEAM-SET-036 "Add employee" opens the Employees dialog over '
      'the step; a create ticks the step and the count live', (tester) async {
    final h = await pumpSetup(tester, edit: noActivePeople);
    // Nobody active: the page opens on step 2's empty state.
    expect(byKey('setup-no-people'), findsOneWidget);
    expect(find.text(_progress(h, 3)), findsOneWidget);
    final reads = h.server.callsTo('/staff/employees', method: 'GET').length;

    await h.tapKey(const ValueKey('setup-add-employee'));
    expect(find.byType(AddEmployeeDialog), findsOneWidget);
    await h.shot('add-employee');
    await h.tap(_surfaceText('Records only').hitTestable());
    await h.enterText(
      _inSurface(find.widgetWithText(DashTextField, 'Name')).first,
      'Rania Adel',
    );
    await h.tap(_inSurface(find.widgetWithText(DashCheckChip, 'Maadi')));
    await h.tap(_inSurface(find.widgetWithText(DashButton, 'Add employee')));

    expect(_posts(h).single['name'], 'Rania Adel');
    await h.expectToast(h.t('dawam.employeeAddedNoApp'));
    expect(find.byType(AddEmployeeDialog), findsNothing);
    // `/staff` invalidated: the checklist asked again and the step ticked.
    expect(
      h.server.callsTo('/staff/employees', method: 'GET').length,
      greaterThan(reads),
    );
    expect(find.text(_progress(h, 4)), findsOneWidget);
    expect(byKey('setup-complete'), findsOneWidget);
    // Back on the same step, now listing the person.
    expect(byKey('setup-body-employees'), findsOneWidget);
    expect(
      find.text(h.t('dawam.setupEmployeeCount', count: 1)),
      findsOneWidget,
    );
    expect(find.text('Rania Adel'), findsOneWidget);
  });

  testWidgets('TEAM-SET-036 closing the dialog returns to the step and sends '
      'nothing', (tester) async {
    final h = await pumpSetup(tester, edit: noActivePeople);
    await h.tapKey(const ValueKey('setup-add-employee'));
    await h.tap(_inSurface(find.widgetWithText(DashButton, 'Cancel')));
    expect(find.byType(AddEmployeeDialog), findsNothing);
    expect(_posts(h), isEmpty);
    expect(byKey('setup-no-people'), findsOneWidget);
  });

  testWidgets('TEAM-SET-036 phone: the dialog is a centred card', (
    tester,
  ) async {
    final h = await pumpSetup(
      tester,
      edit: noActivePeople,
      size: DashSize.phone,
      locale: 'ar',
    );
    await h.tapKey(const ValueKey('setup-add-employee'));
    expect(find.byType(AddEmployeeDialog), findsOneWidget);
    expectPhoneDialog(
      tester,
      primary: h.t('dawam.addEmployee'),
      secondary: h.t('common.cancel'),
    );
    await h.shot('add-employee');
  });

  testWidgets('TEAM-SET-037 "Import from a spreadsheet" opens the import '
      'dialog; its creates tick the step', (tester) async {
    final h = await pumpSetup(tester, edit: noActivePeople);
    await h.tapKey(const ValueKey('setup-import-people'));
    expect(find.byType(ImportPeopleDialog), findsOneWidget);
    await h.shot('import-people');
    h.files.fileQueue.add(
      PickedFile(
        name: 'people.csv',
        bytes: utf8.encode(
          'Name,WhatsApp,Branch\r\n'
          'Yara Nabil,01001114444,Maadi\r\n'
          'Sara Lotfy,01001234567,Zamalek\r\n',
        ),
      ),
    );
    await h.tap(_surfaceText(h.t('teamEmployees.chooseFile')));
    await h.tap(_surfaceText('Add 2'));
    expect(
      [for (final p in _posts(h)) p['name']],
      ['Yara Nabil', 'Sara Lotfy'],
    );
    await h.flushTimers();
    await h.tap(_inSurface(find.widgetWithText(DashButton, 'Close')).first);
    expect(find.byType(ImportPeopleDialog), findsNothing);
    expect(find.text(_progress(h, 4)), findsOneWidget);
    expect(
      find.text(h.t('dawam.setupEmployeeCount', count: 2)),
      findsOneWidget,
    );
  });

  testWidgets('TEAM-SET-036 a refused create keeps the dialog and the '
      'checklist as they were', (tester) async {
    final h = await pumpSetup(tester, edit: noActivePeople);
    final refused = MockResponse.unprocessable(
      'A name is needed',
      code: 'NAME_REQUIRED',
    );
    h.server.fail('POST', '/staff/employees', refused);
    await h.tapKey(const ValueKey('setup-add-employee'));
    await h.tap(_surfaceText('Records only').hitTestable());
    await h.enterText(
      _inSurface(find.widgetWithText(DashTextField, 'Name')).first,
      'Rania Adel',
    );
    await h.tap(_inSurface(find.widgetWithText(DashCheckChip, 'Maadi')));
    final reads = h.server.callsTo('/staff/employees', method: 'GET').length;
    await h.tap(_inSurface(find.widgetWithText(DashButton, 'Add employee')));
    expect(h.server.callsTo('/staff/employees', method: 'POST'), hasLength(1));
    expect(find.byType(AddEmployeeDialog), findsOneWidget);
    await h.flushTimers();
    expect(
      h.server.callsTo('/staff/employees', method: 'GET'),
      hasLength(reads),
    );
    expect(find.text(_progress(h, 3)), findsOneWidget);
  });

  // ── The nav leaf ─────────────────────────────────────────────────────

  testWidgets('TEAM-ALL-003 the Set-up leaf shows while the checklist is '
      'incomplete and leaves once the last step is done', (tester) async {
    final h = await pumpSetup(tester, edit: rulesNeverSaved);
    expect(_inSidebar(h.t('nav.staffSetup')), findsOneWidget);
    await h.tapKey(const ValueKey('setup-save-rules'));
    await h.flushTimers();
    expect(find.text(_progress(h, 4)), findsOneWidget);
    expect(_inSidebar(h.t('nav.staffSetup')), findsNothing);
    // The page itself stays open on its "all set" panel.
    expect(byKey('setup-complete'), findsOneWidget);
  });

  testWidgets('TEAM-ALL-003 all done: no Set-up leaf', (tester) async {
    final h = await pumpSetup(tester, path: '/staff/employees');
    expect(_inSidebar(h.t('nav.employees')), findsOneWidget);
    expect(_inSidebar(h.t('nav.staffSetup')), findsNothing);
  });

  testWidgets('TEAM-ALL-003 refusal: without hr.rules.edit no leaf, and the '
      'sidebar asks for no checklist', (tester) async {
    final s = setupServer(persona: Persona.manager, edit: rulesNeverSaved);
    final h = await pumpSetup(
      tester,
      persona: Persona.manager,
      s: s,
      path: '/staff/employees',
    );
    expect(_inSidebar(h.t('nav.employees')), findsOneWidget);
    expect(_inSidebar(h.t('nav.staffSetup')), findsNothing);
    expect(h.server.callsTo('/staff/attendance/settings'), isEmpty);
    expect(h.server.callsTo('/staff/work-shifts'), isEmpty);
  });

  testWidgets('TEAM-ALL-004 the command palette offers Set-up only while the '
      'checklist is incomplete', (tester) async {
    Finder inPalette(String s) => find.descendant(
      of: find.byType(DashCommandPalette),
      matching: find.text(s),
    );
    var h = await pumpSetup(tester, edit: rulesNeverSaved);
    await _openPalette(tester, h);
    await h.enterText(find.byType(DashCommandPalette), 'staff/setup');
    expect(inPalette(h.t('nav.staffSetup')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    h = await pumpSetup(tester, path: '/staff/employees');
    await _openPalette(tester, h);
    await h.enterText(find.byType(DashCommandPalette), 'staff/setup');
    expect(inPalette(h.t('nav.staffSetup')), findsNothing);
  });

  // ── Refresh failures ─────────────────────────────────────────────────

  testWidgets('TEAM-ALL-022 a failed refresh of the branches (outside '
      '/staff) keeps the data and never toasts', (tester) async {
    final h = await pumpSetup(tester);
    final boom = MockResponse.error(500, 'branches unavailable');
    h.server.fail('GET', '/branches', boom);
    await h.tapKey(const ValueKey('setup-refresh'));
    expect(byKey('setup-ready'), findsOneWidget);
    expect(find.text(h.refusalWords(boom)), findsNothing);
  });
}
