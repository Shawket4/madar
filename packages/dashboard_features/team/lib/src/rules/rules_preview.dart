/// What a rule would charge, worked out the way the server does it, for the
/// Rules page's "try it" preview (`staff/rules-preview.ts`). Mirrors
/// `MadarRust/src/staff/rules.rs` `select_late_tier` (the FIRST rung whose
/// range holds the minutes); the pricing itself is the area's one copy,
/// `shared/ladder_pricing.dart`.
library;

import 'dart:math' as math;

import '../shared/ladder_pricing.dart';
import 'rules_form.dart';

export '../shared/ladder_pricing.dart' show PayExample, dayPiastres;

/// The rung [lateMinutes] falls on, or null (on time, or past a ladder that
/// stops) (`selectTier`).
RuleTier? selectTier(List<RuleTier> tiers, num lateMinutes) {
  if (lateMinutes <= 0) return null;
  for (final t in tiers) {
    final to = t.to;
    if (lateMinutes >= math.max(0, t.from) &&
        (to == null || lateMinutes <= to)) {
      return t;
    }
  }
  return null;
}

/// What a rung costs in piastres for one pay example (`tierPiastres`).
num tierPiastres(RuleTier tier, PayExample ex) =>
    rungPiastres(tier.kind.wire, tier.value, ex);
