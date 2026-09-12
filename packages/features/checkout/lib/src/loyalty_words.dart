import 'package:rust_bridge/rust_bridge.dart';

/// A key → words lookup (`bridge.tr`, or a widget's own `tr`).
typedef Tr = String Function(String key);

/// Loyalty wording resolved at RENDER from the structured fields the core
/// returns — never the finished words it phrased at lookup time.
///
/// A member, a reward and an award outcome are fetched once and then held in
/// state for as long as the sheet is up. The core phrases their labels in the
/// language in force at the fetch, so a teller who switched language kept
/// reading the old one ("30 points" under an Arabic sheet). Every figure and
/// flag needed is on the view model; only the words are chosen here, from the
/// same keys the core uses (`loyalty::balance_label_key`).

/// "points" / "orders" for a programme's `mode` (`points` | `visits`).
String loyaltyUnit(Tr tr, String mode) =>
    tr(mode == 'visits' ? 'loyalty.unit_orders' : 'loyalty.unit_points');

/// "30 / 100", or the earned line once the card reaches a reward.
String loyaltyProgress(Tr tr, LoyaltyMemberView m) =>
    m.nextRewardCost > 0 && m.balance >= m.nextRewardCost
    ? tr('loyalty.reward_earned')
    : '${m.balance} / ${m.nextRewardCost}';

/// "5 orders" — what one reward costs.
String loyaltyCost(Tr tr, LoyaltyRewardView r) =>
    '${r.costAmount} ${loyaltyUnit(tr, r.costCurrency)}';

/// The award sheet's headline: added, already collected, nothing, or queued.
String loyaltyAwardHeadline(Tr tr, LoyaltyAwardOutcome o) => tr(switch (o) {
  LoyaltyAwardOutcome(queued: true) => 'loyalty.points_queued',
  LoyaltyAwardOutcome(alreadyCollected: true) => 'loyalty.already_collected',
  LoyaltyAwardOutcome(pointsAwarded: 0) => 'loyalty.no_points',
  _ => 'loyalty.points_added',
});

/// The line under it: where the customer now stands, or why there is no
/// balance to show.
String loyaltyAwardDetail(Tr tr, LoyaltyAwardOutcome o) => switch (o.member) {
  null => tr('loyalty.queued_hint'),
  final m =>
    '${m.name} — ${m.balance} ${loyaltyUnit(tr, m.mode)} · '
        '${loyaltyProgress(tr, m)}',
};
