/// What the links page editor works out in the browser
/// (`features/links/admin/links-pane.tsx`, `features/links/public/
/// links-page.tsx`, `features/public-shell/brand-color.ts`), as pure
/// functions.
library;

import 'dart:math';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart' show Translator;
import 'package:flutter/services.dart' show TextInputFormatter;

import '../shared/social_links.dart';

const int linksMaxTagline = 160;
const int linksMaxTitle = 60;

/// The web's `maxLength` and the server count UTF-16 code units, not
/// characters: an Arabic line with diacritics is held to what the server
/// takes (LNK-010, 016). Shortening always goes through, so a longer saved
/// value can still be cut down.
// ponytail: an over-long paste is refused whole, not cut to fit like the browser.
TextInputFormatter codeUnitLimit(int max) => TextInputFormatter.withFunction(
  (old, next) =>
      next.text.length <= max || next.text.length < old.text.length
      ? next
      : old,
);

/// A branch row as edited: the settings plus what the list shows.
class LinksBranchDraft {
  const LinksBranchDraft({
    required this.branchId,
    required this.name,
    required this.visible,
    required this.mapsUrl,
    this.address,
  });

  factory LinksBranchDraft.of(LinksPageBranch b) => LinksBranchDraft(
    branchId: b.id,
    name: b.name,
    address: b.address,
    visible: b.visible,
    mapsUrl: b.mapsUrl ?? '',
  );

  final String branchId;
  final String name;
  final String? address;
  final bool visible;
  final String mapsUrl;

  LinksBranchDraft copyWith({bool? visible, String? mapsUrl}) =>
      LinksBranchDraft(
        branchId: branchId,
        name: name,
        address: address,
        visible: visible ?? this.visible,
        mapsUrl: mapsUrl ?? this.mapsUrl,
      );
}

/// A new own link: visible, empty, with a client id (`crypto.randomUUID`).
LinksPageItem newCustomLink() => LinksPageItem(
  kind: LinksItemKind.custom,
  visible: true,
  id: _uuidV4(),
  titleEn: '',
  titleAr: '',
  url: '',
);

String _uuidV4() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

/// An item with [patch]ed fields (the web's `{...it, ...patch}`).
LinksPageItem patchLink(
  LinksPageItem it, {
  bool? visible,
  String? titleEn,
  String? titleAr,
  String? url,
}) => LinksPageItem(
  kind: it.kind,
  visible: visible ?? it.visible,
  id: it.id,
  titleEn: titleEn ?? it.titleEn,
  titleAr: titleAr ?? it.titleAr,
  url: url ?? it.url,
);

/// A URL field is marked invalid: something typed, and not https.
bool linkUrlInvalid(String? url) {
  final v = (url ?? '').trim();
  return v.isNotEmpty && !isHttpsUrl(v);
}

/// `customProblem`: an own link with no English title, a title over 60, or
/// an address that is not https.
bool linksCustomProblem(List<LinksPageItem> items) => items.any(
  (it) =>
      it.kind == LinksItemKind.custom &&
      ((it.titleEn ?? '').trim().isEmpty ||
          (it.titleEn ?? '').length > linksMaxTitle ||
          (it.titleAr ?? '').length > linksMaxTitle ||
          !isHttpsUrl((it.url ?? '').trim())),
);

/// `mapsProblem`: a Maps link typed that is not https.
bool linksMapsProblem(List<LinksBranchDraft> branches) =>
    branches.any((b) => linkUrlInvalid(b.mapsUrl));

String? _trimmedOrNull(String? v) {
  final s = (v ?? '').trim();
  return s.isEmpty ? null : s;
}

/// The PUT body (SET-LNK-021): own links trimmed (an empty Arabic title is
/// `null`), modules as `{kind, visible}` only, taglines and Maps links
/// trimmed or `null`, the socials as a patch over [savedSocial].
LinksPageInput linksSaveBody({
  required List<LinksPageItem> items,
  required String taglineEn,
  required String taglineAr,
  required bool showCover,
  required bool showBranches,
  required List<LinksBranchDraft> branches,
  required Map<String, String> social,
  required Map<String, Object?> savedSocial,
}) => LinksPageInput(
  items: [
    for (final it in items)
      it.kind == LinksItemKind.custom
          ? LinksPageItem(
              kind: it.kind,
              visible: it.visible,
              id: it.id,
              titleEn: (it.titleEn ?? '').trim(),
              titleAr: _trimmedOrNull(it.titleAr),
              url: (it.url ?? '').trim(),
              explicitNulls: const {'title_ar'},
            )
          : LinksPageItem(kind: it.kind, visible: it.visible),
  ],
  taglineEn: _trimmedOrNull(taglineEn),
  taglineAr: _trimmedOrNull(taglineAr),
  showCover: showCover,
  showBranches: showBranches,
  branches: [
    for (final b in branches)
      LinksPageBranchInput(
        branchId: b.branchId,
        visible: b.visible,
        mapsUrl: _trimmedOrNull(b.mapsUrl),
        explicitNulls: const {'maps_url'},
      ),
  ],
  socialLinks: socialLinksPatch(social, savedSocial),
  explicitNulls: const {'tagline_en', 'tagline_ar'},
);

