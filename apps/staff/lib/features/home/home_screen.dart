import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

import '../../app/providers.dart';
import '../../format.dart';
import '../../platform/location.dart';
import '../../ui/kit.dart';
import 'clock_slider.dart';

/// The one screen this app exists for: a live clock, today's shift, and the
/// slider that starts or ends it.
///
/// Everything shown is decided by the SERVER — whether the slider is live,
/// whether the arrival was late, which branch this is. The screen re-reads
/// `staffToday()` after every punch rather than optimistically flipping its own
/// state, so what the employee sees is what was actually recorded.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _busy = false;
  Timer? _tick;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // One second, for the wall clock and the elapsed counter. Cheap, and the
    // screen is only alive while someone is looking at it.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _punch({required bool checkingIn, String? branchId}) async {
    final t = ref.read(tProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final fix = await ref.read(locationProvider).current();
      if (fix case LocationDenied(:final reason)) {
        messenger.showSnackBar(
          SnackBar(content: Text(t(_locationKey(reason)))),
        );
        return;
      }
      final position = fix as LocationFix;

      final bridge = ref.read(coreProvider).bridge;
      if (checkingIn) {
        if (branchId == null) return;
        await bridge.staffCheckIn(
          branchId: branchId,
          latitude: position.latitude,
          longitude: position.longitude,
        );
        messenger.showSnackBar(SnackBar(content: Text(t('home.checkedIn'))));
      } else {
        await bridge.staffCheckOut(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        messenger.showSnackBar(SnackBar(content: Text(t('home.checkedOut'))));
      }
      await ref.read(todayProvider.notifier).refresh();
    } on MadarError catch (e) {
      // A geofence refusal already names the measured distance in the server's
      // own words. Showing it verbatim tells the employee how far off they are;
      // re-wording it here would throw that away.
      messenger.showSnackBar(
        SnackBar(content: Text(ref.read(coreProvider).bridge.humanMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _locationKey(LocationFailure reason) => switch (reason) {
    LocationFailure.serviceDisabled => 'location.disabled',
    LocationFailure.permissionDenied => 'location.denied',
    LocationFailure.unavailable => 'location.failed',
  };

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final today = ref.watch(todayProvider);
    final name = ref.watch(sessionProvider)?.displayName ?? '';
    final canManage = ref.watch(managerCapableProvider);

    return ColoredBox(
      color: colors.bg,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // OUTSIDE the async switch on purpose: the greeting carries the
            // account menu and the manager toggle, and a failed `today()` must
            // not strand someone with no way to sign out or switch sides.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.lg,
                Space.md,
                Space.lg,
                0,
              ),
              child: _Greeting(name: name, canManage: canManage),
            ),
            Expanded(
              child: today.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.all(Space.xl),
                  child: ErrorState(
                    message: '$e',
                    retryLabel: t('common.retry'),
                    onRetry: () => ref.read(todayProvider.notifier).refresh(),
                  ),
                ),
                data: (view) => RefreshIndicator(
                  color: colors.accent,
                  onRefresh: () async {
                    ref.invalidate(requestsProvider);
                    await ref.read(todayProvider.notifier).refresh();
                  },
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(
                      Space.lg,
                      Space.md,
                      Space.lg,
                      Space.lg,
                    ),
                    children: [
                      _ClockHero(view: view, now: _now),
                      const SizedBox(height: Space.sm + 2),
                      if (view.scheduled.isNotEmpty)
                        _TodayCard(view: view, now: _now),
                      const SizedBox(height: Space.sm + 2),
                      _NextShiftStrip(),
                      const SizedBox(height: Space.lg),
                      _Slider(view: view, busy: _busy, onPunch: _punch),
                      const SizedBox(height: Space.md),
                      _TodayPermissions(businessDate: view.businessDate),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Name, initials, and — for a manager — the switch to the other side.
class _Greeting extends ConsumerWidget {
  const _Greeting({required this.name, required this.canManage});

  final String name;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    return Row(
      children: [
        Expanded(
          child: Text(
            t('home.greeting', {'name': name}),
            style: MadarType.h2.copyWith(color: colors.textPrimary),
          ),
        ),
        if (canManage)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: Space.sm),
            child: TactileScale(
              onTap: () => ref.read(managerModeProvider.notifier).set(true),
              child: IconTile(
                icon: 'person.2',
                size: 40,
                background: colors.accentBg,
                tint: colors.accent,
              ),
            ),
          ),
        // The avatar is the account menu — language and sign-out live behind
        // it, so neither takes a slot in the tab bar it would not earn.
        TactileScale(
          onTap: () => showAccountSheet(context, ref),
          child: InitialsTile(name: name, size: 40),
        ),
      ],
    );
  }
}

/// The hero: live clock, date, duty chip, geofence chip.
class _ClockHero extends ConsumerWidget {
  const _ClockHero({required this.view, required this.now});

  final TodayView view;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final open = view.openRecord;
    final since = open == null ? null : DateTime.tryParse(open.checkInAt);

    return MadarCard(
      radius: Radii.lg,
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Num(
                '${now.hour.toString().padLeft(2, '0')}:'
                '${now.minute.toString().padLeft(2, '0')}',
                style: MadarType.numDisplay,
              ),
              const SizedBox(width: 3),
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Num(
                  now.second.toString().padLeft(2, '0'),
                  style: MadarType.numMd,
                  color: colors.navy,
                ),
              ),
            ],
          ),
          Text(
            formatLongDate(view.businessDate),
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: Space.md),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StatusChip(
              label: since != null
                  ? t('home.onDutySince', {
                      'time': formatClock(open!.checkInAt),
                    })
                  : t('home.offDuty'),
              tone: since != null ? ChipTone.accent : ChipTone.neutral,
              icon: since != null ? 'clock' : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            child: Divider(height: 1, thickness: 1, color: colors.borderLight),
          ),
          // The fence is the SERVER's call at punch time; before that all the
          // app can honestly say is which branch it will try.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: StatusChip(
              label: view.canCheckIn || view.canCheckOut
                  ? t('home.insideFence', {'branch': view.branchName})
                  : view.blockedReason.isNotEmpty
                  ? view.blockedReason
                  : t('home.fenceUnknown'),
              tone: view.canCheckIn || view.canCheckOut
                  ? ChipTone.success
                  : ChipTone.warning,
              icon: 'mappin.and.ellipse',
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's shift window, a progress bar, and three figures.
class _TodayCard extends ConsumerWidget {
  const _TodayCard({required this.view, required this.now});

  final TodayView view;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final shift = view.scheduled.first;
    final start = DateTime.tryParse(shift.scheduledStartAt);
    final end = DateTime.tryParse(shift.scheduledEndAt);
    final scheduled = (start != null && end != null)
        ? end.difference(start).inMinutes
        : 0;

    final open = view.openRecord;
    final since = open == null ? null : DateTime.tryParse(open.checkInAt);
    final elapsed = since == null ? Duration.zero : now.difference(since);
    final worked =
        view.closedRecords.fold<int>(0, (sum, r) => sum + r.workedMinutes) +
        elapsed.inMinutes;
    final overtime = view.closedRecords.fold<int>(
      0,
      (sum, r) => sum + r.overtimeMinutes,
    );

    return MadarCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: FieldLabel(t('home.today'))),
              Num(
                '${formatClock(shift.scheduledStartAt)}–'
                '${formatClock(shift.scheduledEndAt)}',
                style: MadarType.num.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          ProgressBar(fraction: scheduled == 0 ? 0 : worked / scheduled),
          const SizedBox(height: Space.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Figure(
                label: t('home.elapsed'),
                value: since == null ? '0:00' : formatHms(elapsed),
              ),
              _Figure(
                label: t('home.scheduled'),
                value: formatHm(scheduled),
                align: CrossAxisAlignment.center,
              ),
              _Figure(
                label: t('home.overtime'),
                value: formatHm(overtime),
                color: overtime > 0 ? colors.navy : null,
                align: CrossAxisAlignment.end,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.color,
    this.align = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final Color? color;
  final CrossAxisAlignment align;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        FieldLabel(label),
        const SizedBox(height: 2),
        Num(value, style: MadarType.numMd, color: color),
      ],
    );
  }
}

/// The next rostered shift, so the last thing seen before leaving is when to
/// come back.
class _NextShiftStrip extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final today = DateTime.now();
    final range = (
      from: isoDate(today.add(const Duration(days: 1))),
      to: isoDate(today.add(const Duration(days: 8))),
    );

    final next = ref
        .watch(scheduleProvider(range))
        .maybeWhen(
          data: (days) => days.where((d) => d.shifts.isNotEmpty).firstOrNull,
          orElse: () => null,
        );
    if (next == null) return const SizedBox.shrink();
    final shift = next.shifts.first;

    return MadarCard(
      radius: Radii.sm + 2,
      child: Row(
        children: [
          MadarIcon('calendar.days', tint: colors.accent, size: IconSize.lg),
          const SizedBox(width: Space.sm + 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                FieldLabel(t('home.nextShift')),
                Row(
                  children: [
                    Text(
                      formatWeekday(next.date),
                      style: MadarType.bodySm.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: Space.xs),
                    Num(
                      '${formatClock(shift.scheduledStartAt)}–'
                      '${formatClock(shift.scheduledEndAt)}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          MadarIcon('chevron.forward', tint: colors.textMuted),
        ],
      ),
    );
  }
}

class _Slider extends ConsumerWidget {
  const _Slider({
    required this.view,
    required this.busy,
    required this.onPunch,
  });

  final TodayView view;
  final bool busy;
  final void Function({required bool checkingIn, String? branchId}) onPunch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;
    final enabled =
        !busy &&
        (view.canCheckOut || (view.canCheckIn && view.branchId.isNotEmpty));

    return Column(
      children: [
        ClockSlider(
          clockedIn: view.canCheckOut,
          enabled: enabled,
          labelIn: t('home.slideIn'),
          labelOut: t('home.slideOut'),
          onToggle: () => view.canCheckOut
              ? onPunch(checkingIn: false)
              : onPunch(checkingIn: true, branchId: view.branchId),
        ),
        if (!enabled && view.blockedReason.isNotEmpty && !view.canCheckOut) ...[
          const SizedBox(height: Space.sm),
          Text(
            view.blockedReason,
            textAlign: TextAlign.center,
            style: MadarType.labelSm.copyWith(color: colors.warning),
          ),
        ],
      ],
    );
  }
}

/// Today's approved permissions.
///
/// The point is reassurance BEFORE the punch: an employee with an approved
/// 10:00 arrival should be able to see they are not late, rather than clocking
/// in nervously and finding out at payroll.
class _TodayPermissions extends ConsumerWidget {
  const _TodayPermissions({required this.businessDate});

  /// The SERVER's business date (branch timezone). Comparing against the
  /// device's own date would put a night-shift employee on the wrong day.
  final String businessDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final colors = context.madarColors;

    final covering = ref
        .watch(requestsProvider)
        .maybeWhen(
          data: (rows) => rows.where((r) {
            if (r.status != 'approved') return false;
            final end = r.endDate.isEmpty ? r.onDate : r.endDate;
            return r.onDate.compareTo(businessDate) <= 0 &&
                end.compareTo(businessDate) >= 0;
          }).toList(),
          orElse: () => const <StaffRequestView>[],
        );
    if (covering.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(t('home.permissionsToday')),
        const SizedBox(height: Space.sm),
        for (final r in covering)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: MadarCard(
              color: colors.accentBg,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm + 2,
              ),
              child: Row(
                children: [
                  MadarIcon(
                    requestKindIcon(r.kind),
                    tint: colors.accent,
                    size: IconSize.lg,
                  ),
                  const SizedBox(width: Space.sm + 2),
                  Expanded(
                    child: Text(
                      t('kind.${r.kind}'),
                      style: MadarType.body.copyWith(
                        color: colors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Num(requestWindow(r), color: colors.accent),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Icon per request kind. Shared with the requests screen.
String requestKindIcon(String kind) => switch (kind) {
  'late_arrival' => 'clock',
  'early_departure' => 'rectangle.portrait.and.arrow.right',
  'excuse' => 'timer',
  'mission' => 'briefcase',
  'correction' => 'pencil',
  _ => 'sun.max',
};

/// The window a request covers, as a bare number string.
String requestWindow(StaffRequestView r) => switch (r.kind) {
  'late_arrival' => r.toTime,
  'early_departure' => r.fromTime,
  'excuse' => '${r.fromTime}–${r.toTime}',
  _ =>
    r.endDate.isNotEmpty && r.endDate != r.onDate
        ? '${r.onDate} → ${r.endDate}'
        : r.onDate,
};

/// Language and sign-out. Reached from the avatar on either side of the app.
Future<void> showAccountSheet(BuildContext context, WidgetRef ref) {
  final t = ref.read(tProvider);
  final locale = ref.read(localeProvider);
  return showMadarSheet<void>(
    context,
    builder: (sheetContext) {
      final colors = sheetContext.madarColors;
      return Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              ref.read(sessionProvider)?.displayName ?? '',
              style: MadarType.h3.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: Space.lg),
            SecondaryButton(
              // Labelled in the language it switches TO, so it reads as an
              // offer rather than a statement of where you already are.
              label: locale == 'ar' ? 'English' : 'العربية',
              onPressed: () {
                ref.read(localeProvider.notifier).toggle();
                Navigator.of(sheetContext).pop();
              },
            ),
            const SizedBox(height: Space.sm),
            SecondaryButton(
              label: t('common.signOut'),
              icon: 'rectangle.portrait.and.arrow.right',
              tone: colors.danger,
              onPressed: () {
                Navigator.of(sheetContext).pop();
                ref.read(sessionProvider.notifier).signOut();
              },
            ),
          ],
        ),
      );
    },
  );
}
