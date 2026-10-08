// Sign-in: validation, the refusal in the reader's language, the eye, the
// way back, the brand panel on a wide window only.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _email = ValueKey('signin-email');
const _password = ValueKey('signin-password');
const _submit = ValueKey('signin-submit');

void main() {
  testWidgets('empty: both fields say they are required, nothing is sent', (
    tester,
  ) async {
    final h = await pumpShell(tester, persona: null);
    await h.tapKey(_submit);
    expect(text('This field is required'), findsNWidgets(2));
    expect(h.server.callsTo('/auth/login'), isEmpty);
    await h.shot('sign-in/required');
  });

  testWidgets('a malformed email is refused before sending', (tester) async {
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

  testWidgets('a wrong password: the refusal toast, still signed out', (
    tester,
  ) async {
    final h = await pumpShell(tester, persona: null);
    await h.enterText(find.byKey(_email), Persona.owner.email);
    await h.enterText(find.byKey(_password), 'wrong');
    await h.tapKey(_submit);
    expect(h.server.callsTo('/auth/login'), hasLength(1));
    expect(h.location.path, '/login');
    await h.shot('sign-in/refused');
    await h.expectToast('Invalid credentials');
  });

  testWidgets('the refusal in Arabic is Arabic', (tester) async {
    final h = await pumpShell(tester, persona: null, locale: 'ar');
    await h.enterText(find.byKey(_email), Persona.owner.email);
    await h.enterText(find.byKey(_password), 'wrong');
    await h.tapKey(_submit);
    await h.expectToast('بيانات الدخول غير صحيحة');
  });

  testWidgets('a server failure shows its words', (tester) async {
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

  testWidgets('the eye shows and hides the password', (tester) async {
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

  testWidgets('signs in and opens home', (tester) async {
    final h = await pumpShell(tester, persona: null);
    await h.enterText(find.byKey(_email), Persona.manager.email);
    await h.enterText(find.byKey(_password), Persona.password);
    await h.tapKey(_submit);
    expect(h.location.path, '/');
    expect(h.container.read(currentSessionProvider)?.user.name, 'Karim Adel');
  });

  testWidgets('the brand panel shows on a wide window, not on a phone', (
    tester,
  ) async {
    await pumpShell(tester, persona: null);
    expect(text('Coffee Shop Management'), findsOneWidget);
    expect(text('Till'), findsOneWidget);
    await pumpShell(tester, persona: null, size: DashSize.phone);
    expect(text('Coffee Shop Management'), findsNothing);
    expect(text('© 2026 Madar. All rights reserved.'), findsOneWidget);
  });

  testWidgets('the legal links open outside the app', (tester) async {
    final h = await pumpShell(tester, persona: null);
    await h.tapText('Privacy Policy');
    expect(
      h.openedLinks.single.toString(),
      'https://legal.madar-pos.cloud/privacy-policy.html',
    );
  });
}
