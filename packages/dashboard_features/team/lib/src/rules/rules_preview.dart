/// What a rule would charge, for the Rules page's "try it" preview
/// (`staff/rules-preview.ts`): madar-dawam's `select_late_tier` through the
/// core (the FIRST rung whose range holds the minutes); the pricing is
/// `shared/ladder_pricing.dart`.
library;

import 'package:rust_bridge_dashboard/rules.dart' as rules;

import '../shared/ladder_pricing.dart';
import 'rules_form.dart';

export '../shared/ladder_pricing.dart' show PayExample, dayPiastres;

/// The rung [lateMinutes] falls on, or null (on time, or past a ladder that
/// stops) (`selectTier`).
///
/// A rung the form cannot read yet (a blank or partial number) holds no
/// minutes, so it is left out of the choice.
RuleTier? selectTier(List<RuleTier> tiers, num lateMinutes) {
  final readable = [
    for (final t in tiers)
      if (t.from.isFinite && (t.to?.isFinite ?? true)) t,
  ];
  final i = rules.selectLateTier(
    rungs: [
      for (final t in readable)
        rules.LadderRung(fromMinutes: t.from.ceil(), toMinutes: t.to?.floor()),
    ],
    lateMinutes: lateMinutes.isFinite ? lateMinutes.floor() : 0,
  );
  return i == null ? null : readable[i];
}

/// What a rung costs in piastres for one pay example (`tierPiastres`).
num tierPiastres(RuleTier tier, PayExample ex) =>
    rungPiastres(tier.kind.wire, tier.value, ex);
