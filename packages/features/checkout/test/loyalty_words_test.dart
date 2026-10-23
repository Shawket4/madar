import 'package:feature_checkout/src/loyalty_words.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

LoyaltyMemberView _member({List<LoyaltyTrackView> tracks = const []}) =>
    LoyaltyMemberView(
      id: 'm',
      name: 'Sara',
      phone: '',
      mode: 'visits',
      balance: 3,
      nextRewardCost: 5,
      rewardsReady: 0,
      progressToNext: 3,
      pointsToNextReward: 2,
      canRedeem: false,
      progressLabel: '',
      balanceLabel: '',
      tracks: tracks,
    );

LoyaltyAwardOutcome _outcome(List<LoyaltyTrackAward> tracks) =>
    LoyaltyAwardOutcome(
      member: _member(),
      queued: false,
      alreadyCollected: false,
      pointsAwarded: 1,
      headline: '',
      detail: '',
      tracks: tracks,
    );

String _tr(String k) => switch (k) {
  'loyalty.unit_orders' => 'orders',
  'loyalty.reward_earned' => 'Reward earned',
  _ => k,
};

void main() {
  test('a one-track award reads exactly as before', () {
    expect(loyaltyAwardDetail(_tr, _outcome([])), 'Sara — 3 orders · 3 / 5');
  });

  test('a several-track award adds a line per other track', () {
    final o = _outcome(const [
      LoyaltyTrackAward(
        position: 1,
        name: 'orders',
        awarded: 1,
        balance: 3,
        size: 5,
      ),
      LoyaltyTrackAward(
        position: 2,
        name: 'Sandwiches',
        awarded: 2,
        balance: 2,
        size: 6,
      ),
      LoyaltyTrackAward(
        position: 3,
        name: 'Cakes',
        awarded: 0,
        balance: 4,
        size: 4,
      ),
    ]);
    expect(
      loyaltyAwardDetail(_tr, o),
      'Sara — 3 orders · 3 / 5\nSandwiches +2 · 2 / 6\nCakes +0 · Reward earned',
    );
  });
}
