/// Every Madar app and where it is listed: the Dart copy of MadarDashboard
/// `shared/apps.ts` (the marketing site and the web dashboard read that one).
/// CHANGE BOTH: when an app goes live on a store, its URL here and there is
/// the whole change. A URL shows that store's official badge; the icons,
/// badges and QR codes are `assets/apps/` (copied from `shared/apps/`, each
/// QR encoding the app's downloads page).
library;

enum MadarApp {
  cashier(
    appStore: 'https://apps.apple.com/us/app/madar-cashier/id6815221877',
    // Not on Google Play yet: its URL goes here.
    googlePlay: null,
    download: 'pos',
  ),
  kitchen(download: 'kitchen'),
  dashboard(download: 'dashboard'),
  dawam(download: 'dawam');

  const MadarApp({required this.download, this.appStore, this.googlePlay});

  final String? appStore;
  final String? googlePlay;

  /// The downloads site's id for the app (`?app=`).
  final String download;

  /// On at least one store.
  bool get isLive => appStore != null || googlePlay != null;

  String get icon => 'packages/dashboard_overview/assets/apps/icons/$name.svg';

  /// The QR of [downloadsUri] in [lang].
  String qr(String lang) =>
      'packages/dashboard_overview/assets/apps/qr/$name-${_lang(lang)}.svg';
}

/// The order the family is shown in: the till first, it is what a shop
/// needs to sell (the web's `FAMILY`).
const List<MadarApp> madarFamily = [
  MadarApp.cashier,
  MadarApp.kitchen,
  MadarApp.dawam,
  MadarApp.dashboard,
];

/// Every build (Android APKs, Mac, Windows, Linux) lives on the downloads site.
const String downloadsUrl = 'https://downloads.madar-pos.cloud';

/// The downloads page in [lang], with [app]'s card in the middle of the
/// screen (`downloadsHref`).
Uri downloadsUri(String lang, MadarApp app) => Uri.parse(
  '$downloadsUrl/${_lang(lang) == 'ar' ? 'ar/' : ''}?app=${app.download}',
);

/// The stores' official badges, unaltered.
String appStoreBadge(String lang) =>
    'packages/dashboard_overview/assets/apps/stores/app-store-${_lang(lang)}.svg';
String googlePlayBadge(String lang) =>
    'packages/dashboard_overview/assets/apps/stores/google-play-${_lang(lang)}.png';

String _lang(String lang) => lang.startsWith('ar') ? 'ar' : 'en';
