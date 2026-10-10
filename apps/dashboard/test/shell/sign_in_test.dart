// Sign-in: validation, the refusal in the reader's language, the eye, the
// way back, the brand panel on a wide window only.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _email = ValueKey('signin-email');
const _password = ValueKey('signin-password');
const _submit = ValueKey('signin-submit');

void main() {
  testWidgets(
    'ADM-APP-006 ADM-APP-007: empty: both fields say they are required, '
    'nothing is sent',
    (tester) async {
      final h = await pumpShell(tester, persona: null);
      await h.tapKey(_submit);
      expect(text('This field is required'), findsNWidgets(2));
      expect(h.server.callsTo('/auth/login'), isEmpty);
      await h.shot('sign-in/required');
    },
  );

  testWidgets('ADM-APP-006: a malformed email is refused before sending', (
    tester,
  ) async {
    final h = await pumpShell(tester, persona: null);
    await h.enterText(find.byKey(_email), 'nour@sabah');
    await h.enterText(find.byKey(_password), 'x');
    await h.tapKey(_submit);
    expect(text('Enter a valid email'), findsOneWidget);
    expect(h.server.callsTo('/auth/login'), isEmpty);
    // Fixing it clears the message (re-checked on change).
    await h.enterText(find.byKey(_email), 'nour@sabah.test');
    expect(text('Enter a valid email'), findsNothing);
  });

  testWidgets(
    'ADM-APP-012: a wrong password: the refusal toast, still signed out',
    (tester) async {
      final h = await pumpShell(tester, persona: null);
      await h.enterText(find.byKey(_email), Persona.owner.email);
      await h.enterText(find.byKey(_password), 'wrong');
      await h.tapKey(_submit);
      expect(h.server.callsTo('/auth/login'), hasLength(1));
      expect(h.location.path, '/login');
      await h.shot('sign-in/refused');
      await h.expectToast('Invalid credentials');
    },
  );

  testWidgets('ADM-APP-012: the refusal in Arabic is Arabic', (tester) async {
    final h = await pumpShell(tester, persona: null, locale: 'ar');
    await h.enterText(find.byKey(_email), Persona.owner.email);
    await h.enterText(find.byKey(_password), 'wrong');
    await h.tapKey(_submit);
    await h.expectToast('بيانات الدخول غير صحيحة');
  });

  testWidgets('ADM-APP-012: a server failure shows its words', (tester) async {
    final h = await pumpShell(tester, persona: null);
    h.server.fail(
      'POST',
      '/auth/login',
      MockResponse.error(503, 'The service is restarting, try again shortly'),
    );
    await h.enterText(find.byKey(_email), Persona.owner.email);
    await h.enterText(find.byKey(_password), Persona.password);
    await h.tapKey(_submit);
    await h.expectToast('The service is restarting, try again shortly');
  });

  testWidgets('ADM-APP-008: the eye shows and hides the password', (
    tester,
  ) async {
    final h = await pumpShell(tester, persona: null);
    expect(labelled('Show password'), findsOneWidget);
    await h.tap(labelled('Show password'));
    expect(labelled('Hide password'), findsOneWidget);
    final field = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(_password),
        matching: find.byType(EditableText),
      ),
    );
    expect(field.obscureText, isFalse);
  });

  testWidgets('ADM-APP-009 ADM-APP-011: signs in and opens home', (
    tester,
  ) async {
    final h = await pumpShell(tester, persona: null);
    await h.enterText(find.byKey(_email), Persona.manager.email);
    await h.enterText(find.byKey(_password), Persona.password);
    await h.tapKey(_submit);
    expect(h.location.path, '/');
    expect(h.container.read(currentSessionProvider)?.user.name, 'Karim Adel');
  });

  testWidgets(
    'ADM-APP-003 ADM-APP-014: the brand panel shows on a wide window, '
    'not on a phone',
    (tester) async {
      await pumpShell(tester, persona: null);
      expect(text('Coffee Shop Management'), findsOneWidget);
      expect(text('Till'), findsOneWidget);
      await pumpShell(tester, persona: null, size: DashSize.phone);
      expect(text('Coffee Shop Management'), findsNothing);
      expect(text('© 2026 Madar. All rights reserved.'), findsOneWidget);
    },
  );

  testWidgets('ADM-APP-013: the legal links open outside the app', (
    tester,
  ) async {
    final h = await pumpShell(tester, persona: null);
    await h.tapText('Privacy Policy');
    expect(
      h.openedLinks.single.toString(),
      'https://legal.madar-pos.cloud/privacy-policy.html',
    );
  });

  testWidgets('ADM-APP-005 ADM-APP-007 ADM-APP-009: Enter in the email field '
      'signs in; the fields offer autofill', (tester) async {
    final h = await pumpShell(tester, persona: null);
    expect(find.byType(AutofillGroup), findsOneWidget);
    List<String>? hints(Key key) => tester
        .widget<EditableText>(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(EditableText),
          ),
        )
        .autofillHints
        ?.toList();
    expect(hints(_email), [AutofillHints.email]);
    expect(hints(_password), [AutofillHints.password]);
    await h.enterText(find.byKey(_password), Persona.password);
    // Typing last into the email field leaves the focus there.
    await h.enterText(find.byKey(_email), Persona.owner.email);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    final calls = h.server.callsTo('/auth/login');
    expect(calls, hasLength(1));
    final body = calls.single.body! as Map;
    expect(body['email'], Persona.owner.email);
    expect(body['password'], Persona.password);
    expect(h.location.path, '/');
  });

  testWidgets('ADM-APP-010: while the sign-in runs, a spinner; a second tap '
      'sends nothing', (tester) async {
    final h = await pumpShell(tester, persona: null);
    final gate = h.server.hold('POST', '/auth/login');
    await h.enterText(find.byKey(_email), Persona.owner.email);
    await h.enterText(find.byKey(_password), Persona.password);
    await h.tapKey(_submit);
    final spinner = find.descendant(
      of: find.byKey(_submit),
      matching: find.byType(CircularProgressIndicator),
    );
    expect(spinner, findsOneWidget);
    await tester.tap(find.byKey(_submit), warnIfMissed: false);
    await h.settle();
    expect(h.server.callsTo('/auth/login'), hasLength(1));
    gate.release();
    await h.settle();
    expect(h.location.path, '/');
  });

  testWidgets('ADM-APP-012 ADM-APP-121: a suspended business, then too many '
      'tries: each says so, still signed out', (tester) async {
    final h = await pumpShell(tester, persona: null);
    final suspended = MockResponse.error(
      403,
      'Forbidden: This business is suspended',
      code: 'ORG_SUSPENDED',
    );
    h.server.fail('POST', '/auth/login', suspended);
    await h.enterText(find.byKey(_email), Persona.owner.email);
    await h.enterText(find.byKey(_password), Persona.password);
    await h.tapKey(_submit);
    await h.expectToast(h.refusalWords(suspended));
    expect(h.location.path, '/login');
    final busy = MockResponse.error(
      429,
      'Too many sign-in attempts',
      retryAfterSeconds: 60,
    );
    h.server.fail('POST', '/auth/login', busy);
    await h.tapKey(_submit);
    await h.expectToast(h.refusalWords(busy));
    expect(h.location.path, '/login');
  });
}
