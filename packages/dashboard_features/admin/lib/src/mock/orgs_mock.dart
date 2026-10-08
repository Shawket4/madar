/// `/orgs` Organizations (ADM-ORG rows): GET /orgs (listOrgs, replaces the
/// core's), DELETE/PATCH /orgs/{id}, PUT /orgs/{id}/logo, POST /orgs/provision,
/// GET /orgs/templates (seed: `AdminSeed.templates`). `GET /timezones` is
/// the core's.
///
/// Handlers behave like the backend (MadarRust `src/orgs/handlers.rs`,
/// `provision.rs`, `slugs.rs`, `social.rs`): super-admin only except the
/// logo (a member may change their own org's), the same refusals in the
/// same order with the same sentences, soft deletes, and state over the
/// shared [MockDb] (a create shows in the next list).
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';

import '../area_seed.dart';

/// The backend's reserved slugs (`slugs.rs` `RESERVED`).
const Set<String> reservedSlugs = {
  'api', 'demo', 'demo-api', 'get', 'legal', 'loyalty', 'order', //
  'reservations', 'sentry', 'www', 'autoconfig', 'autodiscover', 'mail',
  'smtp', 'imap', 'pop', 'mx', 'ns', 'ns1', 'ns2', 'ftp', 'postmaster',
  'hostmaster', 'webmaster', 'abuse', 'noreply', 'no-reply', 'madar',
  'madarpos',
};

/// The social platforms the server links to (`social.rs` `PLATFORMS`).
const List<String> socialPlatformKeys = [
  'instagram',
  'facebook',
  'tiktok',
  'x',
  'youtube',
  'whatsapp',
  'talabat',
  'website',
];

/// `slugs::validate`: null when [slug] may be a shop's short name, else the
/// 400 sentence.
String? slugProblem(String slug) {
  final s = slug.trim();
  String bad(String why) => 'That short name $why.';
  if (s.isEmpty) return bad('cannot be empty');
  if (s.runes.length < 3) return bad('has to be at least three characters');
  if (utf8.encode(s).length > 63) return bad('is too long for a web address');
  if (!RegExp(r'^[a-z0-9-]+$').hasMatch(s)) {
    return bad('may only use lowercase letters, numbers and hyphens');
  }
  if (s.startsWith('-') || s.endsWith('-')) {
    return bad('cannot start or end with a hyphen');
  }
  if (s.startsWith('xn--')) return bad('cannot start with "xn--"');
  if (RegExp(r'^[0-9]+$').hasMatch(s)) return bad('cannot be only numbers');
  if (reservedSlugs.contains(s)) return bad('is reserved');
  return null;
}

bool _safeLink(String url) {
  final uri = Uri.tryParse(url);
  return uri != null &&
      uri.scheme == 'https' &&
      uri.host.isNotEmpty &&
      !url.contains(RegExp(r'\s'));
}

/// The org as the API answers it (the soft-delete mark is the table's own).
Map<String, Object?> _public(MockRow row) =>
    Map<String, Object?>.of(row)..remove('deleted_at');

