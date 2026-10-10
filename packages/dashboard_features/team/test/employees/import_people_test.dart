// The spreadsheet import (TEAM-EMP-050…056, 075): pick a file, read it,
// preview every row with its problem, then one create per row, one at a
// time, the result on each row.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/employees/import_people_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employees_support.dart';

const String _sheet =
    'Name,WhatsApp,Branch,Salary\r\n'
    'Rania Adel,010 0123 4567,Zamalek,"9,000"\r\n'
    ',0101,Maadi,\r\n'
    'Karim Samy,12,Maadi,\r\n'
    'Sara Lotfy,01001234567,Maadi,\r\n'
    'Mona Saad,01001112222,Giza,\r\n'
    'Hesham Ali,01001113333,Maadi,abc\r\n'
    ',,,\r\n'
    'Yara Nabil,01001114444,maadi,\r\n';

PickedFile csv(String text, [String name = 'people.csv']) =>
    PickedFile(name: name, bytes: utf8.encode(text));

Future<DashHarness> openImport(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  Srv? s,
}) async {
  final h = await pumpEmployees(
    tester,
    persona: persona,
    size: size,
    locale: locale,
    s: s,
  );
  await h.tap(pageText(h.t('dawam.importTitle')));
  expect(find.byType(ImportPeopleDialog), findsOneWidget);
  return h;
}

Future<void> choose(DashHarness h, PickedFile f) async {
  h.files.fileQueue.add(f);
  await h.tap(surfaceText(h.t('teamEmployees.chooseFile')));
}

Finder rowOf(int n) => find.byKey(ValueKey('import-row-$n'));

Finder inRow(int n, String text) =>
    find.descendant(of: rowOf(n), matching: find.text(text));

List<Map<String, Object?>> posts(DashHarness h) => [
  for (final c in h.server.callsTo(listT, method: 'POST'))
    (c.body! as Map).cast<String, Object?>(),
];

