// Driven tests of the step bodies and their inline editors
// (ADM-ONB-012..022, 030, 031): the café's identity and logo, then each
// "add through the real editor" step — branch, payment method, ingredient,
// category, add-on (with a new choice group), team member, menu item — and
// the recipes step, which edits an item.
import 'dart:convert';

import 'package:dashboard_admin/src/mock/onboarding_mock.dart';
import 'package:dashboard_admin/src/onboarding/step_navigator.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// A 1×1 PNG.
final List<int> _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

Finder get _nav => find.byType(OnbStepNavigator);

/// Opens [title]'s step from the navigator.
Future<void> _open(DashHarness h, String title) => h.tap(
  find.descendant(of: _nav, matching: find.bySemanticsLabel(RegExp(title))),
);

/// A fresh café with the wizard open.
Future<({DashHarness h, MockDb db})> _fresh(
  WidgetTester tester, {
  void Function(MockDb db)? seed,
  Persona persona = Persona.owner,
  Map<String, String>? prefs,
}) async {
  final s = onboardingServer(persona: persona);
  freshCafe(s.db);
  seed?.call(s.db);
  final h = await pumpOnboarding(
    tester,
    server: s.server,
    db: s.db,
    persona: persona,
    prefs: prefs,
  );
  return (h: h, db: s.db);
}

Future<void> _type(DashHarness h, String key, String text) =>
    h.enterText(field(key), text);

/// Picks [option] in the select with [key].
Future<void> _choose(DashHarness h, Finder select, String option) async {
  await h.tap(select);
  await pick(h, option);
}

