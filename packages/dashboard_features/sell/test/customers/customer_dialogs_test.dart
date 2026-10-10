// Add / edit, erase and merge (SELL-CUS-022 … 025, 032 … 039).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_sell/src/customers/customer_dialog.dart';
import 'package:dashboard_sell/src/customers/customer_sheet.dart';
import 'package:dashboard_sell/src/customers/merge_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _name = ValueKey('customer-name');
const _phone = ValueKey('customer-phone');
const _notes = ValueKey('customer-notes');

/// The dialog's own button labelled [label] (the footer's, not the title).
Finder dialogButton(String label) =>
    find.byWidgetPredicate((w) => w is DashButton && w.label == label).last;

/// The first customers of the merge picker's window (20, most recent first)
/// matching [test], with a name nobody else has.
MockRow pickable(MockDb db, bool Function(MockRow c) test, {Object? not}) {
  final names = <Object?, int>{};
  for (final c in db['customers'].rows) {
    names[c['name']] = (names[c['name']] ?? 0) + 1;
  }
  return listOrder(db)
      .take(20)
      .firstWhere((c) => c['id'] != not && names[c['name']] == 1 && test(c));
}

/// The merge picker's option for [name].
Finder option(String name) => find.descendant(
  of: find.byType(MergeOptions),
  matching: find.byWidgetPredicate(
    (w) =>
        w is DashPressable &&
        (w.semanticLabel == name || w.semanticLabel == '$name, Member'),
  ),
);

/// Opens the picker, searches for [name] (as a person would) and picks it.
Future<void> pick(DashHarness h, String name) async {
  await h.tap(find.byKey(const ValueKey('merge-pick')));
  await h.enterText(find.byKey(const ValueKey('merge-search')), name);
  await h.tester.pump(const Duration(milliseconds: 350));
  await h.settle();
  await h.tap(option(name));
}

