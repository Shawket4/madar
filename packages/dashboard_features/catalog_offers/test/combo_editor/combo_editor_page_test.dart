// The combo editor driven through the real shell: the page frame and its
// states, the header, the General section, the save bar, Save, Delete, the
// image, and the refusals.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_catalog_offers/src/combo_editor/combo_editor_page.dart';
import 'package:dashboard_catalog_offers/src/shared/offers_cache.dart';
import 'package:dashboard_core/dashboard_core.dart'
    show PickedFile, realtimeBusProvider;
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _combo = '/combos/{id}';
const _create = '/combos';
const _econ = '/combos/economics';
const _upload = '/uploads/menu-items/{menu_item_id}';

final _morning = OffersSeed.comboId('morning-croissant');

/// Fills a new combo up to a valid one: "Burger meal" is "Butter Croissant"
/// here (the seed has no burger), EGP 150, one slot "Main".
Future<void> _fillValid(DashHarness h) async {
  await typeInto(h, 'Name', 'Breakfast deal');
  await typeInto(h, 'Combo price', '150');
  await typeInto(h, 'Slot name', 'Main');
  await choose(h, 'Choose an item', 'Butter Croissant', search: 'Butter');
}

Finder get _saveBarSave => labelled('Save');

/// A link row: its name, then its hint (both reach a screen reader).
Finder _link(String label) =>
    inEditor(find.bySemanticsLabel(RegExp('^${RegExp.escape(label)}, ')));

/// Every prefix the bus is asked to refresh from now on.
List<List<String>> _recordInvalidations(DashHarness h) {
  final seen = <List<String>>[];
  final sub = h.container
      .read(realtimeBusProvider)
      .invalidations
      .listen(seen.add);
  addTearDown(sub.cancel);
  return seen;
}

