// What Brand computes in the browser (shop addresses, card colours) and the
// mock's org routes, against hand-computed answers.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart' show settingsNav;
import 'package:dashboard_setup/src/brand_appearance/brand_data.dart';
import 'package:dashboard_setup/src/brand_appearance/settings_shell.dart';
import 'package:dashboard_setup/src/mock/brand_appearance_mock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

Org _org({String? bg, String? fg, String? accent, String name = 'Sabah'}) =>
    Org.fromJson({
      ...MockSeed.instance.org.toJson(),
      'name': name,
      'brand_background': bg,
      'brand_foreground': fg,
      'brand_accent': accent,
    });

Future<MockResponse> _send(
  MockServer s,
  String method,
  String path, {
  Object? body,
  List<ApiFilePart> files = const [],
}) async {
  try {
    final r = await s.send(
      ApiRequest(method: method, path: path, body: body, files: files),
    );
    return MockResponse(r.status, bodyBytes: r.bodyBytes);
  } on ApiException catch (e) {
    return MockResponse.error(e.status, e.message);
  }
}

void main() {
  group('SET-BRD-011 publicRootDomain (shop-address.test.ts)', () {
    test('the API host minus its first label', () {
      expect(publicRootDomain('https://api.madar-pos.cloud'), 'madar-pos.cloud');
      expect(
        publicRootDomain('https://api.staging.madar-pos.cloud/v1'),
        'staging.madar-pos.cloud',
      );
      expect(publicRootDomain(brandApiBase), 'madar-pos.cloud');
    });

    test('none for local development: two labels, an IP, nothing', () {
      expect(publicRootDomain('http://localhost:8081'), isNull);
      expect(publicRootDomain('https://madar.cloud'), isNull);
      expect(publicRootDomain('http://192.168.1.20:8081'), isNull);
      expect(publicRootDomain(''), isNull);
      expect(publicRootDomain(null), isNull);
    });
  });

  group('SET-BRD-012 shopAddresses', () {
    test('five, trailing slashes on the mounts', () {
      expect(shopAddresses('drops', 'madar-pos.cloud'), [
        (key: 'links', url: 'https://drops.madar-pos.cloud/'),
        (key: 'menu', url: 'https://drops.madar-pos.cloud/order/menu'),
        (key: 'order', url: 'https://drops.madar-pos.cloud/order/'),
        (key: 'rewards', url: 'https://drops.madar-pos.cloud/rewards'),
        (key: 'book', url: 'https://drops.madar-pos.cloud/book/'),
      ]);
    });

    test('none without a slug or a root', () {
      expect(shopAddresses(null, 'madar-pos.cloud'), isEmpty);
      expect(shopAddresses('', 'madar-pos.cloud'), isEmpty);
      expect(shopAddresses('drops', null), isEmpty);
    });
  });

  group('SET-BRD-019 resolveCardBrand (brand.ts)', () {
    test('contrast: black on white is 21, white on white 1', () {
      expect(contrast('#000000', '#FFFFFF'), closeTo(21, 1e-9));
      expect(contrast('#FFFFFF', '#ffffff'), closeTo(1, 1e-9));
      // Paper on Madar teal: L 0.8899 and 0.1006, (0.9399)/(0.1506) ≈ 6.24.
      expect(contrast(madarPaper, madarTeal), closeTo(6.24, 0.01));
    });

    test('nothing set: teal, paper text, teal-light accent, dark', () {
      final b = resolveCardBrand(null, programName: 'Loyalty');
      expect(b.orgName, 'Madar');
      expect(b.programName, 'Loyalty');
      expect(b.background, madarTeal);
      expect(b.foreground, madarPaper);
      expect(b.accent, madarTealLight);
      expect(b.isDark, isTrue);
      expect(b.muted.a, closeTo(0.72, 0.01));
    });

    test('a readable configured foreground is kept', () {
      final b = resolveCardBrand(
        _org(bg: '#FFF7ED', fg: '#431407', accent: '#C2410C'),
        programName: 'Loyalty',
      );
      expect((b.background, b.foreground, b.accent), (
        '#FFF7ED',
        '#431407',
        '#C2410C',
      ));
      expect(b.isDark, isFalse);
      expect(b.muted.a, closeTo(0.60, 0.01));
    });

    test('an unreadable foreground falls to ink or paper, whichever '
        'contrasts more', () {
      // #F5F5F5 on #FFFFFF is ~1.1:1, below AA; ink beats paper on white.
      final light = resolveCardBrand(
        _org(bg: '#FFFFFF', fg: '#F5F5F5'),
        programName: 'x',
      );
      expect(light.foreground, madarInk);
      expect(light.accent, madarTeal, reason: 'a light card: teal accent');
      final dark = resolveCardBrand(
        _org(bg: '#101010', fg: '#202020'),
        programName: 'x',
      );
      expect(dark.foreground, madarPaper);
    });

    test('invalid hex values fall back; blank names fall back', () {
      final b = resolveCardBrand(
        _org(bg: 'teal', fg: '#12', accent: 'red', name: '  '),
        programName: ' ',
      );
      expect(b.background, madarTeal);
      expect(b.accent, madarTealLight);
      expect(b.orgName, 'Madar');
      expect(b.programName, 'Rewards');
    });
  });

  group('SET-SHL-002 isActive', () {
    test('Appearance only on the index', () {
      final items = settingsNav.expand((g) => g.items).toList();
      final home = items.first;
      final brand = items[1];
      expect(SettingsShell.isActive(home, '/settings'), isTrue);
      expect(SettingsShell.isActive(home, '/settings/brand'), isFalse);
      expect(SettingsShell.isActive(brand, '/settings/brand'), isTrue);
      expect(SettingsShell.isActive(brand, '/settings/brandx'), isFalse);
    });
  });

  group('mock: the org routes behave like orgs::handlers', () {
    final sabah = '/orgs/${SeedIds.sabahOrg}';

    test('PATCH: an owner is refused (super admin only); a manager lacks '
        'org.settings.edit', () async {
      final owner = setupMockServer();
      final r = await _send(owner.server, 'PATCH', sabah, body: {
        'social_links': {'x': 'https://x.com/a'},
      });
      expect(r.status, 403);
      final manager = setupMockServer(persona: Persona.manager);
      final m = await _send(manager.server, 'PATCH', sabah, body: {
        'social_links': const {},
      });
      expect(m.status, 403);
    });

    test('PATCH social_links: the closed list, https only, stored cleaned '
        'and replacing the map', () async {
      final p = setupMockServer(persona: Persona.platform);
      final bad = await _send(p.server, 'PATCH', sabah, body: {
        'social_links': {'myspace': 'https://myspace.com/a'},
      });
      expect(bad.status, 400);
      final http = await _send(p.server, 'PATCH', sabah, body: {
        'social_links': {'website': 'http://sabah.coffee'},
      });
      expect(http.status, 400);
      expect(brandSafeLink('https://'), isFalse);
      expect(brandSafeLink('https://a b'), isFalse);
      final ok = await _send(p.server, 'PATCH', sabah, body: {
        'social_links': {'instagram': ' https://instagram.com/s ', 'facebook': ''},
      });
      expect(ok.status, 200);
      expect(p.db['orgs'].get(SeedIds.sabahOrg)['social_links'], {
        'instagram': 'https://instagram.com/s',
      });
    });

    test('PUT logo / card-image: own org, the right field, stored as a data '
        'URI', () async {
      final o = setupMockServer();
      final part = ApiFilePart(
        field: 'logo',
        filename: 'l.png',
        bytes: [1, 2, 3],
        contentType: 'image/png',
      );
      final r = await _send(o.server, 'PUT', '$sabah/logo', files: [part]);
      expect(r.status, 200);
      expect(
        o.db['orgs'].get(SeedIds.sabahOrg)['logo_url'],
        'data:image/png;base64,AQID',
      );
      final wrong = await _send(o.server, 'PUT', '$sabah/card-image',
          files: [part]);
      expect(wrong.status, 400, reason: "the card image's field is 'image'");
      final other = await _send(
        o.server,
        'PUT',
        '/orgs/${SeedIds.nakhlaOrg}/logo',
        files: [part],
      );
      expect(other.status, 403);
      final manager = setupMockServer(persona: Persona.manager);
      final m = await _send(manager.server, 'PUT', '$sabah/logo', files: [part]);
      expect(m.status, 403);
    });
  });
}
