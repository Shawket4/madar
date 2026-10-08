// Smoke test for the review unit: the page mounts through the real shell
// on the mock server (no unmatched route, no missing word, no overflow).
import 'package:dashboard_admin/dashboard_admin.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('the Review page opens', (tester) async {
    final h = await DashHarness.pump(
      tester,
      areas: const [adminArea],
      path: '/access/review',
      persona: Persona.owner,
    );
    expect(h.location.path, '/access/review');
    expect(find.text(h.t('access.review.title')), findsWidgets);
    await h.shot('review/scaffold');
  });
}
