// The Employees screenshot matrix: the default page at {phone, tablet,
// desktop} x {en light, ar dark}, scrolled through; and every other state
// (loading, failed, empty, the dialogs and the confirm) at desktop-en-light
// and phone-ar-light. Written only with FDASH_SHOTS set; the pages still
// render (and must not overflow) without.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_team/src/employees/employee_fields.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'employees_support.dart';

const _modes = [('en', false), ('ar', true)];
const _states = [(DashSize.desktop, 'en'), (DashSize.phone, 'ar')];

const String _sheet =
    'Name,WhatsApp,Branch,Salary\n'
    'Rania Adel,010 0123 4567,Zamalek,"9,000"\n'
    ',0101,Maadi,\n'
    'Karim Samy,12,Maadi,\n'
    'Mona Saad,01001112222,Giza,\n'
    'Copy Cat,01110001111,Zamalek,\n'
    'Yara Nabil,01001114444,Maadi,\n';

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in _modes) {
      final tag = '${size.name} $lang ${dark ? 'dark' : 'light'}';
      testWidgets('default, $tag', (tester) async {
        final h = await pumpEmployees(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default');
      });
      testWidgets('Nakhla (app and records-only kinds), $tag', (tester) async {
        final h = await pumpEmployees(
          tester,
          persona: Persona.dawamOnly,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'nakhla');
      });
    }
  }

  for (final (size, lang) in _states) {
    final tag = '${size.name} $lang';
    Future<DashHarness> open(WidgetTester tester, {Srv? s}) =>
        pumpEmployees(tester, size: size, locale: lang, s: s);

    testWidgets('loading, $tag', (tester) async {
      final s = employeesServer();
      final gate = s.server.hold('GET', listT);
      final h = await open(tester, s: s);
      await h.shot('employees/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = employeesServer();
      s.server.fail(
        'GET',
        listT,
        MockResponse.error(500, 'Database error: timeout'),
        times: null,
      );
      final h = await open(tester, s: s);
      await h.shot('employees/failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final h = await open(tester, s: employeesServer(edit: noPeople));
      await h.shot('employees/empty');
    });

    testWidgets('profile, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(inPage(find.text('Mariam Fathy')));
      await h.shot('employees/profile-1');
      await h.tap(surfaceText(h.t('common.save')));
      await h.flushTimers();
      await h.tap(inPage(find.text('Nour El-Sayed')));
      await h.tap(
        inSurface(
          find.widgetWithText(
            DashSelectField<String>,
            h.t('staff.employmentStatus'),
          ),
        ),
      );
      await h.tap(find.text(h.t('staff.statusTerminated')).hitTestable().last);
      await h.tap(surfaceText(h.t('common.save')));
      await h.shot('employees/profile-errors');
      final scroll = find
          .descendant(of: surface(), matching: find.byType(Scrollable))
          .first;
      await tester.drag(scroll, const Offset(0, -2000));
      await h.settle();
      await h.shot('employees/profile-2');
    });

    testWidgets('date picker, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(inPage(find.text('Adham Reda')));
      await h.tap(
        inSurface(
          find.widgetWithText(EmployeeDateField, h.t('staff.hireDate')),
        ),
      );
      await h.shot('employees/date-picker');
    });

    testWidgets('confirm a new number, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(inPage(find.text('Mariam Fathy')));
      await h.enterText(
        inSurface(find.widgetWithText(PhoneField, h.t('dawam.whatsapp'))),
        '01098765432',
      );
      await h.tap(surfaceText(h.t('common.save')));
      await h.shot('employees/confirm-new-number');
    });

    testWidgets('end employment confirm, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(
        inPage(find.bySemanticsLabel(h.t('staff.endEmployment'))).first,
      );
      await h.shot('employees/confirm-end');
    });

    testWidgets('add, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(pageText(h.t('dawam.addEmployee')));
      await h.shot('employees/add-app');
      await h.enterText(
        inSurface(find.widgetWithText(PhoneField, h.t('dawam.whatsapp'))),
        '12',
      );
      await h.tap(inSurface(find.text(h.t('dawam.kind_linked'))).hitTestable());
      await h.shot('employees/add-linked');
      await h.tap(inSurface(find.text(h.t('dawam.kind_manual'))).hitTestable());
      await h.enterText(
        inSurface(find.widgetWithText(DashTextField, h.t('staff.name'))),
        'Saeed Hamdy',
      );
      await h.enterText(
        find
            .descendant(
              of: inSurface(find.byType(SalaryCalculator)),
              matching: find.byType(DashTextInput),
            )
            .first,
        '3100',
      );
      final scroll = find
          .descendant(of: surface(), matching: find.byType(Scrollable))
          .first;
      await tester.drag(scroll, const Offset(0, -2000));
      await h.settle();
      await h.shot('employees/add-manual-salary');
    });

    testWidgets('add as a manager, $tag', (tester) async {
      final h = await pumpEmployees(
        tester,
        persona: Persona.manager,
        size: size,
        locale: lang,
      );
      await h.tap(pageText(h.t('dawam.addEmployee')));
      final scroll = find
          .descendant(of: surface(), matching: find.byType(Scrollable))
          .first;
      await tester.drag(scroll, const Offset(0, -2000));
      await h.settle();
      await h.shot('employees/add-manager');
    });

    testWidgets('import, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(pageText(h.t('dawam.importTitle')));
      await h.shot('employees/import-empty');
      h.files.fileQueue.add(
        PickedFile(name: 'people.csv', bytes: utf8.encode(_sheet)),
      );
      await h.tap(surfaceText(h.t('teamEmployees.chooseFile')));
      await h.shot('employees/import-preview');
      await h.tap(surfaceText(h.t('dawam.importRun', args: {'n': 3})));
      await h.shot('employees/import-done');
      await h.flushTimers();
    });

    testWidgets('import without the pay right, $tag', (tester) async {
      final h = await pumpEmployees(
        tester,
        persona: Persona.manager,
        size: size,
        locale: lang,
      );
      await h.tap(pageText(h.t('dawam.importTitle')));
      h.files.fileQueue.add(
        PickedFile(name: 'people.csv', bytes: utf8.encode(_sheet)),
      );
      await h.tap(surfaceText(h.t('teamEmployees.chooseFile')));
      await h.shot('employees/import-no-pay-right');
    });

    testWidgets('departments, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(pageText(h.t('staff.departments')));
      await h.shot('employees/departments');
      await h.tap(
        find
            .descendant(
              of: surface(),
              matching: find.bySemanticsLabel(h.t('common.delete')),
            )
            .first,
      );
      await h.shot('employees/departments-confirm');
    });

    testWidgets('filter open, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(inPage(find.text(h.t('staff.allStatuses'))));
      await h.shot('employees/filter-status');
    });
  }
}
