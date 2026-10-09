// "New integration credential" (SET-INT-015..019).
import 'dart:math';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/integrations/credential_dialog.dart';
import 'package:dashboard_setup/src/integrations/credential_util.dart';
import 'package:dashboard_setup/src/integrations/secure_random.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final Finder _dialog = find.byType(CredentialDialog);
Finder _in(Finder f) => find.descendant(of: _dialog, matching: f);
final Finder _label = _in(find.byKey(const ValueKey('integrations.label')));
final Finder _branch = _in(find.byKey(const ValueKey('integrations.branch')));

/// The generated username on screen.
String _username(WidgetTester tester) => tester
    .widgetList<SelectableText>(_in(find.byType(SelectableText)))
    .single
    .data!;

/// The issue dialog open over the pane, as a platform admin.
Future<DashHarness> _open(
  WidgetTester tester, {
  ({MockServer server, MockDb db})? backend,
  DashSize size = DashSize.desktop,
}) async {
  final h = await pumpIntegrations(
    tester,
    persona: Persona.platform,
    backend: backend ?? integrationsServer(persona: Persona.platform),
    size: size,
  );
  await h.tap(inPage(find.byKey(const ValueKey('integrations-issue'))));
  expect(_dialog, findsOneWidget);
  return h;
}

Future<void> _fill(DashHarness h, {String label = 'Rue — One Ninety'}) async {
  await h.enterText(_label, label);
  await h.tap(_branch);
  await h.tap(top('Maadi'));
}

/// A fixed random source, so the suffix is known.
void _pinRandom() {
  IntegrationsRandom.source = () => Random(7);
  addTearDown(IntegrationsRandom.reset);
}

