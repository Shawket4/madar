// The scope bar: the org (platform admins), the branch and the period; the
// theme and the language; and the "Branch not found" bug — a branch from
// another org (or one that is gone) never rides into this org's requests.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart'
    show DashErrorState, DashOptionList;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

String? lastBranchHeader(DashHarness h) {
  final calls = h.server.calls.where((c) => !c.stream).toList();
  return calls.isEmpty ? null : calls.last.headers['X-Branch-Id'];
}

Future<void> pickBranch(DashHarness h, String from, String to) async {
  await h.tapText(from);
  await h.tap(inMenu(to));
}

/// [text] in the open picker's options (the page under it names branches
/// too).
Finder inMenu(String text) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DashOptionList),
  matching: find.text(text),
);

void main() {
  testWidgets('ADM-APP-020 ADM-APP-045 ADM-APP-047 ADM-APP-048: owner picks '
      'a branch: scope, header, realtime, remembered', (tester) async {
    final h = await pumpShell(tester);
    expect(h.container.read(scopeProvider).branchId, isNull);
    expect(h.realtime.connections, isEmpty);
    await h.tapText('All branches');
    await h.shot('scope/branch-open');
    await h.tap(inMenu('Zamalek'));
    expect(h.container.read(scopeProvider).branchId, SeedIds.zamalek);
    expect(h.session.branchId, SeedIds.zamalek);
    expect(jsonDecode(h.prefs.values[ScopePrefKeys.branch]!), {
      'org': SeedIds.sabahOrg,
      'branch': SeedIds.zamalek,
    });
    // The one realtime connection follows the branch.
    expect(h.realtime.current?.branchId, SeedIds.zamalek);
    await pickBranch(h, 'Zamalek', 'Maadi');
    expect(h.realtime.connections, hasLength(2));
    expect(h.realtime.connections.first.hasListener, isFalse);
    expect(h.realtime.current?.branchId, SeedIds.maadi);
    await pickBranch(h, 'Maadi', 'All branches');
    expect(h.container.read(scopeProvider).branchId, isNull);
    expect(h.session.branchId, isNull);
  });

  testWidgets('ADM-APP-045: a branch manager has no branch picker (scoped by '
      'the server)', (tester) async {
    final h = await pumpShell(tester, persona: Persona.manager);
    expect(text('All branches'), findsNothing);
    expect(h.session.branchId, SeedIds.zamalek);
  });

  testWidgets('ADM-APP-052 ADM-APP-060 ADM-APP-061: the period: presets, '
      'remembered; custom never is', (tester) async {
    final h = await pumpShell(tester);
    await h.tapText('Last 30 days');
    await h.shot('scope/period-open');
    await h.tap(find.text('Last 7 days').last);
    expect(h.container.read(scopeProvider).preset, ScopePreset.last7Days);
    expect(h.prefs.values[ScopePrefKeys.preset], '7d');
    final range = h.container.read(currentScopeProvider).range;
    expect(range.from, '2026-10-01T21:00:00.000Z');
    expect(range.to, '2026-10-08T20:59:59.999Z');
  });

  testWidgets('ADM-APP-059 ADM-APP-060: a stored custom period restores as '
      'the default', (tester) async {
    final h = await pumpShell(tester, prefs: {ScopePrefKeys.preset: 'custom'});
    expect(h.container.read(scopeProvider).preset, ScopePreset.last30Days);
    expect(text('Last 30 days'), findsOneWidget);
  });

  testWidgets('ADM-APP-058 ADM-APP-061: a deep link carries its scope', (
    tester,
  ) async {
    final h = await pumpShell(
      tester,
      path: '/tills?branchId=${SeedIds.heliopolis}&preset=yesterday',
    );
    expect(h.container.read(scopeProvider).branchId, SeedIds.heliopolis);
    expect(h.container.read(scopeProvider).preset, ScopePreset.yesterday);
  });

  testWidgets('ADM-APP-067: theme: Light / Dark / System, remembered', (
    tester,
  ) async {
    final h = await pumpShell(tester);
    await h.tap(labelled('Toggle theme'));
    await h.shot('scope/theme-menu');
    await h.tapText('Dark');
    expect(h.prefs.values[themePrefKey], 'dark');
    final ctx = tester.element(find.byType(DashSidebar));
    expect(Theme.of(ctx).brightness, Brightness.dark);
  });

  testWidgets('ADM-APP-024 ADM-APP-068: language: one tap to Arabic, right '
      'to left, remembered', (tester) async {
    final h = await pumpShell(tester);
    await h.tap(labelled('Switch language'));
    expect(h.container.read(localeProvider), 'ar');
    expect(h.prefs.values[languagePrefKey], 'ar');
    expect(navText('الطلبات'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(DashSidebar))),
      TextDirection.rtl,
    );
  });

  testWidgets('ADM-APP-063 ADM-APP-064: the user menu: who, language, '
      'theme, sign out', (tester) async {
    final h = await pumpShell(tester);
    await h.tap(labelled('Account'));
    expect(text('Nour El-Sayed'), findsOneWidget);
    expect(text('nour@sabah.test'), findsOneWidget);
    expect(text('Organization Admin'), findsOneWidget);
    await h.shot('scope/user-menu');
    await h.tap(labelled('Switch language').last);
    expect(h.container.read(localeProvider), 'ar');
  });

  group('platform admin', () {
    testWidgets('ADM-APP-040 ADM-APP-041 ADM-APP-042 ADM-APP-043: picks a '
        'shop: org header, its branches, its modules', (tester) async {
      final h = await pumpShell(tester, persona: Persona.platform);
      expect(h.container.read(orgIdProvider), isNull);
      await h.tapText('Select a shop');
      await h.shot('scope/org-picker');
      await h.tap(find.text('Sabah Coffee').last);
      expect(h.container.read(orgIdProvider), SeedIds.sabahOrg);
      expect(h.session.orgId, SeedIds.sabahOrg);
      await h.tapText('All branches');
      expect(find.text('Zamalek'), findsWidgets);
    });

    testWidgets('ADM-APP-043 ADM-APP-049: switching shop drops the branch (the '
        '"Branch not found" bug)', (tester) async {
      final h = await pumpShell(tester, persona: Persona.platform);
      await h.tapText('Select a shop');
      await h.tap(find.text('Sabah Coffee').last);
      await pickBranch(h, 'All branches', 'Zamalek');
      expect(h.session.branchId, SeedIds.zamalek);
      await h.tapText('Sabah Coffee');
      await h.tap(find.text('Nakhla Bakery').last);
      expect(h.container.read(orgIdProvider), SeedIds.nakhlaOrg);
      expect(h.container.read(scopeProvider).branchId, isNull);
      expect(h.session.branchId, isNull);
      expect(text('All branches'), findsOneWidget);
      // No later request carries Sabah's branch into Nakhla.
      final since = h.server.calls.length;
      await h.go('/branches');
      final later = h.server.calls.skip(since);
      expect(
        later.where((c) => c.headers['X-Branch-Id'] == SeedIds.zamalek),
        isEmpty,
      );
    });
  });

  testWidgets('ADM-APP-049: a stored branch of another org is dropped at '
      'start', (tester) async {
    final h = await pumpShell(
      tester,
      prefs: {
        ScopePrefKeys.branch: jsonEncode({
          'org': SeedIds.nakhlaOrg,
          'branch': SeedIds.dokki,
        }),
      },
    );
    expect(h.container.read(scopeProvider).branchId, isNull);
    expect(
      h.session.scopeCalls.where((c) => c.branchId == SeedIds.dokki),
      isEmpty,
    );
    expect(lastBranchHeader(h), isNull);
  });

  testWidgets('ADM-APP-049: a stored branch this org no longer has heals to '
      'all branches', (tester) async {
    final h = await pumpShell(
      tester,
      prefs: {
        ScopePrefKeys.branch: jsonEncode({
          'org': SeedIds.sabahOrg,
          'branch': 'gone-branch',
        }),
      },
    );
    expect(h.container.read(scopeProvider).branchId, isNull);
    expect(h.session.branchId, isNull);
  });

  testWidgets('ADM-APP-065: signing out forgets the scope', (tester) async {
    final h = await pumpShell(tester);
    await pickBranch(h, 'All branches', 'Zamalek');
    await h.tap(labelled('Account'));
    await h.tapText('Sign Out');
    expect(h.prefs.values[ScopePrefKeys.branch], isNull);
    expect(h.session.branchId, isNull);
  });

  testWidgets('ADM-APP-063: the avatar shows the initials', (tester) async {
    await pumpShell(tester);
    // Nour El-Sayed.
    expect(
      find.descendant(of: labelled('Account'), matching: text('NE')),
      findsOneWidget,
    );
  });

  testWidgets('ADM-APP-046: while the branches load, "Loading…"', (
    tester,
  ) async {
    final db = MockDb.seeded();
    final server = MockServer(persona: Persona.owner, clock: db.clock);
    registerAppMocks(server, db);
    final gate = server.hold('GET', '/branches');
    final h = await pumpShell(tester, server: server, db: db);
    final picker = find.byType(DashBranchPicker);
    expect(
      find.descendant(of: picker, matching: text('Loading…')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: text('All branches')),
      findsNothing,
    );
    gate.release();
    await h.settle();
    expect(
      find.descendant(of: picker, matching: text('All branches')),
      findsOneWidget,
    );
  });

  testWidgets('ADM-APP-130: the branch list fails: only All branches, no '
      'error', (tester) async {
    final db = MockDb.seeded();
    final server = MockServer(persona: Persona.owner, clock: db.clock);
    registerAppMocks(server, db);
    server.fail(
      'GET',
      '/branches',
      MockResponse.error(500, 'The branches could not be read'),
      times: null,
    );
    final h = await pumpShell(tester, server: server, db: db);
    final picker = find.byType(DashBranchPicker);
    expect(
      find.descendant(of: picker, matching: text('All branches')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: find.byType(DashErrorState)),
      findsNothing,
    );
    await h.tapText('All branches');
    expect(inMenu('All branches'), findsOneWidget);
    expect(inMenu('Zamalek'), findsNothing);
  });

  testWidgets('ADM-APP-051 ADM-APP-057: a custom range from the link: the '
      'trigger shows its days, the calendar opens on them', (tester) async {
    final h = await pumpShell(
      tester,
      path:
          '/tills?preset=custom&from=2026-09-02T21:00:00.000Z'
          '&to=2026-09-05T20:59:59.999Z',
    );
    final f = h.container.read(formatProvider);
    final label =
        '${f.fmtDate('2026-09-02T21:00:00.000Z')} → '
        '${f.fmtDate('2026-09-05T20:59:59.999Z')}';
    expect(text(label), findsOneWidget);
    await h.tapText(label);
    await h.shot('scope/custom-open');
    // From and To are the link's days, on September's page.
    expect(
      find.textContaining(f.fmtDate('2026-09-02T21:00:00.000Z')),
      findsWidgets,
    );
    expect(find.textContaining('September 2026'), findsOneWidget);
  });
}
