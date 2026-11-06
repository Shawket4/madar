// The output switches as data (SET-QR-030 – 032): what each one sends to the
// server, the image's shape, and how the choice is remembered (per shop, on
// this device, read defensively).
import 'dart:convert';

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/mock.dart' show MemoryPreferences;
import 'package:dashboard_setup/src/qr/qr_output.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProviderContainer _container(MemoryPreferences prefs) {
  final c = ProviderContainer(
    overrides: [preferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('qrRenderParams', () {
    test('SET-QR-030 branded mode sends exactly what the page always sent', () {
      expect(qrRenderParams(const QrOutput()), (
        card: true,
        dpi: 600,
        unbranded: null,
        centreLogo: null,
      ));
      expect(qrRenderParams(const QrOutput(card: false, dpi: 300)), (
        card: false,
        dpi: 300,
        unbranded: null,
        centreLogo: null,
      ));
    });

    test('SET-QR-030 unbranded sends the plain code\'s switches and nothing '
        'of the card\'s', () {
      expect(qrRenderParams(const QrOutput(unbranded: true)), (
        card: null,
        dpi: 600,
        unbranded: true,
        centreLogo: true,
      ));
      expect(
        qrRenderParams(
          const QrOutput(unbranded: true, centreLogo: false, card: false),
        ),
        (card: null, dpi: 600, unbranded: true, centreLogo: false),
      );
    });

    test('names the image\'s shape, for printing it true', () {
      expect(qrShape(const QrOutput()), QrShape.card);
      expect(qrShape(const QrOutput(card: false)), QrShape.receipt);
      expect(
        qrShape(const QrOutput(unbranded: true, card: false)),
        QrShape.plain,
      );
    });
  });

  group('QrOutput.fromJson', () {
    test('SET-QR-032 defaults to today\'s branded card', () {
      expect(QrOutput.fromJson(null), const QrOutput());
      expect(
        const QrOutput(),
        const QrOutput(
          unbranded: false,
          centreLogo: true,
          card: true,
          dpi: 600,
        ),
      );
    });

    test('SET-QR-032 survives anything stored, field by field', () {
      expect(QrOutput.fromJson('{not json'), const QrOutput());
      expect(
        QrOutput.fromJson({
          'unbranded': 'yes',
          'centreLogo': false,
          'dpi': 999,
        }),
        const QrOutput(centreLogo: false),
      );
    });
  });

  group('qrOutputProvider', () {
    test('SET-QR-032 remembers the choice per shop, on this device', () {
      final prefs = MemoryPreferences();
      var c = _container(prefs);
      c
          .read(qrOutputProvider('o-1').notifier)
          .update(const QrOutput(unbranded: true));
      expect(c.read(qrOutputProvider('o-1')).unbranded, isTrue);
      expect(json.decode(prefs.values[qrOutputPrefKey('o-1')]!), {
        'unbranded': true,
        'centreLogo': true,
        'card': true,
        'dpi': 600,
      });

      c
          .read(qrOutputProvider('o-1').notifier)
          .update(const QrOutput(unbranded: true, centreLogo: false));
      expect(
        c.read(qrOutputProvider('o-1')),
        const QrOutput(unbranded: true, centreLogo: false),
      );

      // Another shop on the same device has its own.
      expect(c.read(qrOutputProvider('o-2')), const QrOutput());

      // And a fresh start reads the first shop's back.
      c = _container(prefs);
      expect(
        c.read(qrOutputProvider('o-1')),
        const QrOutput(unbranded: true, centreLogo: false),
      );
      expect(c.read(qrOutputProvider('o-2')), const QrOutput());
    });

    test('two controls are one switch', () {
      final c = _container(MemoryPreferences());
      final a = c.listen(qrOutputProvider('o-1'), (_, _) {});
      final b = c.listen(qrOutputProvider('o-1'), (_, _) {});
      c
          .read(qrOutputProvider('o-1').notifier)
          .update(const QrOutput(unbranded: true));
      expect(a.read().unbranded, isTrue);
      expect(b.read().unbranded, isTrue);
    });

    test('no org: the default, nothing saved', () {
      final prefs = MemoryPreferences();
      final c = _container(prefs);
      c
          .read(qrOutputProvider(null).notifier)
          .update(const QrOutput(unbranded: true));
      expect(c.read(qrOutputProvider(null)), const QrOutput());
      expect(prefs.writes, isEmpty);
    });
  });
}
