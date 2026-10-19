/// "Connect a tablet", the tablet check's fix (web `connect-tablet-dialog.tsx`)
/// in two steps on one screen: put Madar Cashier on the tablet (scan the QR
/// with its camera, or the App Store), then bind it to the branch with an
/// activation code, made on the Devices page (opened on that branch).
library;

import 'package:dashboard_api/dashboard_api.dart' show ReadinessCheck;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../apps/app_tiles.dart';
import '../apps/apps.dart';

Future<void> showConnectTablet(BuildContext context, ReadinessCheck check) =>
    showDashDialog<void>(
      context,
      width: DashMetrics.dialogWide,
      builder: (_) => ConnectTabletSheet(check: check),
    );

class ConnectTabletSheet extends ConsumerWidget {
  const ConnectTabletSheet({required this.check, super.key});
  final ReadinessCheck check;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    // The first branch still without a tablet: the code binds one to it.
    final branch = check.problems
        .where((p) => p.entityType == 'branch')
        .firstOrNull;
    final muted = DashType.meta.copyWith(color: c.textSecondary);
    final router = GoRouter.of(context);

    Future<void> openDevices() async {
      Navigator.of(context).pop();
      if (branch != null) {
        await ref.read(scopeProvider.notifier).setBranch(branch.entityId);
      }
      router.go('/devices');
    }

    return DashSurface(
      title: t('setup.tablet.title'),
      description: branch != null
          ? t('setup.tablet.subtitle', args: {'branch': branch.name})
          : t('setup.tablet.subtitleAny'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          _Step(
            n: 1,
            title: t('setup.tablet.install'),
            child: Wrap(
              spacing: Space.lg,
              runSpacing: Space.md,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const AppQr(MadarApp.cashier, size: 128),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.md,
                    children: [
                      Text(t('setup.tablet.scan'), style: muted),
                      const StoreBadges(MadarApp.cashier),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _Step(
            n: 2,
            title: t('setup.tablet.code'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Text(t('setup.tablet.codeHintDevices'), style: muted),
                DashButton(
                  label: t('setup.tablet.openDevices'),
                  icon: 'tablet',
                  size: DashButtonSize.compact,
                  to: '/devices',
                  onPressed: openDevices,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.child});
  final int n;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.lg,
      children: [
        ExcludeSemantics(
          child: Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
            child: Text(
              '$n',
              style: DashType.smallStrong.copyWith(color: c.textOnAccent),
            ),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: DashType.bodyStrong),
              ),
              child,
            ],
          ),
        ),
      ],
    );
  }
}
