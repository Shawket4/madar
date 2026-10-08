// The scope bar: the org (platform admins), the branch and the period; the
// theme and the language; and the "Branch not found" bug — a branch from
// another org (or one that is gone) never rides into this org's requests.
import 'dart:convert';

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_core/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

String? lastBranchHeader(DashHarness h) {
  final calls = h.server.calls.where((c) => !c.stream).toList();
  return calls.isEmpty ? null : calls.last.headers['X-Branch-Id'];
}

Future<void> pickBranch(DashHarness h, String from, String to) async {
  await h.tapText(from);
  await h.tap(find.text(to).last);
}

void main() {
  testWidgets('owner picks a branch: scope, header, realtime, remembered', (
    tester,
  ) async {
    final h = await pumpShell(tester);
    expect(h.container.read(scopeProvider).branchId, isNull);
    expect(h.realtime.connections, isEmpty);
    await h.tapText('All branches');
    await h.shot('scope/branch-open');
    await h.tap(find.text('Zamalek').last);
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

  testWidgets('a branch manager has no branch picker (scoped by the server)', (
    tester,
  ) async {
    final h = await pumpShell(tester, persona: Persona.manager);
    expect(text('All branches'), findsNothing);
    expect(h.session.branchId, SeedIds.zamalek);
  });

  testWidgets('the period: presets, remembered; custom never is', (
    tester,
  ) async {
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

  testWidgets('a stored custom period restores as the default', (tester) async {
    final h = await pumpShell(tester, prefs: {ScopePrefKeys.preset: 'custom'});
    expect(h.container.read(scopeProvider).preset, ScopePreset.last30Days);
    expect(text('Last 30 days'), findsOneWidget);
  });

  testWidgets('a deep link carries its scope', (tester) async {
    final h = await pumpShell(
      tester,
      path: '/tills?branchId=${SeedIds.heliopolis}&preset=yesterday',
    );
    expect(h.container.read(scopeProvider).branchId, SeedIds.heliopolis);
    expect(h.container.read(scopeProvider).preset, ScopePreset.yesterday);
  });

  testWidgets('theme: Light / Dark / System, remembered', (tester) async {
    final h = await pumpShell(tester);
    await h.tap(labelled('Toggle theme'));
    await h.shot('scope/theme-menu');
    await h.tapText('Dark');
    expect(h.prefs.values[themePrefKey], 'dark');
    final ctx = tester.element(find.byType(DashSidebar));
    expect(Theme.of(ctx).brightness, Brightness.dark);
  });

  testWidgets('language: one tap to Arabic, right to left, remembered', (
    tester,
  ) async {
    final h = await pumpShell(tester);
    await h.tap(labelled('Switch language'));
    expect(h.container.read(localeProvider), 'ar');
    expect(h.prefs.values[languagePrefKey], 'ar');
    expect(text('الطلبات'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.byType(DashSidebar))),
      TextDirection.rtl,
    );
  });

  testWidgets('the user menu: who, language, theme, sign out', (tester) async {
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
    testWidgets('picks a shop: org header, its branches, its modules', (
      tester,
    ) async {
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

    testWidgets(
      'switching shop drops the branch (the "Branch not found" bug)',
      (tester) async {
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
      },
    );
  });

  testWidgets('a stored branch of another org is dropped at start', (
    tester,
  ) async {
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

  testWidgets('a stored branch this org no longer has heals to all branches', (
    tester,
  ) async {
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

  testWidgets('signing out forgets the scope', (tester) async {
    final h = await pumpShell(tester);
    await pickBranch(h, 'All branches', 'Zamalek');
    await h.tap(labelled('Account'));
    await h.tapText('Sign Out');
    expect(h.prefs.values[ScopePrefKeys.branch], isNull);
    expect(h.session.branchId, isNull);
  });
}
