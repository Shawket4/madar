// The loyalty admin's pure rules, against the web's own expectations
// (`form-schema.test.ts`, `catalogue-schema.test.ts`, `earning-schema.test.ts`,
// `ledger.ts`, `server-errors.ts`, `lib/phone.ts`).
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_setup/src/loyalty/loyalty_data.dart';
import 'package:flutter_test/flutter_test.dart';

LoyaltySettings _saved() => LoyaltySettings.fromJson({
  'org_id': 'org-1',
  'branch_id': null,
  'enabled': true,
  'program_name': 'Bean Club',
  'program_name_ar': 'نادي البن',
  'mode': 'visits',
  'earn_piastres_per_point': 1000,
  'earn_on_discounted': true,
  'earn_include_tax': false,
  'stamp_per_line_item': true,
  'default_reward_cost': 5,
  'reward_any_item': false,
  'balance_cap_enabled': true,
  'balance_cap': 12,
  'max_rewards_per_order': 3,
  'require_otp': true,
  'birthday_enabled': true,
  'birthday_reward_amount': 2,
  'birthday_message': 'Hi {name}',
  'birthday_message_ar': null,
  'winback_enabled': false,
  'terms': 'Terms',
  'terms_ar': 'الشروط',
  'allow_negative_balance': true,
  'geofenced_branches': 3,
  'effective_balance_cap': 12,
});

/// Every lookup reads as its key.
final _tr = Translator(Strings.empty(), 'en');

