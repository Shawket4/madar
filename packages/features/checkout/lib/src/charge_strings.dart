import 'package:rust_bridge/rust_bridge.dart';

/// Localise a Charge / Done-card string.
///
/// Every word on these surfaces goes through `bridge.tr` — the core owns the
/// strings for both hosts. A handful of keys are NEW with this screen
/// ("Add tip", "Will send when back online", "cleared?") and the core does
/// not know them yet; `tr` then hands the key itself back, which is what a
/// customer would read over the teller's shoulder. Until the keys land in
/// `i18n.rs` (the exact table is [chargeFallbackStrings], ready to paste) the
/// fallback below supplies the same two languages, chosen by the core's own
/// locale, so nothing on the screen ever reads `charge.add_tip`.
///
/// The check is "did the core return the key unchanged" — the moment the
/// core learns a key, its string wins and the fallback is dead code.
String chargeTr(MadarBridge bridge, String key) {
  final fromCore = bridge.tr(key: key);
  if (fromCore != key) return fromCore;
  final pair = chargeFallbackStrings[key];
  if (pair == null) return fromCore;
  return bridge.isRtl() ? pair.ar : pair.en;
}

/// One string in both scripts.
typedef ChargeString = ({String en, String ar});

/// The keys this feature introduced, with the words the core should carry
/// for them. Keep this table in step with `rust-core/crates/madar-core/src/
/// i18n.rs`; once every key is there this map can go.
const Map<String, ChargeString> chargeFallbackStrings = {
  // The verb, and what the header calls each caller.
  'charge.title': (en: 'Charge', ar: 'تحصيل'),
  'charge.takeaway': (en: 'Takeaway', ar: 'تيك أواي'),
  'charge.bill': (en: 'bill', ar: 'فاتورة'),
  // The hero and its one-line breakdown.
  'charge.vat_included': (en: 'VAT included', ar: 'شامل ضريبة القيمة المضافة'),
  'charge.subtotal_hint': (
    en: 'Service and VAT are added by the server',
    ar: 'تُضاف الخدمة والضريبة من الخادم',
  ),
  // The quiet rows.
  'charge.member': (en: 'Member', ar: 'عضو'),
  'charge.add_tip': (en: 'Add tip', ar: 'إضافة بقشيش'),
  'charge.remove_tip': (en: 'Remove tip', ar: 'إزالة البقشيش'),
  'charge.applied_at_charge': (
    en: 'applied at charge',
    ar: 'يُطبَّق عند التحصيل',
  ),
  'charge.free': (en: 'free', ar: 'مجاناً'),
  // The Done card.
  'charge.sale': (en: 'Sale', ar: 'بيع'),
  'charge.will_send': (
    en: 'Will send when back online',
    ar: 'سيُرسل عند عودة الاتصال',
  ),
  'charge.cleared_q': (en: 'cleared?', ar: 'تم تنظيفها؟'),
  'charge.cleared': (en: 'Cleared', ar: 'تم التنظيف'),
  'charge.not_yet': (en: 'Not yet', ar: 'ليس بعد'),
  'charge.not_printed': (
    en: 'Not printed — no printer',
    ar: 'لم تُطبع — لا توجد طابعة',
  ),
  'charge.printed': (en: 'Printed', ar: 'طُبع'),
  'charge.reprint': (en: 'Reprint', ar: 'إعادة طباعة'),
  'charge.change_short': (en: 'change', ar: 'الباقي'),
};
