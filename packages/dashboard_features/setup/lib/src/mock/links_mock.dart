/// The mock backend for the links page editor (`/settings/links`, SET-LNK
/// rows), after `orgs/links_page.rs` and `qr_card/handlers.rs`:
///
/// - `GET /orgs/{id}/links-page`: same org, `org.settings.read`; the saved
///   page (every module exactly once, in the shop's order) with what each
///   module can show ([SetupSeed.linksModules]), the active branches, the
///   socials and the shop's own address.
/// - `PUT /orgs/{id}/links-page`: same org, `org.settings.edit`; the
///   backend's 400s (a module twice, more than 20 own links, a link with no
///   title, a title over 60, a link or Maps address that is not https, a
///   tagline over 160, a branch not the shop's, a social off the closed
///   list); new links get ids; `social_links` replaces the map (cleaned).
/// - `GET /orgs/{id}/links-qr`: same org, `org.settings.read`; 409 without
///   the shop's own address (custom branding + slug).
/// - `GET /public/orgs/links`: no session; what a customer sees (visible
///   buttons that can show, socials, the shown branches with directions).
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';
import '../shared/social_links.dart' show socialPlatforms;
import 'brand_appearance_mock.dart' show brandSafeLink, brandSocialPlatforms;
import 'support.dart';

/// The saved pages, one row per org (`id` = the org's id).
const String linksPagesTable = 'links_pages';

const int _maxCustom = 20;
const int _maxTitle = 60;
const int _maxTagline = 160;
const List<String> _modules = ['order', 'menu', 'rewards', 'book'];

/// The generic hosts a shop without its own address is served from.
const String _orderHost = 'https://order.madar-pos.cloud';
const String _bookHost = 'https://reservations.madar-pos.cloud';
const String _rewardsHost = 'https://loyalty.madar-pos.cloud';

/// Sabah's own link: its catering form.
final String linksCateringId = mockUuid('links:sabah:catering');

/// Sabah has set its page up: a line under its name, its catering form
/// third, and its own Maps pin for Zamalek. Nakhla never has.
List<MockRow> _seed() => [
  {
    'id': SeedIds.sabahOrg,
    'items': [
      {'kind': 'order', 'visible': true},
      {'kind': 'menu', 'visible': true},
      {
        'kind': 'custom',
        'visible': true,
        'id': linksCateringId,
        'title_en': 'Catering and events',
        'title_ar': 'الضيافة والمناسبات',
        'url': 'https://sabahcoffee.eg/catering',
      },
      {'kind': 'rewards', 'visible': true},
      {'kind': 'book', 'visible': true},
    ],
    'tagline_en': 'Specialty coffee, roasted in Cairo every morning.',
    'tagline_ar': 'قهوة مختصة تُحمَّص في القاهرة كل صباح.',
    'show_cover': true,
    'show_branches': true,
    'branches': {
      SeedIds.zamalek: {
        'hidden': false,
        'maps_url': 'https://maps.app.goo.gl/SabahZamalek26July',
      },
    },
  },
];

String? _clean(Object? v) {
  final s = v is String ? v.trim() : '';
  return s.isEmpty ? null : s;
}

/// `normalize`: every module once, in the shop's order, a missing one
/// appended visible; a module carries no id, title or address.
List<MockRow> _normalize(Iterable<MockRow> items) {
  final seen = <String>{};
  final out = <MockRow>[
    for (final i in items)
      if (i['kind'] == 'custom')
        i
      else if (seen.add(i['kind']! as String))
        {'kind': i['kind'], 'visible': i['visible'] ?? true},
  ];
  for (final m in _modules) {
    if (!seen.contains(m)) out.add({'kind': m, 'visible': true});
  }
  return out;
}

/// `load_stored`: the saved row, or the defaults (every module, cover and
/// branches on). A saved link whose address no longer passes is dropped.
MockRow _stored(MockDb db, String orgId) {
  final row = db[linksPagesTable].find(orgId);
  if (row == null) {
    return {
      'items': _normalize(const []),
      'tagline_en': null,
      'tagline_ar': null,
      'show_cover': true,
      'show_branches': true,
      'branches': const <String, Object?>{},
    };
  }
  return {
    ...row,
    'items': _normalize([
      for (final i in (row['items']! as List).cast<MockRow>())
        if (i['kind'] != 'custom' || brandSafeLink('${i['url'] ?? ''}')) i,
    ]),
  };
}

