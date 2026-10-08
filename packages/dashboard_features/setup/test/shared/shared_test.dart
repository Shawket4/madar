// The setup area's shared pieces: the social-links rules, the mock QR
// image, the links-page module rule over the area seed, the QR preview
// dialog, and the area's i18n supplements in both languages.
import 'dart:ui' as ui;

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart' show DashSize;
import 'package:dashboard_kit/dashboard_kit.dart' show DashBadge;
import 'package:dashboard_setup/src/area_seed.dart';
import 'package:dashboard_setup/src/brand_appearance/settings_shell.dart';
import 'package:dashboard_setup/src/mock/support.dart';
import 'package:dashboard_setup/src/shared/qr_preview_dialog.dart';
import 'package:dashboard_setup/src/shared/scope.dart';
import 'package:dashboard_setup/src/shared/social_links.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support.dart';

void main() {
  group('social links', () {
    test('https only, http refused, empty allowed', () {
      expect(socialLinkValid(''), isTrue);
      expect(socialLinkValid('  '), isTrue);
      expect(socialLinkValid('https://instagram.com/sabahcoffee.eg'), isTrue);
      expect(socialLinkValid('http://instagram.com/sabah'), isFalse);
      expect(socialLinkValid('instagram.com/sabah'), isFalse);
      expect(socialLinkValid('https://'), isFalse);
    });

    test('the patch: values, emptied ones as "", never-set ones left out', () {
      final saved = {
        'instagram': 'https://instagram.com/sabahcoffee.eg',
        'facebook': 'https://facebook.com/sabahcoffee.eg',
      };
      final values = socialLinksToForm(saved)
        ..['facebook'] = ''
        ..['website'] = ' https://sabah.coffee ';
      expect(socialLinksPatch(values, saved), {
        'instagram': 'https://instagram.com/sabahcoffee.eg',
        'facebook': '',
        'website': 'https://sabah.coffee',
      });
    });
  });

  test('inherited: a branch in scope answered with another row', () {
    expect(isInheritedScope(scopeBranchId: null, rowBranchId: null), isFalse);
    expect(
      isInheritedScope(scopeBranchId: SeedIds.maadi, rowBranchId: null),
      isTrue,
    );
    expect(
      isInheritedScope(
        scopeBranchId: SeedIds.zamalek,
        rowBranchId: SeedIds.zamalek,
      ),
      isFalse,
    );
  });

  testWidgets('the mock QR is a real square PNG; codes are stable', (
    tester,
  ) async {
    final qr = mockQrResponse(
      kind: 'org_order',
      longUrl: '${SetupSeed.publicUrl('sabah-coffee')}order/',
      key: 'org-order',
    );
    expect(qr.shortCode, hasLength(6));
    expect(qr.shortCode, mockShortCode('org-order'));
    expect(qr.shortUrl, '$mockShortLinkBase/${qr.shortCode}');
    expect(qr.qrDataUrl, startsWith('data:image/png;base64,'));
    final bytes = qrImageBytes(qr.qrDataUrl)!;
    final size = await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      return (frame.image.width, frame.image.height);
    });
    expect(size!.$1, size.$2);
    expect(size.$1 % 8, 0);
  });

  test('links modules follow the delivery, booking and loyalty rows', () {
    final m = setupMockServer();
    final modules = {
      for (final s in SetupSeed.linksModules(m.db, SeedIds.sabahOrg))
        s.kind.value: s,
    };
    expect(modules['order']!.available, isTrue);
    expect(modules['order']!.branchNames, [
      'Heliopolis',
      'Maadi',
      'New Cairo',
      'Zamalek',
    ]);
    expect(modules['menu']!.branchNames, hasLength(4));
    expect(modules['rewards']!.available, isTrue);
    expect(modules['book']!.branchNames, ['Heliopolis', 'Zamalek']);
    expect(modules['book']!.path, '/book/');
  });

  testWidgets('the QR preview: link, code, copy and download', (tester) async {
    final h = await pumpSetup(tester);
    final qr = mockQrResponse(
      kind: 'org_loyalty',
      longUrl: '${SetupSeed.publicUrl('sabah-coffee')}rewards',
      key: 'org-loyalty',
    );
    final context = tester.element(find.byType(SettingsShell));
    showQrPreview(context, qr: qr, title: h.t('loyalty.joinQr'));
    await h.settle();
    expect(find.text(h.t('loyalty.joinQr')), findsOneWidget);
    expect(find.text(qr.longUrl), findsOneWidget);
    expect(find.text(qr.shortUrl), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DashBadge),
        matching: find.textContaining(qr.shortCode),
      ),
      findsOneWidget,
    );
    await h.shot('shared/qr-preview');

    await h.tapText(h.t('common.download'));
    expect(h.files.saved.single.filename, 'qr-${qr.shortCode}.png');
    expect(h.files.saved.single.mimeType, 'image/png');
  });

  testWidgets('the shell on a phone, in Arabic: the pane picker', (
    tester,
  ) async {
    final h = await pumpSetup(
      tester,
      path: '/settings/loyalty',
      size: DashSize.phone,
      locale: 'ar',
    );
    expect(find.text(h.t('nav.settings')), findsWidgets);
    expect(find.text(h.t('loyalty.subtitle')), findsOneWidget);
    // The picker shows the current pane.
    expect(find.text(h.t('nav.loyalty')), findsWidgets);
    await h.shot('shared/shell-phone');
  });

  testWidgets('the area supplements load (English)', (tester) async {
    final h = await pumpSetup(tester);
    expect(h.t('qr.copyLink'), 'Copy link');
    expect(h.t('kitchen.routedTo'), 'Routed to');
    expect(h.t('legal.retention'), 'Data retention');
    expect(h.t('integrations.hintReadOnly'), startsWith('Partners with'));
  });

  testWidgets('the area supplements load (Arabic)', (tester) async {
    final h = await pumpSetup(tester, locale: 'ar');
    expect(h.t('qr.copyLink'), 'نسخ الرابط');
    expect(h.t('kitchen.routedTo'), 'يُوجَّه إلى');
    expect(h.t('legal.retention'), 'الاحتفاظ بالبيانات');
  });
}
