/// How a deal reads in the list and in the dialog's preview (the web's
/// `features/deals/util.ts`): "Any 2 for EGP 90.00", "Buy 2, get 1 free",
/// "Buy 2, get 1 at 50% off", and the pool as names ("All Bakery, Latte
/// (Large)").
library;

import 'package:dashboard_api/dashboard_api.dart' show DealPoolEntry;
import 'package:dashboard_core/dashboard_core.dart';

import '../shared/menu_options.dart';
import '../shared/offers_format.dart';
import 'deal_form.dart';

/// `dealRuleText`: the price falls back to 0, "get" to 1, the percent to 100
/// (free). Numbers read as JavaScript writes them (2, 2.5).
String dealRuleText(
  Translator t,
  DashFormat f, {
  required String kind,
  required num qty,
  num? price,
  num? getQty,
  num? getPercent,
}) {
  if (kind == DealKind.nForPrice) {
    return t(
      'deals.rule.nForPrice',
      args: {'price': f.fmtMoney(price ?? 0)},
      count: _whole(qty),
    );
  }
  final get = jsNumberString(getQty ?? 1);
  if ((getPercent ?? 100) >= 100) {
    return t(
      'deals.rule.buyGetFree',
      args: {'buy': jsNumberString(qty), 'get': get},
    );
  }
  return t(
    'deals.rule.buyGetOff',
    args: {
      'buy': jsNumberString(qty),
      'get': get,
      'percent': jsNumberString(getPercent!),
    },
  );
}

/// A whole double as an int, so `{{count}}` reads "2", not "2.0".
num _whole(num n) => n.isFinite && n == n.truncateToDouble() ? n.toInt() : n;

/// `poolText`: an item by its name, a category as "All {{name}}", "—" for
/// one the pick lists do not know (yet); a size appended as " (label)" with
/// the RAW label, as the web shows it; joined by the list separator; "—"
/// for an empty pool.
String poolText(Translator t, List<DealPoolEntry> pool, MenuOptions menu) {
  if (pool.isEmpty) return '—';
  return pool
      .map((e) {
        final cat = e.categoryId;
        final name = cat != null && cat.isNotEmpty
            ? t(
                'deals.pool.categoryNamed',
                args: {'name': menu.categoryName(cat) ?? '—'},
              )
            : (menu.itemName(e.menuItemId) ?? '—');
        final size = e.sizeLabel;
        return size != null && size.isNotEmpty ? '$name ($size)' : name;
      })
      .join(t('combos.listSeparator'));
}
