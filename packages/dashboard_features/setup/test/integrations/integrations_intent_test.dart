// Intent warming on Integrations: the only press that reads is "Issue
// credential" (its dialog lists the branches); resting on it warms that
// read, so the dialog opens without asking again. Rotate and revoke are
// writes and warm nothing.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/integrations/credential_dialog.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('resting on "Issue credential" warms the branch list; the '
      'dialog opens without a second request', (tester) async {
    final h = await pumpIntegrations(tester, persona: Persona.platform);
    final issue = inPage(find.byKey(const ValueKey('integrations-issue')));
    expect(tester.widget<DashButton>(issue).onIntent, isNotNull);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    await mouse.moveTo(tester.getCenter(issue));
    await h.settle();
    final warmed = h.server.callsTo('/branches', method: 'GET').length;
    expect(warmed, 1, reason: 'one read of the org\'s branches');

    await h.tap(issue);
    expect(find.byType(CredentialDialog), findsOneWidget);
    expect(h.server.callsTo('/branches', method: 'GET'), hasLength(warmed));
    expect(
      tester
          .widget<DashSelectField<String>>(
            find.byKey(const ValueKey('integrations.branch')),
          )
          .options,
      hasLength(4),
    );
  });
}
