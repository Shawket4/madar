// The Loyalty screenshot matrix: the default state at every size in
// {en light, ar dark}, and every other state (tabs, the card, the dialogs,
// loading, failed, refusals) at desktop-en-light and phone-ar-light. Writes
// PNGs only with FDASH_SHOTS set.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_setup/src/loyalty/loyalty_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _shot = 'loyalty';

/// Shoots the page one screen at a time down the settings shell's scroll.
Future<void> shootPage(DashHarness h, String name, {int max = 4}) async {
  ScrollableState? state;
  for (final e
      in find
          .ancestor(
            of: find.byType(LoyaltyPage),
            matching: find.byType(Scrollable),
          )
          .evaluate()) {
    final s = (e as StatefulElement).state as ScrollableState;
    if (s.position.axis == Axis.vertical) {
      state = s;
      break;
    }
  }
  if (state == null) return h.shot('$_shot/$name-1');
  final position = state.position;
  var i = 1;
  var y = 0.0;
  while (true) {
    position.jumpTo(y);
    await h.settle(rounds: 2);
    await h.shot('$_shot/$name-$i');
    if (y >= position.maxScrollExtent || i >= max) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

Future<void> _openNada(DashHarness h) async {
  await openTab(h, h.t('loyalty.tabMembers'));
  await h.enterText(inPage(find.byType(DashSearchInput)), 'Nada Kamal');
  await h.tester.pump(const Duration(milliseconds: 350));
  await h.settle();
  await h.tap(
    inPage(
      find.byWidgetPredicate(
        (w) => w is DashPressable && w.semanticLabel == 'Nada Kamal',
      ),
    ),
  );
}

void main() {
  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpLoyalty(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await h.settle();
        await shootPage(h, 'default', max: 6);
      });
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final tag = '${size.name} $lang';
    Future<DashHarness> open(
      WidgetTester tester, {
      String query = '',
      Persona persona = Persona.owner,
      ({MockServer server, MockDb db})? backend,
    }) => pumpLoyalty(
      tester,
      query: query,
      size: size,
      locale: lang,
      persona: persona,
      backend: backend ?? loyaltyServer(persona: persona),
    );

    testWidgets('branch scope + platform wallet check, $tag', (tester) async {
      final h = await open(
        tester,
        persona: Persona.platform,
        query: atBranch(SeedIds.zamalek),
      );
      await h.tap(find.byKey(const ValueKey('loyalty-wallet-check')));
      await shootPage(h, 'program-branch', max: 6);
    });

    testWidgets('program errors, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(inPage(find.text(h.t('loyalty.modePoints'))));
      await h.enterText(programField('earn_egp_per_point'), '0');
      await h.enterText(programField('program_name'), '');
      await h.tap(find.byKey(const ValueKey('loyalty-save')));
      await h.tester.ensureVisible(programField('program_name'));
      await h.settle(rounds: 2);
      await h.shot('$_shot/program-errors');
    });

    testWidgets('program loading, $tag', (tester) async {
      final m = loyaltyServer();
      final gate = m.server.hold('GET', LoyaltyRoutes.settings);
      final h = await open(tester, backend: m);
      await h.shot('$_shot/program-loading');
      gate.release();
      await h.settle();
    });

    testWidgets('program failed, $tag', (tester) async {
      final m = loyaltyServer();
      m.server.fail(
        'GET',
        LoyaltyRoutes.settings,
        MockResponse.error(500, 'Database error: timeout'),
        times: null,
      );
      final h = await open(tester, backend: m);
      await h.shot('$_shot/program-failed');
    });

    testWidgets('read-only, $tag', (tester) async {
      final m = loyaltyServer();
      grantOnly(m.server, const ['loyalty.read']);
      final h = await open(tester, backend: m);
      await h.shot('$_shot/program-read-only');
      await openTab(h, h.t('loyalty.tabMembers'));
      await h.shot('$_shot/members-restricted');
    });

    testWidgets('rewards, $tag', (tester) async {
      final m = loyaltyServer();
      m.db['menu_items'].find(MockSeed.menuItemId('cappuccino'))!['is_active'] =
          false;
      settingsRow(m.db)['reward_any_item'] = true;
      final h = await open(tester, backend: m, query: atBranch(SeedIds.maadi));
      await openTab(h, h.t('loyalty.tabRewards'));
      await shootPage(h, 'rewards', max: 5);
    });

    testWidgets('members, $tag', (tester) async {
      final h = await open(tester);
      await openTab(h, h.t('loyalty.tabMembers'));
      await shootPage(h, 'members', max: 2);
    });

    testWidgets('overview, $tag', (tester) async {
      final h = await open(tester);
      await openTab(h, h.t('loyalty.tabOverview'));
      await shootPage(h, 'overview', max: 3);
    });

    testWidgets('member card and dialogs, $tag', (tester) async {
      final h = await open(tester, persona: Persona.platform);
      await _openNada(h);
      await h.shot('$_shot/member-card');
      await h.tap(find.byKey(const ValueKey('member-adjust')));
      await h.tap(find.byKey(const ValueKey('adjust-confirm')));
      await h.shot('$_shot/adjust-dialog');
      await h.tester.tapAt(const Offset(4, 4));
      await h.settle();
      if (find.byKey(const ValueKey('adjust-confirm')).evaluate().isNotEmpty) {
        await h.tap(
          find
              .byWidgetPredicate(
                (w) => w is DashButton && w.label == h.t('common.cancel'),
              )
              .last,
        );
      }
      await h.tap(find.byKey(const ValueKey('member-leave')));
      await h.shot('$_shot/leave-dialog');
      await h.tap(
        find
            .byWidgetPredicate(
              (w) => w is DashButton && w.label == h.t('common.cancel'),
            )
            .last,
      );
      await h.tap(find.byKey(const ValueKey('member-google')));
      await h.tap(inDialog(find.text(h.t('loyalty.refreshFromGoogle'))));
      await h.shot('$_shot/google-object');
    });

    testWidgets('join code, $tag', (tester) async {
      final h = await open(tester, query: atBranch(SeedIds.zamalek));
      await h.tap(find.byKey(const ValueKey('loyalty-code')));
      await h.shot('$_shot/join-code');
    });
  }
}