void main() {
  group('page frame and states', () {
    testWidgets('OFFR-CED-001/003/006 an existing combo loads once, seeded '
        'with nothing unsaved; the pick lists are asked', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('morning-croissant'));
      final gets = h.server.callsTo(_combo, method: 'GET');
      expect(gets, hasLength(1));
      expect(gets.single.path, '/combos/$_morning');
      expect(gets.single.query, isEmpty);
      final items = h.server.callsTo('/menu-items', method: 'GET');
      expect(items.single.query['full'], ['true']);
      expect(h.server.callsTo('/categories', method: 'GET'), hasLength(1));
      expect(h.server.callsTo('/branches', method: 'GET'), isNotEmpty);

      expect(labelled('Category: Bakery'), findsOneWidget);
      expect(editorText('All changes saved'), findsOneWidget);
      expect(editorText('Unsaved changes'), findsNothing);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: labelled('Name'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Morning Croissant Combo',
      );
    });

    testWidgets('OFFR-CED-001/087 /menu/combos/new opens an empty create form', (
      tester,
    ) async {
      final h = await pumpEditor(tester);
      expect(h.server.callsTo(_combo, method: 'GET'), isEmpty);
      expect(editorText('New combo'), findsWidgets);
      expect(editorText('Not saved yet'), findsOneWidget);
      expect(labelled('Create combo'), findsOneWidget);
      expect(labelled('Slot name'), findsOneWidget);
      expect(editorText('Pick 1'), findsOneWidget);
      expect(labelledSelect('Choose an item'), findsOneWidget);
      expect(editorText('Always available'), findsOneWidget);
      expect(
        editorText(
          'Enter a price and at least one slot with a choice to see the figures.',
        ),
        findsOneWidget,
      );
      expect(h.server.callsTo(_econ), isEmpty);
    });

    testWidgets('OFFR-CED-002 without menu.items.read: Restricted, titled '
        '"Combos" (or "New combo"), nothing asked', (tester) async {
      final s = editorServerWithCaps(['orders.read']);
      final h = await pumpEditor(
        tester,
        path: comboPath('morning-croissant'),
        server: s.server,
        db: s.db,
      );
      expect(editorText('Not available on this account'), findsOneWidget);
      expect(
        editorText(
          'This is managed by Madar. Get in touch if you need a change here.',
        ),
        findsOneWidget,
      );
      expect(editorText('Combos'), findsOneWidget);
      expect(h.server.callsTo(_combo), isEmpty);

      await h.go(newComboPath);
      expect(editorText('New combo'), findsOneWidget);
    });

    testWidgets('OFFR-CED-004 loading: back button and skeletons, then the '
        'form', (tester) async {
      final s = editorServer();
      final gate = s.server.hold('GET', _combo);
      final h = await DashHarness.pump(
        tester,
        areas: const [catalogOffersArea],
        path: comboPath('coffee-cookie'),
        server: s.server,
        db: s.db,
      );
      expect(labelled('Back'), findsOneWidget);
      expect(inEditor(find.byType(DashSkeleton)), findsNWidgets(3));
      expect(labelled('Name'), findsNothing);
      gate.release();
      await debounce(h);
      expect(labelled('Name'), findsOneWidget);
      expect(inEditor(find.byType(DashSkeleton)), findsNothing);
    });

    testWidgets('OFFR-ALL-018 (divergence) while the rights load: the '
        'skeleton and nothing asked; then the form', (tester) async {
      final s = editorServer();
      final rights = s.server.hold('GET', '/authz/me');
      final h = await DashHarness.pump(
        tester,
        areas: const [catalogOffersArea],
        path: comboPath('coffee-cookie'),
        server: s.server,
        db: s.db,
      );
      expect(labelled('Back'), findsOneWidget);
      expect(inEditor(find.byType(DashSkeleton)), findsNWidgets(3));
      expect(h.server.callsTo(_combo), isEmpty);
      rights.release();
      await debounce(h);
      expect(labelled('Name'), findsOneWidget);
    });

    testWidgets('OFFR-CED-005 a failed load: "Couldn\'t load this combo", the '
        'server\'s words, Retry asks again (the error stays while it runs)', (
      tester,
    ) async {
      final s = editorServer();
      final refusal = MockResponse.error(500, 'The menu store is down');
      s.server.fail('GET', _combo, refusal, times: null);
      final h = await pumpEditor(
        tester,
        path: comboPath('coffee-cookie'),
        server: s.server,
        db: s.db,
      );
      expect(editorText("Couldn't load this combo"), findsOneWidget);
      expect(editorText(h.refusalWords(refusal)), findsOneWidget);
      expect(editorText('Combos'), findsOneWidget);
      s.server.clearFailures();
      final gate = s.server.hold('GET', _combo);
      await tapLabelled(h, 'Retry');
      expect(editorText("Couldn't load this combo"), findsOneWidget);
      expect(inEditor(find.byType(DashSkeleton)), findsNothing);
      expect(
        tester
            .widget<DashErrorState>(inEditor(find.byType(DashErrorState)))
            .retrying,
        isTrue,
      );
      gate.release();
      await debounce(h);
      expect(h.server.callsTo(_combo, method: 'GET'), hasLength(2));
      expect(labelled('Name'), findsOneWidget);
    });

    testWidgets('OFFR-CED-080 a deep link to an unknown combo shows the '
        'server\'s words', (tester) async {
      final h = await pumpEditor(
        tester,
        path: '/menu/combos/${mockUuid('gone')}',
      );
      expect(editorText("Couldn't load this combo"), findsOneWidget);
      expect(
        editorText(h.refusalWords(MockResponse.notFound('Combo not found'))),
        findsOneWidget,
      );
    });

    testWidgets('OFFR-CED-006 a background refetch never overwrites what is '
        'being typed', (tester) async {
      final h = await pumpEditor(
        tester,
        path: comboPath('coffee-cookie'),
        branch: SeedIds.maadi,
      );
      await typeInto(h, 'Name', 'Coffee & Cookie (new)');
      h.realtime.current!.emit('resync', data: '{}');
      await debounce(h);
      expect(h.server.callsTo(_combo, method: 'GET').length, greaterThan(1));
      expect(editorText('Coffee & Cookie (new)'), findsWidgets);
      expect(editorText('Unsaved changes'), findsOneWidget);
    });

    testWidgets('OFFR-CED-006 (divergence) an untouched form follows a '
        'background refresh, and a cached combo older than 30 s is '
        'refreshed on opening', (tester) async {
      final h = await pumpEditor(
        tester,
        path: comboPath('coffee-cookie'),
        branch: SeedIds.maadi,
      );
      final row = h.db!
          .table(OffersTables.menuItems)
          .get(OffersSeed.comboId('coffee-cookie'));
      String price() => tester
          .widget<EditableText>(
            find.descendant(
              of: labelled('Combo price'),
              matching: find.byType(EditableText),
            ),
          )
          .controller
          .text;
      expect(price(), '120');
      row['base_price'] = 13000;
      h.realtime.current!.emit('resync', data: '{}');
      await debounce(h);
      expect(price(), '130');
      expect(editorText('All changes saved'), findsOneWidget);
      await typeInto(h, 'Name', 'Coffee & Cookie Deal');
      await tapLabelled(h, 'Save');
      expect(
        (h.server.callsTo(_combo, method: 'PUT').single.body! as Map)['price'],
        13000,
      );
      await h.expectToast('Changes saved');

      // Leave, let it age, come back: shown at once, then refreshed.
      await h.go('/menu/combos');
      row['base_price'] = 14000;
      h.db!.clock.advance(const Duration(seconds: 31));
      final gets = h.server.callsTo(_combo, method: 'GET').length;
      await h.go(comboPath('coffee-cookie'));
      await debounce(h);
      expect(h.server.callsTo(_combo, method: 'GET'), hasLength(gets + 1));
      expect(price(), '140');
    });

    testWidgets('OFFR-CED-003/ALL-005 the pick lists are kept like web '
        'queries: fresh for their own 5 minutes, asked again after', (
      tester,
    ) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      int items() => h.server.callsTo('/menu-items', method: 'GET').length;
      // The list in between asks for its own categories: count only what
      // opening the editor asks.
      int cats() => h.server.callsTo('/categories', method: 'GET').length;
      expect((items(), cats()), (1, 1));
      await h.go('/menu/combos');
      var before = cats();
      h.db!.clock.advance(const Duration(seconds: 31));
      await h.go(comboPath('kids-cocoa'));
      await debounce(h);
      expect((items(), cats()), (1, before));
      await h.go('/menu/combos');
      h.db!.clock.advance(const Duration(minutes: 5));
      before = cats();
      await h.go(comboPath('coffee-cookie'));
      await debounce(h);
      expect((items(), cats()), (2, before + 1));
    });

    testWidgets('OFFR-CED-014 two columns from 1024 wide (the price check '
        'beside the form), one column below', (tester) async {
      await pumpEditor(tester, path: comboPath('coffee-cookie'));
      final check = labelled('Price check').first;
      final name = labelled('Name');
      expect(
        tester.getTopLeft(check).dx,
        greaterThan(tester.getTopRight(name).dx),
      );
    });

    testWidgets('OFFR-CED-014 below 1024 wide the price check follows the '
        'sections', (tester) async {
      final h = await pumpEditor(
        tester,
        path: comboPath('coffee-cookie'),
        size: DashSize.phone,
      );
      await h.tester.ensureVisible(labelled('Price check').first);
      await h.settle();
      expect(
        tester.getTopLeft(labelled('Price check').first).dx,
        tester.getTopLeft(_link('Branch prices and on/off')).dx,
      );
    });
  });

  group('header', () {
    testWidgets('OFFR-CED-007/076 the title follows the Name as typed; Back '
        'returns to the list without asking', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      expect(editorText('Coffee & Cookie'), findsWidgets);
      await typeInto(h, 'Name', '');
      expect(editorText('Untitled combo'), findsOneWidget);
      await typeInto(h, 'Name', 'Afternoon pick-me-up');
      expect(editorText('Afternoon pick-me-up'), findsWidgets);
      // OFFR-CED-076: unsaved changes, and still no prompt.
      expect(editorText('Unsaved changes'), findsOneWidget);
      h.allowUnmatched = true;
      await tapLabelled(h, 'Back');
      expect(h.location.path, '/menu/combos');
      expect(find.byType(ComboEditorPage), findsNothing);
    });

    testWidgets('OFFR-CED-008/009 the Fixed bundle / Meal deal and Inactive '
        'pills follow the form', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      expect(editorText('Fixed bundle'), findsOneWidget);
      expect(editorText('Inactive'), findsNothing);
      await tapLabelled(h, 'Add an item');
      expect(editorText('Meal deal'), findsOneWidget);
      await h.tap(inEditor(find.byType(DashSwitch)));
      await debounce(h);
      expect(editorText('Inactive'), findsOneWidget);
    });

    testWidgets('OFFR-CED-010/013/085 read-only without menu.combos.edit: '
        'disabled fields, no add or remove, no Save, no Delete', (
      tester,
    ) async {
      await pumpEditor(
        tester,
        path: comboPath('morning-croissant'),
        persona: Persona.manager,
      );
      expect(editorText('Read only'), findsOneWidget);
      for (final label in ['Name', 'Combo price', 'Slot name']) {
        final field = tester.widget<TextField>(
          find.descendant(
            of: labelled(label).first,
            matching: find.byType(TextField),
          ),
        );
        expect(field.enabled, isFalse, reason: label);
      }
      for (final label in [
        'Save',
        'Delete',
        'Add a slot',
        'Add an item',
        'Add a whole category',
        'Add a window',
        'Move up',
        'Remove this slot',
        'Remove this choice',
      ]) {
        expect(labelled(label), findsNothing, reason: label);
      }
      expect(editorText('All changes saved'), findsNothing);
      final category = tester.widget<DashSelectTrigger>(
        around(labelledSelect('Category'), DashSelectTrigger),
      );
      expect(category.enabled, isFalse);
      final uploader = tester.widget<DashImageUploader>(
        inEditor(find.byType(DashImageUploader)),
      );
      expect(uploader.enabled, isFalse);
    });

    testWidgets('OFFR-CED-087 /menu/combos/new read-only: Meal deal and Read '
        'only, no save bar, only the pick lists asked', (tester) async {
      final h = await pumpEditor(tester, persona: Persona.manager);
      expect(editorText('New combo'), findsWidgets);
      expect(editorText('Meal deal'), findsOneWidget);
      expect(editorText('Read only'), findsOneWidget);
      expect(labelled('Create combo'), findsNothing);
      expect(h.server.callsTo(_combo), isEmpty);
      expect(h.server.callsTo(_econ), isEmpty);
    });

    testWidgets('OFFR-CED-011/012 Delete asks first; Cancel keeps it; '
        'confirmed it deletes, says so and returns to the list', (
      tester,
    ) async {
      final h = await pumpEditor(tester, path: comboPath('morning-croissant'));
      // An outline button with red text, as on the web.
      final delete = inEditor(
        find.byWidgetPredicate((w) => w is DashButton && w.label == 'Delete'),
      );
      expect(
        tester.widget<DashButton>(delete).variant,
        DashButtonVariant.outlineDanger,
      );
      await typeInto(h, 'Name', 'Morning Croissant');
      await tapLabelled(h, 'Delete');
      expect(find.text('Delete Morning Croissant?'), findsOneWidget);
      expect(
        find.text(
          'It leaves the menu at every branch and on every channel. Past '
          'orders keep their lines and still show in the Bundles report.',
        ),
        findsOneWidget,
      );
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Cancel'),
        ),
      );
      expect(h.server.callsTo('/menu-items/{id}', method: 'DELETE'), isEmpty);

      await tapLabelled(h, 'Delete');
      h.allowUnmatched = true;
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      final del = h.server.callsTo('/menu-items/{id}', method: 'DELETE');
      expect(del.single.path, '/menu-items/$_morning');
      await h.expectToast('Combo deleted');
      expect(h.location.path, '/menu/combos');
    });

    testWidgets('OFFR-CED-012 a refused delete says why and stays', (
      tester,
    ) async {
      final s = editorServer();
      s.server.fail(
        'DELETE',
        '/menu-items/{id}',
        MockResponse.denied('menu.items.delete'),
      );
      final h = await pumpEditor(
        tester,
        path: comboPath('morning-croissant'),
        server: s.server,
        db: s.db,
      );
      await tapLabelled(h, 'Delete');
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      await h.expectToast(
        h.refusalWords(MockResponse.denied('menu.items.delete')),
      );
      expect(h.location.path, comboPath('morning-croissant'));
    });

    testWidgets('OFFR-CED-059 the two link rows lead to Pricing & '
        'Availability and to the combo settings, for every reader', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        path: comboPath('coffee-cookie'),
        persona: Persona.manager,
      );
      expect(
        editorText(
          'A branch or delivery channel can have its own combo price, or not '
          'sell it, in Pricing & Availability.',
        ),
        findsOneWidget,
      );
      expect(editorText('Branches and channels'), findsOneWidget);
      h.allowUnmatched = true;
      await h.tap(_link('Branch prices and on/off'));
      expect(h.location.path, '/menu/pricing');
    });

    testWidgets('OFFR-CED-059 "Where combos are sold" leads to the combo '
        'settings', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      expect(
        editorText(
          'POS, QR, online and delivery are switched for every combo at once, '
          'with branch exceptions, in Settings.',
        ),
        findsOneWidget,
      );
      h.allowUnmatched = true;
      await h.tap(_link('Where combos are sold'));
      expect(h.location.path, '/settings/combos');
    });

    testWidgets('OFFR-CED-011 no Delete on a new combo', (tester) async {
      await pumpEditor(tester);
      expect(labelled('Delete'), findsNothing);
    });
  });

  group('General', () {
    testWidgets('OFFR-CED-015/019/021/071 Save with errors: red lines, a '
        'toast, no request; then errors re-check as you type', (tester) async {
      final h = await pumpEditor(tester);
      expect(editorText('General'), findsOneWidget);
      expect(
        editorText(
          "Covers each slot's included size. Extras, bigger sizes and add-ons "
          'are added on top.',
        ),
        findsOneWidget,
      );
      await typeInto(h, 'Combo price', '-5');
      await tapLabelled(h, 'Create combo');
      expect(editorText('This field is required.'), findsWidgets);
      expect(editorText('Enter an amount of 0 or more.'), findsOneWidget);
      expect(editorText('Choose an item or a category.'), findsOneWidget);
      await h.expectToast(
        'Some fields need attention before saving.',
        keep: true,
      );
      await h.flushTimers();
      expect(h.server.callsTo(_create, method: 'POST'), isEmpty);

      await typeInto(h, 'Combo price', 'abc');
      expect(editorText('Enter an amount of 0 or more.'), findsOneWidget);
      await typeInto(h, 'Combo price', '150');
      expect(editorText('Enter an amount of 0 or more.'), findsNothing);
      await typeInto(h, 'Name', 'Breakfast deal');
      expect(
        inEditor(find.text('This field is required.')),
        findsOneWidget, // the slot name's
      );
    });

    testWidgets('OFFR-CED-072/020/023/024/077/086 create sends piastres and '
        'translations, toasts, and opens the new combo', (tester) async {
      final h = await pumpEditor(tester);
      expect(editorText('On the menu'), findsOneWidget);
      expect(
        editorText('Off hides it everywhere without deleting it.'),
        findsOneWidget,
      );
      await _fillValid(h);
      await typeInto(h, 'Name (Arabic)', ' فطور ');
      await typeInto(h, 'Combo price', '19.99');
      await typeInto(h, 'Description (Arabic)', 'وصف');
      expect(editorText('Unsaved changes'), findsOneWidget);
      await tapLabelled(h, 'Create combo');

      final body = bodiesTo(h, _create).single;
      expect(body['name'], 'Breakfast deal');
      expect(body['name_translations'], {'ar': 'فطور'});
      expect(body['price'], 1999);
      expect(body['description'], isNull);
      expect(body['description_translations'], {'ar': 'وصف'});
      expect(body['is_active'], isTrue);
      expect(body['category_id'], isNull);
      expect(body['windows'], isEmpty);
      final slot = (body['slots']! as List).single as Map;
      expect(slot['name'], 'Main');
      expect((slot['min'], slot['max'], slot['sort']), (1, 1, 0));
      final choice = (slot['choices']! as List).single as Map;
      expect(choice['menu_item_id'], OffersSeed.item('croissant'));
      expect(choice['category_id'], isNull);
      expect(choice['surcharge'], 0);

      await h.expectToast('Combo created', keep: true);
      final id = h.db!
          .table(OffersTables.menuItems)
          .rows
          .firstWhere((r) => r['name'] == 'Breakfast deal')['id'];
      expect(h.location.path, '/menu/combos/$id');
      // OFFR-CED-086: the new combo is read again.
      expect(
        h.server.callsTo(_combo, method: 'GET').single.path,
        '/combos/$id',
      );
      await debounce(h);
      expect(editorText('All changes saved'), findsOneWidget);
      expect(labelled('Delete'), findsOneWidget);
      await h.flushTimers();
    });

    testWidgets('OFFR-CED-068/069/070/073 update: Save is off until something '
        'changes; Discard puts it back; Save sends ids and says so', (
      tester,
    ) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      final save = tester.widget<DashButton>(around(_saveBarSave, DashButton));
      expect(save.onPressed, isNull);
      expect(labelled('Discard'), findsNothing);

      await typeInto(h, 'Combo price', '125');
      expect(editorText('Unsaved changes'), findsOneWidget);
      await tapLabelled(h, 'Discard');
      expect(editorText('All changes saved'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: labelled('Combo price'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '120',
      );

      await typeInto(h, 'Combo price', '125');
      final gate = h.server.hold('PUT', _combo);
      await tapLabelled(h, 'Save');
      final saving = tester.widget<DashButton>(
        around(_saveBarSave, DashButton),
      );
      expect(saving.loading, isTrue);
      // A second press while saving is ignored.
      await tester.tap(_saveBarSave, warnIfMissed: false);
      gate.release();
      await h.settle();
      final puts = h.server.callsTo(_combo, method: 'PUT');
      expect(puts, hasLength(1));
      final body = (puts.single.body! as Map).cast<String, Object?>();
      expect(body['price'], 12500);
      expect(
        [for (final s in body['slots']! as List) (s as Map)['id']],
        [
          OffersSeed.slotId('coffee-cookie', 'coffee'),
          OffersSeed.slotId('coffee-cookie', 'cookie'),
        ],
      );
      await h.expectToast('Changes saved');
      expect(editorText('All changes saved'), findsOneWidget);
    });

    testWidgets('OFFR-CED-014/068/072 phone: one column, and a combo is '
        'created from it', (tester) async {
      final h = await pumpEditor(tester, size: DashSize.phone, locale: 'ar');
      expect(editorText(h.t('combos.notSavedYet')), findsOneWidget);
      await typeInto(h, h.t('combos.name'), 'Breakfast deal');
      await typeInto(h, h.t('combos.price'), '150');
      await typeInto(h, h.t('combos.slots.name'), 'Main');
      await openSelect(h, h.t('combos.choice.pickItem'));
      await h.shot('combo-editor/item-sheet');
      await pickOption(h, 'كرواسون زبدة', search: 'كرواسون زبدة');
      expect(editorText(h.t('combos.unsaved')), findsOneWidget);
      await tapLabelled(h, h.t('combos.create'));
      final body = bodiesTo(h, _create).single;
      expect(body['price'], 15000);
      await h.expectToast(h.t('combos.created'));
    });

    testWidgets('OFFR-CED-068 (divergence) typing back what was loaded '
        'leaves nothing unsaved', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      await typeInto(h, 'At most', '2');
      expect(editorText('Unsaved changes'), findsOneWidget);
      await typeInto(h, 'At most', '1');
      expect(editorText('All changes saved'), findsOneWidget);
    });

    testWidgets('OFFR-CED-070/078 Enter on an existing combo with nothing '
        'changed does nothing (Save is off)', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      await tester.showKeyboard(
        find.descendant(
          of: labelled('Combo price'),
          matching: find.byType(EditableText),
        ),
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(h.server.callsTo(_combo, method: 'PUT'), isEmpty);
      expect(find.text('Changes saved'), findsNothing);
    });

    testWidgets('OFFR-CED-078 the pickers by keyboard: ↓ and Enter pick, Esc '
        'closes', (tester) async {
      final h = await pumpEditor(tester);
      await openSelect(h, 'Choose an item');
      await h.enterText(
        find.descendant(of: optionList, matching: find.byType(EditableText)),
        'Croissant',
      );
      // Almond Croissant is first and active; ↓ moves to Butter Croissant.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await debounce(h);
      expect(optionList, findsNothing);
      expect(labelled('Choose an item: Butter Croissant'), findsOneWidget);

      await openSelect(h, 'Category');
      expect(optionList, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await h.settle();
      expect(optionList, findsNothing);
      expect(labelled('Category: No category'), findsOneWidget);
    });

    testWidgets('OFFR-CED-012/072/073 create, update and delete each refresh '
        'every invalidateCombos prefix', (tester) async {
      final h = await pumpEditor(tester);
      final seen = _recordInvalidations(h);
      await _fillValid(h);
      await tapLabelled(h, 'Create combo');
      await h.expectToast('Combo created');
      expect(seen, [combosInvalidationPrefixes]);
      await debounce(h);

      await typeInto(h, 'Combo price', '155');
      await tapLabelled(h, 'Save');
      await h.expectToast('Changes saved');
      expect(seen, hasLength(2));
      expect(seen.last, combosInvalidationPrefixes);

      await tapLabelled(h, 'Delete');
      await h.tap(
        find.descendant(
          of: find.byType(DashConfirmDialog),
          matching: find.text('Delete'),
        ),
      );
      await h.expectToast('Combo deleted');
      expect(seen, hasLength(3));
      expect(seen.last, combosInvalidationPrefixes);
    });

    testWidgets('OFFR-CED-012/073 leaving mid-save: the save finishes, says '
        'so, and refreshes', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      final seen = _recordInvalidations(h);
      await typeInto(h, 'Combo price', '125');
      final gate = h.server.hold('PUT', _combo);
      await tapLabelled(h, 'Save');
      await tapLabelled(h, 'Back');
      expect(h.location.path, '/menu/combos');
      gate.release();
      await h.settle();
      await h.expectToast('Changes saved');
      expect(seen, [combosInvalidationPrefixes]);
    });

    testWidgets('OFFR-CED-078 Enter in a text field saves', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      await typeInto(h, 'Combo price', '130');
      await tester.showKeyboard(
        find.descendant(
          of: labelled('Combo price'),
          matching: find.byType(EditableText),
        ),
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(h.server.callsTo(_combo, method: 'PUT'), hasLength(1));
      await h.expectToast('Changes saved');
    });

    testWidgets('OFFR-CED-075 a slot refusal names the slot; other refusals '
        'are the server\'s words; the form keeps what was typed', (
      tester,
    ) async {
      final s = editorServer();
      s.server.fail(
        'PUT',
        _combo,
        MockResponse.error(
          400,
          'Check slot 2 (choices).',
          code: 'COMBO_SLOT_INVALID',
          vars: {'slot_index': 1, 'field': 'choices'},
        ),
      );
      final h = await pumpEditor(
        tester,
        path: comboPath('coffee-cookie'),
        server: s.server,
        db: s.db,
      );
      await typeInto(h, 'Combo price', '125');
      await tapLabelled(h, 'Save');
      await h.expectToast('Check the slot "Cookie".');
      expect(editorText('Unsaved changes'), findsOneWidget);

      final nested = MockResponse.error(
        400,
        "A combo can't contain another combo.",
        code: 'COMBO_NESTED',
      );
      s.server.fail('PUT', _combo, nested);
      await tapLabelled(h, 'Save');
      await h.expectToast(h.refusalWords(nested));
    });

    testWidgets('OFFR-CED-022 the category shows when the categories arrive '
        'after the combo, and a re-save keeps it', (tester) async {
      final s = editorServer();
      final gate = s.server.hold('GET', '/categories');
      final h = await pumpEditor(
        tester,
        path: comboPath('morning-croissant'),
        server: s.server,
        db: s.db,
      );
      expect(labelled('Category: Bakery'), findsNothing);
      gate.release();
      await debounce(h);
      expect(labelled('Category: Bakery'), findsOneWidget);
      await typeInto(h, 'Combo price', '170');
      await tapLabelled(h, 'Save');
      final body =
          (h.server.callsTo(_combo, method: 'PUT').single.body! as Map);
      expect(body['category_id'], OffersSeed.category('bakery'));
      await h.expectToast('Changes saved');
    });

    testWidgets('OFFR-CED-022 Category offers "No category" and the org\'s '
        'categories; Where the combo shows is the hint', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      expect(
        editorText('Where the combo shows on the till and the menus.'),
        findsOneWidget,
      );
      await choose(h, 'Category', 'Desserts');
      await openSelect(h, 'Category');
      expect(
        find.descendant(of: optionList, matching: find.text('No category')),
        findsOneWidget,
      );
      await pickOption(h, 'No category');
      expect(labelled('Category: No category'), findsOneWidget);
    });

    testWidgets('OFFR-CED-016/018/074/084 an image is held until Save, then '
        'uploaded; Remove only drops a pending one', (tester) async {
      final h = await pumpEditor(tester, path: comboPath('coffee-cookie'));
      expect(editorText('PNG/JPG/WebP, up to 5 MB'), findsOneWidget);
      h.files.imageQueue.add(pngFile());
      await h.tap(inEditor(find.text('Choose Image')));
      expect(h.server.callsTo(_upload), isEmpty);
      expect(editorText('Unsaved changes'), findsOneWidget);
      expect(labelled('Replace'), findsOneWidget);
      await tapLabelled(h, 'Remove');
      expect(editorText('Choose Image'), findsOneWidget);
      expect(editorText('All changes saved'), findsOneWidget);

      h.files.imageQueue.add(pngFile());
      await h.tap(inEditor(find.text('Choose Image')));
      await tapLabelled(h, 'Save');
      final up = h.server.callsTo(_upload, method: 'POST').single;
      expect(
        up.path,
        '/uploads/menu-items/${OffersSeed.comboId('coffee-cookie')}',
      );
      expect(up.files.single.field, 'image');
      await h.expectToast('Changes saved');
      // Still processing: the box shows the combo's own (no) image.
      expect(editorText('Choose Image'), findsOneWidget);
      expect(labelled('Remove'), findsNothing);
    });

    testWidgets('OFFR-CED-074 an image the server refuses (no '
        'menu.items.edit): the combo is saved, the image is not, and both '
        'are said', (tester) async {
      final s = editorServer();
      s.server.fail('POST', _upload, MockResponse.denied('menu.items.edit'));
      final h = await pumpEditor(
        tester,
        path: comboPath('coffee-cookie'),
        server: s.server,
        db: s.db,
      );
      h.files.imageQueue.add(pngFile());
      await h.tap(inEditor(find.text('Choose Image')));
      await tapLabelled(h, 'Save');
      expect(
        find.text(
          h.t(
            'combos.imageFailed',
            args: {
              'error': h.refusalWords(MockResponse.denied('menu.items.edit')),
            },
          ),
        ),
        findsOneWidget,
      );
      await h.expectToast('Changes saved');
      expect(labelled('Remove'), findsNothing);
      expect(editorText('All changes saved'), findsOneWidget);
    });

    testWidgets('OFFR-CED-017 a file that is not an image, or is over 5 MB, '
        'is refused in words', (tester) async {
      final h = await pumpEditor(tester);
      h.files.imageQueue.add(
        const PickedFile(
          name: 'menu.pdf',
          bytes: [37, 80, 68, 70],
          mimeType: 'application/pdf',
        ),
      );
      await h.tap(inEditor(find.text('Choose Image')));
      expect(editorText('Selected file must be an image'), findsOneWidget);
      h.files.imageQueue.add(
        PickedFile(
          name: 'huge.png',
          bytes: Uint8List(5 * 1024 * 1024 + 1),
          mimeType: 'image/png',
        ),
      );
      await h.tap(inEditor(find.text('Choose Image')));
      expect(editorText('Image size exceeds 5MB limit'), findsOneWidget);
      expect(editorText('Not saved yet'), findsOneWidget);
    });

    testWidgets('OFFR-CED-079 Arabic: the page reads right to left, the '
        'Arabic boxes stay right to left and money left to right', (
      tester,
    ) async {
      final h = await pumpEditor(
        tester,
        path: comboPath('morning-croissant'),
        locale: 'ar',
      );
      expect(editorText(h.t('combos.sections.general')), findsOneWidget);
      expect(
        Directionality.of(tester.element(labelled(h.t('combos.name')))),
        TextDirection.rtl,
      );
      EditableText field(String key) => tester.widget<EditableText>(
        find.descendant(
          of: labelled(h.t(key)),
          matching: find.byType(EditableText),
        ),
      );
      expect(field('combos.price').textDirection, TextDirection.ltr);
      expect(field('combos.nameAr').textDirection, TextDirection.rtl);
      expect(field('combos.price').controller.text, '165');
    });
  });
}
