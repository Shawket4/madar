/// The shell's own words and the loader that puts every table together.
///
/// The web's tables (synced into dashboard_core's assets) carry nearly every
/// word the frame needs. What they lack — the web passes an inline default,
/// or the frame is new on the phone (the bottom bar, a page still being
/// ported) — lives here, in English and Arabic, merged
/// over the synced tables before any area's supplement.
library;

import 'package:dashboard_core/src/i18n/loader.dart';
import 'package:dashboard_core/src/i18n/strings.dart';
import 'package:dashboard_core/src/routes/route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The shell supplement: keys the web's tables do not have.
const Map<String, Map<String, String>> shellSupplement = {
  'en': {
    // The web's sidebar passes `{{count}} more` inline.
    'nav.showMoreCount_one': '{{count}} more',
    'nav.showMoreCount_other': '{{count}} more',
    // The phone's bottom bar.
    'shell.home': 'Home',
    'shell.navigation': 'Navigation',
    // A page whose port is not in this build yet.
    'shell.pendingTitle': 'This page is on its way',
    'shell.pendingBody':
        "It hasn't reached the app yet. Until it does, open it on the web dashboard.",
    // Offline: data saved on this device is on screen; a write cannot go.
    'shell.offlineBanner':
        "You're offline. Showing data saved at {{time}}; it may be out of date.",
    'shell.offlineCantSave': "You're offline, so this can't be saved.",
  },
  'ar': {
    'nav.showMoreCount_zero': 'لا مزيد',
    'nav.showMoreCount_one': 'عنصر آخر',
    'nav.showMoreCount_two': 'عنصران آخران',
    'nav.showMoreCount_few': '{{count}} عناصر أخرى',
    'nav.showMoreCount_many': '{{count}} عنصرًا آخر',
    'nav.showMoreCount_other': '{{count}} عنصر آخر',
    'shell.home': 'الرئيسية',
    'shell.navigation': 'التنقل',
    'shell.pendingTitle': 'هذه الصفحة في الطريق',
    'shell.pendingBody':
        'لم تصل إلى التطبيق بعد. إلى أن تصل، افتحها من لوحة التحكم على الويب.',
    'shell.offlineBanner':
        'أنت غير متصل بالإنترنت. تُعرض بيانات محفوظة في {{time}}، وقد لا تكون محدّثة.',
    'shell.offlineCantSave': 'أنت غير متصل بالإنترنت، لذا لا يمكن حفظ هذا.',
  },
};

/// Every supplement asset of [areas], in order.
List<String> areaSupplementAssets(List<DashArea> areas) => [
  for (final a in areas)
    ...(a.i18nSupplements.isEmpty
        ? DashArea.supplementAssets(a.key)
        : a.i18nSupplements),
];

/// The synced web tables, the shell supplement, then every area supplement.
///
/// An area's supplement is read from `packages/dashboard_<area>/…`; inside
/// that area's own package tests (where its assets are unprefixed) the
/// unprefixed `assets/i18n/<lang>.json` stands in, but only when the synced
/// tables themselves came prefixed (so dashboard_core's own tests never take
/// its synced table for a supplement). A declared table that cannot be found
/// is reported in [warnings] and skipped.
Future<Strings> loadDashStrings({
  required List<DashArea> areas,
  AssetBundle? bundle,
  MissingKeyLog? log,
  List<String>? warnings,
}) async {
  final b = bundle ?? rootBundle;
  final tables = <String, Map<String, String>>{};
  var corePrefixed = true;
  for (final lang in supportedLanguages) {
    String text;
    try {
      text = await b.loadString(coreStringsAsset(lang), cache: false);
    } on Object {
      corePrefixed = false;
      text = await b.loadString('assets/i18n/$lang.json', cache: false);
    }
    tables[lang] = parseStringTable(text);
  }
  final supplements = <Map<String, Map<String, String>>>[shellSupplement];
  for (final key in areaSupplementAssets(areas)) {
    final lang = languageOfAsset(key);
    String? text;
    try {
      text = await b.loadString(key, cache: false);
    } on Object {
      if (corePrefixed && key.startsWith('packages/')) {
        try {
          text = await b.loadString('assets/i18n/$lang.json', cache: false);
        } on Object {
          text = null;
        }
      }
    }
    if (text == null) {
      final msg = 'i18n supplement $key could not be loaded';
      warnings?.add(msg);
      debugPrint(msg);
      continue;
    }
    supplements.add({lang: parseStringTable(text)});
  }
  return Strings(tables, supplements: supplements, log: log);
}
