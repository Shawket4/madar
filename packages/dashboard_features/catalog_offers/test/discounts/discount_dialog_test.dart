// The discount dialog (OFFR-DSC-024..038, 044, 045; OFFR-ALL-017, 019),
// driven through the real shell on the mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const String _new = '/discounts?edit=new';
String _edit(String key) => '/discounts?edit=${discountId(key)}';

/// The text a dialog box holds.
String textOf(WidgetTester tester, String label) => tester
    .widget<EditableText>(
      find.descendant(
        of: dialogField(label),
        matching: find.byType(EditableText),
      ),
    )
    .controller
    .text;

/// The dialog's Type select.
Finder get typeSelect => inDialog(find.byType(DashSelect<String>));

/// The dialog's Active switch.
Finder get activeSwitch => inDialog(find.byType(DashSwitch));

Future<void> pickType(DashHarness h, String label) async {
  await h.tap(typeSelect);
  await h.tap(find.text(label).last);
}

List<MockCall> posts(DashHarness h) =>
    h.server.callsTo(listRoute, method: 'POST');
List<MockCall> patches(DashHarness h) =>
    h.server.callsTo(itemRoute, method: 'PATCH');

void main() {
  testWidgets('OFFR-DSC-024 titles "New discount" / "Edit discount", the '
      'subtitle under them', (tester) async {
    final h = await pumpDiscounts(tester, path: _new);
    expect(inDialog(find.text('New discount')), findsOneWidget);
    expect(
      inDialog(find.text('Percentage and fixed-amount discounts')),
      findsOneWidget,
    );
    expect(inDialog(find.text('Create')), findsOneWidget);
    await h.tap(inDialog(find.text('Cancel')));
    await h.tap(inTable(find.text('Staff Meal')));
    expect(inDialog(find.text('Edit discount')), findsOneWidget);
    expect(inDialog(find.text('Save')), findsOneWidget);
  });

  testWidgets('OFFR-DSC-025 the form opens filled: percentage as 0–100, '
      'fixed in EGP; new = empty, Percentage, 0, active', (tester) async {
    final h = await pumpDiscounts(tester, path: _new);
    expect(textOf(tester, 'Discount name'), '');
    expect(textOf(tester, 'Discount name (ع)'), '');
    expect(textOf(tester, 'Percentage (%)'), '0');
    expect(tester.widget<DashSelect<String>>(typeSelect).value, 'percentage');
    expect(tester.widget<DashSwitch>(activeSwitch).value, isTrue);
    await h.tap(inDialog(find.text('Cancel')));

    await h.go(_edit('corporate-vodafone'));
    expect(textOf(tester, 'Discount name'), 'Corporate: Vodafone');
    expect(textOf(tester, 'Discount name (ع)'), 'الشركات: فودافون');
    expect(textOf(tester, 'Percentage (%)'), '12.5');
    await h.tap(inDialog(find.text('Cancel')));

    await h.go(_edit('late-order'));
    expect(tester.widget<DashSelect<String>>(typeSelect).value, 'fixed');
    expect(textOf(tester, 'Amount (EGP)'), '50');
    await h.tap(inDialog(find.text('Cancel')));

    await h.go(_edit('opening-week'));
    expect(tester.widget<DashSwitch>(activeSwitch).value, isFalse);
  });

  testWidgets('OFFR-DSC-026 the name is required; the Arabic box is right to '
      'left, labelled "(ع)"', (tester) async {
    final h = await pumpDiscounts(tester, path: _new);
    final ar = tester.widget<EditableText>(
      find.descendant(
        of: dialogField('Discount name (ع)'),
        matching: find.byType(EditableText),
      ),
    );
    expect(ar.textDirection, TextDirection.rtl);
    await h.tap(inDialog(find.text('Create')));
    expect(inDialog(find.text('This field is required')), findsOneWidget);
    expect(posts(h), isEmpty);
    // Re-checked on every change once Save was pressed.
    await h.enterText(dialogField('Discount name'), 'Staff Iftar');
    expect(inDialog(find.text('This field is required')), findsNothing);
  });

  testWidgets('OFFR-DSC-026 Arabic UI: the Arabic box reads the web\'s label', (
    tester,
  ) async {
    final h = await pumpDiscounts(tester, path: _new, locale: 'ar');
    final label = h.t('discounts.discountName');
    expect(
      inDialog(
        find.text(h.t('bilingualField.arabicLabel', args: {'label': label})),
      ),
      findsOneWidget,
    );
  });

  testWidgets('OFFR-DSC-027 Type: Percentage / Fixed amount; switching '
      'changes the label, hint and limits', (tester) async {
    final h = await pumpDiscounts(tester, path: _new);
    expect(inDialog(find.text('Percentage (%)')), findsOneWidget);
    expect(inDialog(find.text('100% makes the order free.')), findsOneWidget);
    await h.tap(typeSelect);
    expect(find.text('Percentage'), findsWidgets);
    expect(find.text('Fixed amount'), findsWidgets);
    await h.tap(find.text('Fixed amount').last);
    expect(inDialog(find.text('Amount (EGP)')), findsOneWidget);
    expect(
      inDialog(
        find.text(
          'More than the order comes to just makes it free — it never pays '
          'the customer back.',
        ),
      ),
      findsOneWidget,
    );
    // No ceiling for a fixed amount.
    await h.enterText(dialogField('Discount name'), 'Big Order');
    await h.enterText(dialogField('Amount (EGP)'), '150');
    await h.tap(inDialog(find.text('Create')));
    expect(posts(h).single.body, containsPair('value', 15000));
    await h.flushTimers();
  });

  testWidgets('OFFR-DSC-028 a blank value counts as 0', (tester) async {
    final h = await pumpDiscounts(tester, path: _new);
    await h.enterText(dialogField('Discount name'), 'Zero Day');
    await h.enterText(dialogField('Percentage (%)'), '');
    await h.tap(inDialog(find.text('Create')));
    expect(posts(h).single.body, containsPair('value', 0));
    await h.flushTimers();
  });

  testWidgets('OFFR-DSC-029 value rules: below 0, a percentage above 100; 0, '
      '100 % and any fixed amount pass', (tester) async {
    final h = await pumpDiscounts(tester, path: _new);
    await h.enterText(dialogField('Discount name'), 'Rules');
    await h.enterText(dialogField('Percentage (%)'), '-1');
    await h.tap(inDialog(find.text('Create')));
    expect(
      inDialog(find.text("A discount can't be less than zero.")),
      findsOneWidget,
    );
    await h.enterText(dialogField('Percentage (%)'), '150');
    expect(
      inDialog(
        find.text(
          'Enter a percentage between 0 and 100. 100% makes the order free.',
        ),
      ),
      findsOneWidget,
    );
    await h.enterText(dialogField('Percentage (%)'), '100');
    expect(inDialog(find.textContaining('between 0 and 100')), findsNothing);
    await pickType(h, 'Fixed amount');
    await h.enterText(dialogField('Amount (EGP)'), '100000');
    expect(inDialog(find.textContaining('less than zero')), findsNothing);
    expect(posts(h), isEmpty);
    await h.tap(inDialog(find.text('Create')));
    expect(posts(h).single.body, containsPair('value', 10000000));
    await h.flushTimers();
  });

  testWidgets('OFFR-DSC-030 the browser\'s own limits: not a multiple of 0.5 '
      'is refused before sending', (tester) async {
    final h = await pumpDiscounts(tester, path: _new);
    await h.enterText(dialogField('Discount name'), 'Odd');
    await h.enterText(dialogField('Percentage (%)'), '12.3');
    await h.tap(inDialog(find.text('Create')));
    expect(inDialog(find.text(h.t('discounts.valueStep'))), findsOneWidget);
    expect(posts(h), isEmpty);
    await h.enterText(dialogField('Percentage (%)'), '12.5');
    expect(inDialog(find.text(h.t('discounts.valueStep'))), findsNothing);
    await h.tap(inDialog(find.text('Create')));
    expect(posts(h).single.body, containsPair('value', 0.125));
    await h.flushTimers();
  });

  testWidgets('OFFR-DSC-031 the Active switch and its hint', (tester) async {
    final h = await pumpDiscounts(tester, path: _new);
    expect(
      inDialog(find.text("Inactive discounts can't be applied at checkout.")),
      findsOneWidget,
    );
    await h.tap(activeSwitch);
    expect(tester.widget<DashSwitch>(activeSwitch).value, isFalse);
    await h.enterText(dialogField('Discount name'), 'Paused');
    await h.tap(inDialog(find.text('Create')));
    expect(posts(h).single.body, containsPair('is_active', false));
    await h.flushTimers();
  });

  testWidgets('OFFR-DSC-032 Cancel closes; Create spins while busy', (
    tester,
  ) async {
    final s = discountsServer();
    final gate = s.server.hold('POST', listRoute);
    final h = await pumpDiscounts(
      tester,
      path: _new,
      server: s.server,
      db: s.db,
    );
    await h.enterText(dialogField('Discount name'), 'Busy');
    await h.tap(inDialog(find.text('Create')));
    final create = find.ancestor(
      of: inDialog(find.text('Create')),
      matching: find.byType(DashButton),
    );
    expect(tester.widget<DashButton>(create).loading, isTrue);
    gate.release();
    await h.settle();
    await h.expectToast('Discount created');
    expect(dialog, findsNothing);

    await h.tap(inPage(find.text('New discount')));
    await h.tap(inDialog(find.text('Cancel')));
    expect(dialog, findsNothing);
    expect(posts(h), hasLength(1));
  });

  testWidgets('OFFR-DSC-033 Create sends the name as typed, the Arabic name, '
      'the fraction; refreshes; "Discount created"; closes', (tester) async {
    final h = await pumpDiscounts(tester, path: _new);
    final before = h.server.callsTo(listRoute, method: 'GET').length;
    await h.enterText(dialogField('Discount name'), ' Ramadan 14 ');
    await h.enterText(dialogField('Discount name (ع)'), 'رمضان');
    await h.enterText(dialogField('Percentage (%)'), '14');
    await h.tap(inDialog(find.text('Create')));
    await h.expectToast('Discount created');
    expect(posts(h).single.body, {
      'org_id': SeedIds.sabahOrg,
      'name': ' Ramadan 14 ',
      'name_translations': {'ar': 'رمضان'},
      'dtype': 'percentage',
      'value': 0.14,
      'is_active': true,
    });
    expect(dialog, findsNothing);
    expect(h.location.queryParameters.containsKey('edit'), isFalse);
    expect(h.server.callsTo(listRoute, method: 'GET').length, before + 1);
    expect(inTable(find.text(' Ramadan 14 ')), findsOneWidget);
  });

  testWidgets('OFFR-DSC-033 a fixed amount travels in piastres; no Arabic '
      'name, no translations', (tester) async {
    final h = await pumpDiscounts(tester, path: _new);
    await h.enterText(dialogField('Discount name'), 'Fifty Off');
    await pickType(h, 'Fixed amount');
    await h.enterText(dialogField('Amount (EGP)'), '50');
    await h.tap(inDialog(find.text('Create')));
    await h.expectToast('Discount created');
    final body = posts(h).single.body! as Map;
    expect(body.containsKey('name_translations'), isFalse);
    expect(body['dtype'], 'fixed');
    expect(body['value'], 5000);
    expect(inTable(find.text('EGP 50.00')), findsWidgets);
  });

  testWidgets('OFFR-DSC-034 Save PATCHes every field; "Discount updated"', (
    tester,
  ) async {
    final h = await pumpDiscounts(tester, path: _edit('student'));
    await h.enterText(dialogField('Discount name'), 'Student Card');
    await h.enterText(dialogField('Percentage (%)'), '20');
    await h.tap(inDialog(find.text('Save')));
    await h.expectToast('Discount updated');
    final call = patches(h).single;
    expect(call.path, '/discounts/${discountId('student')}');
    expect(call.body, {
      'name': 'Student Card',
      'name_translations': {'ar': 'خصم الطلاب'},
      'dtype': 'percentage',
      'value': 0.2,
      'is_active': true,
    });
    expect(dialog, findsNothing);
    expect(inTable(find.text('Student Card')), findsOneWidget);
    expect(
      inTable(find.text('20%')),
      findsNWidgets(2),
      reason: '+ Opening Week',
    );
  });

  testWidgets('OFFR-DSC-034 a blank Arabic name is left out of the PATCH', (
    tester,
  ) async {
    final h = await pumpDiscounts(tester, path: _edit('student'));
    await h.enterText(dialogField('Discount name (ع)'), '');
    await h.tap(inDialog(find.text('Save')));
    await h.expectToast('Discount updated');
    final body = patches(h).single.body! as Map;
    expect(body.containsKey('name_translations'), isFalse);
  });

  testWidgets('OFFR-DSC-035 a failed save toasts the server\'s words and '
      'keeps the form', (tester) async {
    final s = discountsServer();
    final refusal = MockResponse.badRequest(
      'a percentage discount is a fraction between 0 and 1 (0.14 = 14%)',
    );
    s.server.fail('PATCH', itemRoute, refusal);
    final h = await pumpDiscounts(
      tester,
      path: _edit('student'),
      server: s.server,
      db: s.db,
    );
    await h.enterText(dialogField('Discount name'), 'Student Plus');
    await h.tap(inDialog(find.text('Save')));
    await h.expectToast(refusalText(h, refusal));
    expect(dialog, findsOneWidget);
    expect(textOf(tester, 'Discount name'), 'Student Plus');
    expect(
      tester
          .widget<DashButton>(
            find.ancestor(
              of: inDialog(find.text('Save')),
              matching: find.byType(DashButton),
            ),
          )
          .loading,
      isFalse,
    );
  });

  testWidgets('OFFR-DSC-036 a broken rule: the red line, no request, no '
      'toast', (tester) async {
    final h = await pumpDiscounts(tester, path: _edit('staff-meal'));
    await h.enterText(dialogField('Discount name'), '');
    await h.enterText(dialogField('Percentage (%)'), '101');
    await h.tap(inDialog(find.text('Save')));
    expect(inDialog(find.text('This field is required')), findsOneWidget);
    expect(inDialog(find.textContaining('between 0 and 100')), findsOneWidget);
    expect(patches(h), isEmpty);
    expect(find.text('Discount updated'), findsNothing);
    expect(dialog, findsOneWidget);
  });

  testWidgets('OFFR-DSC-037 Esc, × and outside close without saving', (
    tester,
  ) async {
    final h = await pumpDiscounts(tester, path: _edit('staff-meal'));
    await h.enterText(dialogField('Discount name'), 'Changed');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(dialog, findsNothing);
    expect(h.location.queryParameters.containsKey('edit'), isFalse);

    await h.tap(inTable(find.text('Staff Meal')));
    await h.tap(inDialog(find.bySemanticsLabel('Close')));
    expect(dialog, findsNothing);

    await h.tap(inTable(find.text('Staff Meal')));
    await tester.tapAt(const Offset(4, 300));
    await h.settle();
    expect(dialog, findsNothing);
    expect(patches(h), isEmpty);
    expect(inTable(find.text('Staff Meal')), findsOneWidget);
  });

  testWidgets('OFFR-DSC-038 phone: a full-screen sheet; the names stack, '
      'Type and Value stay side by side', (tester) async {
    final h = await pumpDiscounts(tester, path: _new, size: DashSize.phone);
    expect(
      find.ancestor(of: dialog, matching: find.byType(DashSurfaceScope)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<DashSurfaceScope>(
            find.ancestor(of: dialog, matching: find.byType(DashSurfaceScope)),
          )
          .mode,
      DashSurfaceMode.fullScreen,
    );
    final en = tester.getTopLeft(dialogField('Discount name'));
    final ar = tester.getTopLeft(dialogField('Discount name (ع)'));
    expect(ar.dy, greaterThan(en.dy), reason: 'stacked below 640');
    final type = tester.getTopLeft(inDialog(find.text('Type')));
    final value = tester.getTopLeft(inDialog(find.text('Percentage (%)')));
    expect(type.dy, value.dy, reason: 'two columns at every width');
    await h.enterText(dialogField('Discount name'), 'Phone Deal');
    await h.tap(inDialog(find.text('Create')));
    await h.expectToast('Discount created');
    expect(dialog, findsNothing);
  });

  testWidgets('OFFR-DSC-038 desktop: the names side by side in a 512 dialog', (
    tester,
  ) async {
    await pumpDiscounts(tester, path: _new);
    final en = tester.getTopLeft(dialogField('Discount name'));
    final ar = tester.getTopLeft(dialogField('Discount name (ع)'));
    expect(ar.dy, en.dy);
    expect(tester.getSize(dialog).width, lessThanOrEqualTo(512));
  });

  testWidgets('OFFR-DSC-044 a stored 12.25 % opens as it is and cannot be '
      'saved until moved to a 0.5 step', (tester) async {
    final s = discountsServer();
    s.db.table(OffersTables.discounts).update(discountId('student'), {
      'value_rate': 0.1225,
      'value': 12,
    });
    final h = await pumpDiscounts(
      tester,
      path: _edit('student'),
      server: s.server,
      db: s.db,
    );
    expect(textOf(tester, 'Percentage (%)'), '12.25');
    await h.enterText(dialogField('Discount name'), 'Student Card');
    await h.tap(inDialog(find.text('Save')));
    expect(inDialog(find.text(h.t('discounts.valueStep'))), findsOneWidget);
    expect(patches(h), isEmpty);
    await h.enterText(dialogField('Percentage (%)'), '12');
    await h.tap(inDialog(find.text('Save')));
    await h.expectToast('Discount updated');
    expect(patches(h).single.body, containsPair('value', 0.12));
  });

  testWidgets('OFFR-DSC-045 the hint stays above the red line; switching '
      'type keeps the typed number', (tester) async {
    final h = await pumpDiscounts(tester, path: _new);
    await h.enterText(dialogField('Percentage (%)'), '-5');
    await h.tap(inDialog(find.text('Create')));
    final hint = tester.getTopLeft(
      inDialog(find.text('100% makes the order free.')),
    );
    final error = tester.getTopLeft(
      inDialog(find.text("A discount can't be less than zero.")),
    );
    expect(error.dy, greaterThan(hint.dy));
    await h.enterText(dialogField('Percentage (%)'), '14');
    await pickType(h, 'Fixed amount');
    expect(textOf(tester, 'Amount (EGP)'), '14');
  });

  testWidgets('OFFR-ALL-017 an open dialog re-seeds when its row changes on '
      'a refetch', (tester) async {
    final s = discountsServer();
    final h = await pumpDiscounts(
      tester,
      path: _edit('staff-meal'),
      server: s.server,
      db: s.db,
    );
    await h.enterText(dialogField('Discount name'), 'Typed but lost');
    s.db.table(OffersTables.discounts).update(discountId('staff-meal'), {
      'name': 'Staff Lunch',
    });
    h.container.read(realtimeBusProvider).invalidate(const ['/discounts']);
    await h.settle();
    expect(textOf(tester, 'Discount name'), 'Staff Lunch');

    // A refetch with the same values keeps what is typed.
    await h.enterText(dialogField('Discount name'), 'Kept');
    h.container.read(realtimeBusProvider).invalidate(const ['/discounts']);
    await h.settle();
    expect(textOf(tester, 'Discount name'), 'Kept');
  });

  testWidgets('OFFR-ALL-019 Enter in a box submits the form', (tester) async {
    final h = await pumpDiscounts(tester, path: _new);
    await h.enterText(dialogField('Discount name'), 'Enter Key');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    await h.expectToast('Discount created');
    expect(posts(h).single.body, containsPair('name', 'Enter Key'));
  });

  testWidgets('OFFR-ALL-019 closing mid-save lets the save finish: its toast '
      'and the refreshed list', (tester) async {
    final s = discountsServer();
    final gate = s.server.hold('POST', listRoute);
    final h = await pumpDiscounts(
      tester,
      path: _new,
      server: s.server,
      db: s.db,
    );
    await h.enterText(dialogField('Discount name'), 'Late Night');
    await h.tap(inDialog(find.text('Create')));
    await h.tap(inDialog(find.text('Cancel')));
    expect(dialog, findsNothing);
    gate.release();
    await h.settle();
    await h.expectToast('Discount created');
    expect(inTable(find.text('Late Night')), findsOneWidget);
  });

  testWidgets('OFFR-DSC-024 the Arabic dialog reads in Arabic', (tester) async {
    final h = await pumpDiscounts(
      tester,
      path: _edit('staff-meal'),
      locale: 'ar',
    );
    expect(inDialog(find.text(h.t('discounts.editTitle'))), findsOneWidget);
    expect(
      inDialog(find.text(h.t('discounts.percentageValue'))),
      findsOneWidget,
    );
    expect(inDialog(find.text(h.t('common.save'))), findsOneWidget);
  });
}
