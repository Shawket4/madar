// The links page editor driven through the real app shell, one test per
// SET-LNK row (row ids first in the names), plus refusal, loading and error.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart' show Space;
import 'package:dashboard_setup/src/area_seed.dart';
import 'package:dashboard_setup/src/links/links_page.dart';
import 'package:dashboard_setup/src/links/links_preview.dart';
import 'package:dashboard_setup/src/mock/links_mock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';
import 'support.dart';

const _catering = 'links-item-';

Finder _row(String key) => byKey('links-item-$key');
Finder _inRow(String key, Finder f) => find.descendant(of: _row(key), matching: f);

String get _cat => linksCateringId;

Future<void> _show(DashHarness h, Finder f) async {
  await h.tester.ensureVisible(f);
  await h.settle();
}

Future<void> _type(DashHarness h, String key, String text) async {
  await _show(h, byKey(key));
  await h.enterText(fieldOf(key), text);
}

Future<void> _save(DashHarness h) async {
  await _show(h, byKey('links-save'));
  await h.tap(byKey('links-save'));
}

/// Types into the [index]th social field (Instagram, Facebook, TikTok, X…).
Future<void> _social(DashHarness h, int index, String text) async {
  final f = inKey('links-socials', find.byType(EditableText)).at(index);
  await _show(h, f);
  await h.enterText(f, text);
}

List<Map<String, Object?>> _items(Map<String, Object?> body) =>
    (body['items']! as List).cast<Map<String, Object?>>();