List<MockRow> _activeBranches(MockDb db, String orgId) => db['branches']
    .query(filters: {'org_id': orgId, 'is_active': true}, sort: 'name');

/// The org's programme mode while it runs (`loyalty_mode`).
String? _loyaltyMode(MockDb db, String orgId) {
  final p = db[SetupSeed.loyaltySettingsTable].firstWhere(
    (r) => r['org_id'] == orgId && r['branch_id'] == null,
  );
  return p?['enabled'] == true ? p!['mode'] as String? : null;
}

/// The shop's own origin (`links_page_origin`): custom branding + a slug.
String? _origin(MockRow org) {
  final slug = (org['slug'] as String?)?.trim().toLowerCase();
  if (org['custom_branding'] != true || slug == null || slug.isEmpty) {
    return null;
  }
  return 'https://$slug.${SetupSeed.publicRootDomain}';
}

LinksPageSettings _view(MockDb db, String orgId) {
  final org = db['orgs'].get(orgId, what: 'Organization not found');
  final s = _stored(db, orgId);
  final saved = (s['branches']! as Map).cast<String, Object?>();
  final origin = _origin(org);
  return LinksPageSettings(
    items: [
      for (final i in (s['items']! as List).cast<MockRow>())
        LinksPageItem.fromJson(i),
    ],
    taglineEn: s['tagline_en'] as String?,
    taglineAr: s['tagline_ar'] as String?,
    showCover: s['show_cover']! as bool,
    showBranches: s['show_branches']! as bool,
    branches: [
      for (final b in _activeBranches(db, orgId))
        LinksPageBranch(
          id: b['id']! as String,
          name: b['name']! as String,
          address: b['address'] as String?,
          phone: b['phone'] as String?,
          visible: (saved[b['id']] as Map?)?['hidden'] != true,
          mapsUrl: (saved[b['id']] as Map?)?['maps_url'] as String?,
        ),
    ],
    socialLinks: (org['social_links'] as Map?)?.cast<String, Object?>() ?? {},
    modules: SetupSeed.linksModules(db, orgId),
    publicUrl: origin == null ? null : '$origin/',
    customBranding: org['custom_branding'] == true,
    cardImageUrl: org['brand_card_image'] as String?,
    loyaltyMode: _loyaltyMode(db, orgId),
  );
}

/// `validate_items`, returning the tidied list.
List<MockRow> _validateItems(MockRequest req, MockDb db, Object? raw) {
  if (raw is! List) req.badRequest('Json deserialize error: missing field `items`');
  final modules = <String>{};
  final ids = <String>{};
  var customs = 0;
  final out = <MockRow>[];
  for (final e in raw) {
    final i = (e as Map).cast<String, Object?>();
    final kind = i['kind'];
    if (kind is! String || !(_modules.contains(kind) || kind == 'custom')) {
      req.badRequest('Json deserialize error: unknown variant `$kind`');
    }
    final visible = i['visible'] as bool? ?? true;
    if (kind != 'custom') {
      if (!modules.add(kind)) req.badRequest('"$kind" is in the list twice');
      out.add({'kind': kind, 'visible': visible});
      continue;
    }
    if (++customs > _maxCustom) {
      req.badRequest(
        'A links page can hold at most $_maxCustom of your own links',
      );
    }
    final titleEn = _clean(i['title_en']);
    if (titleEn == null) req.badRequest('Every link needs a title');
    final titleAr = _clean(i['title_ar']);
    for (final t in [titleEn, ?titleAr]) {
      if (t.runes.length > _maxTitle) {
        req.badRequest('A link title can be at most $_maxTitle characters');
      }
    }
    final url = _clean(i['url']) ?? '';
    if (!brandSafeLink(url)) {
      req.badRequest('"$titleEn" has to link to a full https:// address');
    }
    final id = i['id'] as String? ?? db.newId('links_items');
    if (!ids.add(id)) req.badRequest('Two links share one id');
    out.add({
      'kind': 'custom',
      'visible': visible,
      'id': id,
      'title_en': titleEn,
      'title_ar': titleAr,
      'url': url,
    });
  }
  return _normalize(out);
}

