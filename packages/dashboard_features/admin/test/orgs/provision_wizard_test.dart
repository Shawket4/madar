// The provision wizard (ADM-ORG-025..040, 057, 059): three steps, each
// checked on Next, one POST /orgs/provision, the logo after, conflicts sent
// back to their field — driven through the real shell on the mock server.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<DashHarness> _open(
  WidgetTester tester, {
  DashSize size = DashSize.desktop,
  String locale = 'en',
  MockServer? server,
  MockDb? db,
}) => pumpOrgs(
  tester,
  path: '/orgs?edit=new',
  size: size,
  locale: locale,
  server: server,
  db: db,
);

Finder _field(String key) => find.byKey(ValueKey('wizard-$key'));

String _textOf(WidgetTester tester, String key) => tester
    .widget<EditableText>(
      find.descendant(of: _field(key), matching: find.byType(EditableText)),
    )
    .controller
    .text;

Future<void> _type(DashHarness h, String key, String text) =>
    h.enterText(_field(key), text);

Future<void> _next(DashHarness h) => h.tapKey(const ValueKey('wizard-next'));

Future<void> _create(DashHarness h) =>
    h.tapKey(const ValueKey('wizard-create'));

/// Step 1 filled in: Drops Coffee, a café, the rest as it starts.
Future<void> _business(DashHarness h, {String name = 'Drops Coffee'}) async {
  await _type(h, 'name', name);
  await h.tapKey(const ValueKey('wizard-template-cafe'));
}

Future<void> _branch(DashHarness h) => _type(h, 'branchName', 'Zamalek');

Future<void> _owner(DashHarness h, {String email = 'mona@drops.test'}) async {
  await _type(h, 'ownerName', 'Mona Fawzy');
  await _type(h, 'email', email);
  await _type(h, 'password', 'secret123');
}

/// Through steps 1 and 2 to the owner step.
Future<void> _toOwner(DashHarness h) async {
  await _business(h);
  await _next(h);
  await _branch(h);
  await _next(h);
}

DashButton _button(WidgetTester tester, String label) => tester.widget(
  find.byWidgetPredicate((w) => w is DashButton && w.label == label),
);