void main() {
  testWidgets('SET-LNK-001 header, description and Save in the actions', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    expect(inLinks(find.text('Links page')), findsOneWidget);
    expect(inLinks(find.text(h.t('links.editor.desc'))), findsOneWidget);
    expect(inLinks(byKey('links-save')), findsOneWidget);
    expect(find.descendant(of: byKey('links-save'), matching: find.text('Save')), findsOneWidget);
  });

  testWidgets('SET-LNK-002 loading: the bars until the settings arrive', (
    tester,
  ) async {
    final m = setupMockServer();
    final gate = m.server.hold('GET', LinksRoutes.page);
    final h = await pumpLinks(tester, backend: m);
    expect(byKey('links-loading'), findsOneWidget);
    expect(find.byType(LinksEditor), findsNothing);
    expect(find.byType(DashErrorState), findsNothing);
    gate.release();
    await h.settle();
    expect(byKey('links-loading'), findsNothing);
    expect(find.byType(LinksEditor), findsOneWidget);
  });

  testWidgets(
    'SET-LNK-003 (divergence) a failed read shows the error and Retry asks again',
    (tester) async {
      final m = setupMockServer();
      m.server.fail(
        'GET',
        LinksRoutes.page,
        MockResponse.error(500, 'Database is down'),
      );
      final h = await pumpLinks(tester, backend: m);
      expect(inLinks(find.text(h.t('common.loadFailed'))), findsOneWidget);
      expect(gets(h, LinksRoutes.page), 1);
      expect(gets(h, LinksRoutes.public), 0);
      await h.tap(inLinks(find.text('Retry')));
      expect(gets(h, LinksRoutes.page), 2);
      expect(find.byType(LinksEditor), findsOneWidget);
    },
  );

  testWidgets('SET-LNK-004 the preview beside the form from 1280, under it below', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    final form = tester.getRect(byKey('links-address'));
    final preview = tester.getRect(byKey('links-preview-0'));
    expect(preview.left, greaterThan(form.right));
    expect(preview.width, LinksMetrics.preview);
    expect((preview.top - form.top).abs(), lessThan(Space.xxl));

    final t = await pumpLinks(tester, size: DashSize.tablet);
    final visit = tester.getRect(byKey('links-visit'));
    final under = tester.getRect(byKey('links-preview-0'));
    expect(under.top, greaterThan(visit.bottom));
    expect(t.location.path, linksPath);
  });

  testWidgets('SET-LNK-005 the address card with the shop\'s own address', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    expect(inKey('links-address', find.text('Your address')), findsOneWidget);
    expect(inKey('links-address', find.text(h.t('links.editor.addressHint'))), findsOneWidget);
    expect(
      inKey('links-address', find.text('https://sabah-coffee.madar-pos.cloud/')),
      findsOneWidget,
    );
  });

  testWidgets('SET-LNK-006 Copy puts the address on the clipboard', (
    tester,
  ) async {
    final clip = FakeClipboard(tester);
    final h = await pumpLinks(tester);
    await h.tap(byKey('links-copy'));
    expect(clip.text, 'https://sabah-coffee.madar-pos.cloud/');
    await h.expectToast('Address copied');
  });

  testWidgets('SET-LNK-006 a refused clipboard says nothing', (tester) async {
    final clip = FakeClipboard(tester)..refuse = true;
    final h = await pumpLinks(tester);
    await h.tap(byKey('links-copy'));
    expect(clip.text, isNull);
    expect(find.text('Address copied'), findsNothing);
    await h.flushTimers();
  });

  testWidgets('SET-LNK-007 QR code opens "Links page code"; a failure toasts', (
    tester,
  ) async {
    final m = setupMockServer();
    m.server.fail(
      'GET',
      LinksRoutes.qr,
      MockResponse.error(500, 'The link shortener did not answer'),
      times: null,
    );
    final h = await pumpLinks(tester, backend: m);
    await h.tap(byKey('links-qr'));
    await h.expectToast('The link shortener did not answer');
    expect(find.text('Links page code'), findsNothing);

    m.server.clearFailures();
    final before = gets(h, LinksRoutes.qr);
    await h.tap(byKey('links-qr'));
    expect(gets(h, LinksRoutes.qr), before + 1);
    expect(h.server.callsTo(LinksRoutes.qr).last.query, isEmpty);
    expect(find.text('Links page code'), findsOneWidget);
  });

  testWidgets('SET-LNK-008 Open opens the address outside the app', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    await h.tap(byKey('links-open'));
    expect(h.openedLinks.last, Uri.parse('https://sabah-coffee.madar-pos.cloud/'));
  });

  testWidgets('SET-LNK-009 no address yet: the sentence, no buttons', (
    tester,
  ) async {
    final m = setupMockServer();
    m.db['orgs'].update(SeedIds.sabahOrg, {'custom_branding': false});
    final h = await pumpLinks(tester, backend: m);
    expect(inKey('links-address', find.text(h.t('links.editor.noAddress'))), findsOneWidget);
    expect(byKey('links-copy'), findsNothing);
    expect(byKey('links-qr'), findsNothing);
    expect(byKey('links-open'), findsNothing);
  });

  testWidgets('SET-LNK-010 the two lines under the name, 160 at most', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    expect(inKey('links-about', find.text('Line under your name (English)')), findsOneWidget);
    expect(inKey('links-about', find.text('Line under your name (Arabic)')), findsOneWidget);
    await _type(h, 'links-tagline-en', 'x' * 170);
    await _type(h, 'links-tagline-ar', '');
    await _save(h);
    final body = lastBody(h, 'PUT', LinksRoutes.page);
    expect(body['tagline_en'], 'x' * 160);
    expect(body.containsKey('tagline_ar'), isTrue);
    expect(body['tagline_ar'], isNull);
    await h.expectToast('Links page saved');
  });

  testWidgets('SET-LNK-011 the cover switch and its hint', (tester) async {
    final m = setupMockServer();
    final h = await pumpLinks(tester, backend: m);
    expect(inKey('links-about', find.text(h.t('links.editor.coverNone'))), findsOneWidget);
    await h.tap(inKey('links-cover', find.byType(DashSwitch)));
    await _save(h);
    expect(lastBody(h, 'PUT', LinksRoutes.page)['show_cover'], isFalse);
    await h.expectToast('Links page saved');

    m.db['orgs'].update(SeedIds.sabahOrg, {
      'brand_card_image': 'https://cdn.madar-pos.cloud/sabah/card.jpg',
    });
    final h2 = await pumpLinks(tester, backend: m);
    expect(inKey('links-about', find.text(h2.t('links.editor.coverHint'))), findsOneWidget);
  });

  testWidgets('SET-LNK-012 the buttons in saved order with their titles', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    expect(inKey('links-buttons', find.text('Buttons')), findsOneWidget);
    expect(inKey('links-buttons', find.text(h.t('links.editor.buttonsHint'))), findsOneWidget);
    final tops = [
      for (final k in ['order', 'menu', _cat, 'rewards', 'book'])
        tester.getTopLeft(_row(k)).dy,
    ];
    expect([...tops]..sort(), tops);
    expect(_inRow('order', find.text('Order now')), findsOneWidget);
    expect(_inRow('menu', find.text('Menu')), findsOneWidget);
    expect(_inRow(_cat, find.text('Catering and events')), findsWidgets);
    expect(_inRow('rewards', find.text('Rewards card')), findsOneWidget);
    expect(_inRow('book', find.text('Book a table')), findsOneWidget);
  });

  testWidgets('SET-LNK-013 each row\'s line: link, reason it is off, branches, On', (
    tester,
  ) async {
    final m = setupMockServer();
    for (final r in m.db[SetupSeed.bookingSettingsTable].rows) {
      r['enabled'] = false;
    }
    final h = await pumpLinks(tester, backend: m);
    expect(_inRow(_cat, find.text('https://sabahcoffee.eg/catering')), findsWidgets);
    expect(
      _inRow('order', find.text('Heliopolis · Maadi · New Cairo · Zamalek')),
      findsOneWidget,
    );
    expect(_inRow('rewards', find.text('On')), findsOneWidget);
    expect(_inRow('book', find.text(h.t('links.editor.off.book'))), findsOneWidget);
  });

  testWidgets('SET-LNK-014 up and down swap with the neighbour (sent on Save)', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    Finder up(String k) => _inRow(k, find.bySemanticsLabel('Move up'));
    Finder down(String k) => _inRow(k, find.bySemanticsLabel('Move down'));
    expect(tester.widget<DashIconButton>(find.ancestor(of: up('order'), matching: find.byType(DashIconButton)).first).onPressed, isNull);
    expect(tester.widget<DashIconButton>(find.ancestor(of: down('book'), matching: find.byType(DashIconButton)).first).onPressed, isNull);
    await _show(h, _row('rewards'));
    await h.tap(up('rewards'));
    await h.tap(down('order'));
    await _save(h);
    expect(_items(lastBody(h, 'PUT', LinksRoutes.page)).map((i) => i['kind']), [
      'menu',
      'order',
      'rewards',
      'custom',
      'book',
    ]);
    await h.expectToast('Links page saved');
  });

  testWidgets('SET-LNK-015 a switch hides a button; an unavailable one is off and locked', (
    tester,
  ) async {
    final m = setupMockServer();
    for (final r in m.db[SetupSeed.bookingSettingsTable].rows) {
      r['enabled'] = false;
    }
    final h = await pumpLinks(tester, backend: m);
    final book = tester.widget<DashSwitch>(
      find.descendant(of: _row('book'), matching: find.byType(DashSwitch)),
    );
    expect((book.value, book.enabled), (false, false));
    expect(book.semanticLabel, 'Show Book a table');
    await _show(h, _row('menu'));
    await h.tap(_inRow('menu', find.byType(DashSwitch)));
    await _save(h);
    final items = _items(lastBody(h, 'PUT', LinksRoutes.page));
    expect(items[1], {'kind': 'menu', 'visible': false});
    await h.expectToast('Links page saved');
  });

  testWidgets('SET-LNK-016 an own link\'s fields, the https mark, and Remove', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    final url = '$_catering$_cat-url';
    await _type(h, url, 'http://sabahcoffee.eg/catering');
    final input = tester.widget<DashTextInput>(byKey(url));
    expect(input.invalid, isTrue);
    expect(byKey('$_catering$_cat-title-en'), findsOneWidget);
    expect(byKey('$_catering$_cat-title-ar'), findsOneWidget);
    await h.tap(_inRow(_cat, find.bySemanticsLabel('Remove link')));
    expect(_row(_cat), findsNothing);
    await _save(h);
    expect(
      _items(lastBody(h, 'PUT', LinksRoutes.page)).any((i) => i['kind'] == 'custom'),
      isFalse,
    );
    await h.expectToast('Links page saved');
  });

  testWidgets('SET-LNK-017 "Add your own link" appends a visible empty row', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    await _show(h, byKey('links-add'));
    await h.tap(byKey('links-add'));
    expect(inKey('links-buttons', find.text('New link')), findsOneWidget);
    expect(inKey('links-buttons', find.text('Your own link')), findsOneWidget);
  });

  testWidgets('SET-LNK-018 the socials: same fields and https rule as Brand', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    for (final p in ['Instagram', 'Facebook', 'TikTok', 'X', 'YouTube', 'WhatsApp', 'Talabat', 'Website']) {
      expect(inKey('links-socials', find.text(p)), findsOneWidget, reason: p);
    }
    await _social(h, 3, 'http://x.com/sabah');
    await _save(h);
    expect(inKey('links-socials', find.text(h.t('orgs.socialInvalid'))), findsOneWidget);
    expect(h.server.callsTo(LinksRoutes.page, method: 'PUT'), isEmpty);
  });

  testWidgets('SET-LNK-019 "Visit us": branches, their switches and Maps links', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    await _show(h, byKey('links-visit'));
    expect(inKey('links-visit', find.text('Show “Visit us”')), findsOneWidget);
    expect(inKey('links-visit', find.text('Baghdad St, Korba, Heliopolis')), findsOneWidget);
    final maadi = 'links-branch-${SeedIds.maadi}';
    await h.tap(inKey(maadi, find.byType(DashSwitch)));
    final maps = tester.widget<DashTextInput>(
      byKey('links-maps-${SeedIds.maadi}'),
    );
    expect(maps.enabled, isFalse);
    await _type(h, 'links-maps-${SeedIds.heliopolis}', 'maps.google.com/x');
    expect(
      tester.widget<DashTextInput>(byKey('links-maps-${SeedIds.heliopolis}')).invalid,
      isTrue,
    );
    await h.tap(inKey('links-show-branches', find.byType(DashSwitch)));
    expect(byKey(maadi), findsNothing);
  });

  testWidgets('SET-LNK-020 an own link or Maps link that is not right stops Save', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    await _show(h, byKey('links-add'));
    await h.tap(byKey('links-add'));
    await _save(h);
    await h.expectToast(h.t('links.editor.fixLinks'));
    expect(h.server.callsTo(LinksRoutes.page, method: 'PUT'), isEmpty);

    final h2 = await pumpLinks(tester);
    await _type(h2, 'links-maps-${SeedIds.maadi}', 'http://maps.google.com');
    await _save(h2);
    await h2.expectToast(h2.t('links.editor.fixLinks'));
    expect(h2.server.callsTo(LinksRoutes.page, method: 'PUT'), isEmpty);
  });

  testWidgets('SET-LNK-021 Save sends the page and re-reads it and the preview', (
    tester,
  ) async {
    final m = setupMockServer();
    final h = await pumpLinks(tester, backend: m);
    final pages = gets(h, LinksRoutes.page), publics = gets(h, LinksRoutes.public);
    await _type(h, 'links-tagline-en', '  Roasted in Zamalek  ');
    await _type(h, '$_catering$_cat-title-ar', '   ');
    await _type(h, 'links-maps-${SeedIds.zamalek}', '');
    await _social(h, 0, '');
    await _save(h);
    final body = lastBody(h, 'PUT', LinksRoutes.page);
    expect(_items(body), [
      {'kind': 'order', 'visible': true},
      {'kind': 'menu', 'visible': true},
      {
        'id': _cat,
        'kind': 'custom',
        'title_ar': null,
        'title_en': 'Catering and events',
        'url': 'https://sabahcoffee.eg/catering',
        'visible': true,
      },
      {'kind': 'rewards', 'visible': true},
      {'kind': 'book', 'visible': true},
    ]);
    expect(body['tagline_en'], 'Roasted in Zamalek');
    expect(body['show_cover'], isTrue);
    expect(body['show_branches'], isTrue);
    expect(body['branches'], [
      for (final b in [SeedIds.heliopolis, SeedIds.maadi, SeedIds.newCairo, SeedIds.zamalek])
        {'branch_id': b, 'maps_url': null, 'visible': true},
    ]);
    expect(body['social_links'], {
      'instagram': '',
      'facebook': 'https://facebook.com/sabahcoffee.eg',
      'whatsapp': 'https://wa.me/201001112233',
    });
    await h.expectToast('Links page saved');
    expect(gets(h, LinksRoutes.page), pages + 1);
    expect(gets(h, LinksRoutes.public), publics + 1);
    expect(sabahPage(m.db)['tagline_en'], 'Roasted in Zamalek');
    expect(inPreview(find.text('Roasted in Zamalek')), findsOneWidget);
  });

  testWidgets('SET-LNK-021 a refused or failed save toasts the server\'s words', (
    tester,
  ) async {
    final m = setupMockServer();
    final denied = MockResponse.denied('org.settings.edit');
    m.server.fail('PUT', LinksRoutes.page, denied);
    final h = await pumpLinks(tester, backend: m);
    await _save(h);
    await h.expectToast(h.refusalWords(denied));
    expect(tester.widget<DashButton>(byKey('links-save')).onPressed, isNotNull);

    m.server.fail('PUT', LinksRoutes.page, MockResponse.badRequest('That branch is not one of this shop\'s'));
    await _save(h);
    await h.expectToast('Bad request: That branch is not one of this shop\'s');
  });

  testWidgets('SET-LNK-022 Enter in a field saves', (tester) async {
    final h = await pumpLinks(tester);
    await _type(h, 'links-tagline-en', 'Open late on Thursdays');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await h.settle();
    expect(lastBody(h, 'PUT', LinksRoutes.page)['tagline_en'], 'Open late on Thursdays');
    await h.expectToast('Links page saved');
  });

  testWidgets('SET-LNK-023 the preview shows what is saved, not the draft', (
    tester,
  ) async {
    final h = await pumpLinks(tester);
    expect(find.text('Preview (as saved)'.toUpperCase()), findsOneWidget);
    expect(inPreview(find.text('Sabah Coffee')), findsOneWidget);
    expect(inPreview(find.text('Order now')), findsOneWidget);
    expect(inPreview(find.text('Visit us')), findsOneWidget);
    expect(h.server.callsTo(LinksRoutes.public).last.query['org_id'], [SeedIds.sabahOrg]);
    await _type(h, 'links-tagline-en', 'Draft line');
    expect(inPreview(find.text('Draft line')), findsNothing);
    final call = inPreview(find.bySemanticsLabel('Call')).first;
    await _show(h, call);
    await h.tap(call);
    expect(h.openedLinks.last.scheme, 'tel');
  });

  testWidgets('SET-LNK-023 a failed preview says so and retries', (tester) async {
    final m = setupMockServer();
    m.server.fail('GET', LinksRoutes.public, MockResponse.error(500, 'down'));
    final h = await pumpLinks(tester, backend: m);
    expect(inPreview(find.text(h.t('links.error.title'))), findsOneWidget);
    await _show(h, inPreview(find.text('Retry')));
    await h.tap(inPreview(find.text('Retry')));
    expect(inPreview(find.text('Sabah Coffee')), findsOneWidget);
  });

  testWidgets('SET-LNK-024 another org starts a fresh editor', (tester) async {
    final h = await pumpLinks(
      tester,
      persona: Persona.platform,
      prefs: picked(SeedIds.sabahOrg),
    );
    await _type(h, 'links-tagline-en', 'Unsaved');
    await h.container.read(selectedOrgProvider.notifier).select(SeedIds.nakhlaOrg);
    await h.settle();
    await h.container.read(selectedOrgProvider.notifier).select(SeedIds.sabahOrg);
    await h.settle();
    expect(find.text('Unsaved'), findsNothing);
    expect(find.text('Specialty coffee, roasted in Cairo every morning.'), findsWidgets);
  });

  testWidgets('SET-LNK-025 (divergence) no org: "Select an organization", no read', (
    tester,
  ) async {
    final h = await pumpLinks(tester, persona: Persona.platform);
    expect(inLinks(find.text(h.t('branches.pickOrg'))), findsOneWidget);
    expect(gets(h, LinksRoutes.page), 0);
  });

  testWidgets('SET-LNK-026 a save keeps the server\'s ids and an off module\'s flag', (
    tester,
  ) async {
    final m = setupMockServer();
    for (final r in m.db[SetupSeed.bookingSettingsTable].rows) {
      r['enabled'] = false;
    }
    final h = await pumpLinks(tester, backend: m);
    await _show(h, byKey('links-add'));
    await h.tap(byKey('links-add'));
    final row = find.descendant(of: byKey('links-buttons'), matching: find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.endsWith('-title-en') && !(w.key! as ValueKey<String>).value.contains(_cat)));
    final newKey = (tester.widget(row.first).key! as ValueKey<String>).value;
    await _type(h, newKey, 'Our beans');
    await _type(h, newKey.replaceFirst('-title-en', '-url'), 'https://sabahcoffee.eg/beans');
    await _save(h);
    await h.expectToast('Links page saved');
    final first = _items(lastBody(h, 'PUT', LinksRoutes.page));
    expect(first.firstWhere((i) => i['kind'] == 'book'), {'kind': 'book', 'visible': true});
    await _save(h);
    await h.expectToast('Links page saved');
    final mine = _items(sabahPage(m.db)).where((i) => i['title_en'] == 'Our beans');
    expect(mine, hasLength(1));
  });

  testWidgets('refusal: a manager without org settings reads the refusal', (
    tester,
  ) async {
    final h = await pumpLinks(tester, persona: Persona.manager);
    expect(
      inLinks(find.text(h.refusalWords(MockResponse.denied('org.settings.read')))),
      findsOneWidget,
    );
    expect(find.byType(LinksEditor), findsNothing);
  });

  testWidgets('empty: no buttons left and no branches still draws the page', (
    tester,
  ) async {
    final m = setupMockServer();
    m.db[linksPagesTable].put({
      'id': SeedIds.sabahOrg,
      'items': [
        for (final k in ['order', 'menu', 'rewards', 'book'])
          {'kind': k, 'visible': false},
      ],
      'tagline_en': null,
      'tagline_ar': null,
      'show_cover': false,
      'show_branches': false,
      'branches': <String, Object?>{},
    });
    final h = await pumpLinks(tester, backend: m);
    expect(inPreview(find.text('Order now')), findsNothing);
    expect(inPreview(find.text('Visit us')), findsNothing);
    expect(inPreview(find.text('Sabah Coffee')), findsOneWidget);
    expect(h.location.path, linksPath);
  });
}
