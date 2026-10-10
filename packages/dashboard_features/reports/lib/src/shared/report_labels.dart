/// Words the report pages derive from server codes, shared by Operations,
/// Financial and Bundles: payment methods, order channels and the bilingual
/// names of menu rows (`features/analytics/lib.ts` `tName`,
/// `analytics-page.tsx:125-138,264,629`).
library;

import 'package:dashboard_core/dashboard_core.dart';

/// `t('payments.<code>', code)`: the translated method, else the raw code
/// (a method outside the list shows as stored, as on the web).
String paymentMethodLabel(Translator t, String code) {
  final key = 'payments.$code';
  return t.exists(key) ? t(key) : code;
}

/// `t('orders.<dineIn|channel>', channel)`: "Dine-in", "Takeaway",
/// "Delivery"; any other channel as its raw code (REP-FIN-064).
String channelLabel(Translator t, String channel) {
  final key = 'orders.${channel == 'dine_in' ? 'dineIn' : channel}';
  return t.exists(key) ? t(key) : channel;
}

/// `tName`: in Arabic, the row's Arabic translation when it has one; else
/// the stored name (REP-OPS-064). [translations] is the wire's
/// `{ar?: string}` object (or null).
String translatedName(String name, Object? translations, String lang) {
  if (lang == 'ar' && translations is Map) {
    final ar = translations['ar'];
    if (ar is String && ar.isNotEmpty) return ar;
  }
  return name;
}
