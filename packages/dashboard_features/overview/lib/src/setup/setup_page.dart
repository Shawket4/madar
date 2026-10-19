/// `/setup` (web `features/setup/setup-page.tsx`): can this shop sell yet,
/// and what exactly stops it. Everything on it is the server's readiness
/// answer; each row opens the real page that fixes it. After the first sale
/// it stays as the shop's health page.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Readiness, ReadinessCheck;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'check_row.dart';
import 'checks.dart';
import 'setup_hero.dart';
import 'tablet_sheet.dart';

class SetupPage extends ConsumerWidget {
  const SetupPage({super.key});

  static const String path = '/setup';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final orgId = ref.watch(orgIdProvider);
    final q = orgId == null ? null : ref.watch(readinessProvider(orgId));
    final r = q?.value;
    final stage = r == null ? null : stageOf(r);
    final live = stage == SetupStage.live;

    final Widget body;
    if (orgId == null) {
      body = DashEmptyState(icon: 'store', title: t('scope.pickOrg'));
    } else if (r == null && (q?.hasError ?? false)) {
      body = DashErrorState(
        onRetry: () => ref.invalidate(readinessProvider(orgId)),
      );
    } else if (r == null) {
      body = const _Loading();
    } else if (stage == SetupStage.none) {
      final dawam = ref.watch(orgModulesProvider).has(OrgModule.dawam);
      body = DashEmptyState(
        icon: 'store',
        title: t('setup.noPos.title'),
        description: t('setup.noPos.body'),
        action: dawam
            ? DashButton(
                label: t('setup.noPos.cta'),
                variant: DashButtonVariant.outline,
                to: '/staff/setup',
                onPressed: () => context.go('/staff/setup'),
              )
            : null,
      );
    } else {
      body = _SetupBody(r: r, stage: stage!);
    }
    return DashPageScaffold(
      title: live ? t('setup.healthTitle') : t('setup.title'),
      subtitle: live ? t('setup.healthSubtitle') : t('setup.subtitle'),
      width: DashPageWidth.reading,
      onRefresh: orgId == null
          ? null
          : () => ref.refresh(readinessProvider(orgId).future),
      body: body,
    );
  }
}

class _SetupBody extends ConsumerWidget {
  const _SetupBody({required this.r, required this.stage});
  final Readiness r;
  final SetupStage stage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final shop = ref.watch(currentOrgProvider).value?.name ?? '';
    final must = blockingChecks(r);
    // Open advice first; what is already fine sits quietly underneath.
    final worth = [
      ...adviceChecks(r).where((c) => !c.ok),
      ...adviceChecks(r).where((c) => c.ok),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xxl,
      children: [
        SetupHero(readiness: r, stage: stage, shopName: shop),
        _Section(
          title: t('setup.sellHeading'),
          children: [
            for (final c in must)
              CheckRow(check: c, actions: _rowActions(context, ref, c)),
          ],
        ),
        if (worth.isNotEmpty)
          _Section(
            title: t('setup.worthHeading'),
            children: [for (final c in worth) CheckRow(check: c)],
          ),
      ],
    );
  }

  /// The two checks whose fix starts here rather than on another page.
  List<Widget>? _rowActions(
    BuildContext context,
    WidgetRef ref,
    ReadinessCheck c,
  ) {
    if (c.ok) return null;
    final t = ref.read(tProvider);
    if (c.key == 'tablet') {
      return [
        DashButton(
          label: t.checkAction('tablet'),
          size: DashButtonSize.compact,
          icon: 'tablet',
          onPressed: () => showConnectTablet(context, c),
        ),
      ];
    }
    if (c.key == 'menu') {
      // An empty menu: bring it from Foodics, or build it on the menu page.
      final canImport = ref.read(authzProvider).can(Cap.menuItemsCreate);
      return [
        if (canImport)
          DashButton(
            label: t('menuImport.cardCta'),
            icon: 'file-spreadsheet',
            size: DashButtonSize.compact,
            to: '/menu/import',
            onPressed: () => context.go('/menu/import'),
          ),
        DashButton(
          label: t.checkAction('menu'),
          variant: canImport
              ? DashButtonVariant.outline
              : DashButtonVariant.primary,
          size: DashButtonSize.compact,
          to: '/menu/items',
          onPressed: () => context.go('/menu/items'),
        ),
      ];
    }
    return null;
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.sm,
    children: [
      Semantics(
        header: true,
        child: Text(
          Directionality.of(context) == TextDirection.rtl
              ? title
              : title.toUpperCase(),
          style: DashType.tableHeader.copyWith(
            color: context.madarColors.textMuted,
          ),
        ),
      ),
      const SizedBox(height: Space.xs),
      for (final (i, row) in children.indexed)
        DashEntrance(
          delay: Duration(milliseconds: 40 * i),
          rise: Space.sm,
          child: row,
        ),
    ],
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.md,
    children: [
      const DashSkeleton(height: 220, radius: Radii.sheet),
      for (var i = 0; i < 5; i++)
        const DashSkeleton(height: 72, radius: Radii.card),
    ],
  );
}
