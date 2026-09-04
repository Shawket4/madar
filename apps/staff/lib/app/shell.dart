import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../ui/kit.dart';
import 'providers.dart';

/// Bar height below the safe-area inset (the handoff's 74px).
const double _barHeight = 74;

/// One destination in the bottom bar.
typedef _Tab = ({String path, String icon, String labelKey});

/// The app's two faces.
///
/// An EMPLOYEE gets five tabs about their own working life. A MANAGER — anyone
/// the backend has granted the staff permissions to — gets four about everyone
/// else's. They are different jobs, so they get different bars rather than one
/// bar with half its entries greyed out.
const _employeeTabs = <_Tab>[
  (path: '/', icon: 'house', labelKey: 'nav.home'),
  (path: '/timesheet', icon: 'clock', labelKey: 'nav.timesheet'),
  (path: '/shifts', icon: 'calendar.days', labelKey: 'nav.shifts'),
  (path: '/requests', icon: 'sun.max', labelKey: 'nav.requests'),
  (path: '/payslips', icon: 'receipt', labelKey: 'nav.payslips'),
];

const _managerTabs = <_Tab>[
  (path: '/team', icon: 'person.2', labelKey: 'nav.team'),
  (path: '/approvals', icon: 'tray', labelKey: 'nav.approvals'),
  (path: '/roster', icon: 'person', labelKey: 'nav.roster'),
  (path: '/payroll', icon: 'creditcard', labelKey: 'nav.payroll'),
];

class AppShell extends ConsumerWidget {
  const AppShell({required this.location, required this.child, super.key});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final managing = ref.watch(managerModeProvider);
    final tabs = managing ? _managerTabs : _employeeTabs;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          Expanded(child: child),
          _TabBar(tabs: tabs, location: location),
        ],
      ),
    );
  }
}

class _TabBar extends ConsumerWidget {
  const _TabBar({required this.tabs, required this.location});

  final List<_Tab> tabs;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final t = ref.watch(tProvider);
    final pending = ref.watch(pendingApprovalsCountProvider);

    final index = tabs.indexWhere(
      (tab) =>
          tab.path == '/' ? location == '/' : location.startsWith(tab.path),
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        // A hairline, not a shadow: the bar sits ON the paper, it does not
        // float above it.
        border: Border(top: BorderSide(color: colors.borderLight)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: _barHeight,
          child: Row(
            children: [
              for (var i = 0; i < tabs.length; i++)
                Expanded(
                  child: _TabItem(
                    tab: tabs[i],
                    label: t(tabs[i].labelKey),
                    selected: i == (index < 0 ? 0 : index),
                    // The approvals queue is the one number a manager needs to
                    // see without opening anything.
                    badge: tabs[i].path == '/approvals' && pending > 0
                        ? pending
                        : null,
                    onTap: () => context.go(tabs[i].path),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final _Tab tab;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final tint = selected ? colors.accent : colors.textMuted;

    return TactileScale(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              MadarIcon(tab.icon, tint: tint, size: IconSize.xxl),
              if (badge != null)
                PositionedDirectional(
                  top: -4,
                  end: -8,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: colors.danger,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    alignment: Alignment.center,
                    child: Num(
                      '$badge',
                      style: MadarType.num.copyWith(fontSize: 10),
                      color: colors.textOnAccent,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MadarType.labelSm.copyWith(
              color: tint,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
