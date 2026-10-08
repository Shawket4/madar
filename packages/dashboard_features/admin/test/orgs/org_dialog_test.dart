// The organization editor (ADM-ORG-041..059 less the wizard rows): opened by
// ?edit=<id>, prefilled from the row, the logo uploaded at once, one PATCH
// on Save — driven through the real shell on the mock server.
import 'package:dashboard_admin/src/area_seed.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<DashHarness> _open(
  WidgetTester tester,
  String orgId, {
  Persona? persona = Persona.platform,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  MockServer? server,
  MockDb? db,
}) => pumpOrgs(
  tester,
  path: '/orgs?edit=$orgId',
  persona: persona,
  size: size,
  locale: locale,
  server: server,
  db: db,
);

Finder _field(String key) => find.byKey(ValueKey('org-$key'));

String _textOf(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(of: _field(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

Future<void> _type(DashHarness h, String key, String text) =>
    h.enterText(_field(key), text);

Future<void> _save(DashHarness h) => h.tapKey(const ValueKey('org-save'));

Finder _switch(String label) => find.byWidgetPredicate(
  (w) => w is DashSwitch && w.semanticLabel == label,
);

bool _switchOn(WidgetTester tester, String label) =>
    tester.widget<DashSwitch>(_switch(label)).value;

Map<String, Object?> _patch(DashHarness h) =>
    lastBody(h.server, '/orgs/{id}', method: 'PATCH');

DashButton _button(WidgetTester tester, String label) => tester.widget(
  find.byWidgetPredicate((w) => w is DashButton && w.label == label),
);

void main() {
  testWidgets('ADM-ORG-041 the editor: title, description, the row\'s '
      'values', (tester) async {
    await _open(tester, AdminSeed.layaliOrg);
    expect(find.text('Edit Organization'), findsOneWidget);
    expect(
      find.text('Update the details for this organization.'),
      findsOneWidget,
    );
    expect(_textOf(tester, 'name'), 'Layali Bistro');
    expect(_textOf(tester, 'slug'), 'layali-bistro');
    expect(_textOf(tester, 'currency'), 'EGP');
    expect(_textOf(tester, 'taxRate'), '14');
    expect(_textOf(tester, 'serviceCharge'), '12');
    expect(
      _textOf(tester, 'receiptFooter'),
      'Shukran — we hope to see you again soon.',
    );
    expect(_switchOn(tester, 'Menu prices include tax'), isFalse);
    expect(_switchOn(tester, 'Tax the service charge'), isTrue);
    expect(_switchOn(tester, 'Active'), isTrue);
    expect(_switchOn(tester, 'Every dine-in sale belongs to a table'), isTrue);
    expect(_switchOn(tester, 'Custom branding'), isFalse);
    expect(
      _textOf(tester, 'social-instagram'),
      'https://instagram.com/layalibistro',
    );
  });

  testWidgets('ADM-ORG-041 each opening starts from the stored row', (
    tester,
  ) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    await _type(h, 'name', 'Layali Garden');
    await h.tapText('Cancel');
    await h.tapText('Layali Bistro');
    expect(_textOf(tester, 'name'), 'Layali Bistro');
    expect(h.server.callsTo('/orgs/{id}', method: 'PATCH'), isEmpty);
  });

  testWidgets('ADM-ORG-042 a picked logo is uploaded at once; the list and '
      'the picked shop follow', (tester) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    await h.container
        .read(selectedOrgProvider.notifier)
        .select(AdminSeed.layaliOrg);
    await h.settle();
    h.files.imageQueue.add(pngFile('layali.png'));
    await h.tapText('Choose Image');
    final put = h.server.callsTo('/orgs/{id}/logo', method: 'PUT').single;
    expect(put.path, '/orgs/${AdminSeed.layaliOrg}/logo');
    expect(put.files.single.field, 'logo');
    expect(put.files.single.contentType, 'image/png');
    expect(put.status, 200);
    expect(
      h.container.read(selectedOrgProvider)?.logoUrl,
      startsWith('data:image/png;base64,'),
    );
    await h.tapText('Cancel');
    // The table's mark is the picture now, not the letters.
    expect(find.text('LA'), findsNothing);
  });

  testWidgets('ADM-ORG-042 a refused upload shows its words under the '
      'picker', (tester) async {
    final s = orgsServer();
    s.server.fail(
      'PUT',
      '/orgs/{id}/logo',
      MockResponse.forbidden(
        "You can only change your own organisation's logo",
      ),
    );
    final h = await _open(tester, AdminSeed.layaliOrg, server: s.server, db: s.db);
    h.files.imageQueue.add(pngFile());
    await h.tapText('Choose Image');
    expect(
      find.text("You don't have permission to perform this action."),
      findsOneWidget,
    );
    expect(
      find.text('Recommended: square PNG or SVG, at least 128×128 px'),
      findsNothing,
    );
    expect(find.text('Edit Organization'), findsOneWidget);
  });

  testWidgets('ADM-ORG-043 Remove (only with a logo) clears it', (
    tester,
  ) async {
    final s = orgsServer();
    s.db['orgs'].update(AdminSeed.layaliOrg, {
      'logo_url': 'data:image/png;base64,${base64Png()}',
    });
    final h = await _open(tester, AdminSeed.layaliOrg, server: s.server, db: s.db);
    await h.container
        .read(selectedOrgProvider.notifier)
        .select(
          AdminSeed.layaliOrg,
          logoUrl: 'data:image/png;base64,${base64Png()}',
        );
    await h.settle();
    expect(find.text('Choose Image'), findsNothing);
    await h.tapLabel('Remove');
    final patch = h.server.callsTo('/orgs/{id}', method: 'PATCH').single;
    expect(patch.body, {'logo_url': null});
    expect(h.container.read(selectedOrgProvider)?.logoUrl, isNull);
    expect(find.text('Choose Image'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove'), findsNothing);
    await h.expectToast('Logo removed');
    expect(orgNamed(s.db, 'Layali Bistro').logoUrl, isNull);
  });

  testWidgets('ADM-ORG-043 no logo, no Remove', (tester) async {
    await _open(tester, AdminSeed.qahwaOrg);
    expect(find.text('Choose Image'), findsOneWidget);
    expect(find.bySemanticsLabel('Remove'), findsNothing);
  });

  testWidgets('ADM-ORG-044 the name is required; editing it never rewrites '
      'the slug', (tester) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    await _type(h, 'name', 'Layali Garden');
    expect(_textOf(tester, 'slug'), 'layali-bistro');
    await _type(h, 'name', '');
    await _save(h);
    expect(find.text('This field is required'), findsOneWidget);
    expect(h.server.callsTo('/orgs/{id}', method: 'PATCH'), isEmpty);
    // After a Save, a fix clears the words at once.
    await _type(h, 'name', 'Layali Garden');
    expect(find.text('This field is required'), findsNothing);
  });

  testWidgets('ADM-ORG-045 a branded shop\'s slug is frozen (409 toast)', (
    tester,
  ) async {
    final h = await _open(tester, SeedIds.sabahOrg);
    await _type(h, 'slug', 'sabah-cairo');
    await _save(h);
    await h.expectToast(
      "This shop's short name is part of its web address and the codes it "
      'has printed, so it cannot be changed. Turn custom branding off first '
      'if it really has to move.',
    );
    expect(find.text('Edit Organization'), findsOneWidget);
  });

  testWidgets('ADM-ORG-045 a taken slug is refused', (tester) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    await _type(h, 'slug', 'qahwa-corner');
    await _save(h);
    await h.expectToast("Slug 'qahwa-corner' is already taken");
    expect(h.server.callsTo('/orgs/{id}', method: 'PATCH').single.status, 409);
  });

  testWidgets('ADM-ORG-046 currency and tax rate side by side; the rate is a '
      'percent, 0..100', (tester) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    final currency = tester.getRect(_field('currency'));
    final tax = tester.getRect(_field('taxRate'));
    expect(currency.top, tax.top);
    expect(currency.right, lessThan(tax.left));
    await _type(h, 'taxRate', '150');
    await _save(h);
    expect(find.text('Enter a rate between 0 and 100'), findsOneWidget);
    await _type(h, 'taxRate', '12.5');
    expect(find.text('Enter a rate between 0 and 100'), findsNothing);
    await _type(h, 'currency', 'usd');
    expect(_textOf(tester, 'currency'), 'USD');
    await _save(h);
    expect(_patch(h)['tax_rate'], 0.125);
    expect(_patch(h)['currency_code'], 'USD');
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-047 "Menu prices include tax" and its hint', (
    tester,
  ) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    expect(textHas('On, the price on the menu is what the customer pays'), findsOneWidget);
    await h.tap(_switch('Menu prices include tax'));
    await _save(h);
    expect(_patch(h)['tax_inclusive'], isTrue);
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-048 service charge 0..100 with its hint; "Tax the '
      'service charge"', (tester) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    expect(
      find.text('0 for none. Shown as its own line on the bill.'),
      findsOneWidget,
    );
    await _type(h, 'serviceCharge', '101');
    await _save(h);
    expect(find.text('Enter a rate between 0 and 100'), findsOneWidget);
    await _type(h, 'serviceCharge', '10');
    await h.tap(_switch('Tax the service charge'));
    await _save(h);
    expect(_patch(h)['service_charge_rate'], 0.1);
    expect(_patch(h)['service_charge_taxable'], isFalse);
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-049 the timezone with its hint', (tester) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    expect(
      find.text('Default for all branches. A branch can override its own.'),
      findsOneWidget,
    );
    await h.tap(find.text('Africa/Cairo'));
    await h.enterText(find.byType(DashOptionList<String>), 'riyadh');
    await h.tapText('Asia/Riyadh');
    await _save(h);
    expect(_patch(h)['timezone'], 'Asia/Riyadh');
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-050 an emptied receipt footer is sent as null; '
      'Active', (tester) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    await _type(h, 'receiptFooter', '');
    await h.tap(_switch('Active'));
    await _save(h);
    final body = _patch(h);
    expect(body.containsKey('receipt_footer'), isTrue);
    expect(body['receipt_footer'], isNull);
    expect(body['is_active'], isFalse);
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-051 "Every dine-in sale belongs to a table"', (
    tester,
  ) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    expect(textHas('The till stops ringing up dine-in sales'), findsOneWidget);
    await h.tap(_switch('Every dine-in sale belongs to a table'));
    await _save(h);
    expect(_patch(h)['require_table_for_orders'], isFalse);
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-052 "Custom branding" and its hint', (tester) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    expect(textHas("Puts this organisation's own logo"), findsOneWidget);
    await h.tap(_switch('Custom branding'));
    await _save(h);
    expect(_patch(h)['custom_branding'], isTrue);
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-053 a platform admin sets the modules; at least one', (
    tester,
  ) async {
    final h = await _open(tester, AdminSeed.qahwaOrg);
    expect(find.text('Modules'), findsOneWidget);
    expect(
      find.text(
        'Switching a module off hides its pages and keeps every record.',
      ),
      findsOneWidget,
    );
    await h.tapKey(const ValueKey('org-module-pos'));
    await _save(h);
    expect(find.text('Pick at least one module'), findsOneWidget);
    expect(h.server.callsTo('/orgs/{id}', method: 'PATCH'), isEmpty);
    await h.tapKey(const ValueKey('org-module-pos'));
    await h.tapKey(const ValueKey('org-module-dawam'));
    expect(find.text('Pick at least one module'), findsNothing);
    await _save(h);
    expect(_patch(h)['modules'], ['pos', 'dawam']);
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-053 anyone else: no Modules box, modules never sent '
      '(and the server refuses the save)', (tester) async {
    final s = orgsServer(persona: Persona.owner);
    // An owner who can read the list (not the backend's rule) to reach the
    // editor at all.
    s.server.on(
      'GET',
      '/orgs',
      (req) => MockResponse.ok(s.db['orgs'].query(sort: 'name')),
    );
    final h = await _open(
      tester,
      SeedIds.sabahOrg,
      persona: Persona.owner,
      server: s.server,
      db: s.db,
    );
    expect(find.text('Edit Organization'), findsOneWidget);
    expect(find.text('Modules'), findsNothing);
    await _save(h);
    expect(_patch(h).containsKey('modules'), isFalse);
    await h.expectToast("You don't have permission to perform this action.");
    expect(find.text('Edit Organization'), findsOneWidget);
  });

  testWidgets('ADM-ORG-054 social links: eight https-only fields; what a '
      'save sends', (tester) async {
    final h = await _open(tester, SeedIds.sabahOrg);
    expect(find.text('Where else to find you'), findsOneWidget);
    for (final p in [
      'Instagram',
      'Facebook',
      'TikTok',
      'X',
      'YouTube',
      'WhatsApp',
      'Talabat',
      'Website',
    ]) {
      expect(find.text(p), findsOneWidget, reason: p);
    }
    expect(find.text('https://tiktok.com/@yourshop'), findsOneWidget);
    await _type(h, 'social-x', 'http://x.com/sabah');
    await _type(h, 'social-website', 'sabah.coffee');
    await _save(h);
    expect(
      find.text('Use the full address, starting with https://'),
      findsNWidgets(2),
    );
    expect(h.server.callsTo('/orgs/{id}', method: 'PATCH'), isEmpty);
    await _type(h, 'social-x', ' https://x.com/sabah ');
    await _type(h, 'social-website', '');
    await _type(h, 'social-facebook', '');
    await _save(h);
    expect(_patch(h)['social_links'], {
      'instagram': 'https://instagram.com/sabahcoffee.eg',
      'facebook': '',
      'x': 'https://x.com/sabah',
      'whatsapp': 'https://wa.me/201001112233',
    });
    expect(orgNamed(h.db!, 'Sabah Coffee').socialLinks, {
      'instagram': 'https://instagram.com/sabahcoffee.eg',
      'x': 'https://x.com/sabah',
      'whatsapp': 'https://wa.me/201001112233',
    });
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-055 Save: one PATCH with every field, the list again, '
      'the toast, closed', (tester) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    await _type(h, 'name', 'Layali Garden');
    await _save(h);
    final call = h.server.callsTo('/orgs/{id}', method: 'PATCH').single;
    expect(call.path, '/orgs/${AdminSeed.layaliOrg}');
    expect(call.body, {
      'currency_code': 'EGP',
      'custom_branding': false,
      'is_active': true,
      'modules': ['pos', 'dawam'],
      'name': 'Layali Garden',
      'receipt_footer': 'Shukran — we hope to see you again soon.',
      'require_table_for_orders': true,
      'service_charge_rate': 0.12,
      'service_charge_taxable': true,
      'slug': 'layali-bistro',
      'social_links': {'instagram': 'https://instagram.com/layalibistro'},
      'tax_inclusive': false,
      'tax_rate': 0.14,
      'timezone': 'Africa/Cairo',
    });
    expect(find.text('Edit Organization'), findsNothing);
    expect(h.location.queryParameters.containsKey('edit'), isFalse);
    expect(find.text('Layali Garden'), findsOneWidget);
    await h.expectToast('Organization updated');
  });

  testWidgets('ADM-ORG-055 a failed save is a toast; the editor stays; '
      'Cancel is off while saving', (tester) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    final gate = h.server.hold('PATCH', '/orgs/{id}');
    await _save(h);
    expect(_button(tester, 'Save').loading, isTrue);
    expect(_button(tester, 'Cancel').onPressed, isNull);
    gate.release();
    await h.settle();
    await h.flushTimers();
    h.server.fail(
      'PATCH',
      '/orgs/{id}',
      MockResponse.error(500, 'Internal error'),
    );
    await h.tapText('Layali Bistro');
    await _save(h);
    await h.expectToast('Internal error');
    expect(find.text('Edit Organization'), findsOneWidget);
    expect(_button(tester, 'Cancel').onPressed, isNotNull);
  });

  testWidgets('ADM-ORG-056 Esc, a tap outside and the ✕ close it and drop '
      '?edit', (tester) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(find.text('Edit Organization'), findsNothing);
    expect(h.location.queryParameters.containsKey('edit'), isFalse);

    await h.tapText('Layali Bistro');
    expect(find.text('Edit Organization'), findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await h.settle();
    expect(find.text('Edit Organization'), findsNothing);
    expect(h.location.queryParameters.containsKey('edit'), isFalse);

    await h.tapText('Layali Bistro');
    await h.tapLabel('Close');
    expect(find.text('Edit Organization'), findsNothing);
    expect(h.location.queryParameters.containsKey('edit'), isFalse);
  });

  testWidgets('ADM-ORG-056 a phone: full screen, closed by ✕', (tester) async {
    final h = await _open(
      tester,
      AdminSeed.layaliOrg,
      size: DashSize.phone,
      locale: 'ar',
    );
    expect(find.text(h.t('orgs.editTitle')), findsOneWidget);
    await h.tapLabel(h.t('common.close'));
    expect(find.text(h.t('orgs.editTitle')), findsNothing);
    expect(h.location.queryParameters.containsKey('edit'), isFalse);
  });

  testWidgets('ADM-ORG-058 (divergence) what was typed survives the refetch '
      'a logo upload causes', (tester) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    await _type(h, 'name', 'Layali Garden');
    h.files.imageQueue.add(pngFile());
    await h.tapText('Choose Image');
    expect(h.server.callsTo('/orgs/{id}/logo', method: 'PUT'), hasLength(1));
    expect(_textOf(tester, 'name'), 'Layali Garden');
    await _save(h);
    expect(_patch(h)['name'], 'Layali Garden');
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-059 the editor does not trim: a space-only name '
      'passes and is sent', (tester) async {
    final h = await _open(tester, AdminSeed.layaliOrg);
    await _type(h, 'name', '   ');
    await _save(h);
    expect(find.text('This field is required'), findsNothing);
    expect(_patch(h)['name'], '   ');
    await h.flushTimers();
  });
}
