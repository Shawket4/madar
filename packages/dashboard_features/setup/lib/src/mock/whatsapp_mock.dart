/// The mock backend for WhatsApp pairing, platform admins only (`/settings/whatsapp`, SET-WA rows).
///
/// MadarRust `src/delivery/gateway.rs`: every handler is
/// `require_super_admin`; status never fails (an unset or silent gateway
/// reads `configured`/`reachable` false); pair and logout need a reachable
/// gateway (503 otherwise); pause only flips the persisted switch. Each
/// answers the full status snapshot. The gateway's live state is one row,
/// [WhatsappMock.table]: tests edit it to stand in for the phone (a scan
/// links the number) or the gateway (unset, down).
library;

import 'package:dashboard_api/dashboard_api.dart' show PauseInput;
import 'package:dashboard_api/mock.dart';

import 'support.dart';

abstract final class WhatsappMock {
  static const String table = 'whatsapp_gateway';
  static const String id = 'default';

  /// What the gateway encodes in its pairing QR (WhatsApp's ref, keys).
  static const String pairingRef =
      '2@Yq7hT3bK9mVwXc1Lr8sPz0Q,ZmFrZS1ub2lzZS1rZXk=,'
      'aWRlbnRpdHkta2V5LXNhYmFo,QWR2LXNlY3JldC1tYWRhcg==';

  /// The gateway row (seeded linked and sending on first use).
  static MockRow state(MockDb db) {
    final t = db[table];
    return t.find(id) ??
        t.insert({
          'id': id,
          'configured': true,
          'reachable': true,
          'connected': true,
          'logged_in': true,
          'has_qr': false,
          'paused': false,
          'paused_at': null,
          'session': 'main',
        }, timestamps: false);
  }

  /// Patches the gateway row (a scan, the gateway going down).
  static void set(MockDb db, MockRow patch) {
    state(db);
    db[table].update(id, patch);
  }
}

void registerWhatsappMocks(MockServer server, MockDb db) {
  // `build_status`: the gateway's link state is only known when it answers.
  MockResponse status() {
    final s = WhatsappMock.state(db);
    final live = s['configured'] == true && s['reachable'] == true;
    final qr = live && s['has_qr'] == true;
    return MockResponse.ok({
      'configured': s['configured'],
      'reachable': live,
      'session': s['session'],
      'connected': live && s['connected'] == true,
      'logged_in': live && s['logged_in'] == true,
      'has_qr': qr,
      'qr_image': qr ? qrPngDataUrl(WhatsappMock.pairingRef) : null,
      'paused': s['paused'],
      'paused_at': s['paused_at'],
    });
  }

  // `require_gateway` + the relay call: unset or silent → 503.
  void requireGateway() {
    final s = WhatsappMock.state(db);
    if (s['configured'] != true) {
      throw MockHttpError(
        MockResponse.error(
          503,
          'Service unavailable: WhatsApp gateway is not configured '
          '(WHATSAPP_SERVICE_URL unset)',
        ),
      );
    }
    if (s['reachable'] != true) {
      throw MockHttpError(
        MockResponse.error(
          503,
          'Service unavailable: WhatsApp gateway is unreachable',
        ),
      );
    }
  }

  server.on('GET', '/whatsapp/status', (req) {
    req.requirePlatform();
    return status();
  });

  server.on('POST', '/whatsapp/pair', (req) {
    req.requirePlatform();
    requireGateway();
    // 409 from the gateway (already linked) is fine: nothing changes.
    if (WhatsappMock.state(db)['logged_in'] != true) {
      WhatsappMock.set(db, {'has_qr': true, 'connected': true});
    }
    return status();
  });

  server.on('POST', '/whatsapp/logout', (req) {
    req.requirePlatform();
    requireGateway();
    WhatsappMock.set(db, {
      'logged_in': false,
      'connected': false,
      'has_qr': false,
    });
    return status();
  });

  server.on('POST', '/whatsapp/pause', (req) {
    req.requirePlatform();
    final paused = req.bodyAs(PauseInput.fromJson).paused;
    WhatsappMock.set(db, {
      'paused': paused,
      'paused_at': paused ? db.nowIso : null,
    });
    return status();
  });
}
