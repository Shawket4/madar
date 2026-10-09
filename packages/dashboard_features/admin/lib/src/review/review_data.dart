/// The Review page's read and the rules the web runs in the browser
/// (`features/access/{review-page,flag-detail}.ts`).
library;

import 'package:dashboard_api/dashboard_api.dart' show ReplayFlag;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashTone;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `GET /authz/flags[?include_reviewed=true]` (listFlags), keyed like the
/// web's `useListFlags({include_reviewed: showReviewed || undefined})`
/// (ADM-REV-003, 005). The org rides the header, as on the web.
final reviewFlagsProvider = FutureProvider.autoDispose
    .family<List<ReplayFlag>, bool>((ref, includeReviewed) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(reviewFlagsPath));
      return ref
          .watch(apiProvider)
          .authz
          .listFlags(includeReviewed: includeReviewed ? true : null);
    });

/// What the web's review and bulk review invalidate: every key starting
/// `/authz/flags` (ADM-REV-011, 015).
const String reviewFlagsPath = '/authz/flags';

/// `REASON_TONE`; an unknown reason is neutral (ADM-REV-007).
DashTone reasonTone(String reason) => switch (reason) {
  'stale_snapshot' => DashTone.info,
  'unauthorized_offline' => DashTone.danger,
  'pin_wrong_branch' => DashTone.warning,
  _ => DashTone.neutral,
};

/// Every detail the staff-drink replay path writes, with its tone.
const Map<String, Map<String, DashTone>> _details = {
  'orders.staff_drink.record': {
    'comp_mismatch': DashTone.warning,
    'overspent': DashTone.warning,
    'device_overcounted': DashTone.info,
    'duplicate_id': DashTone.warning,
    'pool_off': DashTone.danger,
    'no_eligible_items': DashTone.danger,
    'item_not_eligible': DashTone.danger,
    'note_required': DashTone.warning,
  },
};

/// A flag's `capability` cell read (`readFlagCapability`): the capability
/// without its `:detail`, and the words + tone of a detail we own (null for
/// a plain cell or a detail we have no words for) (ADM-REV-008, 009).
({String capability, ({String key, DashTone tone})? known}) readFlagCapability(
  String cell,
) {
  final at = cell.indexOf(':');
  if (at < 0) return (capability: cell, known: null);
  final capability = cell.substring(0, at);
  final detail = cell.substring(at + 1);
  final tone = _details[capability]?[detail];
  return (
    capability: capability,
    known: tone == null
        ? null
        : (
            key:
                'access.review.details.${capability.replaceAll('.', '_')}.$detail',
            tone: tone,
          ),
  );
}
