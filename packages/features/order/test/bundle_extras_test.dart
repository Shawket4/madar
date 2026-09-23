import 'package:feature_order/src/bundle_detail_sheet.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The bundle sheet's live total must be the figure the cart (and the
/// server) charge: a component's up-charge counts once per component UNIT
/// (madar-shared M3 — `(addons + optionals) × component qty`).
void main() {
  const bundle = BundleView(
    id: 'combo',
    name: 'Combo',
    priceMinor: 5000,
    isAvailable: true,
    components: [
      BundleComponentView(itemId: 'latte', itemName: 'Latte', quantity: 2),
      BundleComponentView(itemId: 'cake', itemName: 'Cake', quantity: 1),
    ],
  );
  BundleComponentDraft draft(int extras) => BundleComponentDraft(
    sizeLabel: null,
    addons: const [],
    optionalIds: const [],
    extrasMinor: extras,
  );

  test('a component ×2 with +500 oat milk adds 1000', () {
    final state = BundleConfigState(drafts: {0: draft(500)});
    expect(state.extrasMinor(bundle), 1000);
    expect(bundle.priceMinor + state.extrasMinor(bundle), 6000);
  });

  test('each component counts at its own quantity', () {
    final state = BundleConfigState(drafts: {0: draft(500), 1: draft(300)});
    expect(state.extrasMinor(bundle), 500 * 2 + 300);
    expect(const BundleConfigState().extrasMinor(bundle), 0);
  });
}
