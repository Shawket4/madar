/// `/access/review` Review (ADM-REV rows): GET /authz/flags, POST
/// /authz/flags/{id}/review, POST /authz/flags/bulk-review (seed:
/// `AdminSeed.flags`), as MadarRust `src/authz/api.rs` answers them:
/// `approvals.review` first, the org from the request, newest first, open
/// only unless `include_reviewed=true`; a single review answers
/// `{"reviewed": true}` (404 when the flag is not open); a bulk review is
/// per id, an already reviewed id counting as resolved.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show BulkReviewPending, BulkReviewRequest, BulkReviewResult;
import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

void registerReviewMocks(MockServer server, MockDb db) {
  final flags = db[AdminTables.flags];

  /// The flags of the request's org (the seed's are Sabah's).
  List<MockRow> orgFlags(MockRequest req) {
    final org = req.orgId;
    if (org == null) {
      throw MockHttpError(MockResponse.forbidden('No organization selected'));
    }
    return flags.where((r) => (r['org_id'] ?? SeedIds.sabahOrg) == org);
  }

  MockRow? openFlag(List<MockRow> rows, Object? id) =>
      rows.where((r) => r['id'] == id && r['reviewed_at'] == null).firstOrNull;

  server.on('GET', '/authz/flags', (req) {
    req.requireCap('approvals.review');
    final all = req.qBool('include_reviewed') ?? false;
    final rows =
        [
          for (final r in orgFlags(req))
            if (all || r['reviewed_at'] == null) r,
        ]..sort(
          (a, b) => (b['created_at']! as String).compareTo(
            a['created_at']! as String,
          ),
        );
    return MockResponse.ok(rows.take(500).toList());
  });

  server.on('POST', '/authz/flags/{id}/review', (req) {
    req.requireCap('approvals.review');
    final flag = openFlag(orgFlags(req), int.tryParse(req.param('id')));
    if (flag == null) {
      throw MockHttpError(MockResponse.notFound('No such open flag'));
    }
    flag
      ..['reviewed_at'] = req.now.toUtc().toIso8601String()
      ..['reviewed_by'] = req.persona.userId;
    return MockResponse.ok({'reviewed': true});
  });

  server.on('POST', '/authz/flags/bulk-review', (req) {
    req.requireCap('approvals.review');
    // actix's JSON extractor: `flag_ids` has no serde default.
    if (req.json['flag_ids'] is! List) {
      throw MockHttpError(
        MockResponse.badRequest(
          'Json deserialize error: missing field `flag_ids`',
        ),
      );
    }
    final body = req.bodyAs(BulkReviewRequest.fromJson);
    final rows = orgFlags(req);
    final resolved = <int>[];
    final pending = <BulkReviewPending>[];
    for (final id in body.flagIds) {
      final row = rows.where((r) => r['id'] == id).firstOrNull;
      if (row != null && row['reviewed_at'] != null) {
        resolved.add(id);
        continue;
      }
      if (row == null) {
        pending.add(
          BulkReviewPending(id: id, reason: 'no such open flag in this org'),
        );
        continue;
      }
      row
        ..['reviewed_at'] = req.now.toUtc().toIso8601String()
        ..['reviewed_by'] = req.persona.userId
        ..['review_note'] = body.note;
      resolved.add(id);
    }
    return MockResponse.ok(
      BulkReviewResult(resolved: resolved, pending: pending),
    );
  });
}