String? _tagline(MockRequest req, Object? v) {
  final s = _clean(v);
  if (s != null && s.runes.length > _maxTagline) {
    req.badRequest('A tagline can be at most $_maxTagline characters');
  }
  return s;
}

/// `social::validate` + `social::clean`: the closed list, https only; the
/// cleaned map replaces the org's.
Map<String, Object?> _socials(MockRequest req, Object? links) {
  if (links is! Map) {
    req.badRequest('Social links should be a set of named links');
  }
  final cleaned = <String, Object?>{};
  for (final e in links.entries) {
    final key = '${e.key}';
    if (!brandSocialPlatforms.contains(key)) {
      req.badRequest('"$key" is not somewhere we can link to');
    }
    final url = e.value is String ? (e.value as String).trim() : '';
    if (url.isEmpty) continue;
    if (!brandSafeLink(url)) {
      req.badRequest('The $key link has to be a full https:// address');
    }
    cleaned[key] = url;
  }
  return cleaned;
}

/// Where a module opens: on the shop's own host, else the generic one.
String _moduleHref(String? origin, String orgId, String kind) =>
    origin != null
    ? '$origin${SetupSeed.modulePaths[kind]}'
    : switch (kind) {
        'order' => '$_orderHost/order/$orgId',
        'menu' => '$_orderHost/order/$orgId/menu',
        'rewards' => '$_rewardsHost/$orgId',
        _ => '$_bookHost/$orgId',
      };

/// `directions_url`: the shop's pin, else the coordinates, else the address.
String? _directions(MockRow b, String? mapsUrl) {
  if (mapsUrl != null && brandSafeLink(mapsUrl)) return mapsUrl;
  final lat = b['latitude'], lng = b['longitude'];
  if (lat != null && lng != null) {
    return 'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
  }
  final address = _clean(b['address']);
  if (address == null) return null;
  return 'https://www.google.com/maps/search/?api=1&query='
      '${Uri.encodeQueryComponent(address)}';
}

PublicLinksPage _public(MockDb db, MockRow org) {
  final orgId = org['id']! as String;
  final s = _stored(db, orgId);
  final origin = _origin(org);
  final status = {
    for (final m in SetupSeed.linksModules(db, orgId)) m.kind.value: m,
  };
  final ordering = db[SetupSeed.deliverySettingsTable].where(
    (r) => _activeBranches(db, orgId).any((b) => b['id'] == r['branch_id']),
  );
  final channels = [
    for (final (c, field) in const [
      ('pickup', 'pickup_enabled'),
      ('delivery', 'outside_enabled'),
      ('in_mall', 'in_mall_enabled'),
      ('umbrella', 'umbrella_enabled'),
    ])
      if (ordering.any((r) => r[field] == true)) c,
  ];
  final items = <PublicLinksItem>[];
  for (final i in (s['items']! as List).cast<MockRow>()) {
    if (i['visible'] != true) continue;
    final kind = i['kind']! as String;
    if (kind == 'custom') {
      items.add(
        PublicLinksItem(
          kind: LinksItemKind.custom,
          href: i['url']! as String,
          titleEn: i['title_en'] as String?,
          titleAr: i['title_ar'] as String?,
          branchNames: const [],
          channels: const [],
        ),
      );
      continue;
    }
    final m = status[kind]!;
    if (!m.available) continue;
    items.add(
      PublicLinksItem(
        kind: m.kind,
        href: _moduleHref(origin, orgId, kind),
        path: m.path,
        branchNames: m.branchNames,
        channels: kind == 'order' ? channels : const [],
      ),
    );
  }
  final saved = (s['branches']! as Map).cast<String, Object?>();
  final links = (org['social_links'] as Map?) ?? const {};
  final loyalty = items.any((i) => i.kind == LinksItemKind.rewards)
      ? _loyaltyMode(db, orgId)
      : null;
  final o = Org.fromJson(org);
  return PublicLinksPage(
    brand: PublicBrand(
      orgId: o.id,
      name: o.name,
      slug: o.slug,
      customBranding: o.customBranding,
      accentColor: o.brandAccent ?? '#0F766E',
      backgroundColor: o.brandBackground ?? '#FFFFFF',
      foregroundColor: o.brandForeground ?? '#0F172A',
      logoIsMark: o.brandLogoIsMark ?? false,
      logoUrl: o.logoUrl,
      cardImageUrl: o.brandCardImage,
    ),
    taglineEn: s['tagline_en'] as String?,
    taglineAr: s['tagline_ar'] as String?,
    coverImageUrl: s['show_cover'] == true ? o.brandCardImage : null,
    items: items,
    socials: [
      for (final p in socialPlatforms)
        if (links[p.key] case final String url when url.trim().isNotEmpty)
          PublicSocialLink(key: p.key, label: p.label, url: url),
    ],
    branches: s['show_branches'] != true
        ? const []
        : [
            for (final b in _activeBranches(db, orgId))
              if ((saved[b['id']] as Map?)?['hidden'] != true)
                PublicLinksBranch(
                  id: b['id']! as String,
                  name: b['name']! as String,
                  address: _clean(b['address']),
                  phone: _clean(b['phone']),
                  directionsUrl: _directions(
                    b,
                    (saved[b['id']] as Map?)?['maps_url'] as String?,
                  ),
                ),
          ],
    loyaltyMode: loyalty,
  );
}

