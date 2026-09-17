// The owner's ordering for the item sheet's option groups: REQUIRED first,
// and within the required set and the optional set alike, sizes, then milk,
// then coffee type, then extras.
//
// Sizes are the item's own chips, rendered above these cards, so the ranking
// here starts at milk.

import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

AddonGroup _group(String id, String type, {bool required = false}) =>
    AddonGroup(
      id: id,
      title: id,
      addons: [
        ItemAddonView(
          addonItemId: '$id-a',
          name: '$id option',
          addonType: type,
          chargedPriceMinor: 0,
        ),
      ],
      isMulti: type == 'extra',
      maxSel: null,
      isRequired: required,
      minSel: required ? 1 : 0,
    );

List<String> _ids(List<AddonGroup> gs) => [for (final g in gs) g.id];

void main() {
  test('required groups come first, whatever their type', () {
    // Deliberately the worst case: the required group is an `extra`, which
    // ranks LAST by type, and it is sent last. Being required still wins.
    final out = orderGroupsForSheet([
      _group('milk', 'milk_type'),
      _group('coffee', 'coffee_type'),
      _group('must-pick', 'extra', required: true),
    ]);
    expect(_ids(out), ['must-pick', 'milk', 'coffee']);
  });

  test('within a set: milk, then coffee type, then extras, then the rest', () {
    final out = orderGroupsForSheet([
      _group('syrups', 'syrup'),
      _group('extras', 'extra'),
      _group('coffee', 'coffee_type'),
      _group('milk', 'milk_type'),
    ]);
    expect(_ids(out), ['milk', 'coffee', 'extras', 'syrups']);
  });

  test('the two sets are ordered independently', () {
    final out = orderGroupsForSheet([
      _group('opt-milk', 'milk_type'),
      _group('req-extra', 'extra', required: true),
      _group('opt-extra', 'extra'),
      _group('req-milk', 'milk_type', required: true),
    ]);
    expect(_ids(out), ['req-milk', 'req-extra', 'opt-milk', 'opt-extra']);
  });

  test('ties keep the order the shop authored', () {
    // Two slots of the same type, and two types the ranking does not name.
    // `List.sort` is not stable in Dart, so this is the case that breaks if
    // the original index ever stops being the final tiebreak.
    final out = orderGroupsForSheet([
      _group('extra-b', 'extra'),
      _group('extra-a', 'extra'),
      _group('zzz', 'other'),
      _group('aaa', 'another'),
    ]);
    expect(_ids(out), ['extra-b', 'extra-a', 'zzz', 'aaa']);
  });

  test('an empty list and a single group are left alone', () {
    expect(orderGroupsForSheet([]), isEmpty);
    expect(_ids(orderGroupsForSheet([_group('only', 'extra')])), ['only']);
  });
}
