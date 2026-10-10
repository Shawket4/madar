/// The words the inventory pages put on codes: statuses, reasons, movement
/// types, sources and units. Each falls back to the raw code when the tables
/// have no word for it, as the web's `t(key, code)` does.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashTone;

import 'inventory_lib.dart';

/// `inventory.purchasing.statuses.<s>` (`draft` reads "Open").
String poStatusLabel(Translator t, String status) =>
    t('inventory.purchasing.statuses.$status', defaultValue: status);

DashTone poStatusTone(String status) =>
    poStatusTones[status] ?? DashTone.neutral;

/// `inventory.stocktakes.st_<s>`.
String stocktakeStatusLabel(Translator t, String status) =>
    t('inventory.stocktakes.st_$status', defaultValue: status);

DashTone stocktakeStatusTone(String status) =>
    stocktakeStatusTones[status] ?? DashTone.neutral;

/// `inventory.waste.reasons.<r>` (incl. the server's `refund` and
/// `order_cancelled`).
String wasteReasonLabel(Translator t, String reason) =>
    t('inventory.waste.reasons.$reason', defaultValue: reason);

/// `inventory.waste.sources.<s>` for a [wasteSource] value.
String wasteSourceLabel(Translator t, String source) =>
    t('inventory.waste.sources.$source', defaultValue: source);

/// `inventory.varianceReasons.<r>`.
String varianceReasonLabel(Translator t, String reason) =>
    t('inventory.varianceReasons.$reason', defaultValue: reason);

/// `inventory.movements.types.<type>`.
String movementTypeLabel(Translator t, String type) =>
    t('inventory.movements.types.$type', defaultValue: type);

/// A unit as a select offers it (`units.*`: translated, `l` → "L"/"لتر").
String unitOptionLabel(Translator t, String unit) =>
    t('units.$unit', defaultValue: fmtUnit(unit));

/// A figure and its unit as the tables show it: `fmtNumber(qty) fmtUnit(unit)`
/// (the unit is NOT translated).
String qtyWithUnit(DashFormat f, num qty, String? unit) {
  final u = fmtUnit(unit);
  final n = f.fmtNumber(qty);
  return u.isEmpty ? n : '$n $u';
}
