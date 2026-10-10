// The WhatsApp screenshot matrix: the linked default at every size in
// {en light, ar dark}, and every other state (loading, failed, not
// configured, unreachable, a pairing QR, not linked, paused, the unlink
// confirm, refused) at desktop-en-light and phone-ar-light. Writes PNGs only
// with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpWhatsapp(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await h.shot('whatsapp/default');
      });
    }
  }

  final states = <String, MockRow>{
    'not-configured': {'configured': false, 'reachable': false},
    'unreachable': {'reachable': false},
    'qr': {'logged_in': false, 'has_qr': true},
    'not-linked': {'logged_in': false, 'connected': false},
    'paused': {'paused': true, 'paused_at': '2026-10-08T06:30:00Z'},
  };
  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    for (final e in states.entries) {
      testWidgets('${e.key}, ${size.name} $lang', (tester) async {
        final b = whatsappServer();
        WhatsappMock.set(b.db, e.value);
        final h = await pumpWhatsapp(
          tester,
          size: size,
          locale: lang,
          backend: b,
        );
        await h.shot('whatsapp/${e.key}');
      });
    }

    testWidgets('loading, ${size.name} $lang', (tester) async {
      final b = whatsappServer();
      final gate = b.server.hold('GET', waStatus);
      final h = await pumpWhatsapp(
        tester,
        size: size,
        locale: lang,
        backend: b,
      );
      await h.shot('whatsapp/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, ${size.name} $lang', (tester) async {
      final b = whatsappServer();
      b.server.fail(
        'GET',
        waStatus,
        MockResponse.error(500, 'Internal error'),
        times: null,
      );
      final h = await pumpWhatsapp(
        tester,
        size: size,
        locale: lang,
        backend: b,
      );
      await h.shot('whatsapp/failed');
    });

    testWidgets('unlink confirm, ${size.name} $lang', (tester) async {
      final h = await pumpWhatsapp(tester, size: size, locale: lang);
      await h.tap(inPage(find.byKey(const ValueKey('whatsapp-unlink'))));
      await h.shot('whatsapp/unlink-confirm');
    });

    testWidgets('refused, ${size.name} $lang', (tester) async {
      final h = await pumpWhatsapp(
        tester,
        persona: Persona.owner,
        size: size,
        locale: lang,
      );
      await h.shot('whatsapp/refused');
    });
  }
}
