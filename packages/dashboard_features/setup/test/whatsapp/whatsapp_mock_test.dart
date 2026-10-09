// The WhatsApp handlers against MadarRust `src/delivery/gateway.rs`: the
// super-admin gate on every route, the status snapshot per gateway state,
// the 503s, pause persisting, and a body that does not fit.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  Future<ApiResponse> send(
    MockServer s,
    String method,
    String path, [
    Object? body,
  ]) => s.send(ApiRequest(method: method, path: path, body: body));

  Map<String, Object?> json(ApiResponse r) =>
      jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, Object?>;

  /// A refusal's status and words (the transport throws them).
  Future<(int, String)> refused(Future<ApiResponse> f) async {
    try {
      final r = await f;
      return (r.status, utf8.decode(r.bodyBytes));
    } on ApiException catch (e) {
      return (e.status, e.message);
    }
  }

  for (final persona in [
    Persona.owner,
    Persona.manager,
    Persona.limited,
    Persona.dawamOnly,
  ]) {
    test('${persona.name} is refused on every route', () async {
      final b = whatsappServer(persona: persona);
      for (final (m, p, body) in [
        ('GET', waStatus, null),
        ('POST', waPair, null),
        ('POST', waLogout, null),
        ('POST', waPause, {'paused': true}),
      ]) {
        final (status, words) = await refused(send(b.server, m, p, body));
        expect(status, 403, reason: '$m $p');
        expect(words, contains('Super admin access required'));
      }
      expect(WhatsappMock.state(b.db)['paused'], false);
    });
  }

  test('status: linked by default; a QR only while pairing, as a PNG data '
      'URL', () async {
    final b = whatsappServer();
    var s = json(await send(b.server, 'GET', waStatus));
    expect(s, {
      'configured': true,
      'reachable': true,
      'session': 'main',
      'connected': true,
      'logged_in': true,
      'has_qr': false,
      'qr_image': null,
      'paused': false,
      'paused_at': null,
    });
    WhatsappMock.set(b.db, {'logged_in': false, 'has_qr': true});
    s = json(await send(b.server, 'GET', waStatus));
    expect(s['qr_image'], startsWith('data:image/png;base64,'));
    expect(WhatsappStatus.fromJson(s).hasQr, isTrue);
  });

  test('status never fails: unset or silent gateways read not reachable, '
      'nothing live', () async {
    final b = whatsappServer();
    WhatsappMock.set(b.db, {'reachable': false, 'has_qr': true});
    var s = json(await send(b.server, 'GET', waStatus));
    expect(s['configured'], true);
    expect(s['reachable'], false);
    expect(s['logged_in'], false);
    expect(s['has_qr'], false);
    expect(s['qr_image'], isNull);
    WhatsappMock.set(b.db, {'configured': false});
    s = json(await send(b.server, 'GET', waStatus));
    expect(s['configured'], false);
    expect(s['reachable'], false);
  });

  test('pair: a QR when not linked; nothing changes when linked', () async {
    final b = whatsappServer();
    var s = json(await send(b.server, 'POST', waPair));
    expect(s['logged_in'], true);
    expect(s['has_qr'], false);
    WhatsappMock.set(b.db, {'logged_in': false, 'connected': false});
    s = json(await send(b.server, 'POST', waPair));
    expect(s['has_qr'], true);
    expect(s['qr_image'], isNotNull);
    // The next read agrees.
    expect(json(await send(b.server, 'GET', waStatus))['has_qr'], true);
  });

  test('logout: unlinks and is idempotent', () async {
    final b = whatsappServer();
    for (var i = 0; i < 2; i++) {
      final s = json(await send(b.server, 'POST', waLogout));
      expect(s['logged_in'], false);
      expect(s['connected'], false);
      expect(s['has_qr'], false);
    }
  });

  test('pair and logout need a reachable gateway (503)', () async {
    final b = whatsappServer();
    WhatsappMock.set(b.db, {'reachable': false});
    for (final p in [waPair, waLogout]) {
      final (status, words) = await refused(send(b.server, 'POST', p));
      expect(status, 503);
      expect(words, contains('WhatsApp gateway is unreachable'));
    }
    WhatsappMock.set(b.db, {'configured': false});
    final (status, words) = await refused(send(b.server, 'POST', waPair));
    expect(status, 503);
    expect(words, contains('WHATSAPP_SERVICE_URL unset'));
  });

  test('pause persists with its time, resume clears it; works without a '
      'gateway', () async {
    final b = whatsappServer();
    WhatsappMock.set(b.db, {'configured': false});
    var s = json(await send(b.server, 'POST', waPause, {'paused': true}));
    expect(s['paused'], true);
    expect(s['paused_at'], b.db.nowIso);
    expect(json(await send(b.server, 'GET', waStatus))['paused'], true);
    s = json(await send(b.server, 'POST', waPause, {'paused': false}));
    expect(s['paused'], false);
    expect(s['paused_at'], isNull);
  });

  test('pause without {paused} is a 400 like actix', () async {
    final b = whatsappServer();
    final (status, words) = await refused(
      send(b.server, 'POST', waPause, {'muted': true}),
    );
    expect(status, 400);
    expect(words, contains('Json deserialize error'));
    expect(WhatsappMock.state(b.db)['paused'], false);
  });
}