void main() {
  testWidgets('TEAM-EMP-050 the dialog: title, words, the file field; '
      'nothing to add yet', (tester) async {
    final h = await openImport(tester);
    expect(surfaceText('Import from a spreadsheet'), findsOneWidget);
    expect(surfaceText(h.t('dawam.importHint')), findsOneWidget);
    expect(surfaceText('Spreadsheet'), findsOneWidget);
    expect(surfaceText('No file chosen'), findsOneWidget);
    final add = tester.widget<DashButton>(
      inSurface(find.widgetWithText(DashButton, 'Add 0')),
    );
    expect(add.onPressed, isNull);
    // Cancelled pick: nothing changes.
    await h.tap(surfaceText(h.t('teamEmployees.chooseFile')));
    expect(inSurface(find.textContaining('people')), findsNothing);
  });

  testWidgets('TEAM-EMP-051/052/053 a CSV: headers matched, blank rows '
      'skipped, each problem worded on its row, "Skipped"; rows in sheet '
      'order', (tester) async {
    final h = await openImport(tester);
    await choose(h, csv(_sheet));
    expect(surfaceText('people.csv'), findsOneWidget);
    for (final head in ['#', 'Name', 'WhatsApp number', 'Branch', 'Salary']) {
      expect(surfaceText(head), findsWidgets, reason: head);
    }
    expect(inRow(2, 'Rania Adel'), findsOneWidget);
    expect(inRow(2, '+201001234567'), findsOneWidget);
    expect(inRow(2, 'Zamalek'), findsOneWidget);
    expect(inRow(2, 'EGP 9,000.00'), findsOneWidget);
    expect(inRow(3, 'No name'), findsOneWidget);
    expect(inRow(4, '"12" isn\'t a phone number'), findsOneWidget);
    expect(
      inRow(5, '01001234567 is already on an earlier row'),
      findsOneWidget,
    );
    expect(inRow(6, 'No branch called "Giza"'), findsOneWidget);
    expect(inRow(7, '"abc" isn\'t a salary'), findsOneWidget);
    expect(rowOf(8), findsNothing);
    expect(inRow(9, 'Maadi'), findsOneWidget);
    expect(inRow(9, '—'), findsOneWidget);
    for (final n in [3, 4, 5, 6, 7]) {
      expect(inRow(n, 'Skipped'), findsOneWidget);
    }
    final ys = [
      for (final n in [2, 3, 4, 5, 6, 7, 9]) tester.getTopLeft(rowOf(n)).dy,
    ];
    expect(ys, [...ys]..sort());
    expect(surfaceText('Add 2'), findsOneWidget);
    expect(h.server.callsTo(listT, method: 'POST'), isEmpty);
  });

  testWidgets('TEAM-EMP-051 Arabic headers, a byte-order mark, the only '
      'branch used when the sheet names none', (tester) async {
    final s = employeesServer(
      edit: (db) => db['branches'].removeWhere(
        (b) => b['org_id'] == SeedIds.sabahOrg && b['id'] != SeedIds.maadi,
      ),
    );
    final h = await openImport(tester, s: s);
    await choose(
      h,
      csv('﻿الاسم,رقم الواتساب,الفرع,الراتب\nرانيا عادل,01001234567,,\n'),
    );
    expect(inRow(2, 'رانيا عادل'), findsOneWidget);
    expect(inRow(2, 'Maadi'), findsOneWidget);
    expect(surfaceText('Add 1'), findsOneWidget);
  });

  testWidgets('TEAM-EMP-051 an .xlsx: the first sheet, numbers and dates read '
      'as shown', (tester) async {
    final h = await openImport(tester);
    h.exports.readQueue.add(const [
      SheetData(
        name: 'Staff',
        rows: [
          ['Full name', 'Mobile', 'Branch', 'Monthly salary'],
          ['Rania Adel', 1001234567, 'Zamalek', 9000],
          ['Omar Fawzy', '01001234568', 'Maadi', 8500.5],
        ],
      ),
      SheetData(
        name: 'Other',
        rows: [
          ['Name'],
          ['Nobody'],
        ],
      ),
    ]);
    await choose(
      h,
      PickedFile(name: 'people.xlsx', bytes: const [0x50, 0x4b, 0x03, 0x04, 0]),
    );
    expect(inRow(2, '+201001234567'), findsOneWidget);
    expect(inRow(3, 'EGP 8,500.50'), findsOneWidget);
    expect(surfaceText('Nobody'), findsNothing);
    expect(surfaceText('Add 2'), findsOneWidget);
  });

  testWidgets('TEAM-EMP-054 without the pay right: the salaries notice, no '
      'salary shown or sent', (tester) async {
    final h = await openImport(tester, persona: Persona.manager);
    await choose(
      h,
      csv('Name,Phone,Branch,Salary\nRania Adel,01001234567,Zamalek,9000\n'),
    );
    expect(surfaceText(h.t('dawam.importNoSalaryRight')), findsOneWidget);
    expect(inRow(2, '—'), findsOneWidget);
    expect(inRow(2, 'EGP 9,000.00'), findsNothing);
    await h.tap(surfaceText('Add 1'));
    expect(posts(h).single.containsKey('base_salary_piastres'), isFalse);
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-054 with the pay right: no notice, the salary sent', (
    tester,
  ) async {
    final h = await openImport(tester);
    await choose(
      h,
      csv('Name,Phone,Branch,Salary\nRania Adel,01001234567,Zamalek,9000\n'),
    );
    expect(surfaceText(h.t('dawam.importNoSalaryRight')), findsNothing);
    await h.tap(surfaceText('Add 1'));
    expect(posts(h).single['base_salary_piastres'], 900000);
    await h.flushTimers();
  });

  testWidgets('TEAM-EMP-055 Add n: one create per row, in order, the result '
      'on each row, everything under /staff refetched, "2 of 2 added"', (
    tester,
  ) async {
    final h = await openImport(tester);
    await choose(h, csv(_sheet));
    final departments = h.server.callsTo(departmentsT).length;
    await h.tap(surfaceText('Add 2'));
    expect(posts(h), [
      {
        'name': 'Rania Adel',
        'phone': '201001234567',
        'app_access': true,
        'branch_ids': [SeedIds.zamalek],
        'base_salary_piastres': 900000,
      },
      {
        'name': 'Yara Nabil',
        'phone': '201001114444',
        'app_access': true,
        'branch_ids': [SeedIds.maadi],
      },
    ]);
    expect(inRow(2, 'Added'), findsOneWidget);
    expect(inRow(9, 'Added'), findsOneWidget);
    await h.expectToast('2 of 2 added');
    expect(h.server.callsTo(departmentsT).length, greaterThan(departments));
    expect(surfaceText('Add 0'), findsOneWidget);
    expect(
      tester
          .widget<DashButton>(
            inSurface(find.widgetWithText(DashButton, 'Add 0')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('TEAM-EMP-055 a refused row shows the server\'s words; Add '
      'again retries only the rows not added', (tester) async {
    final h = await openImport(tester);
    await choose(
      h,
      csv(
        'Name,Phone,Branch\n'
        'Rania Adel,01001234567,Zamalek\n'
        'Copy Cat,01110001111,Zamalek\n',
      ),
    );
    await h.tap(surfaceText('Add 2'));
    expect(inRow(2, 'Added'), findsOneWidget);
    expect(
      inRow(
        3,
        h.t('errors.codes.PHONE_TAKEN', args: {'phone': '+201110001111'}),
      ),
      findsOneWidget,
    );
    await h.expectToast('1 of 2 added');
    expect(surfaceText('Add 1'), findsOneWidget);
    await h.tap(surfaceText('Add 1'));
    expect(posts(h), hasLength(3));
    expect(posts(h).last['name'], 'Copy Cat');
    await h.expectToast('1 of 2 added');
  });

  testWidgets('TEAM-EMP-055/075 closed mid-run: the run goes on and still '
      'says "2 of 2 added"', (tester) async {
    final h = await openImport(tester);
    await choose(h, csv(_sheet));
    final gate = h.server.hold('POST', listT);
    await h.tap(surfaceText('Add 2'));
    await h.tap(surfaceText('Close'));
    expect(find.byType(ImportPeopleDialog), findsNothing);
    gate.release();
    await h.settle();
    expect(posts(h), hasLength(2));
    await h.expectToast('2 of 2 added');
  });

  testWidgets('TEAM-EMP-056 Close closes; nothing sent', (tester) async {
    final h = await openImport(tester);
    await choose(h, csv(_sheet));
    await h.tap(surfaceText('Close'));
    expect(find.byType(ImportPeopleDialog), findsNothing);
    expect(h.server.callsTo(listT, method: 'POST'), isEmpty);
  });

  testWidgets('TEAM-EMP-075 another file replaces the preview and clears the '
      'results; an unreadable one toasts and keeps the last', (tester) async {
    final h = await openImport(tester);
    await choose(h, csv('Name,Phone,Branch\nRania Adel,01001234567,Zamalek\n'));
    await h.tap(surfaceText('Add 1'));
    expect(inRow(2, 'Added'), findsOneWidget);
    await h.flushTimers();
    await choose(
      h,
      csv('Name,Phone,Branch\nYara Nabil,01001114444,Maadi\n', 'more.csv'),
    );
    expect(inRow(2, 'Yara Nabil'), findsOneWidget);
    expect(inRow(2, 'Added'), findsNothing);
    expect(surfaceText('Add 1'), findsOneWidget);
    await choose(
      h,
      PickedFile(name: 'broken.xlsx', bytes: utf8.encode('not a workbook')),
    );
    await h.expectToast(h.t('errors.unknown'));
    expect(inRow(2, 'Yara Nabil'), findsOneWidget);
    expect(surfaceText('more.csv'), findsOneWidget);
  });

  testWidgets('TEAM-EMP-075 the summary is a success toast even when nobody '
      'was added', (tester) async {
    final h = await openImport(tester);
    await choose(h, csv('Name,Phone,Branch\nCopy Cat,01110001111,Zamalek\n'));
    await h.tap(surfaceText('Add 1'));
    await h.expectToast('0 of 1 added');
  });

  testWidgets('TEAM-EMP-050/073 phone: the import in a centred card, rows '
      'as cards', (tester) async {
    final h = await openImport(tester, size: DashSize.phone, locale: 'ar');
    await choose(h, csv(_sheet));
    expect(find.byType(ImportPeopleDialog), findsOneWidget);
    expectPhoneDialog(
      tester,
      primary: tester
          .widget<DashButton>(
            find.byWidgetPredicate(
              (w) => w is DashButton && w.icon == 'upload',
            ),
          )
          .label,
      secondary: h.t('common.close'),
    );
    expect(
      find.descendant(of: rowOf(2), matching: find.byType(DashCard)),
      findsNothing,
    );
    expect(rowOf(2), findsOneWidget);
    expect(tester.widget(rowOf(2)), isA<DashCard>());
  });
}
