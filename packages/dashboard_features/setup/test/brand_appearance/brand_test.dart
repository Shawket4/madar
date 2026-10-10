// `/settings/brand` Brand (SET-BRD-001 … 021), driven through the app shell
// on the mock server.
import 'dart:typed_data';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/brand_appearance/brand_data.dart';
import 'package:dashboard_setup/src/brand_appearance/card_face.dart';
import 'package:dashboard_setup/src/shared/social_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

const String _sabahUrl = 'https://sabah-coffee.madar-pos.cloud';

Finder _links() => inBrand(find.byType(SocialLinksFields));
Finder _field(int i) =>
    find.descendant(of: _links(), matching: find.byType(EditableText)).at(i);
String _text(WidgetTester tester, int i) =>
    tester.widget<EditableText>(_field(i)).controller.text;
Finder _choose(String uploader) => inKey(uploader, find.text('Choose Image'));
Finder _replace(String uploader) => inKey(
  uploader,
  find.byWidgetPredicate((w) => w is DashIconButton && w.icon == 'upload'),
);
Finder _card() => inBrand(find.byType(BrandCardFace));
Finder _inCard(Finder f) => find.descendant(of: _card(), matching: f);

/// Sabah with [changes] applied to its row before the page opens.
({MockServer server, MockDb db}) _sabah([Map<String, Object?>? changes]) {
  final m = setupMockServer();
  if (changes != null) m.db['orgs'].update(SeedIds.sabahOrg, changes);
  return m;
}

