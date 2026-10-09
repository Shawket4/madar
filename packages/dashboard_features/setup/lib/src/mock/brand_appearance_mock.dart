/// The mock backend for Brand and appearance (`/settings/brand`, `/settings`,
/// SET-BRD, SET-APP and SET-SHL rows).
///
/// Routes this unit answers (`orgs::handlers`), each only when no other area
/// does (`onIfAbsent`: admin's org dialog answers the same routes in the app):
/// - `PATCH /orgs/{id}` (`update_org`): `org.settings.edit`, then super admin
///   only — a shop owner's links save is refused by the real server too;
///   `social_links` checked (closed list, https only) and stored cleaned,
///   replacing the map.
/// - `PUT /orgs/{id}/logo` (field `logo`) and `PUT /orgs/{id}/card-image`
///   (field `image`): `org.settings.edit` and the caller's own org (or a
///   super admin). The asset worker finishes at once here: the stored address
///   is the picture itself as a `data:` URI, so it draws with no network.
///   The palette is not re-derived (the seed's stays).
///
/// `GET /orgs/{id}` is the core's (`org.settings.read`, same org).
library;

import 'dart:convert';

import 'package:dashboard_api/mock.dart';

import 'support.dart';

/// The backend's closed list of places a shop can link to.
const List<String> brandSocialPlatforms = [
  'instagram',
  'facebook',
  'tiktok',
  'x',
  'youtube',
  'whatsapp',
  'talabat',
  'website',
];

/// `social::is_safe`: `https://`, something after it, no whitespace.
bool brandSafeLink(String url) =>
    url.startsWith('https://') &&
    url.length > 'https://'.length &&
    !url.contains(RegExp(r'\s'));

void registerBrandAppearanceMocks(MockServer server, MockDb db) {
  final orgs = db['orgs'];

  Map<String, Object?> live(MockRequest req, String id) =>
      orgs.get(id, what: 'Org not found');

  MockResponse upload(MockRequest req, String field, String column) {
    req.requireCap('org.settings.edit');
    final id = req.param('id');
    if (!req.persona.isPlatform && req.persona.orgId != id) {
      req.fail(
        MockResponse.forbidden(
          field == 'logo'
              ? "You can only change your own organisation's logo"
              : "You can only change your own organisation's card image",
        ),
      );
    }
    live(req, id);
    final file = req.file(field);
    if (file == null) {
      req.badRequest(
        field == 'logo'
            ? "No logo file received in field 'logo'"
            : "No file received in field 'image'",
      );
    }
    final type = file.contentType ?? 'image/png';
    final url = 'data:$type;base64,${base64Encode(file.bytes)}';
    final updated = orgs.update(id, {column: url});
    return MockResponse.ok({
      ...updated,
      'asset_job_id': db.newId('asset_jobs'),
      'status': 'processing',
    });
  }

  onIfAbsent(
    server,
    'PUT',
    '/orgs/{id}/logo',
    (req) => upload(req, 'logo', 'logo_url'),
  );
  onIfAbsent(
    server,
    'PUT',
    '/orgs/{id}/card-image',
    (req) => upload(req, 'image', 'brand_card_image'),
  );

  onIfAbsent(server, 'PATCH', '/orgs/{id}', (req) {
    req.requireCap('org.settings.edit');
    req.requirePlatform();
    final id = req.param('id');
    live(req, id);
    final body = req.json;
    final patch = <String, Object?>{};
    final links = body['social_links'];
    if (links != null) {
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
      patch['social_links'] = cleaned;
    }
    for (final f in const ['name', 'receipt_footer', 'custom_branding']) {
      if (body[f] != null) patch[f] = body[f];
    }
    return MockResponse.ok(orgs.update(id, patch));
  });
}