void registerLinksMocks(MockServer server, MockDb db) {
  seedTableIfAbsent(db, linksPagesTable, _seed);

  onIfAbsent(server, 'GET', '/orgs/{id}/links-page', (req) {
    final id = req.param('id');
    req.requireSameOrg(id);
    req.requireCap('org.settings.read');
    return MockResponse.ok(_view(db, id));
  });

  onIfAbsent(server, 'PUT', '/orgs/{id}/links-page', (req) {
    final id = req.param('id');
    req.requireSameOrg(id);
    req.requireCap('org.settings.edit');
    final org = db['orgs'].get(id, what: 'Organization not found');
    final body = req.json;
    final items = _validateItems(req, db, body['items']);
    final taglineEn = _tagline(req, body['tagline_en']);
    final taglineAr = _tagline(req, body['tagline_ar']);
    final ours = {
      for (final b in db['branches'].query(filters: {'org_id': id})) b['id'],
    };
    final branches = <String, Object?>{};
    for (final e in (body['branches'] as List?) ?? const []) {
      final b = (e as Map).cast<String, Object?>();
      final bid = b['branch_id'];
      if (!ours.contains(bid)) {
        req.badRequest("That branch is not one of this shop's");
      }
      final maps = _clean(b['maps_url']);
      if (maps != null && !brandSafeLink(maps)) {
        req.badRequest('A Maps link has to be a full https:// address');
      }
      final visible = b['visible'] as bool? ?? true;
      if (visible && maps == null) continue; // the default; nothing stored
      branches[bid! as String] = {'hidden': !visible, 'maps_url': maps};
    }
    final social = body['social_links'] == null
        ? null
        : _socials(req, body['social_links']);
    db[linksPagesTable].put({
      'id': id,
      'items': items,
      'tagline_en': taglineEn,
      'tagline_ar': taglineAr,
      'show_cover': body['show_cover'] as bool? ?? true,
      'show_branches': body['show_branches'] as bool? ?? true,
      'branches': branches,
    });
    if (social != null) org['social_links'] = social;
    return MockResponse.ok(_view(db, id));
  });

  onIfAbsent(server, 'GET', '/orgs/{id}/links-qr', (req) {
    final id = req.param('id');
    req.requireSameOrg(id);
    req.requireCap('org.settings.read');
    final org = db['orgs'].get(id, what: 'Organization not found');
    final origin = _origin(org);
    if (origin == null) {
      req.conflict(
        "The links page lives at the shop's own web address, which comes "
        'with custom branding',
      );
    }
    return MockResponse.ok(
      mockQrResponse(
        kind: 'org_links',
        longUrl: '$origin/',
        key: 'org_links:$id',
      ),
    );
  });

  onIfAbsent(server, 'GET', '/public/orgs/links', (req) {
    final id = req.q('org_id');
    final slug = req.q('slug');
    final org = db['orgs'].firstWhere(
      (o) =>
          o['is_active'] == true &&
          ((id != null && o['id'] == id) ||
              (slug != null && o['slug'] == slug)),
    );
    if (org == null) return MockResponse.notFound('No shop at that address');
    return MockResponse.ok(_public(db, org));
  });
}