void main() {
  group('the programme form (SET-LOY-013 … 031)', () {
    test('fromWire keeps the figures as typed fields', () {
      final v = programFromWire(_saved());
      expect(v.text('earn_egp_per_point'), '10');
      expect(v.text('balance_cap'), '12');
      expect(v.text('max_rewards_per_order'), '3');
      expect(v.text('birthday_reward_amount'), '2');
      expect(v.text('winback_reward_amount'), '');
      expect(v.flag('stamp_per_line_item'), isTrue);
      expect(v.mode, 'visits');
      expect(programFromWire(_saved()), v, reason: 'equal by value');
    });

    test('a piastre rate shows as EGP with its fraction', () {
      final s = LoyaltySettings.fromJson({
        ..._saved().toJson(),
        'earn_piastres_per_point': 1250,
      });
      expect(programFromWire(s).text('earn_egp_per_point'), '12.5');
    });

    test('validation: names, earn rate, whole numbers, optional ones', () {
      final ok = programFromWire(_saved());
      expect(validateProgram(ok), isEmpty);
      expect(validateProgram(ok.set('program_name', '  ')), {
        'program_name': 'loyalty.errors.nameRequired',
      });
      for (final bad in ['', '0', '0.001', 'abc', '1000001']) {
        expect(
          validateProgram(ok.set('earn_egp_per_point', bad)).keys,
          ['earn_egp_per_point'],
          reason: bad,
        );
      }
      expect(validateProgram(ok.set('earn_egp_per_point', '0.01')), isEmpty);
      for (final bad in ['', '0', '-3', '2.5', 'x']) {
        expect(
          validateProgram(ok.set('default_reward_cost', bad)).keys,
          ['default_reward_cost'],
          reason: bad,
        );
      }
      for (final bad in ['0', '-3', '2.5', 'abc', '2147483648']) {
        expect(
          validateProgram(ok.set('balance_cap', bad)).keys,
          ['balance_cap'],
          reason: bad,
        );
      }
      expect(validateProgram(ok.set('balance_cap', '')), isEmpty);
    });

    test('toWire: the saved row with the form on top', () {
      final v = programFromWire(_saved())
          .set('program_name', '  Bean Club+  ')
          .set('earn_egp_per_point', '19.99')
          .set('program_name_ar', '');
      final w = programToWire(v, orgId: 'org-1', branchId: 'b-1', saved: _saved())
          .toJson();
      expect(w['branch_id'], 'b-1');
      expect(w['program_name'], 'Bean Club+');
      expect(w['program_name_ar'], isNull);
      expect(w.containsKey('program_name_ar'), isTrue);
      // 19.99 × 100 is 1998.999…: rounded, never truncated.
      expect(w['earn_piastres_per_point'], 1999);
      expect(w['balance_cap'], 12);
      expect(w['allow_negative_balance'], true);
      expect(w['terms_ar'], 'الشروط');
      expect(w['stamp_per_line_item'], true);
    });

    test('toWire: a feature switched off carries no gift or message; the cap '
        'figure only with the cap on', () {
      final v = programFromWire(_saved())
          .set('birthday_enabled', false)
          .set('balance_cap_enabled', false)
          .set('max_rewards_per_order', '');
      final w = programToWire(v, orgId: 'org-1', branchId: null, saved: _saved())
          .toJson();
      expect(w['birthday_reward_amount'], isNull);
      expect(w['birthday_message'], isNull);
      expect(w['balance_cap'], isNull);
      expect(w['max_rewards_per_order'], isNull);
      expect(w.containsKey('branch_id'), isTrue);
    });

    test('the preview renders the edited values; none while birthdays are '
        'off', () {
      final v = programFromWire(_saved())
          .set('birthday_reward_amount', '4')
          .set('program_name', '');
      final p = birthdayPreviewOf(v, _saved())!;
      expect(p.birthdayRewardAmount, 4);
      expect(p.programName, 'Bean Club');
      expect(birthdayPreviewOf(v.set('birthday_enabled', false), _saved()), isNull);
    });
  });

  group('the reward catalogue (SET-LOY-041 … 045)', () {
    MenuItem item(String id, {bool active = true, bool deleted = false}) =>
        MenuItem.fromJson({
          'id': id,
          'org_id': 'org-1',
          'name': id,
          'base_price': 1000,
          'is_active': active,
          'deleted_at': deleted ? '2026-10-01T00:00:00Z' : null,
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
          'name_translations': <String, Object?>{},
          'description_translations': <String, Object?>{},
        });
    RewardRow row(String id, String cost) =>
        (menuItemId: id, name: id, cost: cost);

    test('problems: cost, duplicate, deleted, switched off', () {
      final menu = [item('a'), item('b', active: false), item('c', deleted: true)];
      expect(
        rewardProblems([
          row('a', '5'),
          row('a', '5'),
          row('b', '5'),
          row('c', '5'),
          row('x', '5'),
          row('a', '0'),
        ], menu),
        [
          null,
          RewardProblem.duplicate,
          RewardProblem.inactive,
          RewardProblem.unavailable,
          RewardProblem.unavailable,
          RewardProblem.cost,
        ],
      );
      expect(rewardProblems([row('x', '5')], null), [null]);
      expect(rewardBlocking(RewardProblem.inactive), isFalse);
      expect(rewardBlocking(RewardProblem.duplicate), isTrue);
      expect(menuItemOfferable(item('b', active: false)), isFalse);
    });

    test('changed: length, order, item or cost', () {
      final saved = [
        RewardItem.fromJson({
          'menu_item_id': 'a',
          'name': 'a',
          'base_price': 100,
          'cost_currency': 'visits',
          'cost_amount': 5,
          'sort_order': 0,
        }),
      ];
      expect(rewardsChanged([row('a', '5')], saved), isFalse);
      expect(rewardsChanged([row('a', '6')], saved), isTrue);
      expect(rewardsChanged([row('a', '')], saved), isTrue);
      expect(rewardsChanged([], saved), isTrue);
      expect(rewardsToWire([row('a', '7')], 'points').single.toJson(), {
        'menu_item_id': 'a',
        'cost_currency': 'points',
        'cost_amount': 7,
      });
    });
  });

  group('the items that collect (SET-LOY-051)', () {
    EarningItem saved(String id) => EarningItem.fromJson({
      'menu_item_id': id,
      'name': id,
      'base_price': 100,
      'sort_order': 0,
    });
    test('a reorder is not a change; ids deduplicated in order', () {
      final rows = [
        (menuItemId: 'b', name: 'b'),
        (menuItemId: 'a', name: 'a'),
      ];
      expect(earningChanged(rows, [saved('a'), saved('b')]), isFalse);
      expect(earningChanged(rows.take(1).toList(), [saved('a'), saved('b')]), isTrue);
      expect(
        earningToWire([...rows, (menuItemId: 'b', name: 'b')]),
        ['b', 'a'],
      );
    });
  });

  group('the ledger (SET-LOY-067, 084)', () {
    LedgerEntry e(String kind, String source, {String? by, String? name, String? rev}) =>
        LedgerEntry.fromJson({
          'id': '$kind-$source',
          'branch_id': 'b',
          'created_at': '2026-10-01T10:00:00Z',
          'created_by': by,
          'created_by_name': name,
          'currency': 'visits',
          'kind': kind,
          'source': source,
          'points': 1,
          'reverses_id': rev,
        });
    test('labels and tones', () {
      final t = _tr;
      expect(ledgerLabel(e('earn', 'sale'), t), 'loyalty.ledger.sale');
      expect(ledgerLabel(e('reverse_redeem', 'refund'), t), 'loyalty.ledger.refundRedeem');
      expect(ledgerLabel(e('reverse_earn', 'refund'), t), 'loyalty.ledger.refundEarn');
      expect(ledgerLabel(e('reverse_adjust', 'void'), t), 'loyalty.ledger.voidAdjust');
      expect(ledgerLabel(e('reverse_earn', 'other'), t), 'loyalty.ledger.reversal');
      expect(ledgerLabel(e('odd', 'mystery'), t), 'odd');
      expect(ledgerTone(e('redeem', 'redemption')), LedgerTone.spend);
      expect(ledgerTone(e('adjust', 'birthday')), LedgerTone.gift);
      expect(ledgerTone(e('adjust', 'manual')), LedgerTone.manual);
      expect(ledgerTone(e('reverse_earn', 'void')), LedgerTone.reversal);
      expect(ledgerSigned(-5), '−5');
      expect(ledgerSigned(12), '+12');
      expect(ledgerSigned(0), '0');
      expect(ledgerReversedIds([e('reverse_earn', 'void', rev: 'x')]), {'x'});
    });

    test('the actor: a name, a gone account, the system', () {
      final t = Translator(
        Strings({
          'en': {
            'loyalty.ledger.by': 'by {{name}}',
            'loyalty.ledger.bySystem': 'automatic',
          },
        }),
        'en',
      );
      expect(ledgerActor(e('earn', 'sale', by: 'u', name: 'Mona'), t), 'by Mona');
      expect(ledgerActor(e('earn', 'sale', by: 'u'), t), 'by —');
      expect(ledgerActor(e('earn', 'sale'), t), 'automatic');
    });
  });

  test('refusals the screen can point at (SET-LOY-044, 072)', () {
    ApiException ex(String text) => ApiException(
      status: 400,
      message: text,
      details: {'error': 'Bad request: $text'},
    );
    expect(
      loyaltyServerError(ex('Say why the points are being adjusted (note)'), _tr).kind,
      LoyaltyRefusal.noteRequired,
    );
    expect(
      loyaltyServerError(ex('reward items must be active menu items of this org'), _tr)
          .message,
      'loyalty.errors.serverInactiveReward',
    );
    expect(loyaltyServerError(ex('Something else'), _tr).message, 'Something else');
  });

  test('phones read +20 1xx xxx xxxx; anything else as given', () {
    expect(formatPhoneDisplay('01001234567'), '+20 100 123 4567');
    expect(formatPhoneDisplay('٠١٠٠١٢٣٤٥٦٧'), '+20 100 123 4567');
    expect(formatPhoneDisplay('+44 20 7946 0958'), '+442079460958');
    expect(formatPhoneDisplay('0100123'), '0100123');
    expect(formatPhoneDisplay(null), '');
  });
}
