// The router's guards and the page gates, as the web runs them.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  group('dashRedirect (pure)', () {
    const known = OrgModulesState(modules: ['pos', 'dawam'], known: true);
    String? r(
      String loc, {
      SessionStatus s = SessionStatus.signedIn,
      SignOutReason? why,
      bool onboarding = false,
      OrgModulesState modules = known,
    }) => dashRedirect(
      uri: Uri.parse(loc),
      session: s,
      signedOutBecause: why,
      toOnboarding: onboarding,
      modules: modules,
    );

    test('legacy paths land on their replacement, query as the web keeps', () {
      expect(r('/analytics'), '/reports/operations');
      expect(r('/inventory'), '/inventory/today');
      expect(r('/menu/'), '/menu/items');
      expect(
        r('/users?edit=u1&branches=1&x=2'),
        '/access/users?edit=u1&branches=1',
      );
      expect(r('/permissions?user=u1&role=r'), '/access/roles?user=u1');
      expect(r('/shifts?from=a&to=b'), '/tills?from=a&to=b');
      expect(r('/qr?x=1'), '/settings/qr');
    });

    test('signed out: every page goes to sign-in with the way back', () {
      expect(
        r('/orders?order=7', s: SessionStatus.signedOut),
        '/login?redirect=%2Forders%3Forder%3D7',
      );
      expect(r('/', s: SessionStatus.signedOut), '/login?redirect=%2F');
      expect(r('/login', s: SessionStatus.signedOut), isNull);
    });

    test('signing out on purpose opens a bare sign-in', () {
      expect(
        r('/orders', s: SessionStatus.signedOut, why: SignOutReason.requested),
        '/login',
      );
      expect(
        r(
          '/orders',
          s: SessionStatus.signedOut,
          why: SignOutReason.unauthorized,
        ),
        '/login?redirect=%2Forders',
      );
    });

    test('nothing is decided while the session restores', () {
      expect(r('/orders', s: SessionStatus.loading), isNull);
      expect(r('/login', s: SessionStatus.loading), isNull);
    });

    test('signed in, /login goes on to a safe redirect or home', () {
      expect(r('/login'), '/');
      expect(r('/login?redirect=%2Ftills%3Fx%3D1'), '/tills?x=1');
      expect(r('/login?redirect=https%3A%2F%2Fevil.test'), '/');
      expect(r('/login?redirect=%2F%2Fevil.test'), '/');
      expect(r('/login?redirect=%2Flogin'), '/');
    });

    test('the onboarding gate and a Dawam-only home', () {
      expect(r('/orders', onboarding: true), '/onboarding');
      expect(r('/onboarding', onboarding: true), isNull);
      const dawam = OrgModulesState(modules: ['dawam'], known: true);
      expect(r('/', modules: dawam), '/staff/team');
      expect(r('/', modules: const OrgModulesState()), isNull);
      expect(r('/'), isNull);
    });
  });

  group('in the app', () {
    testWidgets('signed out at a page: sign-in, then back to that page', (
      tester,
    ) async {
      final h = await pumpShell(tester, path: '/tills', persona: null);
      expect(h.location.path, '/login');
      expect(h.location.queryParameters['redirect'], '/tills');
      await h.enterText(
        find.byKey(const ValueKey('signin-email')),
        Persona.owner.email,
      );
      await h.enterText(
        find.byKey(const ValueKey('signin-password')),
        Persona.password,
      );
      await h.tapKey(const ValueKey('signin-submit'));
      expect(h.location.path, '/tills');
      expect(text('Tills'), findsWidgets);
    });

    testWidgets('a legacy link lands on the page that replaced it', (
      tester,
    ) async {
      final h = await pumpShell(tester, path: '/users?edit=x&tab=y');
      expect(h.location.path, '/access/users');
      expect(h.location.queryParameters, {'edit': 'x'});
    });

    testWidgets('signed in, /login goes home', (tester) async {
      final h = await pumpShell(tester, path: '/login');
      expect(h.location.path, '/');
    });

    testWidgets('a page of a switched-off module says so', (tester) async {
      final h = await pumpShell(
        tester,
        path: '/orders',
        persona: Persona.dawamOnly,
      );
      expect(text("Not part of this business's plan"), findsOneWidget);
      expect(
        text(
          'Madar POS is switched off for this business. Ask Madar to switch it on.',
        ),
        findsOneWidget,
      );
      await h.shot('gates/module-off');
    });

    testWidgets('a Dawam-only home is the team', (tester) async {
      final h = await pumpShell(tester, persona: Persona.dawamOnly);
      expect(h.location.path, '/staff/team');
    });

    testWidgets('a page without the capability is Restricted', (tester) async {
      final h = await pumpShell(
        tester,
        path: '/inventory/today',
        persona: Persona.limited,
      );
      expect(text('Not available on this account'), findsOneWidget);
      expect(text('Today'), findsWidgets);
      await h.shot('gates/restricted');
    });

    testWidgets(
      'platform-only pages: Restricted for an owner, open for platform',
      (tester) async {
        await pumpShell(tester, path: '/orgs');
        expect(text('Not available on this account'), findsOneWidget);
        await pumpShell(tester, path: '/orgs', persona: Persona.platform);
        expect(text('Not available on this account'), findsNothing);
        expect(text('Organizations'), findsWidgets);
      },
    );

    testWidgets('an unknown path is the not-found page, inside the frame', (
      tester,
    ) async {
      final h = await pumpShell(tester, path: '/no/such/page');
      expect(text('Page not found'), findsOneWidget);
      expect(text('Dashboard'), findsWidgets); // the sidebar is there
      await h.shot('gates/not-found');
      await h.tapText('Back to the dashboard');
      expect(h.location.path, '/');
    });

    testWidgets('a 401 signs out once and keeps the way back', (tester) async {
      final h = await pumpShell(tester, path: '/tills');
      final api = h.container.read(apiProvider);
      h.server.fail(
        'GET',
        '/branches',
        MockResponse.unauthorized('Token expired'),
        times: 3,
      );
      await Future.wait([
        for (var i = 0; i < 3; i++)
          api.branches
              .listBranches(orgId: SeedIds.sabahOrg)
              .then<void>((_) {}, onError: (_) {}),
      ]);
      await h.settle();
      expect(h.session.signOutCount, 1);
      expect(h.location.path, '/login');
      expect(h.location.queryParameters['redirect'], '/tills');
    });

    testWidgets('sign out from the user menu opens a bare sign-in', (
      tester,
    ) async {
      final h = await pumpShell(tester, path: '/tills');
      await h.tap(labelled('Account'));
      await h.tapText('Sign Out');
      expect(h.location.toString(), '/login');
    });
  });
}
