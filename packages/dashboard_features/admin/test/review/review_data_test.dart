// The Review page's pure rules (`flag-detail.ts`, `REASON_TONE`) and its
// mock handlers against MadarRust `src/authz/api.rs`.
import 'dart:convert';

import 'package:dashboard_admin/src/review/review_data.dart';
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashTone;
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

Future<ApiResponse> _send(
  MockServer s,
  String method,
  String path, {
  Map<String, List<String>> query = const {},
  Object? body,
}) => s.send(ApiRequest(method: method, path: path, query: query, body: body));

Object? _json(ApiResponse r) => jsonDecode(utf8.decode(r.bodyBytes));

/// The status a call answers (the mock throws a refusal as an exception).
Future<int> _status(Future<ApiResponse> call) async {
  try {
    return (await call).status;
  } on ApiException catch (e) {
    return e.status;
  }
}

void main() {
  group('ADM-REV-007/008 rules', () {
    test('ADM-REV-007 reason tones; unknown is neutral', () {
      expect(reasonTone('stale_snapshot'), DashTone.info);
      expect(reasonTone('unauthorized_offline'), DashTone.danger);
      expect(reasonTone('pin_wrong_branch'), DashTone.warning);
      expect(reasonTone('something_else'), DashTone.neutral);
    });

    test('ADM-REV-008 a staff-drink detail has words and a tone', () {
      final tones = {
        'comp_mismatch': DashTone.warning,
        'overspent': DashTone.warning,
        'device_overcounted': DashTone.info,
        'duplicate_id': DashTone.warning,
        'pool_off': DashTone.danger,
        'no_eligible_items': DashTone.danger,
        'item_not_eligible': DashTone.danger,
        'note_required': DashTone.warning,
      };
      for (final MapEntry(key: d, value: tone) in tones.entries) {
        final r = readFlagCapability('orders.staff_drink.record:$d');
        expect(r.capability, 'orders.staff_drink.record');
        expect(r.known?.tone, tone, reason: d);
        expect(
          r.known?.key,
          'access.review.details.orders_staff_drink_record.$d',
        );
      }
    });

    test('ADM-REV-008 a plain cell or an unknown detail has none', () {
      expect(readFlagCapability('orders.void').known, isNull);
      expect(readFlagCapability('orders.void').capability, 'orders.void');
      final other = readFlagCapability('orders.discount.preset:inactive');
      expect(other.capability, 'orders.discount.preset');
      expect(other.known, isNull);
      expect(readFlagCapability('orders.staff_drink.record:new').known, isNull);
    });
  });

  group('mock handlers', () {
    test('ADM-REV-003/005 open only, newest first; include_reviewed adds the '
        'reviewed', () async {
      final s = reviewServer();
      final open = _json(await _send(s.server, 'GET', '/authz/flags'))! as List;
      expect([for (final f in open) (f as Map)['id']], [1, 2, 3, 4, 5, 6]);
      final all =
          _json(
                await _send(
                  s.server,
                  'GET',
                  '/authz/flags',
                  query: {
                    'include_reviewed': ['true'],
                  },
                ),
              )!
              as List;
      expect(all, hasLength(8));
    });

    test('ADM-REV-004 every route refuses without approvals.review', () async {
      final s = reviewServer(persona: Persona.manager);
      expect(await _status(_send(s.server, 'GET', '/authz/flags')), 403);
      expect(
        await _status(_send(s.server, 'POST', '/authz/flags/1/review')),
        403,
      );
      expect(
        await _status(
          _send(
            s.server,
            'POST',
            '/authz/flags/bulk-review',
            body: {
              'flag_ids': [1],
            },
          ),
        ),
        403,
      );
    });

    test(
      'ADM-REV-011 review answers {"reviewed": true}; a second time 404',
      () async {
        final s = reviewServer();
        final r = await _send(s.server, 'POST', '/authz/flags/1/review');
        expect(r.status, 200);
        expect(_json(r), {'reviewed': true});
        // The spec's ReviewedOut (MadarRust 7043a9f4) decodes it.
        expect(
          ReviewedOut.fromJson(_json(r)! as Map<String, Object?>).reviewed,
          isTrue,
        );
        expect(
          await _status(_send(s.server, 'POST', '/authz/flags/1/review')),
          404,
        );
        final row = flagRows(s.db).rows.firstWhere((f) => f['id'] == 1);
        expect(row['reviewed_by'], SeedIds.owner);
      },
    );

    test('ADM-REV-015 bulk: per id; an already reviewed id is resolved, an '
        'unknown one pending with the reason; the note is kept', () async {
      final s = reviewServer();
      final r = await _send(
        s.server,
        'POST',
        '/authz/flags/bulk-review',
        body: {
          'flag_ids': [1, 7, 999],
          'note': 'checked',
        },
      );
      expect(_json(r), {
        'resolved': [1, 7],
        'pending': [
          {'id': 999, 'reason': 'no such open flag in this org'},
        ],
      });
      final row = flagRows(s.db).rows.firstWhere((f) => f['id'] == 1);
      expect(row['review_note'], 'checked');
      final bad = _send(
        s.server,
        'POST',
        '/authz/flags/bulk-review',
        body: {'note': 'x'},
      );
      expect(await _status(bad), 400, reason: 'flag_ids is required');
    });
  });
}
