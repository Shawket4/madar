// Rotate, revoke, `?edit=new` and server refusals (SET-INT-011..014, 030,
// 031).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/src/integrations/credential_dialog.dart';
import 'package:dashboard_setup/src/integrations/secure_random.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

final String _rue = IntegrationsSeed.id('rue');

Finder _rotateRue() => find.byKey(ValueKey('integrations-rotate-$_rue'));
Finder _revokeRue() => find.byKey(ValueKey('integrations-revoke-$_rue'));
final Finder _handoff = find.byKey(const ValueKey('handoff-dialog'));

/// Calls to [template] with [method].
int _calls(DashHarness h, String method, String template) =>
    h.server.callsTo(template).where((c) => c.method == method).length;

void main() {
  group('rotate', () {
    testWidgets('SET-INT-011 a device without a secure random source: the '
        'reason, and nothing is asked', (tester) async {
      IntegrationsRandom.source = () => null;
      addTearDown(IntegrationsRandom.reset);
      final h = await pumpIntegrations(tester, persona: Persona.platform);
      await h.tap(_rotateRue());
      expect(top('Rotate password?'), findsNothing);
      expect(_calls(h, 'POST', IntegrationsRoutes.rotate), 0);
      await h.expectToast(h.t('integrations.handoff.noSecureRandom'));
    });

    testWidgets('SET-INT-012 confirm names the partner; Cancel asks nothing', (
      tester,
    ) async {
      final h = await pumpIntegrations(tester, persona: Persona.platform);
      await h.tap(_rotateRue());
      expect(top('Rotate password?'), findsOneWidget);
      expect(
        top(
          'Rue — One Ninety will stop working immediately until the '
          'partner updates to the new password.',
        ),
        findsOneWidget,
      );
      await h.tap(top('Cancel'));
      expect(_calls(h, 'POST', IntegrationsRoutes.rotate), 0);
      expect(_handoff, findsNothing);
    });

    testWidgets('SET-INT-012 Rotate → the request, the list again, the '
        'handoff in "rotated" mode', (tester) async {
      final h = await pumpIntegrations(tester, persona: Persona.platform);
      final seen = watchInvalidations(h);
      await h.tap(_rotateRue());
      await h.tap(top('Rotate'));
      final call = h.server.callsTo(IntegrationsRoutes.rotate).single;
      expect(call.path, '/integrations/credentials/$_rue/rotate');
      expect(seen, [
        ['/integrations/credentials'],
      ]);
      expect(listCalls(h), 2);
      expect(top('New password for Rue — One Ninety'), findsOneWidget);
      expect(top(h.t('integrations.handoff.rotatedHint')), findsOneWidget);
      // Saved at once: Done closes without asking.
      expect(h.files.saved, hasLength(1));
      await h.tap(top('Done'));
      expect(_handoff, findsNothing);
    });

    testWidgets('SET-INT-012 a failed rotation toasts the server\'s words; '
        'no handoff', (tester) async {
      final m = integrationsServer(persona: Persona.platform);
      final boom = MockResponse.notFound(IntegrationsRefusals.notFound);
      m.server.fail('POST', IntegrationsRoutes.rotate, boom);
      final h = await pumpIntegrations(
        tester,
        persona: Persona.platform,
        backend: m,
      );
      await h.tap(_rotateRue());
      await h.tap(top('Rotate'));
      expect(_handoff, findsNothing);
      expect(listCalls(h), 1);
      await h.expectToast(h.refusalWords(boom));
    });
  });

  group('revoke', () {
    testWidgets('SET-INT-013 confirm → DELETE → the list again → "Access '
        'revoked"; the row turns Revoked', (tester) async {
      final h = await pumpIntegrations(tester, persona: Persona.platform);
      final seen = watchInvalidations(h);
      await h.tap(_revokeRue());
      expect(top('Revoke access?'), findsOneWidget);
      expect(
        top(h.t('integrations.revokeHint', args: {'name': 'Rue — One Ninety'})),
        findsOneWidget,
      );
      await h.tap(top('Revoke'));
      expect(
        h.server.callsTo(IntegrationsRoutes.revoke).single.path,
        '/integrations/credentials/$_rue',
      );
      expect(seen, [
        ['/integrations/credentials'],
      ]);
      expect(listCalls(h), 2);
      await h.expectToast('Access revoked');
      expect(stat(tester, 'integrations-active').value, 1);
      expect(stat(tester, 'integrations-revoked').value, 2);
      expect(_rotateRue(), findsNothing);
      expect(_revokeRue(), findsNothing);
    });

    testWidgets('SET-INT-013 Cancel keeps it', (tester) async {
      final h = await pumpIntegrations(tester, persona: Persona.platform);
      await h.tap(_revokeRue());
      await h.tap(top('Cancel'));
      expect(_calls(h, 'DELETE', IntegrationsRoutes.revoke), 0);
    });

    testWidgets('SET-INT-013 SET-INT-030 a refused revoke toasts the '
        'server\'s words and changes nothing', (tester) async {
      final m = integrationsServer(persona: Persona.platform);
      final denied = MockResponse.forbidden('Super admin access required');
      m.server.fail('DELETE', IntegrationsRoutes.revoke, denied);
      final h = await pumpIntegrations(
        tester,
        persona: Persona.platform,
        backend: m,
      );
      await h.tap(_revokeRue());
      await h.tap(top('Revoke'));
      expect(listCalls(h), 1);
      expect(stat(tester, 'integrations-active').value, 2);
      await h.expectToast(h.refusalWords(denied));
    });

    testWidgets('SET-INT-030 a refused rotation toasts the refusal', (
      tester,
    ) async {
      final m = integrationsServer(persona: Persona.platform);
      final denied = MockResponse.forbidden('Super admin access required');
      m.server.fail('POST', IntegrationsRoutes.rotate, denied);
      final h = await pumpIntegrations(
        tester,
        persona: Persona.platform,
        backend: m,
      );
      await h.tap(_rotateRue());
      await h.tap(top('Rotate'));
      expect(_handoff, findsNothing);
      await h.expectToast(h.refusalWords(denied));
    });
  });

  group('?edit=new', () {
    testWidgets('SET-INT-014 a platform admin: the issue dialog opens; '
        'closing it clears the param', (tester) async {
      final h = await pumpIntegrations(
        tester,
        persona: Persona.platform,
        query: '?edit=new',
      );
      expect(find.byType(CredentialDialog), findsOneWidget);
      await h.tap(top('Cancel'));
      expect(find.byType(CredentialDialog), findsNothing);
      expect(h.location.queryParameters.containsKey('edit'), isFalse);
      expect(h.location.path, intPath);
    });

    testWidgets('SET-INT-014 SET-INT-031 anyone else: nothing opens and the '
        'param stays', (tester) async {
      final h = await pumpIntegrations(tester, query: '?edit=new');
      expect(find.byType(CredentialDialog), findsNothing);
      expect(h.location.queryParameters['edit'], 'new');
      expect(inTable(find.text('Rue — One Ninety')), findsOneWidget);
    });

    testWidgets('SET-INT-014 a platform admin with no org: nothing opens', (
      tester,
    ) async {
      await pumpIntegrations(
        tester,
        persona: Persona.platform,
        pickOrg: false,
        query: '?edit=new',
      );
      expect(find.byType(CredentialDialog), findsNothing);
    });
  });
}
