// The links page mock against hand-computed answers: the saved page and
// what each module can show, the save's 400s and state, the links code,
// and the public page a customer gets.
import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_setup/src/area_seed.dart';
import 'package:dashboard_setup/src/links/links_data.dart';
import 'package:dashboard_setup/src/mock/links_mock.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

Future<ApiException> _refusal(Future<Object?> call) async {
  try {
    await call;
  } on ApiException catch (e) {
    return e;
  }
  fail('expected a refusal');
}

void main() {
  final org = SeedIds.sabahOrg;

  ({OrgsApi orgs, QrApi qr, MockDb db}) backend([Persona p = Persona.owner]) {
    final m = setupMockServer(persona: p);
    final api = DashboardApi(m.server);
    return (orgs: api.orgs, qr: api.qr, db: m.db);
  }

  test('the saved page: Sabah\'s order, modules, branches, address', () async {
    final s = await backend().orgs.getLinksPage(id: org);
    expect(s.items.map((i) => i.kind.value), [
      'order',
      'menu',
      'custom',
      'rewards',
      'book',
    ]);
    expect(s.items[2].id, linksCateringId);
    expect(s.taglineEn, 'Specialty coffee, roasted in Cairo every morning.');
    expect(s.publicUrl, 'https://sabah-coffee.madar-pos.cloud/');
    expect(s.customBranding, isTrue);
    expect(s.cardImageUrl, isNull);
    // Every branch delivers or takes pickups; bookings at two; the org's
    // programme runs (visits).
    final m = {for (final x in s.modules) x.kind.value: x};
    expect(m['order']!.branchNames, [
      'Heliopolis',
      'Maadi',
      'New Cairo',
      'Zamalek',
    ]);
    expect(m['book']!.branchNames, ['Heliopolis', 'Maadi', 'New Cairo']);
    expect(m['rewards']!.available, isTrue);
    expect(s.loyaltyMode, 'visits');
    expect(s.branches.map((b) => (b.name, b.visible, b.mapsUrl)), [
      ('Heliopolis', true, null),
      ('Maadi', true, null),
      ('New Cairo', true, null),
      ('Zamalek', true, 'https://maps.app.goo.gl/SabahZamalek26July'),
    ]);
  });

  test(
    'a shop that never saved gets every module, cover and branches on',
    () async {
      final b = backend(Persona.dawamOnly);
      final s = await b.orgs.getLinksPage(id: SeedIds.nakhlaOrg);
      expect(s.items.map((i) => (i.kind.value, i.visible)), [
        ('order', true),
        ('menu', true),
        ('rewards', true),
        ('book', true),
      ]);
      expect((s.showCover, s.showBranches, s.publicUrl), (true, true, null));
    },
  );

  test('refusals: another org, no capability, no address for a code', () async {
    expect(
      (await _refusal(
        backend().orgs.getLinksPage(id: SeedIds.nakhlaOrg),
      )).status,
      403,
    );
    expect(
      (await _refusal(
        backend(Persona.manager).orgs.getLinksPage(id: org),
      )).status,
      403,
    );
    final b = backend(Persona.dawamOnly);
    final e = await _refusal(b.qr.orgLinksQr(id: SeedIds.nakhlaOrg));
    expect(e.status, 409);
  });

  test('the links code points at the shop\'s own address', () async {
    final qr = await backend().qr.orgLinksQr(id: org);
    expect(qr.kind, 'org_links');
    expect(qr.longUrl, 'https://sabah-coffee.madar-pos.cloud/');
  });

  test('a save is checked like the backend and kept', () async {
    final b = backend();
    LinksPageInput input(List<LinksPageItem> items, {String? tagline}) =>
        LinksPageInput(items: items, taglineEn: tagline);
    LinksPageItem custom(String title, String url, {String? id}) =>
        LinksPageItem(
          kind: LinksItemKind.custom,
          titleEn: title,
          url: url,
          id: id,
        );
    Future<String> refused(LinksPageInput body) async =>
        (await _refusal(b.orgs.putLinksPage(id: org, body: body))).message;

    expect(
      await refused(
        input([
          const LinksPageItem(kind: LinksItemKind.menu),
          const LinksPageItem(kind: LinksItemKind.menu),
        ]),
      ),
      endsWith('"menu" is in the list twice'),
    );
    expect(
      await refused(input([custom(' ', 'https://a.eg')])),
      endsWith('Every link needs a title'),
    );
    expect(
      await refused(input([custom('Beans', 'http://a.eg')])),
      endsWith('"Beans" has to link to a full https:// address'),
    );
    expect(
      await refused(input([custom('x' * 61, 'https://a.eg')])),
      endsWith('A link title can be at most 60 characters'),
    );
    expect(
      await refused(input(const [], tagline: 'y' * 161)),
      endsWith('A tagline can be at most 160 characters'),
    );
    expect(
      await refused(
        input([for (var i = 0; i < 21; i++) custom('L$i', 'https://a.eg/$i')]),
      ),
      endsWith('A links page can hold at most 20 of your own links'),
    );

    final saved = await b.orgs.putLinksPage(
      id: org,
      body: LinksPageInput(
        items: [
          const LinksPageItem(kind: LinksItemKind.book, visible: false),
          custom('  Beans  ', 'https://sabahcoffee.eg/beans'),
        ],
        taglineEn: '  Hello  ',
        showBranches: false,
        branches: [
          LinksPageBranchInput(branchId: SeedIds.maadi, visible: false),
        ],
        socialLinks: const {'instagram': '', 'x': 'https://x.com/sabah'},
      ),
    );
    // Missing modules are appended visible; the new link gets an id.
    expect(saved.items.map((i) => (i.kind.value, i.visible)), [
      ('book', false),
      ('custom', true),
      ('order', true),
      ('menu', true),
      ('rewards', true),
    ]);
    expect(saved.items[1].titleEn, 'Beans');
    expect(saved.items[1].id, isNotNull);
    expect(saved.taglineEn, 'Hello');
    expect(saved.showBranches, isFalse);
    expect(
      saved.branches.firstWhere((x) => x.id == SeedIds.maadi).visible,
      isFalse,
    );
    expect(saved.socialLinks, {'x': 'https://x.com/sabah'});
    expect((await b.orgs.getLinksPage(id: org)).items[1].id, saved.items[1].id);
  });

  test(
    'the public page: visible buttons that can show, socials, branches',
    () async {
      final b = backend();
      // Bookings off everywhere: "Book a table" cannot show.
      for (final r in b.db[SetupSeed.bookingSettingsTable].rows) {
        r['enabled'] = false;
      }
      final p = await b.orgs.publicOrgLinks(orgId: org);
      expect(p.brand.name, 'Sabah Coffee');
      expect(p.items.map((i) => i.kind.value), [
        'order',
        'menu',
        'custom',
        'rewards',
      ]);
      expect(p.items[0].href, 'https://sabah-coffee.madar-pos.cloud/order/');
      expect(p.items[0].channels, ['pickup', 'delivery', 'in_mall']);
      expect(p.items[2].href, 'https://sabahcoffee.eg/catering');
      expect(p.loyaltyMode, 'visits');
      expect(p.socials.map((s) => s.key), [
        'instagram',
        'facebook',
        'whatsapp',
      ]);
      expect(p.branches.length, 4);
      expect(
        p.branches.last.directionsUrl,
        'https://maps.app.goo.gl/SabahZamalek26July',
      );
      expect(
        p.branches.first.directionsUrl,
        startsWith(
          'https://www.google.com/maps/search/?api=1&query=30.0911,31.326',
        ),
      );
      expect(p.coverImageUrl, isNull);
      final none = await _refusal(b.orgs.publicOrgLinks(orgId: 'nope'));
      expect(none.status, 404);
    },
  );

  test('readableOn walks a pale colour to AA, keeps a legible one', () {
    expect(linksReadableOn('#0D6273', linksGroundLight), '#0D6273');
    final walked = linksReadableOn('#FFF7ED', linksGroundLight);
    expect(walked, isNot('#FFF7ED'));
    expect(linksContrast(walked, linksGroundLight), greaterThanOrEqualTo(4.5));
    expect(
      linksContrast(
        linksReadableOn('#0D6273', linksGroundDark),
        linksGroundDark,
      ),
      greaterThanOrEqualTo(4.5),
    );
    expect(linksHostOf('https://www.sabahcoffee.eg/beans'), 'sabahcoffee.eg');
    expect(linksHostOf('not a url'), 'not a url');
  });
}
