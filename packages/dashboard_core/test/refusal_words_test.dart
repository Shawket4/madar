// The mock's refusals worded as real mode words them (madar-core
// `answer_words` plus the app's `errors.codes.*`), LEDGER line 25.
import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, ApiRequest, DashboardApi;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/rig.dart';

void main() {
  final en = Translator(syncedStrings(), 'en');
  final ar = Translator(syncedStrings(), 'ar');
  String said(int status, String message, Translator t, {String? code}) =>
      wordRefusal(
        ApiException(
          status: status,
          code: code,
          message: message,
          details: {'error': message, 'code': ?code},
        ),
        t,
      ).message;

  test('English: the server\'s sentence without its kind', () {
    expect(said(409, 'Conflict: Already paid.', en), 'Already paid.');
    expect(said(400, 'Bad request: Name is required', en), 'Name is required');
    expect(said(404, 'Not found: Order', en), 'Order');
    expect(said(502, 'HTTP 502', en), en('errors.server'));
  });

  test('an uncoded 403 or 429 is the words for it, in both languages', () {
    for (final t in [en, ar]) {
      expect(
        said(403, 'Forbidden: missing orders.void', t),
        t('errors.unauthorized'),
      );
      expect(said(429, 'Slow down', t), t('errors.tooManyRequests'));
    }
  });

  test('Arabic never reads the server\'s English: the status\'s words', () {
    expect(said(409, 'Conflict: Already paid.', ar), ar('errors.conflict'));
    expect(said(400, 'Bad request: x', ar), ar('errors.validation'));
    expect(said(404, 'Not found: x', ar), ar('errors.notFound'));
    expect(said(500, 'Database error: x', ar), ar('errors.server'));
  });

  test('a coded refusal reads the app\'s errors.codes.*; an unknown code '
      'falls through to the rules', () {
    for (final t in [en, ar]) {
      expect(
        said(409, 'Conflict: plan changed', t, code: 'PLAN_CHANGED'),
        t('errors.codes.PLAN_CHANGED'),
      );
    }
    expect(said(409, 'Conflict: odd', en, code: 'NO_SUCH_CODE'), 'odd');
    expect(
      said(403, 'Forbidden: odd', en, code: 'NO_SUCH_CODE'),
      'odd',
      reason: 'a coded 403 keeps its sentence',
    );
  });

  test('the transport words a refusal and leaves an answer alone', () async {
    final server = MockServer()
      ..on('GET', '/branches', (_) => MockResponse.ok(const <Object?>[]))
      ..on('GET', '/orgs', (req) => req.conflict('Already there.'));
    final api = DashboardApi(RefusalWordingTransport(server, () => ar));
    expect(await api.branches.listBranches(orgId: 'o'), isEmpty);
    await expectLater(
      api.orgs.listOrgs(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 409)
            .having((e) => e.message, 'message', ar('errors.conflict')),
      ),
    );
    // An unreached call (status 0) is the offline seam's to word.
    final offline = MockServer()..offline = true;
    await expectLater(
      RefusalWordingTransport(
        offline,
        () => ar,
      ).send(const ApiRequest(method: 'GET', path: '/x')),
      throwsA(isA<ApiException>().having((e) => e.status, 'status', 0)),
    );
  });
}