void main() {
  testWidgets('ADM-ORG-025 the dialog: title, "Step 1 of 3 · Business", the '
      'progress strip; the templates are read while it is open', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(find.text('New Organization'), findsOneWidget);
    expect(find.text('Step 1 of 3 · Business'), findsOneWidget);
    expect(find.bySemanticsLabel('Progress'), findsOneWidget);
    for (final s in ['Business', 'First branch', 'Owner']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    expect(h.server.callsTo('/orgs/templates', method: 'GET'), hasLength(1));
    await _business(h);
    await _next(h);
    expect(find.text('Step 2 of 3 · First branch'), findsOneWidget);
    // The finished step shows a check.
    expect(
      find.byWidgetPredicate((w) => w is DashIcon && w.name == 'check'),
      findsOneWidget,
    );
    await _branch(h);
    await _next(h);
    expect(find.text('Step 3 of 3 · Owner'), findsOneWidget);
    expect(
      find.byWidgetPredicate((w) => w is DashIcon && w.name == 'check'),
      findsNWidgets(2),
    );
  });

  testWidgets('ADM-ORG-026 the logo is held until the org exists; Remove '
      'clears it; a non-image or an oversized one is refused', (tester) async {
    final h = await _open(tester);
    expect(find.text('Logo'), findsOneWidget);
    expect(
      find.text('Recommended: square PNG or SVG, at least 128×128 px'),
      findsOneWidget,
    );
    h.files.imageQueue.add(pngFile());
    await h.tapText('Choose Image');
    expect(h.server.callsTo('/orgs/{id}/logo'), isEmpty);
    expect(find.text('Choose Image'), findsNothing);
    expect(find.bySemanticsLabel('Remove'), findsOneWidget);
    await h.tapLabel('Remove');
    expect(find.text('Choose Image'), findsOneWidget);

    h.files.imageQueue.add(
      const PickedFile(
        name: 'menu.pdf',
        bytes: [37, 80, 68, 70],
        mimeType: 'application/pdf',
      ),
    );
    await h.tapText('Choose Image');
    expect(find.text('Selected file must be an image'), findsOneWidget);

    h.files.imageQueue.add(
      PickedFile(
        name: 'huge.png',
        bytes: Uint8List(5 * 1024 * 1024 + 1),
        mimeType: 'image/png',
      ),
    );
    await h.tapText('Choose Image');
    expect(find.text('Image size exceeds 5MB limit'), findsOneWidget);
  });

  testWidgets('ADM-ORG-027 every keystroke of the name rewrites the slug', (
    tester,
  ) async {
    final h = await _open(tester);
    await _type(h, 'name', 'Layali  Bistro 2!');
    expect(_textOf(tester, 'slug'), 'layali-bistro-2');
    await _type(h, 'name', '  Zahra Café  ');
    expect(_textOf(tester, 'slug'), 'zahra-caf');
  });

  testWidgets('ADM-ORG-028 the slug is required (trimmed)', (tester) async {
    final h = await _open(tester);
    await _business(h);
    await _type(h, 'slug', '   ');
    await _next(h);
    expect(find.text('This field is required'), findsOneWidget);
    expect(find.text('Step 1 of 3 · Business'), findsOneWidget);
  });

  testWidgets('ADM-ORG-029 the template cards: names, hints, required', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(find.text('Café'), findsOneWidget);
    expect(find.text('Restaurant'), findsOneWidget);
    expect(find.text('Tables, waiters and kitchen.'), findsOneWidget);
    expect(
      find.text('Counter service; the cashier marks items ready. No bookings.'),
      findsOneWidget,
    );
    await _type(h, 'name', 'Drops');
    await _next(h);
    expect(find.text('Choose a template'), findsOneWidget);
    await h.tapKey(const ValueKey('wizard-template-restaurant'));
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('wizard-template-restaurant')),
      ),
      isSemantics(isChecked: true, isInMutuallyExclusiveGroup: true),
    );
    await _next(h);
    expect(find.text('Choose a template'), findsNothing);
    expect(find.text('Step 2 of 3 · First branch'), findsOneWidget);
  });

  testWidgets('ADM-ORG-029 Arabic: the template names in Arabic', (
    tester,
  ) async {
    final h = await _open(tester, locale: 'ar');
    expect(find.text('مقهى'), findsOneWidget);
    expect(find.text('مطعم'), findsOneWidget);
    expect(find.text(h.t('orgs.wizard.cafeHint')), findsOneWidget);
  });

  testWidgets('ADM-ORG-029 a failed templates read shows its words under '
      'the cards', (tester) async {
    final s = orgsServer();
    s.server.fail(
      'GET',
      '/orgs/templates',
      MockResponse.error(500, 'Internal error'),
    );
    await _open(tester, server: s.server, db: s.db);
    expect(find.text('Internal error'), findsOneWidget);
    expect(find.text('Café'), findsNothing);
  });

  testWidgets('ADM-ORG-030 the currency starts EGP, reads upper case and is '
      'sent upper case', (tester) async {
    final h = await _open(tester);
    expect(_textOf(tester, 'currency'), 'EGP');
    await _type(h, 'currency', ' usd ');
    expect(_textOf(tester, 'currency'), ' USD ');
    await _business(h);
    await _next(h);
    await _branch(h);
    await _next(h);
    await _owner(h);
    await _create(h);
    expect(lastBody(h.server, '/orgs/provision')['currency_code'], 'USD');
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-031 the tax rate: 0..100 percent, sent as a fraction', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(_textOf(tester, 'taxRate'), '0');
    await _business(h);
    await _type(h, 'taxRate', '150');
    await _next(h);
    expect(find.text('Enter a rate between 0 and 100'), findsOneWidget);
    await _type(h, 'taxRate', '-1');
    await _next(h);
    expect(find.text('Enter a rate between 0 and 100'), findsOneWidget);
    await _type(h, 'taxRate', '14');
    await _next(h);
    await _branch(h);
    await _next(h);
    await _owner(h);
    await _create(h);
    expect(lastBody(h.server, '/orgs/provision')['tax_rate'], 0.14);
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-032 the timezone: Africa/Cairo first, searchable', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(h.server.callsTo('/timezones'), isNotEmpty);
    expect(find.text('Africa/Cairo'), findsOneWidget);
    await h.tap(find.text('Africa/Cairo'));
    expect(find.text('Search timezones…'), findsOneWidget);
    await h.enterText(find.byType(DashOptionList<String>), 'dubai');
    expect(find.text('Asia/Riyadh'), findsNothing);
    await h.tapText('Asia/Dubai');
    expect(find.text('Asia/Dubai'), findsOneWidget);
    await _business(h);
    await _next(h);
    await _branch(h);
    await _next(h);
    await _owner(h);
    await _create(h);
    expect(lastBody(h.server, '/orgs/provision')['timezone'], 'Asia/Dubai');
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-033 modules: POS on to start, at least one', (
    tester,
  ) async {
    final h = await _open(tester);
    expect(find.text('Modules'), findsOneWidget);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('org-module-pos'))),
      isSemantics(label: 'Madar POS', isChecked: true),
    );
    await _business(h);
    await h.tapKey(const ValueKey('org-module-pos'));
    await _next(h);
    expect(find.text('Pick at least one module'), findsOneWidget);
    await h.tapKey(const ValueKey('org-module-dawam'));
    await h.tapKey(const ValueKey('org-module-pos'));
    await _next(h);
    await _branch(h);
    await _next(h);
    await _owner(h);
    await _create(h);
    expect(lastBody(h.server, '/orgs/provision')['modules'], ['dawam', 'pos']);
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-034 Next checks only its own step; Enter is Next, and '
      'Create on the last step', (tester) async {
    final h = await _open(tester);
    await _next(h);
    // Name, slug and template — nothing of the later steps.
    expect(find.text('This field is required'), findsNWidgets(2));
    expect(find.text('Choose a template'), findsOneWidget);
    await _business(h);
    await tester.showKeyboard(_field('name'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(find.text('Step 2 of 3 · First branch'), findsOneWidget);
    await _branch(h);
    await tester.showKeyboard(_field('branchName'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(find.text('Step 3 of 3 · Owner'), findsOneWidget);
    await _owner(h);
    await tester.showKeyboard(_field('password'));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(h.server.callsTo('/orgs/provision'), hasLength(1));
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-035 the first branch: a name, optional address and '
      'phone (left out when blank)', (tester) async {
    final h = await _open(tester);
    await _business(h);
    await _next(h);
    expect(find.text('Branch name'), findsOneWidget);
    expect(find.text('Address (optional)'), findsOneWidget);
    expect(find.text('Phone (optional)'), findsOneWidget);
    await _next(h);
    expect(find.text('This field is required'), findsOneWidget);
    await _branch(h);
    await _type(h, 'phone', '   ');
    await _next(h);
    await _owner(h);
    await _create(h);
    expect(lastBody(h.server, '/orgs/provision')['branch'], {
      'name': 'Zamalek',
    });
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-035 an address and phone are sent trimmed', (
    tester,
  ) async {
    final h = await _open(tester);
    await _business(h);
    await _next(h);
    await _branch(h);
    await _type(h, 'address', ' 26 July St, Zamalek ');
    await _type(h, 'phone', '+20 2 2735 0011');
    await _next(h);
    await _owner(h);
    await _create(h);
    expect(lastBody(h.server, '/orgs/provision')['branch'], {
      'name': 'Zamalek',
      'address': '26 July St, Zamalek',
      'phone': '+20 2 2735 0011',
    });
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-036 the owner: name, a valid email, 8+ characters, '
      'an optional 6-digit PIN', (tester) async {
    final h = await _open(tester);
    await _toOwner(h);
    await _type(h, 'email', 'mona');
    await _type(h, 'password', 'short');
    await _type(h, 'pin', '12345');
    await _create(h);
    expect(find.text('This field is required'), findsOneWidget);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(find.text('The PIN is exactly 6 digits'), findsOneWidget);
    expect(h.server.callsTo('/orgs/provision'), isEmpty);
    // After a Create, every change re-checks its field.
    await _type(h, 'pin', '123456');
    expect(find.text('The PIN is exactly 6 digits'), findsNothing);
    await _owner(h);
    expect(find.text('Enter a valid email'), findsNothing);
    await _create(h);
    final owner = lastBody(h.server, '/orgs/provision')['owner']! as Map;
    expect(owner, {
      'email': 'mona@drops.test',
      'name': 'Mona Fawzy',
      'password': 'secret123',
      'pin': '123456',
    });
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-037 the summary names the rate typed on step 1', (
    tester,
  ) async {
    final h = await _open(tester);
    await _type(h, 'taxRate', '14.5');
    await _business(h);
    await _next(h);
    await _branch(h);
    await _next(h);
    expect(find.text('The new organization starts with:'), findsOneWidget);
    expect(
      find.text('A teller may void only their own sale, within 10 minutes.'),
      findsOneWidget,
    );
    expect(find.text("Refunds need a manager's approval."), findsOneWidget);
    expect(find.text("Waiters can't refund."), findsOneWidget);
    expect(find.text('Tax 14.5% unless set.'), findsOneWidget);
    await h.tapText('Back');
    await h.tapText('Back');
    await _type(h, 'taxRate', '');
    await _next(h);
    await _next(h);
    expect(find.text('Tax 0% unless set.'), findsOneWidget);
  });

  testWidgets('ADM-ORG-038 Cancel on step 1, Back after it (values kept); '
      'Back is off while creating', (tester) async {
    final h = await _open(tester);
    expect(find.text('Back'), findsNothing);
    await _business(h);
    await _next(h);
    expect(find.text('Cancel'), findsNothing);
    await h.tapText('Back');
    expect(find.text('Step 1 of 3 · Business'), findsOneWidget);
    expect(_textOf(tester, 'name'), 'Drops Coffee');
    await _next(h);
    await _branch(h);
    await _next(h);
    await _owner(h);
    final gate = h.server.hold('POST', '/orgs/provision');
    await h.tapKey(const ValueKey('wizard-create'));
    expect(_button(tester, 'Back').onPressed, isNull);
    expect(_button(tester, 'Create').loading, isTrue);
    gate.release();
    await h.settle();
    await h.flushTimers();
    expect(find.text('New Organization'), findsNothing);
  });

  testWidgets('ADM-ORG-038 Cancel closes the wizard', (tester) async {
    final h = await _open(tester);
    await h.tapText('Cancel');
    expect(find.text('New Organization'), findsNothing);
    expect(h.location.queryParameters.containsKey('edit'), isFalse);
    expect(h.server.callsTo('/orgs/provision'), isEmpty);
  });

  testWidgets('ADM-ORG-039 Create: one call, then the logo, the list again, '
      'the toast, closed', (tester) async {
    final h = await _open(tester);
    h.files.imageQueue.add(pngFile('drops.png'));
    await h.tapText('Choose Image');
    await _business(h);
    await _type(h, 'taxRate', '14');
    await h.tapKey(const ValueKey('org-module-dawam'));
    await _next(h);
    await _branch(h);
    await _next(h);
    await _owner(h);
    await _create(h);
    final provision = h.server.callsTo('/orgs/provision').single;
    expect(provision.status, 201);
    expect(provision.body, {
      'branch': {'name': 'Zamalek'},
      'currency_code': 'EGP',
      'modules': ['pos', 'dawam'],
      'name': 'Drops Coffee',
      'owner': {
        'email': 'mona@drops.test',
        'name': 'Mona Fawzy',
        'password': 'secret123',
      },
      'slug': 'drops-coffee',
      'tax_rate': 0.14,
      'template': 'cafe',
      'timezone': 'Africa/Cairo',
    });
    final created = orgNamed(h.db!, 'Drops Coffee');
    final logo = h.server.callsTo('/orgs/{id}/logo', method: 'PUT').single;
    expect(logo.path, '/orgs/${created.id}/logo');
    expect(logo.files.single.field, 'logo');
    expect(logo.files.single.filename, 'drops.png');
    expect(find.text('New Organization'), findsNothing);
    expect(h.location.queryParameters.containsKey('edit'), isFalse);
    expect(find.text('Drops Coffee'), findsOneWidget);
    await h.expectToast('Organization created');
  });

  testWidgets('ADM-ORG-039 a failed logo upload says so; the org stays '
      'created', (tester) async {
    final h = await _open(tester);
    h.server.fail(
      'PUT',
      '/orgs/{id}/logo',
      MockResponse.badRequest('Image uploads are disabled in the demo.'),
    );
    h.files.imageQueue.add(pngFile());
    await h.tapText('Choose Image');
    await _toOwner(h);
    await _owner(h);
    await _create(h);
    expect(
      find.text('Image uploads are disabled in the demo.'),
      findsOneWidget,
    );
    expect(find.text('Organization created'), findsOneWidget);
    expect(find.text('New Organization'), findsNothing);
    expect(find.text('Drops Coffee'), findsOneWidget);
    await h.flushTimers();
  });

  testWidgets('ADM-ORG-040 a taken slug sends the wizard back to step 1 '
      'with the words under Slug', (tester) async {
    final h = await _open(tester);
    await _business(h, name: 'Sabah Coffee');
    await _next(h);
    await _branch(h);
    await _next(h);
    await _owner(h);
    await _create(h);
    expect(h.server.callsTo('/orgs/provision').single.status, 409);
    expect(find.text('Step 1 of 3 · Business'), findsOneWidget);
    expect(find.text("Slug 'sabah-coffee' is already taken"), findsOneWidget);
    // A changed slug re-checks: the server's words go.
    await _type(h, 'slug', 'sabah-coffee-2');
    expect(find.text("Slug 'sabah-coffee' is already taken"), findsNothing);
  });

  testWidgets('ADM-ORG-040 a taken email sends it to step 3, under Email', (
    tester,
  ) async {
    final h = await _open(tester);
    await _toOwner(h);
    await _owner(h, email: 'nour@sabah.test');
    await _create(h);
    expect(find.text('Step 3 of 3 · Owner'), findsOneWidget);
    expect(find.text('Email already in use'), findsOneWidget);
    expect(find.text('New Organization'), findsOneWidget);
  });

  testWidgets('ADM-ORG-040 any other failure is a toast; the wizard stays', (
    tester,
  ) async {
    final h = await _open(tester);
    h.server.fail(
      'POST',
      '/orgs/provision',
      MockResponse.error(500, 'Internal error'),
    );
    await _toOwner(h);
    await _owner(h);
    await _create(h);
    await h.expectToast('Internal error');
    expect(find.text('Step 3 of 3 · Owner'), findsOneWidget);
  });

  testWidgets('ADM-ORG-040 Arabic: the conflict in Arabic words under Slug', (
    tester,
  ) async {
    final h = await _open(tester, locale: 'ar');
    await _business(h, name: 'Sabah Coffee');
    await _next(h);
    await _branch(h);
    await _next(h);
    await _owner(h);
    await _create(h);
    expect(find.text(h.t('errors.conflict')), findsOneWidget);
    expect(_textOf(tester, 'slug'), 'sabah-coffee');
  });

  testWidgets('ADM-ORG-057 the server\'s slug rules arrive as a toast on '
      'step 3', (tester) async {
    final h = await _open(tester);
    await _business(h);
    await _type(h, 'slug', 'ab');
    await _next(h);
    await _branch(h);
    await _next(h);
    await _owner(h);
    await _create(h);
    await h.expectToast('That short name has to be at least three characters.');
    expect(find.text('Step 3 of 3 · Owner'), findsOneWidget);
    await h.tapText('Back');
    await h.tapText('Back');
    await _type(h, 'slug', 'madar');
    await _next(h);
    await _next(h);
    await _create(h);
    await h.expectToast('That short name is reserved.');
  });

  testWidgets('ADM-ORG-057 an Arabic-only name leaves the slug empty: '
      'required until a Latin one is typed', (tester) async {
    final h = await _open(tester);
    await _business(h, name: 'ليالي');
    expect(_textOf(tester, 'slug'), '');
    await _next(h);
    expect(find.text('This field is required'), findsOneWidget);
    await _type(h, 'slug', 'layali-2');
    await _next(h);
    expect(find.text('Step 2 of 3 · First branch'), findsOneWidget);
  });

  testWidgets('ADM-ORG-059 the wizard checks the email as typed: a leading '
      'space is invalid', (tester) async {
    final h = await _open(tester);
    await _toOwner(h);
    await _owner(h, email: ' mona@drops.test');
    await _create(h);
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(h.server.callsTo('/orgs/provision'), isEmpty);
  });

  testWidgets('ADM-ORG-025 a phone shows the wizard full screen', (
    tester,
  ) async {
    final h = await _open(tester, size: DashSize.phone, locale: 'ar');
    expect(find.text(h.t('orgs.newTitle')), findsOneWidget);
    expect(find.bySemanticsLabel(h.t('common.close')), findsWidgets);
    await _business(h);
    await _next(h);
    expect(
      find.text(
        '${h.t('orgs.wizard.stepOf', args: {'current': 2, 'total': 3})}'
        ' · ${h.t('orgs.wizard.stepBranch')}',
      ),
      findsOneWidget,
    );
  });
}
