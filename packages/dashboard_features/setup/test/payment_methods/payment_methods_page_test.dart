// `/settings/payment-methods`, the Payment Methods tab, the editor and the
// export, driven through the real app shell (SET-PAY-001..021, -037, -038,
// -041; SET-SHL-012/013).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/payment_methods/payment_method_dialog.dart';
import 'package:dashboard_setup/src/brand_appearance/settings_shell.dart';
import 'package:dashboard_setup/src/payment_methods/payment_methods_page.dart';
import 'package:dashboard_setup/src/payment_methods/pm_data.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'pm_support.dart';

Finder _dialog() => find.byType(PaymentMethodDialog);
Finder _inDialog(Finder f) => find.descendant(of: _dialog(), matching: f);
Finder _key(String k) => find.byKey(ValueKey(k));

/// The names the table shows, in order.
List<String> _names(WidgetTester tester) => [
  for (final e in inPage(find.byType(PmNameCell)).evaluate())
    (e.widget as PmNameCell).method.name,
];

void main() {
  group('header, tabs, stats', () {
    testWidgets('SET-PAY-001 no org in scope: the title and "Select an '
        'organization", nothing read', (tester) async {
      final h = await pumpPm(tester, persona: Persona.platform);
      expect(inPage(find.text('Payment Methods')), findsOneWidget);
      expect(inPage(find.text('Select an organization')), findsOneWidget);
      expect(inPage(find.byKey(const ValueKey('pm-add'))), findsNothing);
      expect(h.server.callsTo(PmRoutes.list), isEmpty);
    });

    testWidgets('SET-PAY-001 a Dawam-only org meets the module gate; '
        'nothing read', (tester) async {
      final h = await pumpPm(tester, persona: Persona.dawamOnly);
      expect(find.text(h.t('dawam.moduleOffTitle')), findsOneWidget);
      expect(find.byType(PaymentMethodsPage), findsNothing);
      expect(h.server.callsTo(PmRoutes.list), isEmpty);
    });

    testWidgets('SET-PAY-002 title, description, Export Excel and Add',
        (tester) async {
      final h = await pumpPm(tester);
      expect(inPage(find.text('Payment Methods')), findsWidgets);
      expect(
        inPage(find.text(h.t('settings.paymentMethodsHint'))),
        findsOneWidget,
      );
      final export = tester.widget<DashButton>(
        find.descendant(
          of: inPage(_key('pm-export')),
          matching: find.byType(DashButton),
        ),
      );
      expect(export.label, 'Export Excel');
      expect(export.onPressed, isNotNull);
      expect(inPage(find.text('Add')), findsOneWidget);
    });

    testWidgets('SET-PAY-002 Export is disabled with no methods',
        (tester) async {
      final m = setupMockServer();
      m.db['payment_methods'].clear();
      await pumpPm(tester, backend: m);
      final export = tester.widget<DashButton>(
        find.descendant(
          of: inPage(_key('pm-export')),
          matching: find.byType(DashButton),
        ),
      );
      expect(export.onPressed, isNull);
      expect(inPage(find.text('No results found')), findsOneWidget);
    });

    testWidgets('SET-PAY-003 tabs: Payment Methods (default) and '
        'Availability, not in the URL', (tester) async {
      final h = await pumpPm(tester);
      final tabs = inPage(_key('pm-tabs'));
      expect(
        find.descendant(of: tabs, matching: find.text('Payment Methods')),
        findsOneWidget,
      );
      expect(inPage(find.byType(PmNameCell)), findsWidgets);
      await h.tap(
        find.descendant(of: tabs, matching: find.text('Availability')),
      );
      expect(inPage(find.byType(PmNameCell)), findsNothing);
      expect(
        inPage(find.text('Select a branch to view its tills')),
        findsOneWidget,
      );
      expect(h.location.queryParameters, isEmpty);
    });

    testWidgets('SET-PAY-004 stats: Total, Active, Inactive, System methods',
        (tester) async {
      await pumpPm(tester);
      // 6 core methods (talabat_cash off) + InstaPay + the retired gift card.
      expect(stat(tester, 'Total').value, 8);
      expect(stat(tester, 'Active').value, 6);
      expect(stat(tester, 'Active').tone, DashTone.success);
      expect(stat(tester, 'Inactive').value, 2);
      expect(stat(tester, 'Inactive').tone, DashTone.warning);
      expect(stat(tester, 'System methods').value, 6);
      expect(stat(tester, 'System methods').tone, DashTone.info);
    });

    testWidgets('SET-PAY-004 SET-PAY-010 loading: stat skeletons and table '
        'skeleton rows', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', PmRoutes.list);
      final h = await pumpPm(tester, backend: m);
      expect(stat(tester, 'Total').loading, isTrue);
      expect(
        tester.widget<DashDataTable<OrgPaymentMethod>>(
          inPage(find.byType(DashDataTable<OrgPaymentMethod>)),
        ).loading,
        isTrue,
      );
      gate.release();
      await h.settle();
      expect(stat(tester, 'Total').loading, isFalse);
      expect(inPage(find.byType(PmNameCell)), findsNWidgets(8));
    });
  });

  group('table', () {
    testWidgets('SET-PAY-005 Name: colour disc, label in the language, '
        '"System" under built-in methods', (tester) async {
      await pumpPm(tester);
      expect(_names(tester), [
        'cash',
        'card',
        'digital_wallet',
        'mixed',
        'talabat_online',
        'talabat_cash',
        'instapay',
        'gift_card',
      ]);
      expect(inPage(find.text('InstaPay')), findsOneWidget);
      expect(inPage(find.text('System')), findsNWidgets(6));
      // A hex colour is drawn as is; a name falls back to chart colour 3.
      Color discOf(String name) {
        final disc = find.byWidgetPredicate(
          (w) => w is PmDisc && w.method.name == name,
        );
        final box = tester.widget<Container>(
          find.descendant(of: disc, matching: find.byType(Container)).first,
        );
        return (box.decoration! as BoxDecoration).color!;
      }

      expect(discOf('instapay'), hexColor('#7C3AED'));
      final ctx = tester.element(inPage(find.byType(PmDisc)).first);
      expect(discOf('cash'), dashSeriesColor(ctx, 2));
    });

    testWidgets('SET-PAY-005 Arabic labels, and the English then the '
        'identifier when one is missing', (tester) async {
      final m = setupMockServer();
      m.db['payment_methods'].update(pmId('instapay'), {
        'label_translations': {'en': 'InstaPay', 'ar': ''},
      });
      m.db['payment_methods'].update(pmId('gift_card'), {
        'label_translations': <String, String>{},
      });
      await pumpPm(tester, backend: m, locale: 'ar');
      Finder name(String s) => inPage(
        find.descendant(of: find.byType(PmNameCell), matching: find.text(s)),
      );
      expect(name('نقدي'), findsOneWidget);
      expect(name('InstaPay'), findsOneWidget);
      expect(name('gift_card'), findsOneWidget);
      expect(inPage(find.text('نظامي')), findsNWidgets(6));
    });

    testWidgets('SET-PAY-006 Type: Cash (success) / Non-cash', (tester) async {
      await pumpPm(tester);
      final badges = tester
          .widgetList<DashBadge>(inPage(find.byType(DashBadge)))
          .where((b) => b.label == 'Cash' || b.label == 'Non-cash')
          .toList();
      expect([for (final b in badges) b.label], [
        'Cash',
        'Non-cash',
        'Non-cash',
        'Non-cash',
        'Non-cash',
        'Cash',
        'Non-cash',
        'Non-cash',
      ]);
      expect(badges.first.tone, DashTone.success);
      expect(badges[1].tone, DashTone.neutral);
    });

    testWidgets('SET-PAY-007 Partners: "Hidden" only when not shared',
        (tester) async {
      await pumpPm(tester);
      // The seed hides Mixed and the gift card from partners.
      expect(inPage(find.text('Hidden')), findsNWidgets(2));
      expect(
        inPage(find.byKey(ValueKey('pm-hidden-${pmId('gift_card')}'))),
        findsOneWidget,
      );
      expect(
        inPage(find.byKey(ValueKey('pm-hidden-${pmId('mixed')}'))),
        findsOneWidget,
      );
      expect(inPage(find.text('—')), findsNWidgets(6));
    });

    testWidgets('SET-PAY-008 the status switch deactivates at once, no '
        'toast, refetch; it does not open the row', (tester) async {
      final h = await pumpPm(tester);
      final before = h.server.callsTo(PmRoutes.list).length;
      await h.tap(inPage(_key('pm-active-${pmId('card')}')));
      expect(h.server.callsTo(PmRoutes.deactivate).single.path,
          '/payment-methods/${pmId('card')}/deactivate');
      expect(h.server.callsTo(PmRoutes.list).length, before + 1);
      expect(h.location.queryParameters['edit'], isNull);
      expect(_dialog(), findsNothing);
      expect(stat(tester, 'Active').value, 5);
      expect(find.text('Saved'), findsNothing);
      // And back on.
      await h.tap(inPage(_key('pm-active-${pmId('card')}')));
      expect(h.server.callsTo(PmRoutes.activate).single.path,
          '/payment-methods/${pmId('card')}/activate');
      expect(stat(tester, 'Active').value, 6);
    });

    testWidgets('SET-PAY-008 SET-PAY-037 a refused toggle toasts the '
        "server's words (manager by URL)", (tester) async {
      final h = await pumpPm(tester, persona: Persona.manager);
      expect(inPage(find.byType(PmNameCell)), findsNWidgets(8));
      await h.tap(inPage(_key('pm-active-${pmId('card')}')));
      await h.expectToast(
        h.refusalWords(MockResponse.denied('payment_methods.edit')),
      );
      expect(stat(tester, 'Active').value, 6);
    });

    testWidgets('SET-PAY-009 search filters by identifier, not by label',
        (tester) async {
      final h = await pumpPm(tester);
      final search = inPage(find.byType(DashSearchInput));
      expect(
        tester.widget<DashSearchInput>(search).placeholder,
        'Search',
      );
      await h.enterText(search, 'talabat');
      expect(_names(tester), ['talabat_online', 'talabat_cash']);
      await h.enterText(search, 'Talabat Online');
      expect(_names(tester), isEmpty);
      expect(inPage(find.text('No results found')), findsOneWidget);
      await h.enterText(search, 'INSTA');
      expect(_names(tester), ['instapay']);
    });

    testWidgets('SET-PAY-009 ten a page with the pager, no Columns menu',
        (tester) async {
      final m = setupMockServer();
      for (var i = 1; i <= 4; i++) {
        m.db['payment_methods'].insert({
          'org_id': SeedIds.sabahOrg,
          'name': 'voucher_$i',
          'label_translations': {'en': 'Voucher $i', 'ar': 'قسيمة $i'},
          'color': '#334155',
          'icon': 'receipt',
          'is_cash': false,
          'is_active': true,
          'visible_in_integrations': true,
        });
      }
      final h = await pumpPm(tester, backend: m);
      expect(_names(tester), hasLength(10));
      expect(inPage(find.text(h.t('common.columns'))), findsNothing);
      expect(
        inPage(find.text(h.t('common.page', args: {'current': 1, 'total': 2}))),
        findsOneWidget,
      );
      await h.tap(inPage(find.bySemanticsLabel(h.t('common.next'))));
      expect(_names(tester), ['voucher_3', 'voucher_4']);
    });

    testWidgets('SET-PAY-010 (divergence) a failed read shows the error '
        'with Retry, not "No results"', (tester) async {
      final m = setupMockServer();
      final boom = MockResponse.error(500, 'Service unavailable: boom');
      m.server.fail('GET', PmRoutes.list, boom, times: null);
      final h = await pumpPm(tester, backend: m);
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(inPage(find.text(h.refusalWords(boom))), findsOneWidget);
      expect(inPage(find.text('No results found')), findsNothing);
      m.server.clearFailures();
      final gate = m.server.hold('GET', PmRoutes.list);
      final before = h.server.calls.length;
      await h.tap(inPage(find.text('Retry')));
      // On its way again: the skeleton, never "No results".
      expect(inPage(find.text('No results found')), findsNothing);
      expect(
        tester.widget<DashDataTable<OrgPaymentMethod>>(
          inPage(find.byType(DashDataTable<OrgPaymentMethod>)),
        ).loading,
        isTrue,
      );
      gate.release();
      await h.settle();
      expect(inPage(find.byType(PmNameCell)), findsNWidgets(8));
      expect(
        [for (final c in h.server.calls.skip(before)) c.path],
        ['/payment-methods'],
      );
    });

    testWidgets('SET-PAY-037 a persona without payment_methods.read sees '
        'the refusal in the table', (tester) async {
      final h = await pumpPm(tester, persona: Persona.limited);
      expect(inPage(find.text("Couldn't load this")), findsOneWidget);
      expect(
        inPage(
          find.text(h.refusalWords(MockResponse.denied('payment_methods.read'))),
        ),
        findsOneWidget,
      );
    });

    testWidgets('SET-PAY-037 the rail shows Payment methods only with '
        'payment_methods.edit', (tester) async {
      for (final (persona, shown) in [
        (Persona.owner, true),
        (Persona.manager, false),
      ]) {
        final h = await pumpPm(tester, persona: persona);
        final rail = find.byWidgetPredicate(
          (w) => w is Text && w.data == h.t('nav.paymentMethods'),
        );
        expect(
          find.descendant(of: find.byType(SettingsShell), matching: rail),
          shown ? findsOneWidget : findsNothing,
          reason: persona.name,
        );
      }
    });
  });

  group('editor', () {
    testWidgets('SET-PAY-011 the pencil opens ?edit=<id> and the edit '
        'dialog', (tester) async {
      final h = await pumpPm(tester);
      await h.tap(inPage(_key('pm-edit-${pmId('instapay')}')));
      expect(h.location.queryParameters['edit'], pmId('instapay'));
      expect(_inDialog(find.text('Edit payment method')), findsOneWidget);
      expect(
        tester.widget<DashIconButton>(inPage(_key('pm-edit-${pmId('cash')}')))
            .semanticLabel,
        'Edit',
      );
    });

    testWidgets('SET-PAY-011 a row tap opens its editor', (tester) async {
      final h = await pumpPm(tester);
      await h.tap(inPage(find.text('InstaPay')));
      expect(h.location.queryParameters['edit'], pmId('instapay'));
      expect(_dialog(), findsOneWidget);
    });

    testWidgets('SET-PAY-012 Add opens ?edit=new; closing removes the param '
        'and keeps the scope', (tester) async {
      final h = await pumpPm(tester, query: zamalek);
      await h.tap(inPage(_key('pm-add')));
      expect(h.location.queryParameters, {
        'branchId': SeedIds.zamalek,
        'edit': 'new',
      });
      expect(_inDialog(find.text('New payment method')), findsOneWidget);
      await h.tap(_inDialog(_key('pm-cancel')));
      expect(_dialog(), findsNothing);
      expect(h.location.queryParameters, {'branchId': SeedIds.zamalek});
    });

    testWidgets('SET-PAY-012 deep links: ?edit=new opens on load, '
        '?edit=<id> once the list has it, an unknown id nothing',
        (tester) async {
      var h = await pumpPm(tester, query: '?edit=new');
      expect(_inDialog(find.text('New payment method')), findsOneWidget);

      final m = setupMockServer();
      final gate = m.server.hold('GET', PmRoutes.list);
      h = await pumpPm(tester, query: '?edit=${pmId('card')}', backend: m);
      expect(_dialog(), findsNothing);
      gate.release();
      await h.settle();
      expect(_inDialog(find.text('Edit payment method')), findsOneWidget);
      expect(
        tester.widget<DashTextField>(_inDialog(_key('pm-id'))).value,
        'card',
      );

      h = await pumpPm(tester, query: '?edit=${mockUuid('nope')}');
      expect(_dialog(), findsNothing);
      expect(inPage(find.byType(PmNameCell)), findsNWidgets(8));
    });

    testWidgets('SET-PAY-013 the dialog: titles and the page description',
        (tester) async {
      final h = await pumpPm(tester, query: '?edit=new');
      expect(_inDialog(find.text('New payment method')), findsOneWidget);
      expect(
        _inDialog(find.text(h.t('settings.paymentMethodsHint'))),
        findsOneWidget,
      );
    });

    testWidgets('SET-PAY-014 the identifier: lowercased, underscores, '
        'required, hint; locked when editing', (tester) async {
      final h = await pumpPm(tester, query: '?edit=new');
      final id = _inDialog(_key('pm-id'));
      expect(
        _inDialog(find.text('A unique internal identifier (lowercase, '
            'underscores only).')),
        findsOneWidget,
      );
      expect(tester.widget<DashTextField>(id).placeholder, 'e.g. visa_card');
      expect(tester.widget<DashTextField>(id).mono, isTrue);
      await h.enterText(id, 'Visa Card-2!');
      expect(tester.widget<DashTextField>(id).value, 'visa_card_2_');
      await h.enterText(id, '');
      await h.tap(_inDialog(_key('pm-save')));
      expect(_inDialog(find.text('This field is required')), findsWidgets);
      expect(h.server.callsTo(PmRoutes.list, method: 'POST'), isEmpty);

      await h.tap(_inDialog(_key('pm-cancel')));
      await h.tap(inPage(_key('pm-edit-${pmId('instapay')}')));
      final locked = tester.widget<DashTextField>(_inDialog(_key('pm-id')));
      expect(locked.enabled, isFalse);
      expect(_inDialog(find.text('Identifiers cannot be changed.')),
          findsOneWidget);
    });

    test('SET-PAY-014 the identifier rules', () {
      expect(sanitizeIdentifier('Cash Up'), 'cash_up');
      expect(sanitizeIdentifier('ValU-4'), 'valu_4');
      expect(pmIdentifierPattern.hasMatch('visa_card'), isTrue);
      expect(pmIdentifierPattern.hasMatch('Visa'), isFalse);
      expect(pmIdentifierPattern.hasMatch(''), isFalse);
    });

    testWidgets('SET-PAY-015 SET-PAY-041 labels: English required, Arabic '
        'optional and right-to-left, side by side even on a phone',
        (tester) async {
      final h = await pumpPm(tester, query: '?edit=new', size: DashSize.phone);
      final en = _inDialog(_key('pm-label-en'));
      final ar = _inDialog(_key('pm-label-ar'));
      expect(tester.widget<DashTextField>(en).placeholder, 'Visa Card');
      expect(tester.widget<DashTextField>(ar).placeholder, 'فيزا');
      expect(tester.widget<DashTextField>(ar).textDirection, TextDirection.rtl);
      expect(tester.getTopLeft(en).dy, tester.getTopLeft(ar).dy);
      final cash = _inDialog(_key('pm-is-cash'));
      final active = _inDialog(_key('pm-is-active'));
      expect(tester.getTopLeft(cash).dy, tester.getTopLeft(active).dy);
      expect(
        tester.getSize(_inDialog(_key('pm-visible'))).width,
        greaterThan(tester.getSize(cash).width * 1.8),
      );
      await h.enterText(_inDialog(_key('pm-id')), 'visa');
      await h.tap(_inDialog(_key('pm-save')));
      expect(_inDialog(find.text('This field is required')), findsOneWidget);
      expect(h.server.callsTo(PmRoutes.list, method: 'POST'), isEmpty);
    });

    testWidgets('SET-PAY-016 the icon select: 13 icons, Cash / Money by '
        'default', (tester) async {
      final h = await pumpPm(tester, query: '?edit=new');
      final select = tester.widget<DashSelectField<String>>(
        _inDialog(_key('pm-icon')),
      );
      expect(select.value, 'money');
      expect([for (final o in select.options) o.label], [
        'Cash / Money',
        'Credit Card',
        'Digital Wallet',
        'Mixed / Split',
        'Delivery',
        'QR Code',
        'Bank Transfer',
        'Gift Card',
        'Mobile Pay',
        'Voucher',
        'Store Credit',
        'Loyalty Points',
        'Payment Link',
      ]);
      expect(select.options[1].icon, 'credit-card');
      await h.tap(_inDialog(find.text('Cash / Money')));
      await h.tap(top('Bank Transfer'));
      expect(
        tester.widget<DashSelectField<String>>(_inDialog(_key('pm-icon')))
            .value,
        'bank',
      );
    });

    testWidgets('SET-PAY-017 colours: 14 swatches named by their hex, the '
        'green one chosen by default', (tester) async {
      final h = await pumpPm(tester, query: '?edit=new');
      for (final hex in [
        '#0F172A', '#334155', '#10B981', '#059669', '#3B82F6', '#2563EB',
        '#8B5CF6', '#7C3AED', '#F59E0B', '#D97706', '#EF4444', '#DC2626',
        '#EC4899', '#DB2777', //
      ]) {
        expect(_inDialog(find.bySemanticsLabel(hex)), findsOneWidget);
      }
      DashPressable swatch(String hex) =>
          tester.widget(_inDialog(_key('pm-color-$hex')));
      expect(swatch('#10B981').selected, isTrue);
      await h.tap(_inDialog(_key('pm-color-#2563EB')));
      expect(swatch('#2563EB').selected, isTrue);
      expect(swatch('#10B981').selected, isFalse);
    });

    testWidgets('SET-PAY-018 switches: Accepts cash off, Active on, Share '
        'with partners on', (tester) async {
      final h = await pumpPm(tester, query: '?edit=new');
      bool on(String k) => tester
          .widget<DashSwitch>(
            find.descendant(
              of: _inDialog(_key(k)),
              matching: find.byType(DashSwitch),
            ),
          )
          .value;
      expect(on('pm-is-cash'), isFalse);
      expect(on('pm-is-active'), isTrue);
      expect(on('pm-visible'), isTrue);
      expect(_inDialog(find.text('Counts toward cash drawer.')), findsOneWidget);
      expect(_inDialog(find.text('Available at checkout.')), findsOneWidget);
      expect(
        _inDialog(find.text(h.t('settings.pm.visibleInIntegrationsHint'))),
        findsOneWidget,
      );
      await h.tap(_inDialog(_key('pm-is-cash')));
      expect(on('pm-is-cash'), isTrue);
    });

    testWidgets('SET-PAY-019 Save creates with the whole body, toasts, '
        'refetches and closes', (tester) async {
      final h = await pumpPm(tester, query: '?edit=new');
      final lists = h.server.callsTo(PmRoutes.list, method: 'GET').length;
      await h.enterText(_inDialog(_key('pm-id')), 'visa_card');
      await h.enterText(_inDialog(_key('pm-label-en')), 'Visa Card');
      await h.tap(_inDialog(_key('pm-color-#2563EB')));
      await h.tap(_inDialog(_key('pm-is-cash')));
      await h.tap(_inDialog(_key('pm-save')));
      expect(h.server.callsTo(PmRoutes.list, method: 'POST').single.body, {
        'name': 'visa_card',
        'label_translations': {'en': 'Visa Card', 'ar': ''},
        'color': '#2563EB',
        'icon': 'money',
        'is_cash': true,
        'is_active': true,
        'visible_in_integrations': true,
      });
      await h.expectToast('Saved');
      expect(_dialog(), findsNothing);
      expect(h.location.queryParameters['edit'], isNull);
      expect(
        h.server.callsTo(PmRoutes.list, method: 'GET').length,
        lists + 1,
      );
      expect(inPage(find.text('Visa Card')), findsOneWidget);
      expect(stat(tester, 'Total').value, 9);
    });

    testWidgets('SET-PAY-019 Save on an edit sends every field with PUT',
        (tester) async {
      final h = await pumpPm(tester, query: '?edit=${pmId('instapay')}');
      await h.enterText(_inDialog(_key('pm-label-ar')), 'انستاباي');
      await h.tap(_inDialog(_key('pm-visible')));
      await h.tap(_inDialog(_key('pm-save')));
      final put = h.server.callsTo(PmRoutes.method, method: 'PUT').single;
      expect(put.path, '/payment-methods/${pmId('instapay')}');
      expect(put.body, {
        'name': 'instapay',
        'label_translations': {'en': 'InstaPay', 'ar': 'انستاباي'},
        'color': '#7C3AED',
        'icon': 'smartphone',
        'is_cash': false,
        'is_active': true,
        'visible_in_integrations': false,
      });
      await h.expectToast('Saved');
      expect(
        inPage(find.byKey(ValueKey('pm-hidden-${pmId('instapay')}'))),
        findsOneWidget,
      );
    });

    testWidgets('SET-PAY-019 (divergence) a refetch while the dialog is '
        'open keeps what was typed', (tester) async {
      final h = await pumpPm(tester, query: '?edit=${pmId('instapay')}');
      await h.enterText(_inDialog(_key('pm-label-en')), 'InstaPay EG');
      final lists = h.server.callsTo(PmRoutes.list).length;
      h.container.read(realtimeBusProvider).invalidate(const [
        '/payment-methods',
      ]);
      await h.settle();
      expect(h.server.callsTo(PmRoutes.list).length, lists + 1);
      expect(
        tester.widget<DashTextField>(_inDialog(_key('pm-label-en'))).value,
        'InstaPay EG',
      );
    });

    testWidgets('SET-PAY-019 closing the dialog mid-save still refreshes '
        'the list', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('POST', PmRoutes.list);
      final h = await pumpPm(tester, query: '?edit=new', backend: m);
      await h.enterText(_inDialog(_key('pm-id')), 'valu');
      await h.enterText(_inDialog(_key('pm-label-en')), 'valU');
      await h.tap(_inDialog(_key('pm-save')));
      await h.tap(_inDialog(_key('pm-cancel')));
      expect(_dialog(), findsNothing);
      final lists = h.server.callsTo(PmRoutes.list, method: 'GET').length;
      gate.release();
      await h.settle();
      expect(h.server.callsTo(PmRoutes.list, method: 'GET').length, lists + 1);
      expect(inPage(find.text('valU')), findsOneWidget);
      await h.expectToast('Saved');
    });

    testWidgets("SET-PAY-019 a refused Save toasts the server's words and "
        'stays open', (tester) async {
      final h = await pumpPm(tester, query: '?edit=new');
      await h.enterText(_inDialog(_key('pm-id')), 'cash');
      await h.enterText(_inDialog(_key('pm-label-en')), 'Cash again');
      await h.tap(_inDialog(_key('pm-save')));
      await h.expectToast(
        h.refusalWords(MockResponse.conflict(PmRefusals.nameTakenInOrg)),
      );
      expect(_dialog(), findsOneWidget);
      expect(
        tester.widget<DashButton>(_inDialog(_key('pm-save'))).loading,
        isFalse,
      );
    });

    testWidgets('SET-PAY-019 SET-PAY-037 the manager may not add: 403 '
        'toast', (tester) async {
      final h = await pumpPm(
        tester,
        query: '?edit=new',
        persona: Persona.manager,
      );
      await h.enterText(_inDialog(_key('pm-id')), 'valu');
      await h.enterText(_inDialog(_key('pm-label-en')), 'valU');
      await h.tap(_inDialog(_key('pm-save')));
      await h.expectToast(
        h.refusalWords(MockResponse.denied('payment_methods.create')),
      );
      expect(_dialog(), findsOneWidget);
    });

    testWidgets('SET-PAY-019 Save spins while the answer is on its way',
        (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('POST', PmRoutes.list);
      final h = await pumpPm(tester, query: '?edit=new', backend: m);
      await h.enterText(_inDialog(_key('pm-id')), 'valu');
      await h.enterText(_inDialog(_key('pm-label-en')), 'valU');
      await h.tap(_inDialog(_key('pm-save')));
      expect(
        tester.widget<DashButton>(_inDialog(_key('pm-save'))).loading,
        isTrue,
      );
      gate.release();
      await h.settle();
      await h.expectToast('Saved');
      expect(_dialog(), findsNothing);
    });
  });

  group('export', () {
    testWidgets('SET-PAY-020 export: file, sheet, the four columns, the '
        'whole list', (tester) async {
      final h = await pumpPm(tester);
      await h.tap(inPage(_key('pm-export')));
      await h.expectToast(h.t('excel.done', count: 8));
      final spec = h.exports.built.single;
      expect(h.files.saved.single.filename,
          'Madar-PaymentMethods-2026-10-08.xlsx');
      final sheet = spec.sheets.single;
      expect(sheet.name, 'Payment Methods');
      expect(sheet.title, 'Payment Methods');
      expect([for (final c in sheet.columns) c.header],
          ['Identifier', 'Name', 'Type', 'Status']);
      expect(sheet.rows.first, ['cash', 'Cash', 'Cash', 'Active']);
      expect(sheet.rows.last, ['gift_card', 'Gift card', 'Non-cash', 'Inactive']);
      expect(sheet.rows, hasLength(8));
    });

    testWidgets('SET-PAY-020 an export failure toasts', (tester) async {
      final h = await pumpPm(tester);
      h.exports.failNext = StateError('disk full');
      await h.tap(inPage(_key('pm-export')));
      await h.expectToast('Export failed');
      expect(h.files.saved, isEmpty);
    });
  });

  group('phone', () {
    testWidgets('SET-PAY-021 a card per method: Type, Partners, Status and '
        'the pencil; the switch does not open it, the card does',
        (tester) async {
      final h = await pumpPm(tester, size: DashSize.phone);
      final card = find
          .ancestor(of: inPage(find.text('InstaPay')), matching: find.byType(DashCard))
          .first;
      for (final label in ['Type', 'Partners', 'Status']) {
        expect(
          find.descendant(of: card, matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: card, matching: find.byType(DashIconButton)),
        findsOneWidget,
      );
      await h.tap(
        find.descendant(of: card, matching: find.byType(DashSwitch)),
      );
      expect(h.server.callsTo(PmRoutes.deactivate), hasLength(1));
      expect(h.location.queryParameters['edit'], isNull);
      await h.tap(find.descendant(of: card, matching: find.text('InstaPay')));
      expect(h.location.queryParameters['edit'], pmId('instapay'));
      expect(_dialog(), findsOneWidget);
    });
  });

  group('prefetch', () {
    testWidgets('SET-PAY-038 SET-SHL-013 warming the route reads the list; '
        'opening it asks nothing more', (tester) async {
      final h = await pumpSetup(tester, path: '/settings');
      List<MockCall> lists() => h.server.callsTo(PmRoutes.list, method: 'GET');
      expect(lists(), isEmpty);
      final prefetch = h.container.read(routePrefetchesProvider)[pmPath]!;
      prefetch(DashPrefetcher(h.container), h.container.read(currentScopeProvider));
      await h.settle();
      expect(lists(), hasLength(1));
      await h.go(pmPath);
      expect(inPage(find.byType(PmNameCell)), findsNWidgets(8));
      expect(lists(), hasLength(1), reason: 'served from the cache');
    });

    testWidgets('SET-PAY-038 no org in scope: nothing warmed', (tester) async {
      final h = await pumpSetup(tester, persona: Persona.platform);
      h.container.read(routePrefetchesProvider)[pmPath]!(
        DashPrefetcher(h.container),
        h.container.read(currentScopeProvider),
      );
      await h.settle();
      expect(h.server.callsTo(PmRoutes.list), isEmpty);
    });
  });
}
