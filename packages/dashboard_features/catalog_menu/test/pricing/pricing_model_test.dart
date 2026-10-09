// The pricing matrix's browser rules (area computation 17), by hand:
// resolution, the pristine draft, dirtiness, the write plan and the
// placeholder.
import 'package:dashboard_catalog_menu/src/pricing/pricing_model.dart';
import 'package:flutter_test/flutter_test.dart';

const PricingCol inStore = (channel: null);
const PricingCol outside = (channel: 'outside');

PricingTarget target({
  int catalog = 13000,
  RawOverride branch = emptyRaw,
  RawOverride outsideRow = emptyRaw,
}) => PricingTarget(
  targetType: 'menu_item_size',
  targetId: 's1',
  catalogPrice: catalog,
  branch: branch,
  byChannel: {'outside': outsideRow},
);

PendingCell pending(PricingTarget t, PricingCol col, DraftCell d) =>
    PendingCell(
      key: pricingCellKey(col, t.targetId),
      col: col,
      target: t,
      draft: d,
      resolved: t.resolve(col),
      label: 'Spanish Latte',
    );

void main() {
  group('resolveCell (MENU-PRC-014/015/016)', () {
    test('In-store: branch price, else the catalog; available by default', () {
      final r = target().resolve(inStore);
      expect(r.effectivePrice, 13000);
      expect(r.priceExplicit, isFalse);
      expect(r.priceFromBranch, isFalse);
      expect(r.availEffective, isTrue);
      expect(r.hadOverride, isFalse);
      final b = target(
        branch: (price: 14000, isAvailable: null),
      ).resolve(inStore);
      expect(b.effectivePrice, 14000);
      expect(b.priceExplicit, isTrue);
      expect(b.hadOverride, isTrue);
    });

    test('a channel: channel → branch → catalog, each field on its own', () {
      final t = target(
        branch: (price: 14000, isAvailable: false),
        outsideRow: (price: null, isAvailable: null),
      );
      final r = t.resolve(outside);
      expect(r.effectivePrice, 14000);
      expect(r.priceExplicit, isFalse);
      expect(r.priceFromBranch, isTrue);
      expect(r.availEffective, isFalse);
      expect(r.availExplicit, isFalse);
      expect(r.availInherited, isFalse);
      final c = target(
        branch: (price: 14000, isAvailable: false),
        outsideRow: (price: 14500, isAvailable: true),
      ).resolve(outside);
      expect(c.effectivePrice, 14500);
      expect(c.priceExplicit, isTrue);
      expect(c.availEffective, isTrue);
      expect(c.hadOverride, isTrue);
    });
  });

  group('drafts (MENU-PRC-014/018)', () {
    test('pristine: the typed price only when explicit, as String(egp)', () {
      expect(pristineDraft(target().resolve(inStore)), (
        price: '',
        available: true,
      ));
      expect(
        pristineDraft(
          target(branch: (price: 14550, isAvailable: null)).resolve(inStore),
        ),
        (price: '145.5', available: true),
      );
    });

    test('dirty when the trimmed price or the toggle differs', () {
      final r = target(
        branch: (price: 14000, isAvailable: null),
      ).resolve(inStore);
      expect(isDirtyCell((price: ' 140 ', available: true), r), isFalse);
      expect(isDirtyCell((price: '141', available: true), r), isTrue);
      expect(isDirtyCell((price: '140', available: false), r), isTrue);
    });

    test('the placeholder: an integer, or 2 decimals trimmed', () {
      expect(pricePlaceholder(13000), '130');
      expect(pricePlaceholder(13050), '130.5');
      expect(pricePlaceholder(13005), '130.05');
    });
  });

  group('planCell (MENU-PRC-026/029)', () {
    test('a typed price PUTs piastres, availability null (inherit)', () {
      final t = target();
      final p = planCell(
        pending(t, inStore, (price: '135.25', available: true)),
        'b1',
      )!;
      expect(p.put, isTrue);
      expect(p.body.toJson(), {
        'branch_id': 'b1',
        'channel': null,
        'is_available': null,
        'price': 13525,
        'scope': 'branch',
        'target_id': 's1',
        'target_type': 'menu_item_size',
      });
    });

    test('hidden PUTs is_available false with no price', () {
      final p = planCell(
        pending(target(), outside, (price: '', available: false)),
        'b1',
      )!;
      expect(p.put, isTrue);
      expect(p.body.scope, 'branch_channel');
      expect(p.body.channel, 'outside');
      expect(p.body.price, isNull);
      expect(p.body.isAvailable, isFalse);
    });

    test('blank and available DELETEs a row that existed, else nothing', () {
      final had = target(branch: (price: 14000, isAvailable: null));
      final p = planCell(
        pending(had, inStore, (price: '', available: true)),
        'b1',
      )!;
      expect(p.put, isFalse);
      expect(p.body.toJson()['price'], isNull);
      expect(
        planCell(
          pending(target(), inStore, (price: '', available: true)),
          'b1',
        ),
        isNull,
      );
    });

    test('MENU-PRC-029 (divergence) showing a channel the branch hides '
        'writes is_available true', () {
      final t = target(branch: (price: null, isAvailable: false));
      final p = planCell(
        pending(t, outside, (price: '', available: true)),
        'b1',
      )!;
      expect(p.put, isTrue);
      expect(p.body.isAvailable, isTrue);
      final priced = planCell(
        pending(t, outside, (price: '150', available: true)),
        'b1',
      )!;
      expect(priced.body.isAvailable, isTrue);
      expect(priced.body.price, 15000);
    });

    test('MENU-PRC-017 Remove override DELETEs the row, even under a '
        'branch hide', () {
      final t = target(
        branch: (price: null, isAvailable: false),
        outsideRow: (price: 15000, isAvailable: null),
      );
      final r = t.resolve(outside);
      expect(clearedDraft(r), (price: '', available: false));
      final cell = PendingCell(
        key: pricingCellKey(outside, 's1'),
        col: outside,
        target: t,
        draft: clearedDraft(r),
        resolved: r,
        label: 'Iced Latte',
        cleared: true,
      );
      final p = planCell(cell, 'b1')!;
      expect(p.put, isFalse);
      expect(p.body.toJson(), {
        'branch_id': 'b1',
        'channel': 'outside',
        'is_available': null,
        'price': null,
        'scope': 'branch_channel',
        'target_id': 's1',
        'target_type': 'menu_item_size',
      });
    });

    test('MENU-PRC-025 a negative or non-numeric price is refused', () {
      final t = target();
      expect(invalidPrice('-5'), isTrue);
      expect(invalidPrice('-'), isTrue);
      expect(invalidPrice('.'), isTrue);
      expect(invalidPrice(''), isFalse);
      expect(invalidPrice('0'), isFalse);
      expect(invalidPrice('12.5'), isFalse);
      expect(
        firstInvalidLabel([
          pending(t, inStore, (price: '-1', available: true)),
        ]),
        'Spanish Latte',
      );
      expect(
        planCell(pending(t, inStore, (price: '-1', available: true)), 'b1'),
        isNull,
      );
    });
  });

  test('collectPending: only cells whose draft still differs', () {
    final t = target(branch: (price: 14000, isAvailable: null));
    final drafts = {
      pricingCellKey(inStore, 's1'): (price: '140', available: true),
      pricingCellKey(outside, 's1'): (price: '150', available: true),
    };
    final out = collectPending([t], 'Spanish Latte', drafts);
    expect(out.map((p) => p.key), ['s1|channel:outside']);
  });
}
