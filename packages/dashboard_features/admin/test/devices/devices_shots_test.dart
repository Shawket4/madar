// The Devices screenshots (SPEC 6.2): the default states at phone / tablet /
// desktop in English light and Arabic dark, and every dialog and state at
// desktop-en-light and phone-ar-light. Written only with FDASH_SHOTS set;
// each also checks the state it pictures.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

const _matrix = [
  (DashSize.phone, 'en', false),
  (DashSize.tablet, 'en', false),
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', true),
  (DashSize.tablet, 'ar', true),
  (DashSize.desktop, 'ar', true),
];

const _dialogs = [
  (DashSize.desktop, 'en', false),
  (DashSize.phone, 'ar', false),
];

String _name(DashSize s, String l, bool d) => '${s.name}-$l-${d ? 'dark' : 'light'}';

final _zamalek = atBranch(SeedIds.zamalek);

Finder _edit(DashHarness h) => find
    .byWidgetPredicate(
      (w) => w is DashIconButton && w.semanticLabel == h.t('common.edit'),
    )
    .at(1);

void main() {
  for (final (size, lang, dark) in _matrix) {
    testWidgets('default: the Devices view ${_name(size, lang, dark)}', (
      tester,
    ) async {
      final h = await pumpDevices(
        tester,
        query: _zamalek,
        size: size,
        locale: lang,
        dark: dark,
      );
      expect(deviceRows(), findsNWidgets(5));
      await h.shot('devices/default');
      await h.scrollUntilVisible(find.byKey(const ValueKey('codes-table')));
      expect(codeCells(), findsNWidgets(4));
      await h.shot('devices/default-codes');
    });

    testWidgets('default: Client versions ${_name(size, lang, dark)}', (
      tester,
    ) async {
      final h = await pumpDevices(
        tester,
        query: '?view=clients&all=true',
        size: size,
        locale: lang,
        dark: dark,
      );
      expect(clientRows(), findsNWidgets(12));
      await h.shot('devices/clients');
    });

    testWidgets('default: New Cairo\'s code clash ${_name(size, lang, dark)}', (
      tester,
    ) async {
      final h = await pumpDevices(
        tester,
        query: atBranch(SeedIds.newCairo),
        size: size,
        locale: lang,
        dark: dark,
      );
      expect(find.text(h.t('devices.codeConflict')), findsNWidgets(2));
      await h.shot('devices/conflict');
    });
  }

  for (final (size, lang, dark) in _dialogs) {
    final tag = _name(size, lang, dark);

    testWidgets('the Edit device dialog $tag', (tester) async {
      final h = await pumpDevices(
        tester,
        query: _zamalek,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(_edit(h));
      expect(find.text(h.t('devices.edit')), findsOneWidget);
      await h.shot('devices/edit-dialog');
      await h.enterText(find.byKey(const ValueKey('device-code')), 'T-1');
      await h.tap(find.text(h.t('common.save')).hitTestable());
      expect(find.text(h.t('devices.codeInvalid')), findsOneWidget);
      await h.shot('devices/edit-invalid');
    });

    testWidgets('the New code dialog and the issued code $tag', (
      tester,
    ) async {
      final h = await pumpDevices(
        tester,
        query: _zamalek,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(find.byKey(const ValueKey('issue-code')));
      expect(find.text(h.t('devices.activation.issueTitle')), findsOneWidget);
      await h.shot('devices/issue-dialog');
      await h.tap(find.byKey(const ValueKey('code-kind')));
      await h.shot('devices/issue-kind-open');
      await h.tap(find.text(h.t('devices.kinds.waiter')).hitTestable().last);
      await h.tap(find.byKey(const ValueKey('issue-submit')));
      expect(find.byKey(const ValueKey('issued-code')), findsOneWidget);
      await h.shot('devices/issued-code');
    });

    testWidgets('withdraw a code: the confirmation $tag', (tester) async {
      final h = await pumpDevices(
        tester,
        query: _zamalek,
        size: size,
        locale: lang,
        dark: dark,
      );
      await h.tap(find.text(h.t('devices.activation.revoke')));
      expect(find.text(h.t('devices.activation.revokeTitle')), findsOneWidget);
      await h.shot('devices/withdraw-confirm');
    });

    testWidgets('no branch picked $tag', (tester) async {
      final h = await pumpDevices(
        tester,
        size: size,
        locale: lang,
        dark: dark,
      );
      expect(find.text(h.t('tills.pickBranch')), findsOneWidget);
      await h.shot('devices/pick-branch');
    });

    testWidgets('empty lists $tag', (tester) async {
      final b = DevicesBackend();
      b.devices.removeWhere((d) => d['branch_id'] == SeedIds.heliopolis);
      b.codes.removeWhere((d) => d['branch_id'] == SeedIds.heliopolis);
      final h = await pumpDevices(
        tester,
        query: atBranch(SeedIds.heliopolis),
        size: size,
        locale: lang,
        dark: dark,
        backend: b,
      );
      expect(find.text(h.t('devices.empty')), findsOneWidget);
      await h.shot('devices/empty');
      await h.scrollUntilVisible(
        find.text(h.t('devices.activation.empty')),
      );
      await h.shot('devices/codes-empty');
    });

    testWidgets('a failed load $tag', (tester) async {
      final b = DevicesBackend();
      b.server.fail(
        'GET',
        DevicesRoutes.devices,
        MockResponse.error(500, 'Internal error'),
      );
      final h = await pumpDevices(
        tester,
        query: _zamalek,
        size: size,
        locale: lang,
        dark: dark,
        backend: b,
      );
      expect(find.text(h.t('common.loadFailed')), findsOneWidget);
      await h.shot('devices/error');
    });

    testWidgets('Client versions: legacy only, empty, refused $tag', (
      tester,
    ) async {
      final h = await pumpDevices(
        tester,
        query: '?view=clients',
        size: size,
        locale: lang,
        dark: dark,
      );
      expect(clientRows(), findsNWidgets(3));
      await h.shot('devices/clients-legacy');
      await h.go('/devices?view=clients&branchId=${SeedIds.maadi}');
      expect(find.text(h.t('devices.clients.noLegacy')), findsOneWidget);
      await h.shot('devices/clients-empty');
      await h.tap(find.byKey(const ValueKey('clients-window')));
      await h.shot('devices/clients-window-open');
    });

    testWidgets('Client versions refused (no branches.edit) $tag', (
      tester,
    ) async {
      final h = await pumpDevices(
        tester,
        persona: Persona.manager,
        query: '?view=clients',
        size: size,
        locale: lang,
        dark: dark,
      );
      expect(find.text(h.t('errors.unauthorized')), findsOneWidget);
      await h.shot('devices/clients-refused');
    });
  }
}
