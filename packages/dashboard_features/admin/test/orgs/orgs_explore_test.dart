import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  testWidgets('explore desktop', (tester) async {
    final h = await pumpOrgs(tester);
    await h.shot('orgs/x-default');
    await h.tapKey(const ValueKey('orgs-new'));
    await h.shot('orgs/x-wizard');
    await h.tapText('Cancel');
    await h.tapText('Layali Bistro');
    await h.shot('orgs/x-dialog');
  });

  testWidgets('explore phone ar', (tester) async {
    final h = await pumpOrgs(tester, size: DashSize.phone, locale: 'ar');
    await h.shot('orgs/x-default');
  });

  testWidgets('explore owner', (tester) async {
    final h = await pumpOrgs(tester, persona: Persona.owner);
    await h.shot('orgs/x-refused');
  });
}
