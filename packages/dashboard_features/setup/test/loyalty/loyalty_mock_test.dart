// The loyalty mock against hand-computed figures and the backend's rules
// (`MadarRust src/loyalty/{settings,handlers,model}.rs`, `qr_card`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

({DashboardApi api, MockServer server, MockDb db}) _backend([
  Persona persona = Persona.owner,
]) {
  final m = loyaltyServer(persona: persona);
  return (api: DashboardApi(m.server), server: m.server, db: m.db);
}

Future<int> _status(Future<Object?> call) async {
  try {
    await call;
    return 200;
  } on ApiException catch (e) {
    return e.status;
  }
}

String _item(String key) => MockSeed.menuItemId(key);

void main() {
  group('settings', () {
    test('the org row: geofenced branches counted, no ceiling while the cap '
        'is off; the dearest reward once it is on', () async {
      final b = _backend();
      final s = await b.api.loyalty.getLoyaltySettings();
      expect(s.branchId, isNull);
      expect(s.geofencedBranches, 4);
      expect(s.effectiveBalanceCap, isNull);
      settingsRow(b.db)['balance_cap_enabled'] = true;
      final capped = await b.api.loyalty.getLoyaltySettings();
      expect(capped.effectiveBalanceCap, 6);
      settingsRow(b.db)['balance_cap'] = 9;
      expect((await b.api.loyalty.getLoyaltySettings()).effectiveBalanceCap, 9);
    });

    test('a branch with no row answers the org\'s; Zamalek its own', () async {
      final b = _backend();
      final maadi = await b.api.loyalty.getLoyaltySettings(branchId: SeedIds.maadi);
      expect(maadi.branchId, isNull);
      final zam = await b.api.loyalty.getLoyaltySettings(branchId: SeedIds.zamalek);
      expect(zam.branchId, SeedIds.zamalek);
      expect(zam.defaultRewardCost, 5);
    });

    test('PUT: the backend\'s refusals; an omitted per-item switch keeps the '
        'row\'s; a mode change re-prices the scope\'s catalogue', () async {
      final b = _backend();
      final saved = await b.api.loyalty.getLoyaltySettings();
      Future<int> put(Map<String, Object?> patch) => _status(
        b.api.loyalty.putLoyaltySettings(
          body: LoyaltySettings.fromJson({...saved.toJson(), ...patch}),
        ),
      );
      expect(await put({'program_name': ' '}), 400);
      expect(await put({'earn_piastres_per_point': 0}), 400);
      expect(await put({'default_reward_cost': 0}), 400);
      expect(await put({'balance_cap': 0}), 400);
      expect(await put({'max_rewards_per_order': 0}), 400);
      expect(await put({'birthday_reward_amount': -1}), 400);
      settingsRow(b.db)['stamp_per_line_item'] = true;
      final json = saved.toJson()..remove('stamp_per_line_item');
      json['mode'] = 'points';
      expect(
        await _status(
          b.api.loyalty.putLoyaltySettings(body: LoyaltySettings.fromJson(json)),
        ),
        200,
      );
      expect(settingsRow(b.db)['stamp_per_line_item'], true);
      expect(
        b.db[LoyaltyTables.rewards].rows.every(
          (r) => r['cost_currency'] == 'points',
        ),
        isTrue,
      );
    });

    test('DELETE needs a branch; it puts the branch back on the org\'s',
        () async {
      final b = _backend();
      expect(await _status(b.api.loyalty.deleteLoyaltySettings()), 400);
      await b.api.loyalty.deleteLoyaltySettings(branchId: SeedIds.zamalek);
      final zam = await b.api.loyalty.getLoyaltySettings(branchId: SeedIds.zamalek);
      expect(zam.branchId, isNull);
    });

    test('capabilities and branches', () async {
      expect(
        await _status(_backend(Persona.limited).api.loyalty.getLoyaltySettings()),
        403,
      );
      final manager = _backend(Persona.manager);
      expect(
        await _status(
          manager.api.loyalty.getLoyaltySettings(branchId: SeedIds.maadi),
        ),
        403,
      );
      expect(
        await _status(
          manager.api.loyalty.getLoyaltyWalletStatus(),
        ),
        403,
      );
      expect(
        await _status(
          _backend(Persona.platform).api.loyalty.getLoyaltyWalletStatus(),
        ),
        200,
      );
    });
  });

  group('rewards and earning items', () {
    test('a branch inherits the org\'s catalogue, priced in its own mode',
        () async {
      final b = _backend();
      final org = await b.api.loyalty.getLoyaltyRewardItems();
      expect([for (final i in org.items) i.costAmount], [6, 6, 6, 6, 4]);
      expect(org.inherited, isFalse);
      final zam = await b.api.loyalty.getLoyaltyRewardItems(branchId: SeedIds.zamalek);
      expect(zam.inherited, isTrue);
      expect(zam.items.first.costCurrency, 'visits');
    });

    test('PUT: inactive items refused; duplicates dropped; the default cost '
        'fills a missing amount', () async {
      final b = _backend();
      b.db['menu_items'].find(_item('mocha'))!['is_active'] = false;
      expect(
        await _status(
          b.api.loyalty.putLoyaltyRewardItems(
            body: PutRewardItems(
              items: [RewardItemInput(menuItemId: _item('mocha'))],
            ),
          ),
        ),
        400,
      );
      final saved = await b.api.loyalty.putLoyaltyRewardItems(
        body: PutRewardItems(
          branchId: SeedIds.maadi,
          items: [
            RewardItemInput(menuItemId: _item('latte'), costAmount: 3),
            RewardItemInput(menuItemId: _item('latte'), costAmount: 9),
            RewardItemInput(menuItemId: _item('espresso')),
          ],
        ),
      );
      expect([for (final i in saved.items) i.costAmount], [3, 6]);
      final maadi = await b.api.loyalty.getLoyaltyRewardItems(branchId: SeedIds.maadi);
      expect(maadi.inherited, isFalse);
    });

    test('earning items: empty means everything; a branch inherits',
        () async {
      final b = _backend();
      expect((await b.api.loyalty.getLoyaltyEarningItems()).items, isEmpty);
      await b.api.loyalty.putLoyaltyEarningItems(
        body: PutEarningItems(menuItemIds: [_item('latte'), _item('latte')]),
      );
      final maadi = await b.api.loyalty.getLoyaltyEarningItems(branchId: SeedIds.maadi);
      expect(maadi.inherited, isTrue);
      expect([for (final i in maadi.items) i.name], ['Caffè Latte']);
    });
  });

  group('members', () {
    test('the list: every member, newest first, the cheapest reward as the '
        'target', () async {
      final b = _backend();
      final members = b.db['customers'].rows
          .where((c) => c['is_member'] == true)
          .length;
      final page = await b.api.loyalty.listLoyaltyMembers(limit: 500);
      expect(page.total, members);
      expect(page.members, hasLength(members.clamp(0, 200)));
      final enrolled = [for (final m in page.members) m.enrolledAt];
      expect(enrolled, [...enrolled]..sort((a, c) => c.compareTo(a)));
      final nada = (await b.api.loyalty.listLoyaltyMembers(q: 'Nada Kamal'))
          .members
          .single;
      // Six stamps against a four-stamp cookie: one earned, two to go.
      expect(nada.nextRewardCost, 4);
      expect(nada.rewardsReady, 1);
      expect(nada.pointsToNextReward, 2);
      expect(nada.canRedeem, isTrue);
    });

    test('the ledger sums to the balance', () async {
      final b = _backend();
      for (final c in b.db['customers'].rows.take(60)) {
        if (c['is_member'] != true) continue;
        final sum = b.db[LoyaltyTables.ledger].rows
            .where((e) => e['customer_id'] == c['id'])
            .fold<int>(0, (s, e) => s + (e['points']! as int));
        expect(sum, c['visits_balance'], reason: '${c['name']}');
      }
    });

    test('adjust: a reason, never zero, never below zero; the ledger row and '
        'the balance', () async {
      final b = _backend();
      Future<int> adjust(int points, String note) => _status(
        b.api.loyalty.loyaltyAdjust(
          body: AdjustRequest(
            branchId: SeedIds.zamalek,
            customerId: nadaId,
            points: points,
            note: note,
          ),
        ),
      );
      expect(await adjust(1, '  '), 400);
      expect(await adjust(0, 'Nothing'), 400);
      expect(await adjust(-7, 'Too much'), 400);
      expect(await adjust(-2, 'Duplicate stamps'), 200);
      expect(b.db['customers'].find(nadaId)!['visits_balance'], 4);
      final row = b.db[LoyaltyTables.ledger].rows.last;
      expect(row['points'], -2);
      expect(row['branch_name'], 'Zamalek');
      expect(row['created_by_name'], 'Nour El-Sayed');
    });

    test('leaving keeps the customer; twice is fine', () async {
      final b = _backend();
      await b.api.loyalty.deleteLoyaltyMember(id: nadaId);
      await b.api.loyalty.deleteLoyaltyMember(id: nadaId);
      expect(b.db['customers'].find(nadaId)!['is_member'], false);
      expect(
        await _status(b.api.loyalty.getLoyaltyMember(id: nadaId)),
        404,
      );
    });
  });

  group('analytics and codes', () {
    test('the report over the last 30 days, by hand', () async {
      final b = _backend();
      final now = b.db.clock.now;
      final from = now.subtract(const Duration(days: 30));
      final inRange = b.db[LoyaltyTables.ledger].rows.where((e) {
        final at = DateTime.parse(e['created_at']! as String);
        return !at.isBefore(from) && at.isBefore(now);
      }).toList();
      final redeems = inRange.where((e) => e['kind'] == 'redeem').toList();
      final a = await b.api.loyalty.getLoyaltyAnalytics();
      expect(a.redemptions, redeems.length);
      expect(a.redeemedPoints, redeems.length * 6);
      expect(
        a.redeemedValueMinor,
        redeems.fold<int>(0, (s, e) => s + (e['reward_value_minor']! as int)),
      );
      final members = b.db['customers'].rows.where((c) => c['is_member'] == true);
      expect(
        a.liability.outstandingVisits,
        members.fold<int>(0, (s, c) => s + ((c['visits_balance'] as int?) ?? 0)),
      );
      expect(a.liability.currency, 'visits');
      expect(a.topRewards.length, lessThanOrEqualTo(10));
      expect(
        a.topRewards.fold<int>(0, (s, r) => s + r.redemptions),
        redeems.length,
      );
    });

    test('the sign-up codes: the shop\'s own host; a switched-off programme '
        'is refused', () async {
      final b = _backend();
      final org = await b.api.qr.orgLoyaltyQr(id: SeedIds.sabahOrg);
      expect(org.kind, 'org_loyalty');
      expect(org.longUrl, 'https://sabah-coffee.madar-pos.cloud/rewards');
      final branch = await b.api.qr.branchLoyaltyQr(id: SeedIds.zamalek);
      expect(
        branch.longUrl,
        'https://sabah-coffee.madar-pos.cloud/join/${SeedIds.zamalek}',
      );
      settingsRow(b.db, SeedIds.zamalek)['enabled'] = false;
      expect(
        await _status(b.api.qr.branchLoyaltyQr(id: SeedIds.zamalek)),
        409,
      );
    });

    test('the birthday greeting: the shop\'s words, else ours with the gift',
        () async {
      final b = _backend();
      final saved = await b.api.loyalty.getLoyaltySettings();
      final ours = await b.api.loyalty.previewLoyaltyBirthdayMessage(body: saved);
      expect(ours.en, contains('1 stamps on your Sabah Stamps card'));
      expect(ours.ar, startsWith('كل سنة وأنت طيب يا Sara'));
      final custom = await b.api.loyalty.previewLoyaltyBirthdayMessage(
        body: LoyaltySettings.fromJson({
          ...saved.toJson(),
          'birthday_message': 'Hi {name}!',
        }),
      );
      expect(custom.en, 'Hi Sara!');
      expect(custom.ar, 'Hi Sara!');
    });
  });
}
