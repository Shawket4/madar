import 'package:rust_bridge/rust_bridge.dart';

/// Localise an Orders-screen string.
///
/// Every word on the screen goes through `bridge.tr` — the core owns the
/// strings for both hosts. The redesign introduced a handful of keys the
/// core does not know yet ("This shift", "Tap a sale to see it here", the
/// void-versus-refund sentences); `tr` then hands the key itself back, which
/// is not something a teller should read at 11pm. Until the keys land in
/// `i18n.rs` (the exact table is [historyFallbackStrings], ready to paste)
/// the fallback below supplies the same two languages, chosen by the core's
/// own locale, so nothing on the screen ever reads `history.select_prompt`.
///
/// The check is "did the core return the key unchanged" — the moment the
/// core learns a key, its string wins and the fallback is dead code. Same
/// contract as feature_checkout's `chargeTr`.
String historyTr(MadarBridge bridge, String key) {
  final fromCore = bridge.tr(key: key);
  if (fromCore != key) return fromCore;
  final pair = historyFallbackStrings[key];
  if (pair == null) return fromCore;
  return bridge.isRtl() ? pair.ar : pair.en;
}

/// One string in both scripts.
typedef HistoryString = ({String en, String ar});

/// The keys this feature introduced, with the words the core should carry
/// for them. Keep this table in step with `rust-core/crates/madar-core/src/
/// i18n.rs`; once every key is there this map can go.
const Map<String, HistoryString> historyFallbackStrings = {
  // The scope segment and the header's count line.
  'history.this_shift': (en: 'This shift', ar: 'هذه الوردية'),
  'history.sales_count': (en: '{count} sales', ar: '{count} مبيعات'),
  'history.found_count': (en: '{count} found', ar: '{count} نتيجة'),
  'history.no_shift': (en: 'No shift open', ar: 'لا توجد وردية مفتوحة'),
  'history.search_hint': (
    en: 'Number, customer or amount',
    ar: 'الرقم أو العميل أو المبلغ',
  ),
  // Type chips (the wire has no takeaway value yet; the label is ready).
  'history.type.online': (en: 'Online', ar: 'أونلاين'),
  'history.type.takeaway': (en: 'Takeaway', ar: 'تيك أواي'),
  // The sale beside the list.
  'history.sale': (en: 'Sale', ar: 'بيع'),
  'history.select_prompt': (
    en: 'Tap a sale to see it here.',
    ar: 'اختر عملية بيع لعرضها هنا.',
  ),
  'history.service': (en: 'Service', ar: 'الخدمة'),
  'history.tip': (en: 'Tip', ar: 'بقشيش'),
  'history.vat_included': (en: 'VAT included', ar: 'شامل الضريبة'),
  'history.paid_at': (en: 'Paid {time}', ar: 'دُفعت {time}'),
  'history.reprint': (en: 'Reprint', ar: 'إعادة طباعة'),
  'history.more': (en: 'More', ar: 'المزيد'),
  // What a row's state means, in words.
  'history.queued_hint': (
    en: 'Will send when back online.',
    ar: 'سيُرسل عند عودة الاتصال.',
  ),
  'history.failed_hint': (
    en: 'The server refused this sale — see Sync.',
    ar: 'رفض الخادم عملية البيع هذه — راجع المزامنة.',
  ),
  'history.voided_hint': (
    en: 'This sale was voided.',
    ar: 'أُبطلت عملية البيع هذه.',
  ),
  // Searching every shift.
  'history.offline_search': (
    en: 'Searching past shifts needs a connection.',
    ar: 'البحث في الورديات السابقة يحتاج اتصالاً بالخادم.',
  ),
  'history.offline_cached': (
    en: 'Offline — showing what was loaded.',
    ar: 'غير متصل — تُعرض النتائج المحمّلة سابقاً.',
  ),
  'history.retry': (en: 'Try again', ar: 'أعد المحاولة'),
  // A refund is not a void, and the screen says so.
  'history.void_sale': (en: 'Void sale', ar: 'إبطال البيع'),
  'history.void_teach': (
    en: 'Void removes a mistaken sale as if it never happened.',
    ar: 'الإبطال يزيل عملية بيع خاطئة كأنها لم تحدث.',
  ),
  'history.refund_teach': (
    en:
        'Returning money on a sale that stands is a refund — '
        'the server does not offer refunds yet.',
    ar:
        'إرجاع المال مع بقاء عملية البيع هو استرداد — '
        'والخادم لا يدعم الاسترداد بعد.',
  ),
  'history.void_cannot_queued': (
    en: 'A queued sale cannot be voided until it reaches the server.',
    ar: 'لا يمكن إبطال عملية في الانتظار قبل وصولها إلى الخادم.',
  ),
  'history.void_cannot_voided': (en: 'Already voided.', ar: 'أُبطلت بالفعل.'),
  'history.void_cannot_failed': (
    en: 'This sale never reached the server; there is nothing to void.',
    ar: 'لم تصل عملية البيع هذه إلى الخادم؛ لا شيء لإبطاله.',
  ),
};
