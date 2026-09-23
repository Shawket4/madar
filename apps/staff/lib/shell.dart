import 'package:design_system/design_system.dart';
import 'package:feature_dawam_clock/feature_dawam_clock.dart';
import 'package:feature_dawam_pay/feature_dawam_pay.dart';
import 'package:feature_dawam_requests/feature_dawam_requests.dart';
import 'package:feature_dawam_schedule/feature_dawam_schedule.dart';
import 'package:feature_dawam_team/feature_dawam_team.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

/// Which tab is in front, and whether a manager is on the Manage side.
class ShellNotifier extends Notifier<({int tab, bool manage})> {
  @override
  ({int tab, bool manage}) build() => (tab: 0, manage: false);

  void select(int tab) => state = (tab: tab, manage: state.manage);
  void toggle() => state = (tab: 0, manage: !state.manage);
}

final shellProvider = NotifierProvider<ShellNotifier, ({int tab, bool manage})>(
  ShellNotifier.new,
);

/// One app for everyone (APP-1): the employee's five tabs, and — for people
/// with manager rights — a Manage side they switch to and back from. The
/// POS's shell: rail on a tablet, bottom tabs on a phone.
class StaffShell extends ConsumerWidget {
  const StaffShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final shell = ref.watch(shellProvider);
    final manage = shell.manage && store.canManage;
    final tabs = manage
        ? <(MadarTab, Widget)>[
            (
              MadarTab(
                label: tr('staff.team'),
                glyph: MadarGlyph.users,
                badge: store.openFlags.length,
              ),
              const TeamTab(),
            ),
            (
              MadarTab(
                label: tr('staff.approvals'),
                glyph: MadarGlyph.inbox,
                badge: store.inbox.length + store.adjInbox.length,
              ),
              const ApprovalsTab(),
            ),
            (
              MadarTab(label: tr('staff.schedule'), glyph: MadarGlyph.grid),
              const ScheduleTab(),
            ),
            if (store.canPayroll)
              (
                MadarTab(
                  label: tr('staff.payroll'),
                  glyph: MadarGlyph.banknote,
                ),
                const PayrollTab(),
              ),
          ]
        : <(MadarTab, Widget)>[
            (
              MadarTab(label: tr('staff.home'), glyph: MadarGlyph.clock),
              const HomeTab(),
            ),
            (
              MadarTab(label: tr('staff.timesheet'), glyph: MadarGlyph.list),
              const TimesheetTab(),
            ),
            (
              MadarTab(
                label: tr('staff.shifts'),
                glyph: MadarGlyph.calendar,
                badge: store.reqs
                    .where(
                      (r) =>
                          r.peer == store.me &&
                          r.status == ReqStatus.awaitingPeer,
                    )
                    .length,
              ),
              const ShiftsTab(),
            ),
            (
              MadarTab(label: tr('staff.requests'), glyph: MadarGlyph.note),
              const RequestsTab(),
            ),
            (
              MadarTab(label: tr('staff.pay'), glyph: MadarGlyph.wallet),
              const PayTab(),
            ),
          ];
    final i = shell.tab.clamp(0, tabs.length - 1);
    final u = store.user;
    // The POS's pattern: one Material under the whole shell, the chrome's
    // colour, so ink and fields inside it have their ancestor.
    return Material(
      color: context.madarColors.chrome,
      child: MadarShellScaffold(
        tabs: [for (final t in tabs) t.$1],
        selectedIndex: i,
        onSelect: ref.read(shellProvider.notifier).select,
        person: MadarPerson(name: name(u), initial: name(u).characters.first),
        onPersonTap: () => _settings(context),
        onMarkTap: () => _settings(context),
        topBar: MadarTopBar(
          title: manage ? tr('staff.dawam_manage') : tr('staff.dawam'),
          subtitle: store.myBranches
              .map((b) => branchName(store, b))
              .join(' · '),
          pill: store.offline || store.queued > 0
              ? MadarOutboxPill(
                  state: store.offline
                      ? OutboxState.offline
                      : OutboxState.queued,
                  label: store.offline
                      ? tr('staff.offline')
                      : tr('staff.queued'),
                  count: store.queued,
                  onTap: store.offline ? null : store.sync,
                )
              : null,
          actions: [
            if (store.canManage)
              _ChromeAction(
                glyph: manage ? MadarGlyph.user : MadarGlyph.users,
                label: manage ? tr('staff.my_view') : tr('staff.manage'),
                onTap: ref.read(shellProvider.notifier).toggle,
              ),
            _ChromeAction(
              glyph: MadarGlyph.bell,
              label: tr('staff.inbox'),
              badge: store.unread,
              onTap: () => _inbox(context, ref),
            ),
          ],
        ),
        body: tabs[i].$2,
      ),
    );
  }

  Future<void> _inbox(BuildContext context, WidgetRef ref) async {
    await showDawamSheet<void>(
      context,
      title: tr('staff.inbox'),
      builder: (ctx, ref, store) => DawamSection(
        tr('staff.notifications'),
        children: [
          for (final n in store.myNotices.take(30))
            MadarListRow.bill(
              title: loc(n),
              meta: '${dayLabel(n.at)} · ${hm(n.at)}',
              rail: n.read ? null : MadarTone.accent,
            ),
        ],
      ),
    );
    ref.read(dawamProvider).readAll();
  }

  Future<void> _settings(BuildContext context) => showDawamSheet<void>(
    context,
    title: name(ProviderScope.containerOf(context).read(dawamProvider).user),
    builder: (ctx, ref, store) {
      final u = store.user;
      final role = switch (u.role) {
        Role.employee => tr('staff.employee'),
        Role.manager => tr('staff.branch_manager'),
        Role.owner => tr('staff.owner'),
      };
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          DawamSection(
            tr('settings.account'),
            children: [
              MadarListRow.nav(
                glyph: MadarGlyph.user,
                title: role,
                meta: store.myBranches
                    .map((b) => branchName(store, b))
                    .join(' · '),
              ),
              MadarListRow.nav(
                glyph: MadarGlyph.phone,
                title: u.phone,
                meta: tr('staff.whatsapp'),
              ),
              MadarListRow.nav(
                glyph: MadarGlyph.lock,
                title: u.device,
                meta: tr('staff.this_phone_since', {
                  'date': u.deviceSince ?? '',
                }),
              ),
            ],
          ),
          // The POS's own appearance controls, shared through the kit.
          MadarSectionHeader(text: tr('settings.appearance')),
          MadarThemePicker(
            value: ref.watch(themeChoiceProvider),
            onChanged: ref.read(themeChoiceProvider.notifier).set,
            light: tr('settings.theme_light'),
            dark: tr('settings.theme_dark'),
            system: tr('settings.theme_system'),
          ),
          MadarSectionHeader(text: tr('settings.language')),
          MadarLanguagePicker(
            value: ref.watch(localeProvider),
            onChanged: (l) {
              Navigator.of(ctx).maybePop();
              ref.read(localeProvider.notifier).set(l);
            },
          ),
          MadarButton(
            label: tr('staff.sign_out'),
            glyph: MadarGlyph.signOut,
            variant: MadarButtonVariant.ghost,
            onTap: () {
              Navigator.of(ctx).maybePop();
              ref.read(shellProvider.notifier).select(0);
              store.signOut();
            },
          ),
        ],
      );
    },
  );
}

/// A 44-point action on the dark chrome, with an optional count badge.
class _ChromeAction extends StatelessWidget {
  const _ChromeAction({
    required this.glyph,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });

  final MadarGlyph glyph;
  final String label;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox.square(
            dimension: 44,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                MadarGlyphIcon(glyph, color: c.onChrome),
                if (badge > 0)
                  PositionedDirectional(
                    top: 2,
                    end: 0,
                    child: MadarBadge(count: badge),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
