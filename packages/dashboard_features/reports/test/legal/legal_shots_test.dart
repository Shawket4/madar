// The Legal screenshot matrix: the default (Tax) at {phone, tablet,
// desktop} x {en light, ar dark}; every audit tab, the export menu and the
// loading / failed / empty / no-VAT states at desktop-en-light and
// phone-ar-light. Written only with FDASH_SHOTS set; the pages still render
// (and must not overflow) without.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_reports/src/legal/legal_page.dart';
import 'package:dashboard_reports/src/legal/legal_words.dart';
import 'package:dashboard_reports/src/mock/legal_mock.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'legal_support.dart';

/// Shoots the page top to bottom (at most [max] screens): `<name>-1`, …
Future<void> shootPage(DashHarness h, String name, {int max = 4}) async {
  final scroll = find
      .descendant(
        of: find.byType(LegalReportPage),
        matching: find.byWidgetPredicate(
          (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .first;
  final position = h.tester.state<ScrollableState>(scroll).position;
  var y = 0.0;
  for (var i = 1; i <= max; i++) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('legal/$name-$i');
    if (y >= position.maxScrollExtent) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
  }
  position.jumpTo(0);
  await h.settle(rounds: 2);
}

const _states = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

void main() {
  setUpAll(ensureTimeZones);

  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default (Tax), ${size.name} $lang', (tester) async {
        final h = await pumpLegal(tester, size: size, locale: lang, dark: dark);
        await shootPage(h, 'default');
      });
    }
  }

  for (final (size, lang, dark) in _states) {
    final tag = '${size.name} $lang';
    for (final tab in LegalTab.values.skip(1)) {
      testWidgets('tab ${tab.id}, $tag', (tester) async {
        final s = legalServer();
        final o = s.db['orders'].rows.firstWhere(
          (o) =>
              o['status'] == 'completed' &&
              '${o['created_at']}'.compareTo(defaultFrom) > 0,
        );
        final id = o['id']! as String;
        recordLegalRefund(
          s.db,
          orderId: id,
          amount: 5000,
          reason: 'Cold drink',
          issuedBy: SeedIds.user('nour'),
          issuedAt: s.db.clock.now,
        );
        waiveLegalServiceCharge(
          s.db,
          orderId: id,
          amount: 1200,
          by: SeedIds.user('nour'),
          at: s.db.clock.now,
        );
        flagLegalPrice(s.db, id);
        final h = await pumpLegal(
          tester,
          server: s.server,
          db: s.db,
          size: size,
          locale: lang,
          dark: dark,
        );
        await tapTab(h, h.t(tab.labelKey));
        await shootPage(h, 'tab-${tab.id}', max: 3);
      });
    }

    testWidgets('export menu, $tag', (tester) async {
      final h = await pumpLegal(tester, size: size, locale: lang, dark: dark);
      await tapTab(h, h.t(LegalTab.voids.labelKey));
      await h.tap(auditExport);
      await h.shot('legal/export-menu');
    });

    testWidgets('tax loading, $tag', (tester) async {
      final s = legalServer();
      final gate = s.server.hold('GET', taxRoute);
      final h = await pumpLegal(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('legal/tax-loading');
      gate.release();
      await h.settle();
    });

    testWidgets('audit loading, $tag', (tester) async {
      final s = legalServer();
      final gate = s.server.hold('GET', auditRoute('voids-audit'));
      final h = await pumpLegal(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await tapTab(h, h.t(LegalTab.voids.labelKey));
      await h.shot('legal/audit-loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final s = legalServer();
      s.server.fail(
        'GET',
        taxRoute,
        MockResponse.error(500, 'Internal error'),
        times: null,
      );
      final h = await pumpLegal(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      expect(find.byType(DashErrorState), findsOneWidget);
      await h.shot('legal/failed');
    });

    testWidgets('empty audit, $tag', (tester) async {
      final h = await pumpLegal(tester, size: size, locale: lang, dark: dark);
      await tapTab(h, h.t(LegalTab.refunds.labelKey));
      await h.shot('legal/empty');
    });

    testWidgets('no VAT, $tag', (tester) async {
      final s = legalServer();
      s.db['orgs'].update(SeedIds.sabahOrg, {'tax_rate': 0});
      for (final o in s.db['orders'].rows) {
        o['tax_amount'] = 0;
      }
      final h = await pumpLegal(
        tester,
        server: s.server,
        db: s.db,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('legal/no-vat');
    });

    testWidgets('restricted, $tag', (tester) async {
      final h = await pumpLegal(
        tester,
        persona: Persona.limited,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.shot('legal/restricted');
    });
  }
}