void registerOrgsMocks(MockServer server, MockDb db) {
  final orgs = db['orgs'];

  MockRow live(MockRequest req, String id) {
    final row = orgs.find(id);
    if (row == null || row['deleted_at'] != null) req.notFound('Org not found');
    return row;
  }

  bool knownZone(String tz) => mockTimezones.contains(tz);

  // GET /orgs — every organization, by name (`require_super_admin`).
  server.on('GET', '/orgs', (req) {
    req.requirePlatform();
    return MockResponse.ok([
      for (final o in orgs.query(
        where: (o) => o['deleted_at'] == null,
        sort: 'name',
      ))
        _public(o),
    ]);
  });

  // GET /orgs/templates — the templates a new org can start from.
  server.on('GET', '/orgs/templates', (req) {
    req.requirePlatform();
    return MockResponse.ok(db[AdminTables.templates].rows);
  });

  // DELETE /orgs/{id} — a soft delete; the org stops answering at once.
  server.on('DELETE', '/orgs/{id}', (req) {
    req.requirePlatform();
    final row = live(req, req.param('id'));
    orgs.update(row['id']! as String, {
      'deleted_at': db.nowIso,
      'is_active': false,
    });
    return MockResponse.empty();
  });

  // PATCH /orgs/{id} — `update_org`: COALESCE semantics (a null leaves the
  // field as it is), except `logo_url: null`, which clears the logo.
  server.on('PATCH', '/orgs/{id}', (req) {
    req.requirePlatform();
    final id = req.param('id');
    final existing = live(req, id);
    final body = req.json;

    final slug = body['slug'];
    if (slug is String && slug != existing['slug']) {
      final current = existing['slug'] as String?;
      final frozen =
          existing['custom_branding'] == true &&
          current != null &&
          current.trim().isNotEmpty;
      if (frozen) {
        req.conflict(
          "This shop's short name is part of its web address and the codes "
          'it has printed, so it cannot be changed. Turn custom branding off '
          'first if it really has to move.',
        );
      }
      final problem = slugProblem(slug);
      if (problem != null) req.badRequest(problem);
      final taken = orgs.rows.any(
        (o) => o['slug'] == slug && o['id'] != id,
      );
      if (taken) req.conflict("Slug '$slug' is already taken");
    }

    for (final name in const ['tax_rate', 'service_charge_rate']) {
      final r = body[name];
      if (r is num && (r < 0 || r > 1)) {
        req.badRequest(
          '$name is a fraction between 0 and 1, not a percentage — '
          '0.14 means 14%',
        );
      }
    }

    final tz = body['timezone'];
    if (tz is String && tz.isNotEmpty && !knownZone(tz)) {
      req.badRequest("Unknown timezone '$tz'");
    }

    Map<String, Object?>? social;
    final links = body['social_links'];
    if (links != null) {
      if (links is! Map) {
        req.badRequest('Social links should be a set of named links');
      }
      social = {};
      for (final e in links.entries) {
        final key = '${e.key}';
        if (!socialPlatformKeys.contains(key)) {
          req.badRequest('"$key" is not somewhere we can link to');
        }
        final url = e.value is String ? (e.value as String).trim() : '';
        if (url.isEmpty) continue;
        if (!_safeLink(url)) {
          req.badRequest('The $key link has to be a full https:// address');
        }
        social[key] = url;
      }
    }

    final patch = <String, Object?>{
      for (final f in const [
        'name',
        'slug',
        'currency_code',
        'tax_rate',
        'receipt_footer',
        'is_active',
        'custom_branding',
        'tax_inclusive',
        'service_charge_rate',
        'service_charge_taxable',
        'require_table_for_orders',
        'modules',
      ])
        if (body[f] != null) f: body[f],
      if (tz is String && tz.isNotEmpty) 'timezone': tz,
      'social_links': ?social,
      if (body.containsKey('logo_url')) 'logo_url': body['logo_url'],
    };
    final updated = orgs.update(id, patch);
    return MockResponse.ok(_public(updated));
  });

  // PUT /orgs/{id}/logo — a super admin, or a member for their own org. The
  // asset worker finishes at once here: the stored address is the picture
  // itself, as a data URI, so it draws without a network.
  server.on('PUT', '/orgs/{id}/logo', (req) {
    final id = req.param('id');
    if (!req.persona.isPlatform && req.persona.orgId != id) {
      req.fail(
        MockResponse.forbidden(
          "You can only change your own organisation's logo",
        ),
      );
    }
    live(req, id);
    final file = req.file('logo');
    if (file == null) req.badRequest("No logo file received in field 'logo'");
    final type = file.contentType ?? 'image/png';
    final url = 'data:$type;base64,${base64Encode(file.bytes)}';
    final updated = orgs.update(id, {'logo_url': url});
    return MockResponse.ok({
      ..._public(updated),
      'asset_job_id': db.newId('asset_jobs'),
      'status': 'processing',
    });
  });

  // POST /orgs/provision — the org, its first branch and its owner at once,
  // refused in `provision_org`'s order.
  server.on('POST', '/orgs/provision', (req) {
    req.requirePlatform();
    final b = req.bodyAs(ProvisionOrgRequest.fromJson);
    final name = b.name.trim();
    if (name.isEmpty) req.badRequest('name is required');
    final slugIssue = slugProblem(b.slug);
    if (slugIssue != null) req.badRequest(slugIssue);
    final keys = [
      for (final t in db[AdminTables.templates].rows) t['key']! as String,
    ];
    if (!keys.contains(b.template)) {
      req.badRequest('template must be one of: ${keys.join(', ')}');
    }
    final tax = b.taxRate ?? 0;
    if (tax < 0 || tax > 1) {
      req.badRequest(
        'tax_rate is a fraction between 0 and 1, not a percentage — '
        '0.14 means 14%',
      );
    }
    final tz = (b.timezone == null || b.timezone!.isEmpty)
        ? 'Africa/Cairo'
        : b.timezone!;
    if (!knownZone(tz)) req.badRequest("Unknown timezone '$tz'");
    final branchName = b.branch.name.trim();
    if (branchName.isEmpty) req.badRequest('branch.name is required');
    final ownerName = b.owner.name.trim();
    final email = b.owner.email.trim().toLowerCase();
    if (ownerName.isEmpty || !email.contains('@')) {
      req.badRequest('owner.name and a valid owner.email are required');
    }
    if (b.owner.password.runes.length < 8) {
      req.badRequest('owner.password must be at least 8 characters');
    }
    final pin = b.owner.pin;
    if (pin != null && !RegExp(r'^[0-9]{6}$').hasMatch(pin)) {
      req.badRequest('A new PIN must be 6 digits');
    }
    if (orgs.rows.any((o) => o['slug'] == b.slug)) {
      req.conflict("Slug '${b.slug}' is already taken");
    }
    final emailTaken = db['users'].rows.any(
      (u) =>
          u['deleted_at'] == null &&
          (u['email'] as String?)?.toLowerCase() == email,
    );
    if (emailTaken) req.conflict('Email already in use');

    final now = req.now;
    final org = Org(
      id: db.newId('orgs'),
      name: name,
      slug: b.slug,
      currencyCode: b.currencyCode ?? 'EGP',
      timezone: tz,
      taxRate: tax,
      taxInclusive: false,
      serviceChargeRate: 0,
      serviceChargeTaxable: true,
      requireTableForOrders: false,
      customBranding: false,
      isActive: true,
      modules: b.modules ?? const ['pos'],
      socialLinks: const {},
    );
    orgs.insert(org.toJson());
    String? opt(String? s) {
      final v = s?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    final branch = Branch(
      id: db.newId('branches'),
      orgId: org.id,
      name: branchName,
      address: opt(b.branch.address),
      phone: opt(b.branch.phone),
      timezone: tz,
      isActive: true,
      oldBillHours: 4,
      createdAt: now,
      updatedAt: now,
    );
    db['branches'].insert(branch.toJson());
    final owner = UserPublic(
      id: db.newId('users'),
      name: ownerName,
      email: email,
      role: UserRole.orgAdmin,
      orgId: org.id,
      isActive: true,
    );
    db['users'].insert(owner.toJson());
    return MockResponse.created(
      ProvisionedOrg(
        org: org,
        branchId: branch.id,
        ownerId: owner.id,
        template: b.template,
      ),
    );
  });
}