void main() {
  group('add', () {
    testWidgets('SELL-CUS-022 the Add dialog', (tester) async {
      final h = await pumpCustomers(tester);
      await h.tap(pageText('Add customer'));
      expect(find.byType(CustomerDialog), findsOneWidget);
      expect(inDialog(find.text('Add customer')), findsWidgets);
      expect(
        inDialog(find.text('A phone number lets the till find them again.')),
        findsOneWidget,
      );
      expect(inDialog(find.text('Name')), findsOneWidget);
      expect(inDialog(find.text('Phone')), findsOneWidget);
      expect(inDialog(find.text('Notes')), findsOneWidget);
      expect(inDialog(textHas('(Optional)')), findsNWidgets(2));
      expect(inDialog(find.text('Cancel')), findsOneWidget);
      await h.tap(inDialog(find.text('Cancel')));
      expect(find.byType(CustomerDialog), findsNothing);
      expect(h.server.callsTo('/customers', method: 'POST'), isEmpty);
    });

    testWidgets('SELL-CUS-023 the form\'s rules', (tester) async {
      final h = await pumpCustomers(tester);
      await h.tap(pageText('Add customer'));
      await h.tap(dialogButton('Add customer'));
      expect(inDialog(find.text("Enter the customer's name.")), findsOneWidget);
      await h.enterText(find.byKey(_name), '   ');
      await h.enterText(find.byKey(_phone), '12345');
      await h.enterText(find.byKey(_notes), 'x' * 2001);
      await h.tap(dialogButton('Add customer'));
      expect(inDialog(find.text("Enter the customer's name.")), findsOneWidget);
      expect(
        inDialog(find.text('Enter a valid phone number.')),
        findsOneWidget,
      );
      expect(
        inDialog(find.text('Keep notes under 2000 characters.')),
        findsOneWidget,
      );
      expect(h.server.callsTo('/customers', method: 'POST'), isEmpty);
      // The name box stops at 120.
      await h.enterText(find.byKey(_name), 'N' * 130);
      final field = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(_name),
          matching: find.byType(EditableText),
        ),
      );
      expect(field.controller.text.length, 120);
    });

    testWidgets('SELL-CUS-024 Add: trimmed body, toast, refetch, its sheet '
        'opens', (tester) async {
      final h = await pumpCustomers(tester);
      final reads = listCalls(h).length;
      await h.tap(pageText('Add customer'));
      await h.enterText(find.byKey(_name), '  Mona Hafez ');
      await h.enterText(find.byKey(_phone), ' 0100 987 6543 ');
      await h.tap(dialogButton('Add customer'));
      final post = h.server.callsTo('/customers', method: 'POST').single;
      expect(post.body, {
        'name': 'Mona Hafez',
        'phone': '0100 987 6543',
        'notes': null,
      });
      await h.expectToast('Customer added', keep: true);
      expect(find.byType(CustomerDialog), findsNothing);
      expect(find.byType(CustomerSheet), findsOneWidget);
      expect(sheetText('Mona Hafez'), findsOneWidget);
      expect(listCalls(h).length, greaterThan(reads));
      await h.flushTimers();
    });

    testWidgets('SELL-CUS-024 Add spins while it saves', (tester) async {
      final h = await pumpCustomers(tester);
      await h.tap(pageText('Add customer'));
      await h.enterText(find.byKey(_name), 'Mona Hafez');
      final gate = h.server.hold('POST', '/customers');
      await h.tap(dialogButton('Add customer'));
      expect(
        tester.widget<DashButton>(dialogButton('Add customer')).loading,
        isTrue,
      );
      gate.release();
      h.server.clearFailures();
      await h.settle();
      await h.flushTimers();
    });

    testWidgets('SELL-CUS-024 closed mid-save: the reads refetch, the toast '
        'shows and the new sheet opens', (tester) async {
      final h = await pumpCustomers(tester);
      await h.tap(pageText('Add customer'));
      await h.enterText(find.byKey(_name), 'Mona Hafez');
      final gate = h.server.hold('POST', '/customers');
      await h.tap(dialogButton('Add customer'));
      Navigator.of(tester.element(find.byType(CustomerDialog))).pop();
      await h.settle();
      expect(find.byType(CustomerDialog), findsNothing);
      final reads = listCalls(h).length;
      gate.release();
      h.server.clearFailures();
      await h.settle();
      expect(listCalls(h).length, greaterThan(reads));
      expect(rowOf('Mona Hafez'), findsOneWidget);
      await h.expectToast('Customer added', keep: true);
      expect(find.byType(CustomerSheet), findsOneWidget);
      expect(sheetText('Mona Hafez'), findsOneWidget);
      await h.flushTimers();
    });

    testWidgets('SELL-CUS-032 an untouched Edit follows a fresher copy; '
        'typing stops it', (tester) async {
      final s = customersServer();
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openNada(h);
      await h.tap(sheetText('Edit'));
      String value(Key k) => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(k),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;
      expect(value(_phone), '01001234567');
      // A background refresh is in flight while the dialog shows the cached
      // copy; it lands with a newer phone.
      final gate = s.server.hold('GET', '/customers/{id}');
      h.container.read(realtimeBusProvider).invalidate(const ['/customers']);
      await h.settle();
      customerNamed(s.db, 'Nada Kamal')['phone'] = '01005550000';
      gate.release();
      s.server.clearFailures();
      await h.settle();
      expect(value(_phone), '01005550000');
      // Once typed into, the form keeps what was typed.
      await h.enterText(find.byKey(_name), 'Nada K.');
      customerNamed(s.db, 'Nada Kamal')['notes'] = 'Moved to Zamalek';
      h.container.read(realtimeBusProvider).invalidate(const ['/customers']);
      await h.settle();
      expect(value(_notes), '');
      expect(value(_name), 'Nada K.');
      await h.tap(dialogButton('Save'));
      expect(h.server.callsTo('/customers/{id}', method: 'PATCH').single.body, {
        'name': 'Nada K.',
        'phone': '01005550000',
        'notes': '',
      });
      await h.expectToast('Customer saved');
    });

    testWidgets('SELL-CUS-025 a phone already used goes on the field, no '
        'toast', (tester) async {
      final h = await pumpCustomers(tester);
      await h.tap(pageText('Add customer'));
      await h.enterText(find.byKey(_name), 'Nada Again');
      await h.enterText(find.byKey(_phone), '+20 100 123 4567');
      await h.tap(dialogButton('Add customer'));
      expect(
        inDialog(find.text('Another customer already has this phone number.')),
        findsOneWidget,
      );
      expect(find.byType(CustomerDialog), findsOneWidget);
      expect(find.text('Customer added'), findsNothing);
      // The phone box has the focus.
      final phone = tester.widget<EditableText>(
        find.descendant(
          of: find.byKey(_phone),
          matching: find.byType(EditableText),
        ),
      );
      expect(phone.focusNode.hasFocus, isTrue);
    });

    testWidgets('SELL-CUS-025 any other failure toasts the server\'s words', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await h.tap(pageText('Add customer'));
      await h.enterText(find.byKey(_name), 'Mona Hafez');
      final full = MockResponse.error(500, 'The disk is full');
      h.server.fail('POST', '/customers', full);
      await h.tap(dialogButton('Add customer'));
      await h.expectToast(h.refusalWords(full));
      expect(find.byType(CustomerDialog), findsOneWidget);
    });

    testWidgets('SELL-CUS-025 a refusal toasts "no permission"', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await h.tap(pageText('Add customer'));
      await h.enterText(find.byKey(_name), 'Mona Hafez');
      h.server.fail(
        'POST',
        '/customers',
        MockResponse.denied('customers.create'),
      );
      await h.tap(dialogButton('Add customer'));
      await h.expectToast(h.t('errors.unauthorized'));
    });
  });

  group('edit', () {
    testWidgets('SELL-CUS-032 Edit: prefilled, "" clears, toast, refetch', (
      tester,
    ) async {
      final s = customersServer();
      final c = nonMember(s.db)..['notes'] = 'Likes the window table.';
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await h.tap(rowOf(c['name']! as String));
      final reads = h.server.callsTo('/customers/{id}').length;
      await h.tap(sheetText('Edit'));
      expect(inDialog(find.text('Edit customer')), findsOneWidget);
      String value(Key k) => tester
          .widget<EditableText>(
            find.descendant(
              of: find.byKey(k),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;
      expect(value(_name), c['name']);
      expect(value(_phone), c['phone']);
      expect(value(_notes), 'Likes the window table.');
      await h.enterText(find.byKey(_phone), '');
      await h.enterText(find.byKey(_notes), '  ');
      await h.tap(dialogButton('Save'));
      final patch = h.server.callsTo('/customers/{id}', method: 'PATCH').single;
      expect(patch.path, '/customers/${c['id']}');
      expect(patch.body, {'name': c['name'], 'phone': '', 'notes': ''});
      await h.expectToast('Customer saved', keep: true);
      expect(find.byType(CustomerDialog), findsNothing);
      expect(h.server.callsTo('/customers/{id}').length, greaterThan(reads));
      expect(sheetText('Likes the window table.'), findsNothing);
      await h.flushTimers();
    });

    testWidgets('SELL-CUS-032 a phone clash on edit goes on the field', (
      tester,
    ) async {
      final s = customersServer();
      final c = nonMember(s.db);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await h.tap(rowOf(c['name']! as String));
      await h.tap(sheetText('Edit'));
      await h.enterText(find.byKey(_phone), '01001234567');
      await h.tap(dialogButton('Save'));
      expect(
        inDialog(find.text('Another customer already has this phone number.')),
        findsOneWidget,
      );
    });
  });

  group('erase', () {
    testWidgets('SELL-CUS-033 erase: confirm, toast, refetch, the sheet '
        'closes', (tester) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      final reads = listCalls(h).length;
      await h.tap(sheetText('Erase customer'));
      expect(find.text('Erase Nada Kamal?'), findsOneWidget);
      expect(find.text(h.t('customers.eraseBody')), findsOneWidget);
      await h.tap(dialogButton('Erase customer'));
      expect(
        h.server.callsTo('/customers/{id}/erase').single.path,
        '/customers/$nadaId/erase',
      );
      await h.expectToast('Customer erased', keep: true);
      expect(find.byType(CustomerSheet), findsNothing);
      expect(listCalls(h).length, greaterThan(reads));
      expect(rowOf('Nada Kamal'), findsNothing);
      await h.flushTimers();
    });

    testWidgets('SELL-CUS-033 Cancel erases nothing', (tester) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      await h.tap(sheetText('Erase customer'));
      await h.tap(find.text('Cancel').last);
      expect(h.server.callsTo('/customers/{id}/erase'), isEmpty);
      expect(find.byType(CustomerSheet), findsOneWidget);
    });

    testWidgets('SELL-CUS-033 a failure toasts and the sheet stays', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      h.server.fail(
        'POST',
        '/customers/{id}/erase',
        MockResponse.denied('customers.erase'),
      );
      await h.tap(sheetText('Erase customer'));
      await h.tap(dialogButton('Erase customer'));
      await h.expectToast(h.t('errors.unauthorized'));
      expect(find.byType(CustomerSheet), findsOneWidget);
    });
  });

  group('merge', () {
    testWidgets('SELL-CUS-034 the dialog, and it starts over each time', (
      tester,
    ) async {
      final s = customersServer();
      final x = pickable(s.db, (c) => c['is_member'] != true);
      final y = pickable(s.db, (c) => c['is_member'] != true, not: x['id']);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openSheet(h, x['id']! as String);
      await h.tap(sheetText('Merge into…'));
      expect(find.byType(MergeDialog), findsOneWidget);
      expect(
        inDialog(find.text('Merge into another customer')),
        findsOneWidget,
      );
      expect(
        inDialog(
          find.text(h.t('customers.mergeBody', args: {'name': x['name']})),
        ),
        findsOneWidget,
      );
      await pick(h, y['name']! as String);
      expect(inDialog(textHas("will move to ${y['name']}")), findsOneWidget);
      await h.tap(inDialog(find.text('Cancel')));
      await h.tap(sheetText('Merge into…'));
      expect(inDialog(find.text('Search by name or phone…')), findsOneWidget);
      expect(inDialog(textHas('will move to')), findsNothing);
    });

    testWidgets('SELL-CUS-035 the picker: 20 by server search, the opened '
        'one left out, members starred', (tester) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      final before = h.server.callsTo('/customers').length;
      await h.tap(sheetText('Merge into…'));
      // Asked as the dialog opens, before the picker does.
      expect(h.server.callsTo('/customers'), hasLength(before + 1));
      final call = h.server.callsTo('/customers').last;
      expect(q1(call), {'limit': '20'});
      await h.tap(find.byKey(const ValueKey('merge-pick')));
      // The picker opens on them: no second read.
      expect(h.server.callsTo('/customers'), hasLength(before + 1));
      expect(option('Nada Kamal'), findsNothing);
      final member = pickable(
        h.db!,
        (c) => c['is_member'] == true && c['id'] != nadaId,
      );
      expect(
        find.descendant(
          of: find.byType(MergeOptions),
          matching: find.byWidgetPredicate(
            (w) =>
                w is DashPressable &&
                w.semanticLabel == '${member['name']}, Member',
          ),
        ),
        findsOneWidget,
      );
      // The raw phone, unformatted.
      expect(
        find.descendant(
          of: find.byType(MergeOptions),
          matching: find.text(member['phone']! as String),
        ),
        findsOneWidget,
      );
      await h.enterText(find.byKey(const ValueKey('merge-search')), 'zzzz');
      await tester.pump(const Duration(milliseconds: 350));
      await h.settle();
      expect(q1(h.server.callsTo('/customers').last), {
        'q': 'zzzz',
        'limit': '20',
      });
      expect(find.text('No results found'), findsOneWidget);
    });

    testWidgets('SELL-CUS-035 "Loading…" while the search runs', (
      tester,
    ) async {
      final h = await pumpCustomers(tester);
      await openNada(h);
      final gate = h.server.hold('GET', '/customers');
      await h.tap(sheetText('Merge into…'));
      await h.tap(find.byKey(const ValueKey('merge-pick')));
      expect(find.text('Loading…'), findsOneWidget);
      gate.release();
      h.server.clearFailures();
      await h.settle();
      expect(find.text('Loading…'), findsNothing);
    });

    testWidgets('SELL-CUS-036 the summary once someone is picked', (
      tester,
    ) async {
      final s = customersServer();
      final x = pickable(s.db, (c) => c['is_member'] != true);
      final y = pickable(s.db, (c) => c['is_member'] != true, not: x['id']);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openSheet(h, x['id']! as String);
      await h.tap(sheetText('Merge into…'));
      final merge = dialogButton('Merge');
      expect(tester.widget<DashButton>(merge).onPressed, isNull);
      await pick(h, y['name']! as String);
      expect(
        inDialog(
          find.text(
            "${x['name']}'s orders will move to ${y['name']}, and "
            "${x['name']} will be removed. This can't be undone.",
          ),
        ),
        findsOneWidget,
      );
      expect(tester.widget<DashButton>(merge).onPressed, isNotNull);
    });

    testWidgets('SELL-CUS-037 only the opened one is a member: turned round', (
      tester,
    ) async {
      final s = customersServer();
      final y = pickable(s.db, (c) => c['is_member'] != true);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openNada(h);
      await h.tap(sheetText('Merge into…'));
      await pick(h, y['name']! as String);
      expect(
        inDialog(
          find.text(
            h.t(
              'customers.mergeMemberStays',
              args: {'member': 'Nada Kamal', 'other': y['name']},
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(dialogButton('Merge into Nada Kamal'), findsOneWidget);
      await h.tap(dialogButton('Merge into Nada Kamal'));
      final post = h.server.callsTo('/customers/{id}/merge').single;
      expect(post.path, '/customers/${y['id']}/merge');
      expect(post.body, {'into': nadaId});
      await h.expectToast('Customers merged');
    });

    testWidgets('SELL-CUS-038 both members: the points note', (tester) async {
      final s = customersServer();
      final y = pickable(
        s.db,
        (c) => c['is_member'] == true && c['id'] != nadaId,
      );
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openNada(h);
      await h.tap(sheetText('Merge into…'));
      await pick(h, y['name']! as String);
      expect(
        inDialog(
          find.text(
            h.t(
              'customers.mergeBothMembers',
              args: {'from': 'Nada Kamal', 'into': y['name']},
            ),
          ),
        ),
        findsOneWidget,
      );
      expect(dialogButton('Merge'), findsOneWidget);
    });

    testWidgets('SELL-CUS-039 merge: toast, refetch, the sheet follows the '
        'kept one', (tester) async {
      final s = customersServer();
      final x = pickable(s.db, (c) => c['is_member'] != true);
      final y = pickable(s.db, (c) => c['is_member'] != true, not: x['id']);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await h.tap(rowOf(x['name']! as String));
      final reads = listCalls(h).length;
      await h.tap(sheetText('Merge into…'));
      await pick(h, y['name']! as String);
      await h.tap(dialogButton('Merge'));
      final post = h.server.callsTo('/customers/{id}/merge').single;
      expect(post.path, '/customers/${x['id']}/merge');
      expect(post.body, {'into': y['id']});
      await h.expectToast('Customers merged', keep: true);
      expect(find.byType(MergeDialog), findsNothing);
      expect(sheetText(y['name']! as String), findsOneWidget);
      expect(rowSelected(tester, y['name']! as String), isTrue);
      expect(listCalls(h).length, greaterThan(reads));
      expect(rowOf(x['name']! as String), findsNothing);
      await h.flushTimers();
    });

    testWidgets('SELL-CUS-039 the member-must-stay refusal turns it round, '
        'no toast', (tester) async {
      final s = customersServer();
      final x = pickable(s.db, (c) => c['is_member'] != true);
      final y = pickable(s.db, (c) => c['is_member'] != true, not: x['id']);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openSheet(h, x['id']! as String);
      await h.tap(sheetText('Merge into…'));
      await pick(h, y['name']! as String);
      h.server.fail(
        'POST',
        '/customers/{id}/merge',
        MockResponse.error(
          409,
          'must stay',
          code: 'CUSTOMER_MERGE_MEMBER_SURVIVES',
        ),
      );
      await h.tap(dialogButton('Merge'));
      expect(find.byType(MergeDialog), findsOneWidget);
      expect(find.text('must stay'), findsNothing);
      expect(
        inDialog(
          find.text(
            h.t(
              'customers.mergeMemberStays',
              args: {'member': x['name'], 'other': y['name']},
            ),
          ),
        ),
        findsOneWidget,
      );
      await h.tap(dialogButton('Merge into ${x['name']}'));
      final second = h.server.callsTo('/customers/{id}/merge').last;
      expect(second.path, '/customers/${y['id']}/merge');
      expect(second.body, {'into': x['id']});
      await h.expectToast('Customers merged');
    });

    testWidgets('SELL-CUS-039 another failure toasts; Cancel closes', (
      tester,
    ) async {
      final s = customersServer();
      final x = pickable(s.db, (c) => c['is_member'] != true);
      final y = pickable(s.db, (c) => c['is_member'] != true, not: x['id']);
      final h = await pumpCustomers(tester, server: s.server, db: s.db);
      await openSheet(h, x['id']! as String);
      await h.tap(sheetText('Merge into…'));
      await pick(h, y['name']! as String);
      h.server.fail(
        'POST',
        '/customers/{id}/merge',
        MockResponse.denied('customers.merge'),
      );
      await h.tap(dialogButton('Merge'));
      await h.expectToast(h.t('errors.unauthorized'));
      expect(find.byType(MergeDialog), findsOneWidget);
      await h.tap(inDialog(find.text('Cancel')));
      expect(find.byType(MergeDialog), findsNothing);
    });
  });
}
