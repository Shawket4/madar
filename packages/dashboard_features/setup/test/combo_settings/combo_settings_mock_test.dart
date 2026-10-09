// The Combos and deals settings mock against the backend's rules (MadarRust
// `src/combos/handlers.rs`), and the pane's pure rules
// (`combo_settings_data.dart`, the web's `util.ts` and form schema) against
// hand-computed answers.
import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

typedef _Backend = ({MockServer server, MockDb db});
typedef _Answer = ({int status, Object? json, String error});

Future<_Answer> _send(
  _Backend b,
  String method,
  String path, {
  Object? body,
  Persona? as,
}) async {
  if (as != null) b.server.persona = as;
  try {
    final r = await b.server.send(
      ApiRequest(method: method, path: path, body: body),
    );
    final text = utf8.decode(r.bodyBytes);
    return (
      status: r.status,
      json: text.isEmpty ? null : jsonDecode(text),
      error: '',
    );
  } on ApiException catch (e) {
    return (status: e.status, json: null, error: e.message);
  }
}

String _words(MockResponse r) => MockServer.toApiException(r).message;

String _branch(String id) => '/settings/combos/branches/$id';

void main() {
  group('pure rules', () {
    test('rateToPercent / percentToRate (util.ts)', () {
      expect(rateToPercent('0.5500'), '55');
      expect(rateToPercent('0.55'), '55');
      expect(rateToPercent('0.5933'), '59.33');
      expect(rateToPercent(null), '');
      expect(rateToPercent('junk'), '');
      expect(percentToRate('55'), '0.5500');
      expect(percentToRate('42.5'), '0.4250');
      expect(percentToRate(' 7 '), '0.0700');
      expect(percentToRate(''), isNull);
      expect(percentToRate('  '), isNull);
    });

    test('marginOk: blank, or 0 ≤ n < 100', () {
      for (final ok in ['', ' ', '0', '55', '99', '99.99']) {
        expect(marginOk(ok), isTrue, reason: ok);
      }
      for (final bad in ['100', '-1', 'abc', '1e3']) {
        expect(marginOk(bad), isFalse, reason: bad);
      }
    });

    test('a branch override merged; nothing set means delete', () {
      const o = ChannelOverride(qr: false);
      final next = overrideWith(o, ComboChannel.pos, false);
      expect(next.toJson(), {
        'pos': false,
        'qr': false,
        'online': null,
        'delivery': null,
      });
      expect(overrideSetsAny(next), isTrue);
      final none = overrideWith(o, ComboChannel.qr, null);
      expect(overrideSetsAny(none), isFalse);
      expect(triOf(true), ComboTri.on);
      expect(triOf(false), ComboTri.off);
      expect(triOf(null), ComboTri.inherit);
      expect(boolOf(ComboTri.inherit), isNull);
    });

    test('the org form: equality is "changed"; its PUT body', () {
      final s = ComboSettings(
        branchOverrides: [],
        channels: ChannelToggles(pos: true, delivery: false),
        minMargin: '0.5500',
      );
      final f = ComboSettingsForm.from(s);
      expect(f.sell[ComboChannel.qr], isTrue, reason: 'omitted = on');
      expect(f, ComboSettingsForm.from(s));
      expect(f.withChannel(ComboChannel.qr, false), isNot(f));
      expect(f.withChannel(ComboChannel.qr, false).withChannel(ComboChannel.qr, true), f);
      expect(f.toWire().toJson(), {
        'channels': {'delivery': false, 'online': true, 'pos': true, 'qr': true},
        'min_margin': '0.5500',
      });
      expect(f.withMargin('').toWire().toJson()['min_margin'], isNull);
      expect(f.withMargin('').toWire().toJson().containsKey('min_margin'), isTrue);
    });
  });

  group('GET /settings/combos', () {
    test('the seed: 55 %, delivery apps off, Zamalek and New Cairo differ, '
        'by branch name, each resolved', () async {
      final b = cmbServer();
      final a = await _send(b, 'GET', cmbSettings);
      expect(a.status, 200);
      expect(a.json, {
        'min_margin': '0.5500',
        'channels': {'pos': true, 'qr': true, 'online': true, 'delivery': false},
        'branch_overrides': [
          {
            'branch_id': SeedIds.newCairo,
            'sell': {'pos': null, 'qr': null, 'online': null, 'delivery': true},
            'effective': {'pos': true, 'qr': true, 'online': true, 'delivery': true},
          },
          {
            'branch_id': SeedIds.zamalek,
            'sell': {'pos': null, 'qr': false, 'online': null, 'delivery': null},
            'effective': {'pos': true, 'qr': false, 'online': true, 'delivery': false},
          },
        ],
      });
      // The generated client reads it.
      final parsed = ComboSettings.fromJson(a.json! as Map<String, Object?>);
      expect(parsed.branchOverrides, hasLength(2));
    });

    test('needs org.settings.read: a manager and a reader are refused', () async {
      for (final p in [Persona.manager, Persona.limited]) {
        final a = await _send(cmbServer(persona: p), 'GET', cmbSettings);
        expect(a.status, 403, reason: p.name);
        expect(a.error, _words(MockResponse.denied('org.settings.read')));
      }
    });

    test('an org never saved: every channel on, no margin, no exceptions', () async {
      final b = cmbServer();
      b.db[ComboSettingsMock.orgChannels].clear();
      b.db[ComboSettingsMock.branchChannels].clear();
      b.db[ComboSettingsMock.margins].clear();
      final a = await _send(b, 'GET', cmbSettings);
      expect(a.json, {
        'min_margin': null,
        'channels': {'pos': true, 'qr': true, 'online': true, 'delivery': true},
        'branch_overrides': <Object?>[],
      });
    });
  });

  group('PUT /settings/combos', () {
    test('replaces the margin (rounded to four places) and the switches; '
        'the next read shows them', () async {
      final b = cmbServer();
      final a = await _send(b, 'PUT', cmbSettings, body: {
        'min_margin': '0.42345',
        'channels': {'pos': false, 'qr': true, 'online': true, 'delivery': true},
      });
      expect(a.status, 200);
      final read = await _send(b, 'GET', cmbSettings);
      final json = read.json! as Map;
      expect(json['min_margin'], '0.4235');
      expect(json['channels'], {'pos': false, 'qr': true, 'online': true, 'delivery': true});
      // Zamalek follows the new POS switch.
      final zam = (json['branch_overrides'] as List).last as Map;
      expect((zam['effective'] as Map)['pos'], isFalse);
    });

    test('blank or null clears the margin; no channels keeps the switches', () async {
      final b = cmbServer();
      await _send(b, 'PUT', cmbSettings, body: {'min_margin': ''});
      expect(storedMargin(b.db), isNull);
      expect(ComboSettingsMock.orgSwitches(b.db, SeedIds.sabahOrg)['delivery'], isFalse);
    });

    test('a margin that is not a fraction in 0–1 is a 400', () async {
      final b = cmbServer();
      final bad = await _send(b, 'PUT', cmbSettings, body: {'min_margin': 'lots'});
      expect(bad.status, 400);
      expect(bad.error, _words(MockResponse.badRequest('min_margin must be a decimal fraction')));
      final big = await _send(b, 'PUT', cmbSettings, body: {'min_margin': '1.5'});
      expect(big.error, _words(MockResponse.badRequest('min_margin must be between 0 and 1')));
      expect(storedMargin(b.db), ComboSettingsMock.sabahMinMargin);
    });

    test('needs menu.combos.edit', () async {
      final a = await _send(
        cmbServer(persona: Persona.manager),
        'PUT',
        cmbSettings,
        body: {'min_margin': '0.3'},
      );
      expect(a.status, 403);
      expect(a.error, _words(MockResponse.denied('menu.combos.edit')));
    });
  });

  group('branch overrides', () {
    test('PUT saves (204), all-null deletes, DELETE deletes', () async {
      final b = cmbServer();
      final put = await _send(b, 'PUT', _branch(SeedIds.maadi), body: {
        'pos': false,
        'qr': null,
        'online': null,
        'delivery': null,
      });
      expect(put.status, 204);
      expect(storedOverride(b.db, SeedIds.maadi)!['pos'], isFalse);
      await _send(b, 'PUT', _branch(SeedIds.maadi), body: {
        'pos': null,
        'qr': null,
        'online': null,
        'delivery': null,
      });
      expect(storedOverride(b.db, SeedIds.maadi), isNull);
      final del = await _send(b, 'DELETE', _branch(SeedIds.zamalek));
      expect(del.status, 204);
      expect(storedOverride(b.db, SeedIds.zamalek), isNull);
    });

    test('a branch of another org, or none, is a 404', () async {
      final b = cmbServer();
      for (final id in [SeedIds.dokki, mockUuid('branch:nowhere')]) {
        final a = await _send(b, 'PUT', _branch(id), body: {'pos': true});
        expect(a.status, 404, reason: id);
        expect(a.error, _words(MockResponse.notFound('Branch not found')));
      }
    });

    test('needs menu.combos.edit', () async {
      final a = await _send(
        cmbServer(persona: Persona.manager),
        'DELETE',
        _branch(SeedIds.zamalek),
      );
      expect(a.status, 403);
    });
  });
}