/// A row's title: an own link's English title or "New link"; a module's
/// name.
String linksRowTitle(LinksPageItem it, Translator t) =>
    it.kind == LinksItemKind.custom
    ? ((it.titleEn ?? '').trim().isNotEmpty
          ? it.titleEn!.trim()
          : t('links.editor.newLink'))
    : t('links.module.${it.kind.value}.title');

/// A row's line under its title (SET-LNK-013).
String linksRowSubtitle(
  LinksPageItem it,
  LinksModuleStatus? status,
  Translator t,
) {
  if (it.kind == LinksItemKind.custom) {
    final url = it.url ?? '';
    return url.isNotEmpty ? url : t('links.editor.customHint');
  }
  if (status != null && !status.available) {
    return t('links.editor.off.${it.kind.value}');
  }
  if (status != null && status.branchNames.isNotEmpty) {
    return status.branchNames.join(' · ');
  }
  return t('links.editor.available');
}

// ── the public page (the preview) ──────────────────────────────────────────

/// `hostOf`: the address's host without `www.`, else the address itself.
String linksHostOf(String url) {
  final u = Uri.tryParse(url);
  if (u == null || !u.hasScheme || u.host.isEmpty) return url;
  final host = u.hasPort ? '${u.host}:${u.port}' : u.host;
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// `hintOf`: one line under a module's title, from the server's facts.
String linksHintOf(PublicLinksItem item, String? loyaltyMode, Translator t) {
  switch (item.kind.value) {
    case 'order':
      final ch = [
        for (final c in item.channels)
          if (t.exists('links.channel.$c')) t('links.channel.$c'),
      ];
      return ch.isNotEmpty ? ch.join(' · ') : t('links.module.order.hint');
    case 'book':
      return item.branchNames.length == 1
          ? t('links.module.book.one', args: {'branch': item.branchNames[0]})
          : t('links.module.book.hint');
    case 'rewards':
      return loyaltyMode == 'points'
          ? t('links.module.rewards.points')
          : t('links.module.rewards.visits');
    case 'menu':
      return t('links.module.menu.hint');
  }
  return '';
}

/// A button's title and hint (`useItemText`): an own link's title in the
/// page's language (Arabic falls back to English, then the host).
({String title, String hint}) linksItemText(
  PublicLinksItem item,
  String? loyaltyMode,
  Translator t, {
  required bool arabic,
}) {
  if (item.kind != LinksItemKind.custom) {
    return (
      title: t('links.module.${item.kind.value}.title'),
      hint: linksHintOf(item, loyaltyMode, t),
    );
  }
  final ar = arabic ? (item.titleAr ?? '').trim() : '';
  final en = (item.titleEn ?? '').trim();
  final host = linksHostOf(item.href);
  return (title: ar.isNotEmpty ? ar : (en.isNotEmpty ? en : host), hint: host);
}

/// The page grounds the accent is checked against (`PAGE_GROUND`).
const String linksGroundLight = '#EFF3F4';
const String linksGroundDark = '#14181E';

/// Madar's own teal: the band when the server sent no colour.
const String linksMadarTeal = '#0D6273';

final RegExp _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

double _luminance(String hex) {
  double ch(int i) {
    final c = int.parse(hex.substring(1 + i * 2, 3 + i * 2), radix: 16) / 255;
    return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * ch(0) + 0.7152 * ch(1) + 0.0722 * ch(2);
}

/// WCAG contrast between two `#RRGGBB` colours.
double linksContrast(String a, String b) {
  final la = _luminance(a), lb = _luminance(b);
  final hi = max(la, lb), lo = min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

String _mix(String a, String b, double t) {
  int ch(String h, int i) =>
      int.parse(h.substring(1 + i * 2, 3 + i * 2), radix: 16);
  String c(int i) => (ch(a, i) + (ch(b, i) - ch(a, i)) * t)
      .round()
      .toRadixString(16)
      .padLeft(2, '0');
  return '#${c(0)}${c(1)}${c(2)}';
}

/// `readableOn`: [color] kept when it reads on [ground] (AA, 4.5), else
/// walked toward black (light ground) or white (dark ground) in 8% steps.
String linksReadableOn(String color, String ground) {
  if (!_hex.hasMatch(color) || !_hex.hasMatch(ground)) return color;
  if (linksContrast(color, ground) >= 4.5) return color;
  final target = _luminance(ground) > 0.5 ? '#000000' : '#ffffff';
  var out = color;
  for (var t = 0.08; t <= 1.0001; t += 0.08) {
    out = _mix(color, target, t);
    if (linksContrast(out, ground) >= 4.5) return out;
  }
  return out;
}
