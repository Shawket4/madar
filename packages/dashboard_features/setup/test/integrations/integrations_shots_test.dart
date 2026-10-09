// The Integrations screenshot matrix: the default state at every size in
// {en light, ar dark} for the org admin (audit) and the platform admin
// (issue, rotate, revoke), and every other state (loading, failed, empty,
// refused, no org, the issue dialog, the handoff building / ready / failed,
// the close warning, the rotate confirm) at desktop-en-light and
// phone-ar-light. Writes PNGs only with FDASH_SHOTS set.
import 'dart:async';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/src/integrations/handoff_zip.dart';
import 'package:dashboard_setup/src/integrations/integrations_page.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _shot = 'integrations';

/// Shoots the pane one screen at a time down the settings shell's scroll.
Future<void> shootPage(DashHarness h, String name) async {
  ScrollableState? state;
  for (final e
      in find
          .ancestor(
            of: find.byType(IntegrationsPage),
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
    if (y >= position.maxScrollExtent || i >= 3) break;
    y = (y + position.viewportDimension * 0.85).clamp(
      0,
      position.maxScrollExtent,
    );
    i++;
  }
}

final String _rue = IntegrationsSeed.id('rue');

void main() {
  tearDown(HandoffZipBuilder.reset);

  for (final size in DashSize.values) {
    for (final (lang, dark) in [('en', false), ('ar', true)]) {
      testWidgets('default, ${size.name} $lang', (tester) async {
        final h = await pumpIntegrations(
          tester,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'default');
      });
      testWidgets('platform, ${size.name} $lang', (tester) async {
        final h = await pumpIntegrations(
          tester,
          persona: Persona.platform,
          size: size,
          locale: lang,
          dark: dark,
        );
        await shootPage(h, 'platform');
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
      Persona persona = Persona.platform,
      ({MockServer server, MockDb db})? backend,
      bool pickOrg = true,
    }) => pumpIntegrations(
      tester,
      persona: persona,
      size: size,
      locale: lang,
      backend: backend,
      pickOrg: pickOrg,
    );

    Future<DashHarness> rotate(WidgetTester tester) async {
      final h = await open(tester);
      await h.tap(find.byKey(ValueKey('integrations-rotate-$_rue')));
      await h.tap(top(h.t('integrations.rotate')));
      return h;
    }

    testWidgets('loading, $tag', (tester) async {
      final m = integrationsServer(persona: Persona.platform);
      final gate = m.server.hold('GET', IntegrationsRoutes.list);
      final h = await open(tester, backend: m);
      await h.shot('$_shot/loading');
      gate.release();
      await h.settle();
    });

    testWidgets('failed, $tag', (tester) async {
      final m = integrationsServer(persona: Persona.platform);
      m.server.fail(
        'GET',
        IntegrationsRoutes.list,
        MockResponse.error(500, 'The database is restarting'),
        times: null,
      );
      final h = await open(tester, backend: m);
      await h.shot('$_shot/failed');
    });

    testWidgets('empty, $tag', (tester) async {
      final m = integrationsServer(persona: Persona.platform);
      m.db[IntegrationsSeed.table].clear();
      final h = await open(tester, backend: m);
      await h.shot('$_shot/empty');
    });

    testWidgets('restricted, $tag', (tester) async {
      final h = await open(tester, persona: Persona.manager);
      await h.shot('$_shot/restricted');
    });

    testWidgets('no org, $tag', (tester) async {
      final h = await open(tester, pickOrg: false);
      await h.shot('$_shot/no-org');
    });

    testWidgets('rotate confirm, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(find.byKey(ValueKey('integrations-rotate-$_rue')));
      await h.shot('$_shot/rotate-confirm');
    });

    testWidgets('issue dialog, $tag', (tester) async {
      final h = await open(tester);
      await h.tap(inPage(find.byKey(const ValueKey('integrations-issue'))));
      await h.shot('$_shot/issue-dialog');
      await h.enterText(
        find.byKey(const ValueKey('integrations.label')),
        'Rue — One Ninety',
      );
      await h.tap(top(h.t('integrations.issue')).last);
      await h.shot('$_shot/issue-invalid');
    });

    testWidgets('handoff ready, $tag', (tester) async {
      final h = await rotate(tester);
      await h.shot('$_shot/handoff');
    });

    testWidgets('handoff building, $tag', (tester) async {
      final build = Completer<List<int>>();
      HandoffZipBuilder.build = (files, p) => build.future;
      final h = await rotate(tester);
      await h.shot('$_shot/handoff-building');
      build.complete(const [1]);
      await h.settle();
    });

    testWidgets('handoff failed, $tag', (tester) async {
      HandoffZipBuilder.build = (files, p) async => throw StateError('x');
      final h = await rotate(tester);
      await h.shot('$_shot/handoff-failed');
    });

    testWidgets('handoff close warning, $tag', (tester) async {
      final h = await open(tester);
      h.files.cancelNextSave = true;
      await h.tap(find.byKey(ValueKey('integrations-rotate-$_rue')));
      await h.tap(top(h.t('integrations.rotate')));
      await h.tap(find.byKey(const ValueKey('handoff-done')));
      await h.shot('$_shot/handoff-close');
    });
  }
}