void main() {
  group('page', () {
    testWidgets('SET-BRD-001 the pane header: "Brand" and its description', (
      tester,
    ) async {
      final h = await pumpBrand(tester);
      expect(inBrand(find.text('Brand')), findsOneWidget);
      expect(inBrand(find.text(h.t('settings.brandDesc'))), findsOneWidget);
      expect(h.server.callsTo(orgRoute, method: 'GET'), isNotEmpty);
      expect(h.server.callsTo(orgRoute).map((c) => c.path).toSet(), {
        '/orgs/${SeedIds.sabahOrg}',
      });
    });

    testWidgets('SET-BRD-002 loading: a short bar and two card skeletons, no '
        'header; then the pane', (tester) async {
      final m = setupMockServer();
      final gate = m.server.hold('GET', orgRoute);
      final h = await pumpBrand(tester, backend: m);
      expect(byKey('brand-loading'), findsOneWidget);
      expect(
        find.descendant(
          of: byKey('brand-loading'),
          matching: find.byType(DashSkeleton),
        ),
        findsNWidgets(3),
      );
      expect(inBrand(find.text('Brand')), findsNothing);
      gate.release();
      await h.settle();
      expect(byKey('brand-loading'), findsNothing);
      expect(inBrand(find.text('Brand')), findsOneWidget);
    });

    testWidgets('SET-BRD-002 SET-SHL-020 no org in scope: nothing is asked and '
        'the pane renders without the org', (tester) async {
      final h = await pumpBrand(tester, persona: Persona.platform);
      expect(h.server.callsTo(orgRoute, method: 'GET'), isEmpty);
      expect(inBrand(find.text('Brand')), findsOneWidget);
      expect(_inCard(find.text('Madar')), findsOneWidget);
      expect(_links(), findsNothing);
      // Nowhere to upload to.
      expect(
        tester.widget<DashImageUploader>(inBrand(byKey('brand-logo'))).enabled,
        isFalse,
      );
    });

    testWidgets('SET-BRD-003 a failed read is no error state: no notice, '
        'empty uploaders, no address, no links, a Madar card', (tester) async {
      final m = setupMockServer();
      m.server.fail(
        'GET',
        orgRoute,
        MockResponse.error(500, 'boom'),
        times: null,
      );
      final h = await pumpBrand(tester, backend: m);
      expect(inBrand(find.text('Retry')), findsNothing);
      expect(inBrand(find.text(h.t('settings.brandTierOff'))), findsNothing);
      expect(_choose('brand-logo'), findsOneWidget);
      expect(_choose('brand-card-image'), findsOneWidget);
      expect(byKey('brand-address'), findsNothing);
      expect(_links(), findsNothing);
      expect(_inCard(find.text('Madar')), findsOneWidget);
      final face = tester.widget<BrandCardFace>(_card());
      expect(face.brand.background, madarTeal);
    });

    testWidgets('SET-BRD-003 refusal: a manager without org.settings.read '
        'gets the same quiet pane', (tester) async {
      final h = await pumpBrand(tester, persona: Persona.manager);
      expect(
        h.server.callsTo(orgRoute, method: 'GET').single.persona,
        Persona.manager,
      );
      expect(inBrand(find.text('Brand')), findsOneWidget);
      expect(_links(), findsNothing);
      expect(_inCard(find.text('Madar')), findsOneWidget);
    });

    testWidgets('SET-BRD-004 the tier notice when custom branding is off', (
      tester,
    ) async {
      final h = await pumpBrand(
        tester,
        backend: _sabah({'custom_branding': false}),
      );
      expect(inBrand(find.text(h.t('settings.brandTierOff'))), findsOneWidget);
      expect(
        inBrand(find.text(h.t('settings.brandTierOffHint'))),
        findsOneWidget,
      );
      expect(inKey('brand-tier-off', find.byType(DashIcon)), findsOneWidget);
    });

    testWidgets('SET-BRD-004 no notice on the branding tier', (tester) async {
      final h = await pumpBrand(tester);
      expect(inBrand(find.text(h.t('settings.brandTierOff'))), findsNothing);
    });
  });

  group('uploads', () {
    testWidgets('SET-BRD-005 Logo: header, the current logo, the hint', (
      tester,
    ) async {
      final logo = 'data:image/png;base64,${base64Of(samplePng)}';
      final h = await pumpBrand(tester, backend: _sabah({'logo_url': logo}));
      expect(inBrand(find.text('Logo')), findsOneWidget);
      expect(inBrand(find.text(h.t('settings.logoHint'))), findsOneWidget);
      expect(
        tester.widget<DashImageUploader>(inBrand(byKey('brand-logo'))).value,
        logo,
      );
      expect(inKey('brand-logo', find.byType(Image)), findsOneWidget);
      expect(_choose('brand-logo'), findsNothing);
    });

    testWidgets('SET-BRD-006 upload a logo: the file, Uploading…, the toast, '
        'the re-read, the logo on the card', (tester) async {
      final m = setupMockServer();
      final h = await pumpBrand(tester, backend: m);
      final reads = h.server.callsTo(orgRoute, method: 'GET').length;
      expect(_inCard(byKey('card-logo')), findsNothing);
      queueImage(h);
      final gate = m.server.hold('PUT', logoRoute);
      await h.tap(_choose('brand-logo'));
      expect(inKey('brand-logo', find.text('Uploading...')), findsOneWidget);
      gate.release();
      await h.settle();
      final put = h.server.callsTo(logoRoute, method: 'PUT').single;
      expect(put.path, '/orgs/${SeedIds.sabahOrg}/logo');
      expect(put.files.single.field, 'logo');
      expect(put.files.single.contentType, 'image/png');
      expect(put.files.single.bytes, samplePng);
      await h.expectToast('Logo updated');
      expect(
        h.server.callsTo(orgRoute, method: 'GET').length,
        reads + 1,
        reason: 'the org is read again',
      );
      expect(_inCard(byKey('card-logo')), findsOneWidget);
      expect(inKey('brand-logo', find.byType(Image)), findsOneWidget);
    });

    testWidgets('SET-BRD-007 Replace: over the current logo, no Remove', (
      tester,
    ) async {
      final logo = 'data:image/png;base64,${base64Of(samplePng)}';
      final h = await pumpBrand(tester, backend: _sabah({'logo_url': logo}));
      expect(_replace('brand-logo'), findsOneWidget);
      expect(
        inKey(
          'brand-logo',
          find.byWidgetPredicate((w) => w is DashIconButton && w.icon == 'x'),
        ),
        findsNothing,
      );
      queueImage(h, name: 'new.webp', mimeType: 'image/webp');
      await h.tap(_replace('brand-logo'));
      final put = h.server.callsTo(logoRoute, method: 'PUT').single;
      expect(put.files.single.contentType, 'image/webp');
      await h.expectToast('Logo updated');
    });

    testWidgets('SET-BRD-008 not an image, or over 5 MB: refused in red under '
        'the box, nothing sent', (tester) async {
      final h = await pumpBrand(tester);
      queueImage(h, name: 'notes.txt', mimeType: 'text/plain');
      await h.tap(_choose('brand-logo'));
      expect(
        inKey('brand-logo', find.text('Selected file must be an image')),
        findsOneWidget,
      );
      expect(
        inKey('brand-logo', find.text(h.t('settings.logoHint'))),
        findsNothing,
      );
      queueImage(h, bytes: Uint8List(5 * 1024 * 1024 + 1));
      await h.tap(_choose('brand-logo'));
      expect(
        inKey('brand-logo', find.text('Image size exceeds 5MB limit')),
        findsOneWidget,
      );
      expect(h.server.callsTo(logoRoute), isEmpty);
    });

    testWidgets('SET-BRD-009 a failed upload toasts the server\'s '
        'words and shows the same words under the box', (tester) async {
      final logo = 'data:image/png;base64,${base64Of(samplePng)}';
      final m = _sabah({'logo_url': logo});
      const words = 'The image is too large to store';
      m.server.fail('PUT', logoRoute, MockResponse.error(413, words));
      final h = await pumpBrand(tester, backend: m);
      queueImage(h);
      await h.tap(_replace('brand-logo'));
      await h.expectToast(words);
      expect(inKey('brand-logo', find.text(words)), findsOneWidget);
      expect(
        inKey('brand-logo', find.text(h.t('settings.logoHint'))),
        findsNothing,
      );
      expect(
        tester.widget<DashImageUploader>(inBrand(byKey('brand-logo'))).value,
        logo,
        reason: 'the previous logo stays',
      );
    });

    testWidgets('SET-BRD-009 refusal: a manager\'s upload is refused in the '
        'server\'s words', (tester) async {
      final h = await pumpBrand(tester, persona: Persona.manager);
      queueImage(h);
      await h.tap(_choose('brand-logo'));
      final refusal = h.refusalWords(MockResponse.denied('org.settings.edit'));
      await h.expectToast(refusal);
      expect(inKey('brand-logo', find.text(refusal)), findsOneWidget);
    });

    testWidgets('SET-BRD-010 Card image: header, hint, upload, toast, the '
        'band on the card', (tester) async {
      final h = await pumpBrand(tester);
      expect(inBrand(find.text('Card image')), findsOneWidget);
      expect(inBrand(find.text(h.t('settings.cardImageHint'))), findsOneWidget);
      expect(_inCard(byKey('card-band')), findsNothing);
      final reads = h.server.callsTo(orgRoute, method: 'GET').length;
      queueImage(h, name: 'band.jpg', mimeType: 'image/jpeg');
      await h.tap(_choose('brand-card-image'));
      final put = h.server.callsTo(cardImageRoute, method: 'PUT').single;
      expect(put.path, '/orgs/${SeedIds.sabahOrg}/card-image');
      expect(put.files.single.field, 'image');
      await h.expectToast('Card image updated');
      expect(h.server.callsTo(orgRoute, method: 'GET').length, reads + 1);
      expect(_inCard(byKey('card-band')), findsOneWidget);
    });

    testWidgets('SET-BRD-010 card image refusals: not an image', (
      tester,
    ) async {
      final h = await pumpBrand(tester);
      queueImage(h, name: 'clip.mp4', mimeType: 'video/mp4');
      await h.tap(_choose('brand-card-image'));
      expect(
        inKey('brand-card-image', find.text('Selected file must be an image')),
        findsOneWidget,
      );
      expect(h.server.callsTo(cardImageRoute), isEmpty);
    });

    testWidgets('SET-BRD-021 (divergence) the same file can be chosen twice; '
        'a picker cancel sends nothing', (tester) async {
      final h = await pumpBrand(tester);
      await h.tap(_choose('brand-logo'));
      expect(h.server.callsTo(logoRoute), isEmpty, reason: 'cancelled');
      queueImage(h);
      await h.tap(_choose('brand-logo'));
      await h.expectToast('Logo updated');
      queueImage(h);
      await h.tap(_replace('brand-logo'));
      await h.expectToast('Logo updated');
      expect(h.server.callsTo(logoRoute, method: 'PUT'), hasLength(2));
    });
  });

  group('web address', () {
    testWidgets('SET-BRD-011 the card on the branding tier with a slug', (
      tester,
    ) async {
      final h = await pumpBrand(tester);
      expect(byKey('brand-address'), findsOneWidget);
      expect(
        inKey('brand-address', find.text('Your web address')),
        findsOneWidget,
      );
      expect(
        inKey('brand-address', find.text(h.t('settings.address.hint'))),
        findsOneWidget,
      );
    });

    testWidgets('SET-BRD-011 no card off the tier, or without a slug', (
      tester,
    ) async {
      await pumpBrand(tester, backend: _sabah({'custom_branding': false}));
      expect(byKey('brand-address'), findsNothing);
    });

    testWidgets('SET-BRD-011 no card without a slug', (tester) async {
      await pumpBrand(tester, backend: _sabah({'slug': null}));
      expect(byKey('brand-address'), findsNothing);
    });

    testWidgets('SET-BRD-012 five addresses in order, trailing slashes kept, '
        'each with its label and hint', (tester) async {
      final h = await pumpBrand(tester);
      const expected = {
        'links': '$_sabahUrl/',
        'menu': '$_sabahUrl/order/menu',
        'order': '$_sabahUrl/order/',
        'rewards': '$_sabahUrl/rewards',
        'book': '$_sabahUrl/book/',
      };
      final rows = [
        for (final k in expected.keys)
          tester.getTopLeft(byKey('brand-address-$k')).dy,
      ];
      expect(rows, orderedEquals([...rows]..sort()));
      for (final e in expected.entries) {
        final row = 'brand-address-${e.key}';
        expect(inKey(row, find.text(e.value)), findsOneWidget);
        expect(
          inKey(row, find.text(h.t('settings.address.${e.key}'))),
          findsOneWidget,
        );
        expect(
          inKey(row, find.text(h.t('settings.address.${e.key}Hint'))),
          findsOneWidget,
        );
      }
    });

    testWidgets('SET-BRD-013 Copy: the address on the clipboard, a check for '
        'two seconds', (tester) async {
      final clip = FakeClipboard(tester);
      final h = await pumpBrand(tester);
      Finder icon(String name) => inKey(
        'brand-copy-menu',
        find.byWidgetPredicate((w) => w is DashIcon && w.name == name),
      );
      expect(icon('copy'), findsOneWidget);
      await h.tap(byKey('brand-copy-menu'));
      expect(clip.text, '$_sabahUrl/order/menu');
      expect(icon('check'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      await h.settle();
      expect(icon('copy'), findsOneWidget);
    });

    testWidgets('SET-BRD-013 a refused clipboard toasts "Copy failed"', (
      tester,
    ) async {
      final clip = FakeClipboard(tester)..refuse = true;
      final h = await pumpBrand(tester);
      await h.tap(byKey('brand-copy-links'));
      expect(clip.text, isNull);
      await h.expectToast('Copy failed');
    });

    testWidgets('SET-BRD-014 Open: the address in the browser', (tester) async {
      final h = await pumpBrand(tester);
      await h.tap(byKey('brand-open-book'));
      expect(h.openedLinks, [Uri.parse('$_sabahUrl/book/')]);
    });
  });

  group('links', () {
    testWidgets('SET-BRD-015 eight fields in order with their labels, sample '
        'addresses and the saved values; two columns on a wide screen', (
      tester,
    ) async {
      final h = await pumpBrand(tester);
      expect(inBrand(find.text('Links')), findsOneWidget);
      expect(inBrand(find.text(h.t('orgs.socialLinks'))), findsOneWidget);
      final labels = [
        for (final p in socialPlatforms) h.t('orgs.social.${p.key}'),
      ];
      final tops = [
        for (final l in labels)
          tester.getTopLeft(
            find.descendant(of: _links(), matching: find.text(l)),
          ),
      ];
      // Two a row: the second of each pair sits beside the first.
      for (var i = 0; i < tops.length; i += 2) {
        expect(tops[i].dy, tops[i + 1].dy);
        expect(tops[i].dx, lessThan(tops[i + 1].dx));
      }
      expect(_text(tester, 0), 'https://instagram.com/sabahcoffee.eg');
      expect(_text(tester, 1), 'https://facebook.com/sabahcoffee.eg');
      expect(_text(tester, 2), '');
      expect(_text(tester, 5), 'https://wa.me/201001112233');
      final inputs = tester
          .widgetList<DashTextInput>(
            find.descendant(of: _links(), matching: find.byType(DashTextInput)),
          )
          .toList();
      expect(
        [for (final i in inputs) i.placeholder],
        [for (final p in socialPlatforms) p.sample],
      );
      expect(inputs.every((i) => i.textDirection == TextDirection.ltr), isTrue);
    });

    testWidgets('SET-BRD-015 one column on a phone', (tester) async {
      final h = await pumpBrand(tester, size: DashSize.phone);
      final a = tester.getTopLeft(
        find.descendant(
          of: _links(),
          matching: find.text(h.t('orgs.social.instagram')),
        ),
      );
      final b = tester.getTopLeft(
        find.descendant(
          of: _links(),
          matching: find.text(h.t('orgs.social.facebook')),
        ),
      );
      expect(b.dy, greaterThan(a.dy));
    });

    testWidgets('SET-BRD-015 the form follows the saved links until edited', (
      tester,
    ) async {
      final m = setupMockServer();
      final h = await pumpBrand(tester, backend: m);
      m.db['orgs'].update(SeedIds.sabahOrg, {
        'social_links': {'tiktok': 'https://tiktok.com/@sabah'},
      });
      h.container.invalidate(orgBrandProvider(SeedIds.sabahOrg));
      await h.settle();
      expect(_text(tester, 0), '');
      expect(_text(tester, 2), 'https://tiktok.com/@sabah');
      await h.enterText(_field(7), 'https://sabah.coffee');
      m.db['orgs'].update(SeedIds.sabahOrg, {'social_links': const {}});
      h.container.invalidate(orgBrandProvider(SeedIds.sabahOrg));
      await h.settle();
      expect(
        _text(tester, 2),
        'https://tiktok.com/@sabah',
        reason: 'an edited form is not overwritten',
      );
      expect(_text(tester, 7), 'https://sabah.coffee');
    });

    testWidgets('SET-BRD-016 http:// is refused under the field; nothing is '
        'sent', (tester) async {
      final h = await pumpBrand(tester);
      await h.enterText(_field(7), 'http://sabah.coffee');
      await h.tap(byKey('brand-links-save'));
      expect(
        inBrand(find.text('Use the full address, starting with https://')),
        findsOneWidget,
      );
      expect(h.server.callsTo(orgRoute, method: 'PATCH'), isEmpty);
    });

    testWidgets('SET-BRD-017 the owner saves (B3): only filled platforms, "" '
        'for an emptied one; toast; re-read', (tester) async {
      final m = _sabah();
      final h = await pumpBrand(tester, backend: m);
      final reads = h.server.callsTo(orgRoute, method: 'GET').length;
      await h.enterText(_field(1), '');
      await h.enterText(_field(7), '  https://sabah.coffee ');
      await h.tap(byKey('brand-links-save'));
      expect(lastBody(h, 'PATCH', orgRoute), {
        'social_links': {
          'instagram': 'https://instagram.com/sabahcoffee.eg',
          'facebook': '',
          'whatsapp': 'https://wa.me/201001112233',
          'website': 'https://sabah.coffee',
        },
      });
      await h.expectToast('Links updated');
      expect(h.server.callsTo(orgRoute, method: 'GET').length, reads + 1);
      expect(m.db['orgs'].get(SeedIds.sabahOrg)['social_links'], {
        'instagram': 'https://instagram.com/sabahcoffee.eg',
        'whatsapp': 'https://wa.me/201001112233',
        'website': 'https://sabah.coffee',
      });
      expect(_text(tester, 1), '');
      expect(_text(tester, 7), 'https://sabah.coffee');
    });

    testWidgets('SET-BRD-017 Enter in a field saves (SET-SHL-018)', (
      tester,
    ) async {
      final h = await pumpBrand(tester);
      await h.enterText(_field(3), 'https://x.com/sabah');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await h.settle();
      expect(
        (lastBody(h, 'PATCH', orgRoute)['social_links']! as Map)['x'],
        'https://x.com/sabah',
      );
      await h.expectToast('Links updated');
    });

    testWidgets('SET-BRD-017 a refusal is toasted in the server\'s words and '
        'the form keeps the edit', (tester) async {
      final m = _sabah();
      final denied = MockResponse.denied('org.settings.edit');
      m.server.fail('PATCH', orgRoute, denied);
      final h = await pumpBrand(tester, backend: m);
      await h.enterText(_field(4), 'https://youtube.com/@sabah');
      await h.tap(byKey('brand-links-save'));
      await h.expectToast(h.refusalWords(denied));
      expect(_text(tester, 4), 'https://youtube.com/@sabah');
      expect(
        tester.widget<DashButton>(byKey('brand-links-save')).loading,
        isFalse,
      );
    });

    testWidgets('SET-BRD-017 a server 400 is toasted in its words', (
      tester,
    ) async {
      final m = _sabah();
      const words = 'The website link has to be a full https:// address';
      m.server.fail('PATCH', orgRoute, MockResponse.badRequest(words));
      final h = await pumpBrand(tester, backend: m);
      await h.tap(byKey('brand-links-save'));
      await h.expectToast(h.refusalWords(MockResponse.badRequest(words)));
    });
  });

  group('card preview', () {
    testWidgets('SET-BRD-018 the card face: 3 of 5 stamps, the line, the '
        'member, the program and the org', (tester) async {
      final h = await pumpBrand(tester);
      expect(
        inBrand(find.text('How the loyalty card will look')),
        findsOneWidget,
      );
      expect(_inCard(find.text('Sabah Coffee')), findsOneWidget);
      expect(_inCard(find.text('LOYALTY')), findsOneWidget);
      expect(_inCard(find.text('3')), findsOneWidget);
      expect(_inCard(find.text('of 5 orders')), findsOneWidget);
      expect(
        _inCard(find.text('2 more orders to your next reward.')),
        findsOneWidget,
      );
      expect(_inCard(find.text('MEMBER')), findsOneWidget);
      expect(_inCard(find.text('MEMBER NAME')), findsOneWidget);
      final stamps = tester.widget<StampRow>(_inCard(find.byType(StampRow)));
      expect((stamps.earned, stamps.target), (3, 5));
      // Two to go are numbered; the three done carry a check.
      expect(_inCard(find.text('4')), findsOneWidget);
      expect(_inCard(find.text('5')), findsOneWidget);
      expect(
        _inCard(
          find.byWidgetPredicate((w) => w is DashIcon && w.name == 'check'),
        ),
        findsNWidgets(3),
      );
      expect(h.t('nav.loyalty'), 'Loyalty');
    });

    testWidgets('SET-BRD-019 the card wears the org\'s colours', (
      tester,
    ) async {
      await pumpBrand(tester);
      final face = tester.widget<BrandCardFace>(_card());
      expect(face.brand.background, '#FFF7ED');
      expect(face.brand.foreground, '#431407');
      expect(face.brand.accent, '#C2410C');
      final box = tester.widget<Container>(
        find.descendant(of: _card(), matching: find.byType(Container)).first,
      );
      expect((box.decoration! as BoxDecoration).color, const Color(0xFFFFF7ED));
    });

    testWidgets('SET-BRD-019 an unreadable foreground is replaced by paper', (
      tester,
    ) async {
      await pumpBrand(
        tester,
        backend: _sabah({
          'brand_background': '#0B3D2E',
          'brand_foreground': '#123A2C',
          'brand_accent': 'teal',
        }),
      );
      final face = tester.widget<BrandCardFace>(_card());
      expect(face.brand.foreground, madarPaper);
      expect(face.brand.isDark, isTrue);
      expect(face.brand.accent, madarTealLight);
    });

    testWidgets('SET-BRD-020 the footnote under the preview', (tester) async {
      final h = await pumpBrand(tester);
      expect(inBrand(find.text(h.t('settings.brandDerived'))), findsOneWidget);
    });

    testWidgets('SET-BRD-018 Arabic: the card reads right to left', (
      tester,
    ) async {
      final h = await pumpBrand(tester, locale: 'ar');
      expect(_inCard(find.text(h.t('loyalty.member'))), findsOneWidget);
      final name = tester.getTopRight(_inCard(find.text('Sabah Coffee')));
      final card = tester.getTopRight(_card());
      expect(card.dx - name.dx, lessThan(40), reason: 'starts on the right');
    });
  });
}
