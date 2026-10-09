// Inventory settings, the category actions driven through the real shell:
// add, rename, packaging, delete with its reassign dialog, and the server's
// refusals (INV-SET-010, 012-016, 020, 021, 023, 026).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_inventory/src/area_seed.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Finder get _newName => inPage(byKey('inv-settings-new-name'));
Finder get _add => inPage(byKey('inv-settings-add'));
Finder get _rename => inPage(byKey('inv-category-rename'));
Finder _edit(String slug) =>
    inRow(slug, byKey('inv-category-edit-${cat(slug)}'));
Finder _trash(String slug) =>
    inRow(slug, byKey('inv-category-delete-${cat(slug)}'));
Finder _switch(String slug) => inRow(slug, find.byType(DashSwitch));
Finder get _confirm => inDialog(byKey('inv-delete-category-confirm'));

bool _enabled(WidgetTester tester, Finder f) =>
    tester.widget<DashButton>(f).onPressed != null;

String _text(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(
      find.descendant(of: field, matching: find.byType(EditableText)),
    )
    .controller
    .text;

int _gets(DashHarness h) =>
    h.server.callsTo(categoriesRoute, method: 'GET').length;

void main() {
  group('INV-SET-020 add a category', () {
    testWidgets('"Category name" + Add (disabled while blank) POSTs the name, '
        'refetches and clears the input; no toast', (tester) async {
      final h = await pumpSettings(tester);
      expect(_enabled(tester, _add), isFalse);
      expect(
        find.descendant(of: _newName, matching: find.text('Category name')),
        findsOneWidget,
      );
      await h.enterText(_newName, '  Seasonal  ');
      expect(_enabled(tester, _add), isTrue);
      await h.tap(_add);
      final post = h.server.callsTo(categoriesRoute, method: 'POST').single;
      expect(post.path, '/inventory/orgs/$org/categories');
      expect(post.body, {'name': 'Seasonal'});
      expect(_gets(h), 2);
      expect(_text(tester, _newName), '');
      expect(inList(find.text('Seasonal')), findsOneWidget);
      expect(inList(textHas('seasonal · 0 ingredients')), findsOneWidget);
      // No toast: a toast's timer left running would fail the test.
    });

    testWidgets('Enter in the input adds too', (tester) async {
      final h = await pumpSettings(tester);
      await h.enterText(_newName, 'Tea');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(h.server.callsTo(categoriesRoute, method: 'POST').single.body, {
        'name': 'Tea',
      });
      expect(inList(find.text('Tea')), findsOneWidget);
    });

    testWidgets('no letter or digit: the server\'s 400 is a toast; the name '
        'stays', (tester) async {
      final h = await pumpSettings(tester);
      await h.enterText(_newName, '!!!');
      await h.tap(_add);
      await h.expectToast(
        h.refusalWords(
          MockResponse.badRequest(
            'Category name must contain a letter or digit',
          ),
        ),
      );
      expect(_text(tester, _newName), '!!!');
    });

    testWidgets('a key that exists: the server\'s 409 is a toast', (
      tester,
    ) async {
      final h = await pumpSettings(tester);
      await h.enterText(_newName, 'Milk');
      await h.tap(_add);
      await h.expectToast(
        h.refusalWords(
          MockResponse.conflict(
            "A category with the key 'milk' already exists",
          ),
        ),
      );
    });

    testWidgets('INV-SET-023 a manager (no inventory.items.create): Add is '
        'offered and the server\'s 403 is a toast', (tester) async {
      final h = await pumpSettings(tester, persona: Persona.manager);
      await h.enterText(_newName, 'Tea');
      await h.tap(_add);
      expect(
        h.server.callsTo(categoriesRoute, method: 'POST').single.status,
        403,
      );
      await h.expectToast(
        h.refusalWords(MockResponse.denied('inventory.items.create')),
      );
      expect(inList(find.text('Tea')), findsNothing);
    });
  });

  group('INV-SET-010 / 026 the packaging switch', () {
    testWidgets('aria "{{name}} is packaging"; toggling PATCHes is_packaging '
        'and refetches; no toast', (tester) async {
      final h = await pumpSettings(tester);
      expect(tester.widget<DashSwitch>(_switch('packaging')).value, isTrue);
      expect(tester.widget<DashSwitch>(_switch('milk')).value, isFalse);
      expect(
        tester.widget<DashSwitch>(_switch('milk')).semanticLabel,
        'Milk is packaging',
      );
      expect(inRow('milk', find.text('Packaging')), findsOneWidget);
      await h.tap(_switch('milk'));
      final patch = h.server.callsTo(categoryRoute, method: 'PATCH').single;
      expect(patch.path, '/inventory/orgs/$org/categories/${cat('milk')}');
      expect(patch.body, {'is_packaging': true});
      expect(_gets(h), 2);
      expect(tester.widget<DashSwitch>(_switch('milk')).value, isTrue);
      // No toast: a toast's timer left running would fail the test.
    });

    testWidgets('INV-SET-026 not optimistic: the switch keeps the server\'s '
        'value until the PATCH and refetch land', (tester) async {
      final s = settingsServer();
      final gate = s.server.hold('PATCH', categoryRoute);
      final h = await pumpSettings(tester, server: s.server, db: s.db);
      await h.tap(_switch('milk'));
      expect(tester.widget<DashSwitch>(_switch('milk')).value, isFalse);
      // Several rows at once: no per-row lock.
      await h.tap(_switch('bakery'));
      expect(s.server.callsTo(categoryRoute, method: 'PATCH'), hasLength(2));
      gate.release();
      await h.settle();
      expect(tester.widget<DashSwitch>(_switch('milk')).value, isTrue);
      expect(tester.widget<DashSwitch>(_switch('bakery')).value, isTrue);
    });

    testWidgets('INV-SET-010 the word "Packaging" (the web\'s <label>) '
        'toggles the switch too', (tester) async {
      final h = await pumpSettings(tester);
      Finder word(String slug) =>
          inRow(slug, byKey('inv-category-packaging-label-${cat(slug)}'));
      expect(
        find.descendant(of: word('milk'), matching: find.text('Packaging')),
        findsOneWidget,
      );
      await h.tap(word('milk'));
      final patch = h.server.callsTo(categoryRoute, method: 'PATCH').single;
      expect(patch.path, '/inventory/orgs/$org/categories/${cat('milk')}');
      expect(patch.body, {'is_packaging': true});
      expect(tester.widget<DashSwitch>(_switch('milk')).value, isTrue);
      await h.tap(word('packaging'));
      expect(
        h.server.callsTo(categoryRoute, method: 'PATCH').last.body,
        {'is_packaging': false},
      );
    });

    testWidgets('a failure is a toast and the switch stays', (tester) async {
      final s = settingsServer();
      s.server.fail('PATCH', categoryRoute, MockResponse.error(500, 'boom'));
      final h = await pumpSettings(tester, server: s.server, db: s.db);
      await h.tap(_switch('milk'));
      await h.expectToast(h.refusalWords(MockResponse.error(500, 'boom')));
      expect(tester.widget<DashSwitch>(_switch('milk')).value, isFalse);
    });
  });

  group('INV-SET-012 / 021 rename inline', () {
    testWidgets('the pencil (aria "Edit") opens a focused input with ✓ and ✕; '
        'Enter PATCHes the trimmed name and returns to the view', (
      tester,
    ) async {
      final h = await pumpSettings(tester);
      await h.tap(_edit('milk'));
      expect(_rename, findsOneWidget);
      expect(_text(tester, _rename), 'Milk');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(of: _rename, matching: find.byType(EditableText)),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(
        tester
            .widget<DashIconButton>(inPage(byKey('inv-category-rename-save')))
            .semanticLabel,
        'Save',
      );
      expect(
        tester
            .widget<DashIconButton>(inPage(byKey('inv-category-rename-cancel')))
            .semanticLabel,
        'Cancel',
      );
      await h.enterText(_rename, ' Fresh milk ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      final patch = h.server.callsTo(categoryRoute, method: 'PATCH').single;
      expect(patch.body, {'name': 'Fresh milk'});
      expect(_rename, findsNothing);
      expect(inRow('milk', find.text('Fresh milk')), findsOneWidget);
      expect(
        inRow('milk', textHas('milk ·')),
        findsOneWidget,
        reason: 'the key is unchanged',
      );
      // No toast: a toast's timer left running would fail the test.
    });

    testWidgets('✓ saves too; a blank name asks nothing', (tester) async {
      final h = await pumpSettings(tester);
      await h.tap(_edit('bakery'));
      await h.enterText(_rename, '   ');
      await h.tap(inPage(byKey('inv-category-rename-save')));
      expect(h.server.callsTo(categoryRoute, method: 'PATCH'), isEmpty);
      expect(_rename, findsOneWidget);
      await h.enterText(_rename, 'Pastry');
      await h.tap(inPage(byKey('inv-category-rename-save')));
      expect(h.server.callsTo(categoryRoute, method: 'PATCH').single.body, {
        'name': 'Pastry',
      });
      expect(inRow('bakery', find.text('Pastry')), findsOneWidget);
    });

    testWidgets('Escape and ✕ cancel without a request', (tester) async {
      final h = await pumpSettings(tester);
      await h.tap(_edit('milk'));
      await h.enterText(_rename, 'Oat');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(_rename, findsNothing);
      expect(inRow('milk', find.text('Milk')), findsOneWidget);
      await h.tap(_edit('milk'));
      await h.tap(inPage(byKey('inv-category-rename-cancel')));
      expect(_rename, findsNothing);
      expect(h.server.callsTo(categoryRoute, method: 'PATCH'), isEmpty);
    });

    testWidgets('a failure is a toast and the editor stays', (tester) async {
      final h = await pumpSettings(tester);
      await h.tap(_edit('milk'));
      await h.enterText(_rename, 'M' * 81);
      await h.tap(inPage(byKey('inv-category-rename-save')));
      await h.expectToast(
        h.refusalWords(
          MockResponse.badRequest('Category name must be 1–80 characters'),
        ),
      );
      expect(_rename, findsOneWidget);
    });

    testWidgets('INV-SET-021 one row at a time: a second pencil moves the '
        'editor', (tester) async {
      final h = await pumpSettings(tester);
      await h.tap(_edit('milk'));
      await h.tap(_edit('bakery'));
      expect(_rename, findsOneWidget);
      expect(
        find.descendant(of: row('bakery'), matching: _rename),
        findsOneWidget,
      );
      expect(inRow('milk', find.text('Milk')), findsOneWidget);
    });
  });

  group('INV-SET-013..016 delete', () {
    testWidgets('INV-SET-013 a trash button (aria "Delete") on every '
        'category but General', (tester) async {
      await pumpSettings(tester);
      for (final c in invCategories) {
        expect(
          _trash(c.slug),
          c.slug == 'general' ? findsNothing : findsOneWidget,
          reason: c.slug,
        );
      }
      expect(
        tester.widget<DashIconButton>(_trash('milk')).semanticLabel,
        'Delete',
      );
    });

    testWidgets('INV-SET-014/015/016 in use: title, reassign description, '
        '"Move ingredients to" every other category; Delete waits for a '
        'pick, then DELETEs with reassign_to and toasts "Done"', (
      tester,
    ) async {
      final s = settingsServer();
      final users = usersOf(s.db, 'milk');
      final dairyBefore = usersOf(s.db, 'dairy');
      final h = await pumpSettings(tester, server: s.server, db: s.db);
      await h.tap(_trash('milk'));
      expect(inDialog(find.text('Delete "Milk"?')), findsOneWidget);
      expect(
        inDialog(
          find.text(
            '$users ingredients use this category. Choose where they should '
            'move. The category is removed from counts and reports.',
          ),
        ),
        findsOneWidget,
      );
      expect(inDialog(find.text('Move ingredients to')), findsOneWidget);
      expect(inDialog(find.text('Category')), findsOneWidget);
      expect(_enabled(tester, _confirm), isFalse);
      final select = tester.widget<DashSelectField<String>>(
        inDialog(find.byType(DashSelectField<String>)),
      );
      expect(select.options.map((o) => o.value), [
        for (final c in invCategories)
          if (c.slug != 'milk') cat(c.slug),
      ]);
      await h.tap(inDialog(byKey('inv-delete-category-target')));
      await h.tap(
        find
            .descendant(
              of: find.byWidgetPredicate((w) => w is DashOptionList),
              matching: find.text('Dairy & Eggs'),
            )
            .hitTestable()
            .last,
      );
      expect(_enabled(tester, _confirm), isTrue);
      await h.tap(_confirm);
      final del = s.server.callsTo(categoryRoute, method: 'DELETE').single;
      expect(del.path, '/inventory/orgs/$org/categories/${cat('milk')}');
      expect(del.query, {
        'reassign_to': [cat('dairy')],
      });
      expect(dialog, findsNothing);
      await h.expectToast('Done');
      expect(row('milk'), findsNothing);
      expect(
        inRow('dairy', textHas('dairy · ${dairyBefore + users} ingredients')),
        findsOneWidget,
      );
    });

    testWidgets('INV-SET-014/016 empty: "This category has no ingredients.", '
        'no picker, DELETE without reassign_to', (tester) async {
      final s = settingsServer();
      final id = addEmptyCategory(s.db);
      final h = await pumpSettings(tester, server: s.server, db: s.db);
      await h.tap(_trash('seasonal'));
      expect(
        inDialog(
          find.text(
            'This category has no ingredients. The category is removed from '
            'counts and reports.',
          ),
        ),
        findsOneWidget,
      );
      expect(inDialog(find.byType(DashSelectField<String>)), findsNothing);
      expect(_enabled(tester, _confirm), isTrue);
      await h.tap(_confirm);
      final del = s.server.callsTo(categoryRoute, method: 'DELETE').single;
      expect(del.path, '/inventory/orgs/$org/categories/$id');
      expect(del.query, isEmpty);
      await h.expectToast('Done');
      expect(inList(find.text('Seasonal')), findsNothing);
    });

    testWidgets('INV-SET-012/014 the dialog follows the live row: a refresh '
        'that gives the category ingredients shows the picker', (tester) async {
      final s = settingsServer();
      final id = addEmptyCategory(s.db);
      final h = await pumpSettings(tester, server: s.server, db: s.db);
      await h.tap(_trash('seasonal'));
      expect(inDialog(find.byType(DashSelectField<String>)), findsNothing);
      final ing = s.db[InvTables.ingredients]
          .where((i) => i['category_id'] == cat('milk'))
          .first;
      s.db[InvTables.ingredients].update(ing['id']! as String, {
        'category_id': id,
      });
      h.container.read(realtimeBusProvider).invalidate(const ['/inventory']);
      await h.settle();
      expect(
        inDialog(textHas('1 ingredient uses this category')),
        findsOneWidget,
      );
      expect(inDialog(find.byType(DashSelectField<String>)), findsOneWidget);
      expect(_enabled(tester, _confirm), isFalse);
    });

    testWidgets('INV-SET-016 Cancel closes without a request', (tester) async {
      final h = await pumpSettings(tester);
      await h.tap(_trash('milk'));
      await h.tap(inDialog(find.text('Cancel')));
      expect(dialog, findsNothing);
      expect(h.server.callsTo(categoryRoute, method: 'DELETE'), isEmpty);
    });

    testWidgets('INV-SET-016 a failure is a toast; the dialog stays open', (
      tester,
    ) async {
      final s = settingsServer();
      final refusal = MockResponse.conflict(
        '3 ingredient(s) use this category. Pass reassign_to to move them '
        'first.',
      );
      s.server.fail('DELETE', categoryRoute, refusal);
      final h = await pumpSettings(tester, server: s.server, db: s.db);
      await h.tap(_trash('milk'));
      tester
          .widget<DashSelectField<String>>(
            inDialog(find.byType(DashSelectField<String>)),
          )
          .onChanged(cat('dairy'));
      await h.settle();
      await h.tap(_confirm);
      await h.expectToast(h.refusalWords(refusal));
      expect(dialog, findsOneWidget);
      expect(row('milk'), findsOneWidget);
    });

    testWidgets('INV-SET-023 a manager (no inventory.items.delete): Delete '
        'is offered and the server\'s 403 is a toast', (tester) async {
      final s = settingsServer(persona: Persona.manager);
      final id = addEmptyCategory(s.db);
      final h = await pumpSettings(
        tester,
        persona: Persona.manager,
        server: s.server,
        db: s.db,
      );
      await h.tap(_trash('seasonal'));
      await h.tap(_confirm);
      expect(
        s.server.callsTo(categoryRoute, method: 'DELETE').single.status,
        403,
      );
      await h.expectToast(
        h.refusalWords(MockResponse.denied('inventory.items.delete')),
      );
      expect(s.db[InvTables.categories].find(id), isNotNull);
    });
  });
}
