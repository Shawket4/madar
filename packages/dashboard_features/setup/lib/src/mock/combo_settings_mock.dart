/// The mock backend for Combos and deals settings (`/settings/combos`,
/// SET-CMB rows), as MadarRust `src/combos/handlers.rs` answers:
///
/// - `GET /settings/combos`: `org.settings.read`; the caller's org (a
///   platform admin with none picked is refused: "A super admin must scope
///   this to an org"). The org's four switches (on unless switched off), the
///   minimum margin, and every branch that overrides a switch, by branch
///   name, each with what it resolves to.
/// - `PUT /settings/combos`: `menu.combos.edit`; the margin is replaced
///   (blank or null = no warning; not a decimal, or outside 0–1, is a 400),
///   the switches replaced when sent.
/// - `PUT /settings/combos/branches/{branch_id}`: `menu.combos.edit` at that
///   branch, a branch of the org (else 404); all four null deletes the
///   override. 204.
/// - `DELETE /settings/combos/branches/{branch_id}`: the same gate; 204.
///
/// The margin lives in `offers_org_settings.combo_min_margin`, the row the
/// catalog_offers area's combo editor warns from: same table, same seed
/// (Sabah 55 %), so the two areas agree whichever seeds first.
library;

import 'package:dashboard_api/mock.dart';

import 'support.dart';

abstract final class ComboSettingsMock {
  /// `{id: <org id>, combo_min_margin}` (catalog_offers' `OffersTables.orgSettings`).
  static const String margins = 'offers_org_settings';

  /// `{id: <org id>, pos, qr, online, delivery}` (`combo_channel_settings`).
  static const String orgChannels = 'combo_channel_settings';

  /// `{id: <branch id>, org_id, pos, qr, online, delivery}`, null = follow
  /// (`combo_channel_branch_overrides`).
  static const String branchChannels = 'combo_channel_branch_overrides';

  static const List<String> channels = ['pos', 'qr', 'online', 'delivery'];

  /// Sabah's minimum margin (catalog_offers' `OffersSeed.minMargin`).
  static const String sabahMinMargin = '0.5500';

  /// Sabah sells combos everywhere but the delivery apps.
  static List<MockRow> orgRows() => [
    {
      'id': SeedIds.sabahOrg,
      'pos': true,
      'qr': true,
      'online': true,
      'delivery': false,
    },
  ];

  /// Zamalek has no table QR menu for combos; New Cairo lists them on the
  /// delivery apps.
  static List<MockRow> branchRows() => [
    _over(SeedIds.zamalek, qr: false),
    _over(SeedIds.newCairo, delivery: true),
  ];

  static MockRow _over(
    String branchId, {
    bool? pos,
    bool? qr,
    bool? online,
    bool? delivery,
  }) => {
    'id': branchId,
    'org_id': SeedIds.sabahOrg,
    'pos': pos,
    'qr': qr,
    'online': online,
    'delivery': delivery,
  };

  /// The org's switches, every one on when never saved.
  static Map<String, bool> orgSwitches(MockDb db, String orgId) {
    final row = db[orgChannels].find(orgId);
    return {for (final c in channels) c: row?[c] as bool? ?? true};
  }

  /// `settings_of`: the answer to `GET /settings/combos`.
  static Map<String, Object?> wire(MockDb db, String orgId) {
    final org = orgSwitches(db, orgId);
    final branches = db['branches'];
    String nameOf(MockRow o) => '${branches.find('${o['id']}')?['name']}';
    final overrides =
        db[branchChannels]
            .where(
              (o) =>
                  o['org_id'] == orgId &&
                  branches.find('${o['id']}') != null,
            )
            .toList()
          ..sort((a, b) {
            final byName = nameOf(a).compareTo(nameOf(b));
            return byName != 0 ? byName : '${a['id']}'.compareTo('${b['id']}');
          });
    return {
      'min_margin': db[margins].find(orgId)?['combo_min_margin'],
      'channels': org,
      'branch_overrides': [
        for (final o in overrides)
          {
            'branch_id': o['id'],
            'sell': {for (final c in channels) c: o[c]},
            'effective': {for (final c in channels) c: o[c] as bool? ?? org[c]},
          },
      ],
    };
  }
}

void registerComboSettingsMocks(MockServer server, MockDb db) {
  seedTableIfAbsent(db, ComboSettingsMock.margins, () => [
    {
      'id': SeedIds.sabahOrg,
      'combo_min_margin': ComboSettingsMock.sabahMinMargin,
    },
  ]);
  seedTableIfAbsent(
    db,
    ComboSettingsMock.orgChannels,
    ComboSettingsMock.orgRows,
  );
  seedTableIfAbsent(
    db,
    ComboSettingsMock.branchChannels,
    ComboSettingsMock.branchRows,
  );

  /// `claims_org`.
  String org(MockRequest req) =>
      req.orgId ??
      req.fail(MockResponse.forbidden('A super admin must scope this to an org'));

  /// `branch_of_org`: a live branch of the caller's org.
  void branchOfOrg(MockRequest req, String orgId, String branchId) {
    final b = db['branches'].find(branchId);
    if (b == null || b['org_id'] != orgId || b['deleted_at'] != null) {
      req.notFound('Branch not found');
    }
  }

  server
    ..on('GET', '/settings/combos', (req) {
      req.requireCap('org.settings.read');
      return MockResponse.ok(ComboSettingsMock.wire(db, org(req)));
    })
    ..on('PUT', '/settings/combos', (req) {
      req.requireCap('menu.combos.edit');
      final orgId = org(req);
      final body = req.json;
      final raw = body['min_margin'];
      if (raw != null && raw is! String) {
        req.badRequest('Json deserialize error: min_margin: expected a string');
      }
      final text = (raw as String?)?.trim() ?? '';
      String? min;
      if (text.isNotEmpty) {
        final d = double.tryParse(text);
        if (d == null) req.badRequest('min_margin must be a decimal fraction');
        if (d < 0 || d > 1) req.badRequest('min_margin must be between 0 and 1');
        min = ((d * 10000).round() / 10000).toStringAsFixed(4);
      }
      db[ComboSettingsMock.margins].put({'id': orgId, 'combo_min_margin': min});
      final channels = body['channels'];
      if (channels is Map) {
        db[ComboSettingsMock.orgChannels].put({
          'id': orgId,
          for (final c in ComboSettingsMock.channels)
            c: channels[c] as bool? ?? true,
        });
      }
      return MockResponse.ok(ComboSettingsMock.wire(db, orgId));
    })
    ..on('PUT', '/settings/combos/branches/{branch_id}', (req) {
      final branchId = req.param('branch_id');
      req.requireCap('menu.combos.edit', branchId: branchId);
      final orgId = org(req);
      branchOfOrg(req, orgId, branchId);
      final body = req.json;
      final sell = {
        for (final c in ComboSettingsMock.channels) c: body[c] as bool?,
      };
      final table = db[ComboSettingsMock.branchChannels];
      if (sell.values.every((v) => v == null)) {
        table.delete(branchId);
      } else {
        table.put({'id': branchId, 'org_id': orgId, ...sell});
      }
      return MockResponse.empty();
    })
    ..on('DELETE', '/settings/combos/branches/{branch_id}', (req) {
      final branchId = req.param('branch_id');
      req.requireCap('menu.combos.edit', branchId: branchId);
      branchOfOrg(req, org(req), branchId);
      db[ComboSettingsMock.branchChannels].delete(branchId);
      return MockResponse.empty();
    });
}
