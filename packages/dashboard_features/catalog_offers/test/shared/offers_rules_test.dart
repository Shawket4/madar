// The area seed and the backend rules the mock handlers share: the numbers
// the combos list, the editor's price check and the deals will all show.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_offers/src/area_seed.dart';
import 'package:dashboard_catalog_offers/src/mock/offers_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockDb db;
  final org = SeedIds.sabahOrg;

  setUp(() {
    db = MockDb.seeded();
    OffersSeed.loadInto(db);
  });

  Map<String, Object?> row(String key) =>
      db.table(OffersTables.menuItems).get(OffersSeed.comboId(key));

  Map<String, Object?> summary(String key) =>
      comboSummaryJson(db, row(key));

  Map<String, Object?> economics(String key) =>
      comboJson(db, row(key))['economics']! as Map<String, Object?>;

  List<Object?> codes(String key) => [
    for (final w in economics(key)['warnings']! as List)
      (w as Map)['code'],
  ];

  test('loading twice adds nothing', () {
    OffersSeed.loadInto(db);
    expect(comboRows(db, org), hasLength(6));
    expect(db.table(OffersTables.deals).length, 5);
    expect(db.table(OffersTables.discounts).length, 7);
  });

  test('combos are menu items of kind combo, listed by name', () {
    expect([for (final r in comboRows(db, org)) r['name']], [
      'Brunch for Two',
      'Coffee & Cookie',
      'Iced Afternoon',
      "Kids' Cocoa & Cookie",
      'Morning Croissant Combo',
      'Ramadan Suhoor Box',
    ]);
  });

  test('Morning Croissant Combo: figures and the costliest-picks warning', () {
    final e = economics('morning-croissant');
    expect(e['price'], 16500);
    expect(e['list_default'], 19000); // croissant 75 + latte regular 115
    expect(e['saving_default'], 2500);
    expect(e['cost_default'], 6400);
    expect(e['margin_default'], '0.6121');
    expect(e['cost_max'], 8600);
    expect(e['margin_worst'], '0.4788');
    expect(e['min_margin'], '0.5500');
    expect(codes('morning-croissant'), ['MARGIN_BELOW_MIN']);
    final w = (e['warnings']! as List).first as Map;
    expect(w['vars'], {'margin': '0.4788', 'min': '0.5500'});
  });

  test('Brunch for Two: two items without a cost, so no margin', () {
    final e = economics('brunch-for-two');
    expect(e['list_default'], 59000);
    expect(e['cost_default'], isNull);
    expect(e['margin_default'], isNull);
    expect(codes('brunch-for-two'), ['COST_UNKNOWN', 'COST_UNKNOWN']);
    expect(summary('brunch-for-two')['warning_count'], 2);
  });

  test('the list summaries', () {
    final s = {
      for (final k in OffersSeed.comboKeys) k: summary(k),
    };
    expect(s['coffee-cookie']!['is_fixed'], isTrue);
    expect(s['kids-cocoa']!['is_fixed'], isTrue);
    expect(s['morning-croissant']!['is_fixed'], isFalse);
    expect(s['coffee-cookie']!['margin_default'], '0.7250');
    expect(s['coffee-cookie']!['warning_count'], 0);
    expect(s['iced-afternoon']!['margin_default'], '0.5739');
    expect(s['iced-afternoon']!['warning_count'], 1);
    expect(s['suhoor-box']!['margin_default'], '0.6778');
    expect(s['brunch-for-two']!['slot_count'], 2);
    expect(s['suhoor-box']!['window_count'], 1);
    // Thursday 10:00 in Cairo: the afternoon and weekend windows are shut,
    // Ramadan's box is switched off, Brunch's only window is Zamalek's.
    expect({for (final e in s.entries) e.key: e.value['available_now']}, {
      'morning-croissant': true,
      'coffee-cookie': true,
      'brunch-for-two': true,
      'iced-afternoon': false,
      'suhoor-box': false,
      'kids-cocoa': false,
    });
    expect(
      comboJson(
        db,
        row('brunch-for-two'),
        branchId: SeedIds.zamalek,
      )['available_now'],
      isFalse,
    );
  });

  test('a choice switched off warns CHOICE_INACTIVE; a price at or over the '
      'list value warns NO_SAVING', () {
    db.table(OffersTables.menuItems).get(OffersSeed.item('cookie'))['is_active'] =
        false;
    expect(codes('coffee-cookie'), contains('CHOICE_INACTIVE'));
    expect(codes('coffee-cookie'), contains('SLOT_EMPTY_NOW'));
    db.table(OffersTables.menuItems).get(OffersSeed.item('cookie'))['is_active'] =
        true;
    row('coffee-cookie')['base_price'] = 14000;
    expect(codes('coffee-cookie'), ['NO_SAVING']);
  });

  group('sale windows', () {
    final thu = DateTime.utc(2026, 10, 8);
    Map<String, Object?> w({
      int weekdays = 127,
      String? from,
      String? to,
      String? validFrom,
      String? validTo,
      String? branch,
    }) => {
      'weekdays': weekdays,
      'starts_at': from,
      'ends_at': to,
      'valid_from': validFrom,
      'valid_to': validTo,
      'branch_id': branch,
    };

    test('half-open hours', () {
      final win = w(from: '15:00', to: '19:00');
      expect(windowMatches(win, thu.add(const Duration(hours: 15))), isTrue);
      expect(windowMatches(win, thu.add(const Duration(hours: 19))), isFalse);
      expect(windowMatches(win, thu.add(const Duration(hours: 10))), isFalse);
    });

    test('past midnight belongs to the day it started', () {
      final thursdayNight = w(weekdays: 1 << 4, from: '22:00', to: '03:00');
      final friday1am = thu.add(const Duration(days: 1, hours: 1));
      expect(windowMatches(thursdayNight, friday1am), isTrue);
      expect(
        windowMatches(thursdayNight, thu.add(const Duration(hours: 23))),
        isTrue,
      );
      expect(
        windowMatches(
          thursdayNight,
          thu.add(const Duration(days: 1, hours: 23)),
        ),
        isFalse,
      );
      expect(
        windowMatches(
          w(from: '22:00', to: '03:00', validTo: '2026-10-08'),
          friday1am,
        ),
        isTrue,
      );
    });

    test('only all-branch windows and the branch\'s own apply; none = open',
        () {
      final zamalekOnly = [w(weekdays: 0, branch: 'z')];
      expect(windowsOpen(zamalekOnly, null, thu), isTrue);
      expect(windowsOpen(zamalekOnly, 'z', thu), isFalse);
      expect(windowsOpen(zamalekOnly, 'other', thu), isTrue);
      expect(windowsOpen(const [], 'z', thu), isTrue);
    });

    test('unparseable input never matches', () {
      expect(windowMatches(w(from: '25:00', to: '03:00'), thu), isFalse);
      expect(windowMatches(w(from: '09:00'), thu), isFalse);
      expect(windowMatches(w(validFrom: 'soon'), thu), isFalse);
    });
  });

  test('discounts: the legacy value rounds half away from zero', () {
    expect(legacyDiscountValue(0.14), 14);
    expect(legacyDiscountValue(0.125), 13);
    expect(legacyDiscountValue(1), 100);
    expect(legacyDiscountValue(5000), 5000);
    final vodafone = db
        .table(OffersTables.discounts)
        .get(OffersSeed.discountId('corporate-vodafone'));
    expect(vodafone['value'], 13);
    expect(vodafone['value_rate'], 0.125);
  });
}