void main() {
  testWidgets('SET-INT-015 title, description, 480 wide', (tester) async {
    final h = await _open(tester);
    expect(_in(find.text('New integration credential')), findsOneWidget);
    expect(_in(find.text(h.t('integrations.newHint'))), findsOneWidget);
    expect(credentialDialogWidth, 480);
    expect(tester.getSize(_dialog).width, lessThanOrEqualTo(480));
  });

  testWidgets('SET-INT-015 reopening starts empty with a new suffix', (
    tester,
  ) async {
    final h = await _open(tester);
    await h.enterText(_label, 'Somebody');
    final first = _username(tester);
    await h.tap(top('Cancel'));
    await h.tap(inPage(find.byKey(const ValueKey('integrations-issue'))));
    expect(
      tester.widget<DashTextField>(_label).value,
      isEmpty,
    );
    expect(_username(tester), startsWith('partner-'));
    expect(_username(tester), isNot(first.replaceFirst('somebody', 'partner')));
  });

  testWidgets('SET-INT-016 Label: required, at most 120, its placeholder and '
      'hint', (tester) async {
    final h = await _open(tester);
    final field = tester.widget<DashTextField>(_label);
    expect(field.label, 'Label');
    expect(field.placeholder, 'Rue — One Ninety');
    expect(field.description, 'Who this credential is for. Only you see it.');
    await h.tap(top('Issue credential'));
    expect(_in(find.text('This field is required')), findsOneWidget);
    await h.enterText(_label, '   ');
    await h.tap(top('Issue credential'));
    expect(_in(find.text('This field is required')), findsOneWidget);
    await h.enterText(_label, 'x' * 121);
    await h.tap(top('Issue credential'));
    expect(_in(find.text('At most 120 characters')), findsOneWidget);
    expect(h.server.callsTo(IntegrationsRoutes.create)
        .where((c) => c.method == 'POST'), isEmpty);
  });

  testWidgets('SET-INT-017 Branch: the org\'s active branches, required, '
      'its hint', (tester) async {
    final m = integrationsServer(persona: Persona.platform);
    m.db['branches'].update(SeedIds.newCairo, {'is_active': false});
    final h = await _open(tester, backend: m);
    final select = tester.widget<DashSelectField<String>>(_branch);
    expect(select.placeholder, 'Select a branch');
    expect(select.description, h.t('integrations.branchHint'));
    expect([for (final o in select.options) o.label], [
      'Heliopolis',
      'Maadi',
      'Zamalek',
    ]);
    await h.enterText(_label, 'Rue');
    await h.tap(top('Issue credential'));
    expect(_in(find.text('Choose a branch')), findsOneWidget);
  });

  testWidgets('SET-INT-017 an active warehouse is never offered', (
    tester,
  ) async {
    final m = integrationsServer(persona: Persona.platform);
    final branches = m.db['branches'];
    branches.insert({
      ...branches.get(SeedIds.zamalek),
      'id': 'wh-main',
      'name': 'Main Warehouse',
      'code': 'WH',
      'kind': 'warehouse',
    }, timestamps: false);
    final h = await _open(tester, backend: m);
    final select = tester.widget<DashSelectField<String>>(_branch);
    expect(
      [for (final o in select.options) o.label],
      isNot(contains('Main Warehouse')),
    );
    expect(select.options, hasLength(4));
    await h.tap(_branch);
    expect(top('Main Warehouse'), findsNothing);
  });

  testWidgets('SET-INT-018 the username follows the label; Regenerate draws '
      'a new suffix', (tester) async {
    final h = await _open(tester);
    expect(_in(find.text('Username')), findsOneWidget);
    expect(_in(find.text(h.t('integrations.usernameHint'))), findsOneWidget);
    expect(_username(tester), matches(RegExp(r'^partner-[a-km-z2-9]{6}$')));
    await h.enterText(_label, 'Café Rouge');
    final first = _username(tester);
    expect(first, matches(RegExp(r'^cafe-rouge-[a-km-z2-9]{6}$')));
    await h.enterText(_label, 'Café Rouge — Zamalek');
    // Typing re-slugs the prefix; the suffix stays.
    expect(_username(tester), 'cafe-rouge-zamalek-${first.substring(11)}');
    await h.tap(_in(find.bySemanticsLabel('Regenerate')));
    expect(_username(tester), startsWith('cafe-rouge-zamalek-'));
    expect(_username(tester), isNot('cafe-rouge-zamalek-${first.substring(11)}'));
  });

  testWidgets('SET-INT-019 Issue: {name, branch_id, username} → the list '
      'again → closes → the handoff in "created" mode', (tester) async {
    _pinRandom();
    final h = await _open(tester);
    final seen = watchInvalidations(h);
    await _fill(h, label: '  Rue — One Ninety  ');
    final username = _username(tester);
    await h.tap(top('Issue credential'));
    final call = h.server
        .callsTo(IntegrationsRoutes.create)
        .where((c) => c.method == 'POST')
        .single;
    expect(call.body, {
      'branch_id': SeedIds.maadi,
      'name': 'Rue — One Ninety',
      'username': username,
    });
    expect(seen, [
      ['/integrations/credentials'],
    ]);
    expect(listCalls(h), 2);
    expect(_dialog, findsNothing);
    expect(h.location.queryParameters.containsKey('edit'), isFalse);
    expect(top('Credentials for Rue — One Ninety'), findsOneWidget);
    expect(top(h.t('integrations.handoff.createdHint')), findsOneWidget);
    expect(stat(tester, 'integrations-total').value, 4);
  });

  testWidgets('SET-INT-019 a 409 draws a new suffix and retries once, '
      'silently', (tester) async {
    final m = integrationsServer(persona: Persona.platform);
    final h = await _open(tester, backend: m);
    await _fill(h);
    final firstTry = _username(tester);
    m.server.fail(
      'POST',
      IntegrationsRoutes.create,
      MockResponse.conflict(IntegrationsRefusals.taken),
    );
    await h.tap(top('Issue credential'));
    final posts = h.server
        .callsTo(IntegrationsRoutes.create)
        .where((c) => c.method == 'POST')
        .toList();
    expect(posts, hasLength(2));
    final second = (posts[1].body! as Map)['username'] as String;
    expect(second, isNot(firstTry));
    expect(second, startsWith('rue-one-ninety-'));
    expect(top('Credentials for Rue — One Ninety'), findsOneWidget);
  });

  testWidgets('SET-INT-019 a second 409 (or any other failure) toasts and '
      'keeps the dialog', (tester) async {
    final m = integrationsServer(persona: Persona.platform);
    final h = await _open(tester, backend: m);
    await _fill(h);
    final taken = MockResponse.conflict(IntegrationsRefusals.taken);
    m.server.fail('POST', IntegrationsRoutes.create, taken, times: 2);
    await h.tap(top('Issue credential'));
    expect(_dialog, findsOneWidget);
    expect(find.byKey(const ValueKey('handoff-dialog')), findsNothing);
    await h.expectToast(h.refusalWords(taken));
  });

  testWidgets('SET-INT-019 busy: Cancel and Issue are disabled', (
    tester,
  ) async {
    final m = integrationsServer(persona: Persona.platform);
    final h = await _open(tester, backend: m);
    await _fill(h);
    final gate = m.server.hold('POST', IntegrationsRoutes.create);
    await h.tap(top('Issue credential'));
    DashButton button(String label) => tester.widget<DashButton>(
      _in(find.widgetWithText(DashButton, label)),
    );
    expect(button('Cancel').onPressed, isNull);
    expect(button('Issue credential').onPressed, isNull);
    gate.release();
    await h.settle();
    expect(_dialog, findsNothing);
  });

  testWidgets('SET-INT-019 Escape or the barrier mid-issue keeps the dialog, '
      'so the secret still reaches the handoff', (tester) async {
    final m = integrationsServer(persona: Persona.platform);
    final h = await _open(tester, backend: m);
    await _fill(h);
    final gate = m.server.hold('POST', IntegrationsRoutes.create);
    await h.tap(top('Issue credential'));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await h.settle();
    expect(_dialog, findsOneWidget);
    await tester.tapAt(const Offset(4, 4));
    await h.settle();
    expect(_dialog, findsOneWidget);
    gate.release();
    await h.settle();
    expect(_dialog, findsNothing);
    expect(top('Credentials for Rue — One Ninety'), findsOneWidget);
  });

  testWidgets('SET-INT-019 no secure random: the reason, nothing created', (
    tester,
  ) async {
    final h = await _open(tester);
    await _fill(h);
    IntegrationsRandom.source = () => null;
    addTearDown(IntegrationsRandom.reset);
    await h.tap(top('Issue credential'));
    expect(
      h.server.callsTo(IntegrationsRoutes.create).where(
        (c) => c.method == 'POST',
      ),
      isEmpty,
    );
    expect(_dialog, findsOneWidget);
    await h.expectToast(h.t('integrations.handoff.noSecureRandom'));
  });

  test('SET-INT-018 the slug and the suffix alphabet', () {
    expect(credentialSlug('Rue — One Ninety'), 'rue-one-ninety');
    expect(credentialSlug('Café Rouge'), 'cafe-rouge');
    expect(credentialSlug('مقهى الصباح'), '');
    expect(credentialSlug('ﬁne ①'), 'fine-1');
    expect(credentialSlug('a' * 50), 'a' * 40);
    expect(buildUsername('مقهى', 'abc234'), 'partner-abc234');
    expect(usernameSuffixAlphabet, 'abcdefghijkmnpqrstuvwxyz23456789');
    final suffix = randomUsernameSuffix((b) => b.fillRange(0, b.length, 33));
    expect(suffix, 'bbbbbb');
  });
}