void main() {
  group('Name your café', () {
    testWidgets('ADM-ONB-013 name and currency come from the org', (
      tester,
    ) async {
      final r = await _fresh(tester);
      expect(inPage('Café name'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: field('onb-org-name'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Sabah Coffee',
      );
      expect(
        find.descendant(
          of: field('onb-org-currency'),
          matching: find.text('EGP'),
        ),
        findsOneWidget,
      );
      await r.h.tap(
        find.descendant(
          of: field('onb-org-currency'),
          matching: find.text('EGP'),
        ),
      );
      for (final code in ['USD', 'SAR', 'AED', 'GBP', 'EUR']) {
        expect(find.text(code).hitTestable(), findsOneWidget, reason: code);
      }
      await pick(r.h, 'USD');
    });

    testWidgets('ADM-ONB-014 (refusal) an owner may not rename: the '
        "server's words, the step stays", (tester) async {
      final r = await _fresh(tester);
      await _type(r.h, 'onb-org-name', '  Sabah Roasters ');
      await r.h.tap(buttonOf('Save & continue'));
      final call = r.h.server.callsTo(orgRoute, method: 'PATCH').single;
      expect(call.status, 403);
      expect(call.body, {'name': 'Sabah Roasters', 'currency_code': 'EGP'});
      await r.h.expectToast(
        r.h.refusalWords(MockResponse.forbidden('Super admin access required')),
      );
      expect(inPage('Name your café'), findsWidgets);
    });

    testWidgets('ADM-ONB-014/031 Save & continue (platform admin): saved, '
        'toast, next step; a blank name is left out', (tester) async {
      final r = await _fresh(
        tester,
        persona: Persona.platform,
        prefs: {
          ScopePrefKeys.org: jsonEncode({'id': sabah}),
        },
      );
      final reads = statusReads(r.h.server);
      await _type(r.h, 'onb-org-name', '   ');
      await r.h.tap(
        find.descendant(
          of: field('onb-org-currency'),
          matching: find.text('EGP'),
        ),
      );
      await pick(r.h, 'SAR');
      await r.h.tap(buttonOf('Save & continue'));
      expect(r.h.server.callsTo(orgRoute, method: 'PATCH').single.body, {
        'currency_code': 'SAR',
      });
      expect(r.db['orgs'].get(sabah)['currency_code'], 'SAR');
      await r.h.expectToast('Café details saved.');
      expect(statusReads(r.h.server), greaterThan(reads));
      expect(inPage('Add your first branch'), findsWidgets);
      // ADM-ONB-031: coming back reads the org again (what was typed is gone).
      await r.h.tap(buttonOf('Back'));
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: field('onb-org-name'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'Sabah Coffee',
      );
    });

    testWidgets('ADM-ONB-012/030 the logo uploads at once; the checklist '
        'and the org are asked again', (tester) async {
      final r = await _fresh(tester);
      expect(inPage('PNG, JPG or WebP'), findsOneWidget);
      expect(
        inPage(
          "Add your logo — it shows up across the dashboard, receipts and "
          "your customers' menu.",
        ),
        findsOneWidget,
      );
      final orgReads = r.h.server.callsTo(orgRoute, method: 'GET').length;
      final reads = statusReads(r.h.server);
      r.h.files.imageQueue.add(
        PickedFile(name: 'logo.png', bytes: _png, mimeType: 'image/png'),
      );
      await r.h.tap(
        find.descendant(
          of: field('onb-logo'),
          matching: find.text('Choose Image'),
        ),
      );
      final put = r.h.server.callsTo(logoRoute, method: 'PUT').single;
      expect(put.status, 200);
      expect(r.db['orgs'].get(sabah)['logo_url'], startsWith('data:image/png'));
      expect(
        r.h.server.callsTo(orgRoute, method: 'GET').length,
        greaterThan(orgReads),
      );
      expect(statusReads(r.h.server), greaterThan(reads));
      // The café step is done now: its tile in the navigator has a check.
      expect(r.h.server.callsTo(statusRoute).last.status, 200);
      // ADM-ONB-030 (divergence): an owner keeps their branch pick.
      expect(r.h.container.read(selectedOrgProvider), isNull);
    });

    testWidgets('ADM-ONB-030 a platform admin\'s picked org keeps the new '
        'logo for the shell', (tester) async {
      final r = await _fresh(
        tester,
        persona: Persona.platform,
        prefs: {
          ScopePrefKeys.org: jsonEncode({'id': sabah}),
        },
      );
      r.h.files.imageQueue.add(
        PickedFile(name: 'logo.png', bytes: _png, mimeType: 'image/png'),
      );
      await r.h.tap(
        find.descendant(
          of: field('onb-logo'),
          matching: find.text('Choose Image'),
        ),
      );
      final picked = r.h.container.read(selectedOrgProvider);
      expect(picked?.id, sabah);
      expect(picked?.logoUrl, startsWith('data:image/png'));
    });

    testWidgets('ADM-ONB-012 a failed upload shows the server\'s words '
        'under the picker', (tester) async {
      final s = onboardingServer();
      freshCafe(s.db);
      final refusal = MockResponse.badRequest('Unsupported image type');
      s.server.fail('PUT', logoRoute, refusal);
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      h.files.imageQueue.add(
        PickedFile(name: 'logo.png', bytes: _png, mimeType: 'image/png'),
      );
      await h.tap(
        find.descendant(
          of: field('onb-logo'),
          matching: find.text('Choose Image'),
        ),
      );
      expect(
        find.descendant(
          of: field('onb-logo'),
          matching: find.text(h.refusalWords(refusal)),
        ),
        findsOneWidget,
      );
    });
  });

  group('add through the editor', () {
    testWidgets('ADM-ONB-015 branch: none yet, Add a branch opens the '
        'branch editor; saving one counts it', (tester) async {
      final r = await _fresh(tester);
      await _open(r.h, 'Add your first branch');
      expect(
        inPage('No branch yet — add your first to put your café on the map.'),
        findsOneWidget,
      );
      final reads = statusReads(r.h.server);
      await r.h.tap(buttonOf('Add a branch'));
      expect(inSurface(r.h.t('branches.newTitle')), findsOneWidget);
      await _type(r.h, 'branch-name', 'Heliopolis');
      await r.h.tap(field('branch-submit'));
      await r.h.flushTimers();
      expect(
        r.h.server.callsTo('/branches', method: 'POST').single.status,
        201,
      );
      expect(statusReads(r.h.server), greaterThan(reads));
      expect(inPage('1 branch added — nicely done.'), findsOneWidget);
      expect(buttonOf('Add another branch'), findsOneWidget);
      expect(
        button(tester, 'Add another branch').variant,
        DashButtonVariant.outline,
      );
    });

    testWidgets('ADM-ONB-015 closing the editor without saving still asks '
        'the checklist again', (tester) async {
      final r = await _fresh(tester);
      await _open(r.h, 'Add your first branch');
      expect(button(tester, 'Add a branch').variant, DashButtonVariant.primary);
      final reads = statusReads(r.h.server);
      await r.h.tap(buttonOf('Add a branch'));
      await r.h.tap(buttonOf('Cancel', within: surface));
      expect(statusReads(r.h.server), reads + 1);
    });

    testWidgets('ADM-ONB-016 payment method: required words, the identifier '
        'rule, the create and its count', (tester) async {
      final r = await _fresh(tester);
      await _open(r.h, 'How you get paid');
      expect(inPage('Add at least one way to take payment.'), findsOneWidget);
      await r.h.tap(buttonOf('Add a payment method'));
      expect(inSurface('New payment method'), findsOneWidget);
      expect(
        inSurface('Manage dynamic payment methods and colors'),
        findsOneWidget,
      );
      await r.h.tap(buttonOf('Save', within: surface));
      expect(inSurface('This field is required'), findsNWidgets(2));
      expect(r.h.server.callsTo('/payment-methods', method: 'POST'), isEmpty);
      await _type(r.h, 'pm-id', 'Visa Card');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: field('pm-id'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        'visa_card',
      );
      await _type(r.h, 'pm-label-en', 'Visa');
      await _type(r.h, 'pm-label-ar', 'فيزا');
      await _choose(
        r.h,
        find.descendant(
          of: field('pm-icon'),
          matching: find.text('Cash / Money'),
        ),
        'Credit Card',
      );
      await r.h.tap(field('pm-color-#2563EB'));
      await r.h.tap(
        find.descendant(
          of: surface,
          matching: find.byWidgetPredicate(
            (w) => w is DashSwitch && w.semanticLabel == 'Accepts cash',
          ),
        ),
      );
      await r.h.tap(buttonOf('Save', within: surface));
      expect(lastBody(r.h.server, '/payment-methods'), {
        'color': '#2563EB',
        'icon': 'credit_card',
        'is_active': true,
        'is_cash': true,
        'label_translations': {'en': 'Visa', 'ar': 'فيزا'},
        'name': 'visa_card',
        'visible_in_integrations': true,
      });
      await r.h.expectToast('Saved');
      expect(find.byType(DashSurface), findsNothing);
      expect(inPage('1 payment methods ready.'), findsOneWidget);
    });

    testWidgets('ADM-ONB-016 a refused create keeps the editor open with '
        "the server's words", (tester) async {
      final r = await _fresh(tester, seed: (db) => addPaymentMethod(db));
      await _open(r.h, 'How you get paid');
      await r.h.tap(buttonOf('Add another method'));
      await _type(r.h, 'pm-id', 'cash');
      await _type(r.h, 'pm-label-en', 'Cash');
      await r.h.tap(buttonOf('Save', within: surface));
      await r.h.expectToast(
        r.h.refusalWords(
          MockResponse.conflict(
            'A payment method with this name already exists for the '
            'organization',
          ),
        ),
      );
      expect(inSurface('New payment method'), findsOneWidget);
    });

    testWidgets('ADM-ONB-017 ingredient: General by default, the create '
        'and its count', (tester) async {
      final r = await _fresh(tester);
      await _open(r.h, 'Stock your pantry');
      expect(
        inPage(
          'Optional, but adding ingredients unlocks true cost and margin.',
        ),
        findsOneWidget,
      );
      await r.h.tap(buttonOf('Add an ingredient'));
      expect(inSurface('Create ingredient'), findsOneWidget);
      expect(inSurface('General'), findsOneWidget);
      // Save waits for a name.
      expect(button(tester, 'Save', within: surface).onPressed, isNull);
      await r.h.enterText(
        find
            .descendant(of: surface, matching: find.byType(DashTextField))
            .first,
        'Whole milk',
      );
      await _choose(
        r.h,
        find.descendant(of: surface, matching: find.text(r.h.t('units.g'))),
        r.h.t('units.ml'),
      );
      await r.h.enterText(
        find.descendant(of: surface, matching: find.byType(DashTextField)).last,
        '0.045',
      );
      await r.h.tap(buttonOf('Save', within: surface));
      final body = lastBody(r.h.server, '/inventory/orgs/{org_id}/catalog');
      expect(body['name'], 'Whole milk');
      expect(body['unit'], 'ml');
      expect(body['cost_per_unit'], 5);
      expect(body['category_id'], isNotNull);
      await r.h.expectToast('Changes saved');
      expect(inPage('1 ingredients in your catalog.'), findsOneWidget);
    });

    testWidgets('ADM-ONB-018 category: required words, the create and its '
        'count', (tester) async {
      final r = await _fresh(tester);
      await _open(r.h, 'Organize your menu');
      expect(
        inPage('Add a category — every item lives in one.'),
        findsOneWidget,
      );
      await r.h.tap(buttonOf('Add a category'));
      expect(inSurface('New category'), findsOneWidget);
      await r.h.tap(buttonOf('Save', within: surface));
      expect(inSurface('This field is required'), findsOneWidget);
      final fields = find.descendant(
        of: surface,
        matching: find.byType(EditableText),
      );
      await r.h.enterText(fields.at(0), 'Hot drinks');
      await r.h.enterText(fields.at(1), 'مشروبات ساخنة');
      await r.h.tap(buttonOf('Save', within: surface));
      expect(lastBody(r.h.server, '/categories'), {
        'org_id': sabah,
        'name': 'Hot drinks',
        'name_translations': {'ar': 'مشروبات ساخنة'},
      });
      await r.h.expectToast('Changes saved');
      expect(inPage('1 categories created.'), findsOneWidget);
    });

    testWidgets('ADM-ONB-019 add-on: a new choice group, then the add-on in '
        'it', (tester) async {
      final r = await _fresh(tester);
      await _open(r.h, 'Add-ons & extras');
      await r.h.tap(buttonOf('Add an add-on'));
      expect(inSurface('New add-on'), findsOneWidget);
      // Nothing to pick yet: make the group.
      await r.h.tap(buttonOf('New group', within: surface));
      expect(inSurface('New choice group'), findsOneWidget);
      final editor = surface;
      var fields = find.descendant(
        of: editor,
        matching: find.byType(EditableText),
      );
      await r.h.enterText(fields.at(0), 'Syrups');
      await r.h.tap(
        find.descendant(
          of: editor,
          matching: find.bySemanticsLabel(
            'Nothing to stock (just a note or a price)',
          ),
        ),
      );
      await r.h.tap(buttonOf('Add option', within: editor));
      await r.h.enterText(field('grp-option-name-0'), 'Vanilla');
      await r.h.enterText(field('grp-option-price-0'), '10');
      await r.h.tap(buttonOf('Save', within: editor));
      final group = lastBody(r.h.server, '/modifier-groups');
      expect(group['name'], 'Syrups');
      expect(group['effect'], 'none');
      expect(group['legacy_addon_type'], 'syrups');
      expect(group['selection_type'], 'multi');
      expect(group['sort'], 0);
      expect(
        lastBody(r.h.server, '/modifier-groups/{gid}/options')['price'],
        1000,
      );
      expect(lastBody(r.h.server, '/modifier-options/{oid}', method: 'PATCH'), {
        'sort': 0,
        'is_default': false,
      });
      await r.h.flushTimers();
      // Back in the add-on editor, the new group is the pick.
      expect(inSurface('New add-on'), findsOneWidget);
      expect(
        find.descendant(
          of: field('addon-group'),
          matching: find.text('Syrups'),
        ),
        findsOneWidget,
      );
      fields = find.descendant(
        of: surface,
        matching: find.byType(EditableText),
      );
      await r.h.enterText(fields.at(0), 'Caramel');
      await r.h.enterText(field('addon-price'), '12.5');
      await r.h.tap(buttonOf('Save', within: surface));
      final calls = r.h.server.callsTo(
        '/modifier-groups/{gid}/options',
        method: 'POST',
      );
      expect(calls.last.body, {
        'is_active': true,
        'name': 'Caramel',
        'price': 1250,
      });
      await r.h.expectToast('Changes saved');
      expect(find.byType(DashSurface), findsNothing);
      expect(
        inPage(r.h.t('onboarding.steps.addons.added', args: {'count': 2})),
        findsOneWidget,
      );
    });

    testWidgets('ADM-ONB-019 add-on: the group is required; a refusal '
        "keeps the editor open with the server's words", (tester) async {
      final r = await _fresh(tester, seed: (db) => everythingDoneGroups(db));
      await _open(r.h, 'Add-ons & extras');
      await r.h.tap(buttonOf('Add another add-on'));
      final fields = find.descendant(
        of: surface,
        matching: find.byType(EditableText),
      );
      await r.h.enterText(fields.at(0), 'Oat');
      await r.h.tap(buttonOf('Save', within: surface));
      expect(inSurface('This field is required'), findsOneWidget);
      final refusal = MockResponse.denied('menu.items.edit');
      r.h.server.fail('POST', '/modifier-groups/{gid}/options', refusal);
      await _choose(
        r.h,
        find.descendant(
          of: field('addon-group'),
          matching: find.text('Select…'),
        ),
        'Extras',
      );
      await r.h.tap(buttonOf('Save', within: surface));
      await r.h.expectToast(r.h.refusalWords(refusal));
      expect(inSurface('New add-on'), findsOneWidget);
    });

    testWidgets('ADM-ONB-020 team: Add a team member opens the person '
        'editor; closing asks the checklist again', (tester) async {
      final r = await _fresh(tester);
      await _open(r.h, 'Invite your team');
      expect(buttonOf('Add a team member'), findsOneWidget);
      final reads = statusReads(r.h.server);
      await r.h.tap(buttonOf('Add a team member'));
      // The users unit's editor (when it is there): close it.
      if (find.byType(DashSurface).evaluate().isNotEmpty) {
        await r.h.tap(buttonOf('Cancel', within: surface));
      }
      expect(statusReads(r.h.server), greaterThan(reads));
    });

    testWidgets('ADM-ONB-020 team: with a second person the count shows', (
      tester,
    ) async {
      final r = await _fresh(tester, seed: everythingDone);
      await _open(r.h, 'Invite your team');
      expect(
        inPage(r.h.t('onboarding.steps.team.added', args: {'count': 1})),
        findsOneWidget,
      );
      expect(buttonOf('Add another member'), findsOneWidget);
    });
  });

  group('menu items', () {
    testWidgets('ADM-ONB-021 no category: the warning, the button waits', (
      tester,
    ) async {
      final r = await _fresh(tester);
      await _open(r.h, 'Build your menu');
      expect(
        inPage('Add a category first — every item lives in one.'),
        findsOneWidget,
      );
      expect(button(tester, 'Add a menu item').onPressed, isNull);
    });

    testWidgets('ADM-ONB-021 while the categories load: a skeleton, no '
        'warning', (tester) async {
      final s = onboardingServer();
      freshCafe(s.db);
      addCategory(s.db);
      final gate = s.server.hold('GET', '/categories');
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      await _open(h, 'Build your menu');
      expect(
        inPage('Add a category first — every item lives in one.'),
        findsNothing,
      );
      expect(
        find.descendant(of: page, matching: find.byType(DashSkeleton)),
        findsOneWidget,
      );
      expect(button(tester, 'Add a menu item').onPressed, isNull);
      gate.release();
      await h.settle();
      expect(button(tester, 'Add a menu item').onPressed, isNotNull);
    });

    testWidgets('ADM-ONB-021 a failed categories read: the error and '
        'Retry', (tester) async {
      final s = onboardingServer();
      freshCafe(s.db);
      addCategory(s.db);
      s.server.fail(
        'GET',
        '/categories',
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      await _open(h, 'Build your menu');
      expect(inPage("Couldn't load this"), findsOneWidget);
      expect(
        inPage('Add a category first — every item lives in one.'),
        findsNothing,
      );
      final before = h.server.callsTo('/categories').length;
      s.server.clearFailures();
      await h.tap(buttonOf('Retry'));
      expect(h.server.callsTo('/categories').length, before + 1);
      expect(inPage("Couldn't load this"), findsNothing);
      expect(button(tester, 'Add a menu item').onPressed, isNotNull);
    });

    testWidgets('ADM-ONB-021 a one-price item: item, size, empty recipe; '
        'counted', (tester) async {
      final r = await _fresh(tester, seed: (db) => addCategory(db));
      await _open(r.h, 'Build your menu');
      expect(
        inPage(
          'Build your first item — set its price, sizes, recipe and add-ons '
          'in one go.',
        ),
        findsOneWidget,
      );
      await r.h.tap(buttonOf('Add a menu item'));
      expect(inSurface('New item'), findsOneWidget);
      await r.h.tap(buttonOf('Save', within: surface));
      expect(inSurface('This field is required'), findsNWidgets(2));
      final fields = find.descendant(
        of: surface,
        matching: find.byType(EditableText),
      );
      await r.h.enterText(fields.at(0), 'Latte');
      await r.h.enterText(fields.at(1), 'لاتيه');
      await _choose(
        r.h,
        find.descendant(
          of: field('item-category'),
          matching: find.text('Select category'),
        ),
        'Hot drinks',
      );
      await r.h.enterText(field('item-price'), '65');
      await r.h.tap(buttonOf('Save', within: surface));
      expect(lastBody(r.h.server, '/menu-items'), {
        'base_price': 6500,
        'description': null,
        'category_id': r.db[OnbTables.categories].rows.single['id'],
        'name': 'Latte',
        'name_translations': {'ar': 'لاتيه'},
        'org_id': sabah,
      });
      expect(lastBody(r.h.server, '/menu-items/{id}/sizes', method: 'PUT'), {
        'sizes': [
          {'is_active': true, 'label': 'one_size', 'price': 6500, 'sort': 0},
        ],
      });
      expect(
        lastBody(
          r.h.server,
          '/menu-item-sizes/{size_id}/recipe',
          method: 'PUT',
        ),
        {'lines': <Object?>[]},
      );
      expect(r.h.server.callsTo('/menu-items/{id}/modifier-groups'), isEmpty);
      await r.h.expectToast('Changes saved');
      expect(inPage('1 on the menu board.'), findsOneWidget);
    });

    testWidgets('ADM-ONB-021 sizes, a recipe line, an add-on, a new '
        'category inline and a picture after save', (tester) async {
      final r = await _fresh(
        tester,
        seed: (db) {
          addCategory(db);
          addIngredient(db);
          everythingDoneGroups(db);
        },
      );
      await _open(r.h, 'Build your menu');
      await r.h.tap(buttonOf('Add a menu item'));
      final fields = find.descendant(
        of: surface,
        matching: find.byType(EditableText),
      );
      await r.h.enterText(fields.at(0), 'Flat white');
      // "+" makes a category and picks it.
      await r.h.tap(
        find.descendant(
          of: surface,
          matching: find.bySemanticsLabel('New category'),
        ),
      );
      final catFields = find.descendant(
        of: surface,
        matching: find.byType(EditableText),
      );
      await r.h.enterText(catFields.at(0), 'Espresso bar');
      await r.h.tap(buttonOf('Save', within: surface));
      await r.h.flushTimers();
      expect(inSurface('New item'), findsOneWidget);
      expect(
        find.descendant(
          of: field('item-category'),
          matching: find.text('Espresso bar'),
        ),
        findsOneWidget,
      );
      // Two sizes.
      await r.h.tap(field('item-add-size'));
      await r.h.enterText(field('item-size-label-0'), 'Small');
      await r.h.enterText(field('item-size-price-0'), '55');
      await r.h.enterText(field('item-size-label-1'), 'Large');
      await r.h.enterText(field('item-size-price-1'), '70');
      // A recipe line on Small.
      await r.h.tap(
        find.descendant(
          of: field('recipe-size-0'),
          matching: find.text('Add ingredient'),
        ),
      );
      await _choose(
        r.h,
        find
            .descendant(
              of: field('recipe-size-0'),
              matching: find.text('Ingredient'),
            )
            .last,
        'Whole milk',
      );
      await r.h.enterText(
        find
            .descendant(
              of: field('recipe-size-0'),
              matching: find.byType(EditableText),
            )
            .last,
        '180',
      );
      // An add-on.
      await r.h.tap(
        find.descendant(of: surface, matching: find.text('Extra shot')).last,
      );
      // A picture, uploaded after the item exists.
      r.h.files.imageQueue.add(
        PickedFile(name: 'flat.png', bytes: _png, mimeType: 'image/png'),
      );
      await r.h.tap(
        find.descendant(
          of: field('item-image'),
          matching: find.text('Choose Image'),
        ),
      );
      expect(r.h.server.callsTo('/uploads/menu-items/{menu_item_id}'), isEmpty);
      await r.h.tap(buttonOf('Save', within: surface));
      expect(lastBody(r.h.server, '/menu-items')['base_price'], 5500);
      expect(lastBody(r.h.server, '/menu-items/{id}/sizes', method: 'PUT'), {
        'sizes': [
          {'is_active': true, 'label': 'Small', 'price': 5500, 'sort': 0},
          {'is_active': true, 'label': 'Large', 'price': 7000, 'sort': 1},
        ],
      });
      final recipes = r.h.server.callsTo(
        '/menu-item-sizes/{size_id}/recipe',
        method: 'PUT',
      );
      expect(recipes, hasLength(2));
      final milk = r.db[OnbTables.ingredients].rows.single['id'];
      expect(
        [for (final c in recipes) (c.body! as Map)['lines']],
        containsAll([
          [
            {'ingredient_id': milk, 'quantity': 180.0, 'unit': 'ml'},
          ],
          <Object?>[],
        ]),
      );
      expect(
        r.h.server.callsTo('/uploads/menu-items/{menu_item_id}').single.status,
        200,
      );
      final groups = lastBody(
        r.h.server,
        '/menu-items/{id}/modifier-groups',
        method: 'PUT',
      );
      expect(groups['groups'], [
        {
          'group_id': 'grp-extras',
          'included_option_ids': ['opt-shot'],
          'sort': 0,
        },
      ]);
      await r.h.expectToast('Changes saved');
      expect(inPage('1 on the menu board.'), findsOneWidget);
    });
  });

  group('recipes', () {
    testWidgets('ADM-ONB-022 no item yet: the intro and the empty line', (
      tester,
    ) async {
      final r = await _fresh(tester);
      await _open(r.h, 'Recipes & costs');
      expect(
        inPage(
          'Open an item and add its recipe — Madar then knows the cost and '
          'margin of everything you sell.',
        ),
        findsOneWidget,
      );
      expect(
        inPage('Add a menu item first, then come back to give it a recipe.'),
        findsOneWidget,
      );
    });

    testWidgets('ADM-ONB-022 a failed items read: the error and Retry, '
        'never the empty line', (tester) async {
      final s = onboardingServer();
      freshCafe(s.db);
      addItem(s.db, addCategory(s.db));
      s.server.fail(
        'GET',
        '/menu-items',
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpOnboarding(tester, server: s.server, db: s.db);
      await _open(h, 'Recipes & costs');
      expect(inPage("Couldn't load this"), findsOneWidget);
      expect(
        inPage('Add a menu item first, then come back to give it a recipe.'),
        findsNothing,
      );
      s.server.clearFailures();
      await h.tap(buttonOf('Retry'));
      expect(buttonOf('Add recipe'), findsOneWidget);
    });

    testWidgets('ADM-ONB-022 the first eight items, by their Arabic names '
        'in Arabic', (tester) async {
      final s = onboardingServer();
      freshCafe(s.db);
      final cat = addCategory(s.db);
      for (var i = 1; i <= 9; i++) {
        addItem(s.db, cat, name: 'Drink $i', ar: 'مشروب $i');
      }
      final h = await pumpOnboarding(
        tester,
        server: s.server,
        db: s.db,
        locale: 'ar',
      );
      await _open(h, h.t('onboarding.steps.recipes.title'));
      expect(
        buttonOf(h.t('onboarding.steps.recipes.addFor')),
        findsNWidgets(8),
      );
      expect(inPage('مشروب 1'), findsOneWidget);
      expect(inPage('مشروب 9'), findsNothing);
    });

    testWidgets('ADM-ONB-022 Add recipe edits the item: its sizes come '
        'back, the recipe is written, the checklist asked again', (
      tester,
    ) async {
      final r = await _fresh(
        tester,
        seed: (db) {
          addItem(db, addCategory(db));
          addIngredient(db);
        },
      );
      await _open(r.h, 'Recipes & costs');
      await r.h.tap(buttonOf('Add recipe'));
      expect(inSurface('Edit item'), findsOneWidget);
      final item = r.db[OnbTables.menuItems].rows.single;
      expect(
        r.h.server.callsTo('/menu-items/{id}', method: 'GET').single.path,
        '/menu-items/${item['id']}',
      );
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: field('item-price'),
                matching: find.byType(EditableText),
              ),
            )
            .controller
            .text,
        '65',
      );
      await r.h.tap(
        find.descendant(
          of: field('recipe-size-0'),
          matching: find.text('Add ingredient'),
        ),
      );
      await _choose(
        r.h,
        find
            .descendant(
              of: field('recipe-size-0'),
              matching: find.text('Ingredient'),
            )
            .last,
        'Whole milk',
      );
      await r.h.enterText(
        find
            .descendant(
              of: field('recipe-size-0'),
              matching: find.byType(EditableText),
            )
            .last,
        '200',
      );
      final reads = statusReads(r.h.server);
      await r.h.tap(buttonOf('Save', within: surface));
      expect(lastBody(r.h.server, '/menu-items/{id}', method: 'PATCH'), {
        'category_id': item['category_id'],
        'description': null,
        'is_active': true,
        'name': 'Latte',
        'name_translations': {'ar': 'لاتيه'},
      });
      expect(
        lastBody(
          r.h.server,
          '/menu-item-sizes/{size_id}/recipe',
          method: 'PUT',
        ),
        {
          'lines': [
            {
              'ingredient_id': r.db[OnbTables.ingredients].rows.single['id'],
              'quantity': 200.0,
              'unit': 'ml',
            },
          ],
        },
      );
      await r.h.expectToast('Changes saved');
      expect(statusReads(r.h.server), greaterThan(reads));
      final status = onboardingStatus(r.db, sabah);
      expect(status['recipe_coverage'], 1.0);
    });
  });
}

/// A shared "Extras" group with one option (id `opt-shot`).
void everythingDoneGroups(MockDb db) {
  db[OnbTables.groups].put({
    'id': 'grp-extras',
    'org_id': sabah,
    'name': 'Extras',
    'name_translations': {'ar': 'إضافات'},
    'selection_type': 'multi',
    'min_selections': 0,
    'max_selections': null,
    'is_required': false,
    'sort': 0,
    'is_active': true,
    'legacy_addon_type': 'extras',
    'effect': 'none',
    'is_item_options': false,
    'options': [
      {
        'id': 'opt-shot',
        'name': 'Extra shot',
        'name_translations': {'ar': 'شوت إضافي'},
        'price': 1500,
        'is_default': false,
        'is_active': true,
        'sort': 0,
      },
    ],
  });
}
