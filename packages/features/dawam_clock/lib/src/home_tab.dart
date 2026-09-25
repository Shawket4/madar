import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:staff_core/staff_core.dart';

/// Home: today's shift or shifts, the geofenced punch (CL-2), the check-in
/// window (CL-3), tracking and battery (CL-4, CL-12), covering a no-show
/// (CV-1). On a tablet the day and what's next stand side by side.
///
/// The clock, the elapsed time and the window's state move on their own
/// (06 B9: a 30-second tick), and a fresh reading is taken when Home opens
/// and when the app comes back, so the fence line says where the person
/// really is (06 B4).
class HomeTab extends ConsumerStatefulWidget {
  const HomeTab({super.key});

  @override
  ConsumerState<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends ConsumerState<HomeTab> with WidgetsBindingObserver {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tick?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _locate();
  }

  void _locate() {
    if (mounted) unawaited(ref.read(dawamProvider).noteFix());
  }

  @override
  Widget build(BuildContext context) => _home(context, ref);

  Widget _home(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final c = context.madarColors;
    final u = store.user;
    final mine = store.myNow();
    final active = store.activeShift;
    final covers = store.coverable();
    final upcoming =
        store.shifts
            .where(
              (s) =>
                  s.emp == store.me &&
                  s.date.isAfter(store.today) &&
                  store.isPublished(s),
            )
            .toList()
          ..sort((a, b) => a.startAt.compareTo(b.startAt));

    final today = <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.xs,
        children: [
          Text(
            // English has an afternoon; Arabic says «مساء الخير» from noon.
            tr(
              switch (store.now.hour) {
                < 12 => 'staff.good_morning',
                < 17 => 'staff.good_afternoon',
                _ => 'staff.good_evening',
              },
              {'name': firstName(u)},
            ),
            style: MadarType.h1,
          ),
          Text(
            '${dayLabel(store.now)} · ${hm(store.now)}',
            style: MadarType.body.copyWith(color: c.textSecondary),
          ),
        ],
      ),
      if (!store.rulesSaved)
        NoticeBanner(
          text: tr(
            store.role == Role.owner
                ? 'staff.rules_not_saved_owner'
                : 'staff.rules_not_saved',
          ),
        ),
      if (store.chargePhone)
        NoticeBanner(
          text: tr('staff.battery_at_charge_your_phone_if', {
            'battery': store.battery,
          }),
        ),
      if (store.offline)
        NoticeBanner(
          text: tr('staff.offline_clock_ins_are_saved_on'),
          tone: ChipTone.info,
        ),
      if (mine.isEmpty)
        MadarCard(
          child: EmptyState(
            icon: 'calendar',
            title: tr('staff.no_shift_today_enjoy_your_day'),
          ),
        ),
      for (final s in mine) ShiftCard(s),
      if (active != null) _Tracking(active),
    ];

    final next = <Widget>[
      if (covers.isNotEmpty)
        DawamSection(
          tr('staff.cover_a_colleague'),
          children: [
            for (final s in covers)
              MadarListRow.bill(
                title: tr('staff.hasn_t_clocked_in', {
                  'name': name(store.emp(s.emp ?? '')),
                }),
                meta: '${tplName(s.template)} · ${shiftWindow(s)}',
                rail: MadarTone.warning,
                ctaLabel: tr('staff.cover_action'),
                onCta: () => _confirmCover(context, ref, s),
              ),
          ],
        ),
      DawamSection(
        tr('staff.coming_up'),
        children: [
          for (final s in upcoming.take(5))
            MadarListRow.nav(
              glyph: MadarGlyph.calendar,
              title: dayLabel(s.date),
              meta:
                  '${shiftWindow(s)} · ${tplName(s.template)} · '
                  '${branchName(store, s.template.branch)}',
              trailing: s.changed
                  ? MadarStatusPill.of(
                      tr('staff.changed'),
                      tone: MadarTone.warning,
                    )
                  : null,
            ),
        ],
      ),
    ];

    return MadarLayoutSwitch(
      phone: (_) => DawamPage(children: [...today, ...next]),
      tablet: (_) => MadarContentFrame(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.xl,
          children: [
            Expanded(
              flex: 3,
              child: DawamPage(width: MadarContentWidth.full, children: today),
            ),
            Expanded(
              flex: 2,
              child: DawamPage(width: MadarContentWidth.full, children: next),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmCover(
    BuildContext context,
    WidgetRef ref,
    Shift s,
  ) async {
    final ok = await showMadarConfirm(
      context,
      title: tr('staff.cover_this_shift'),
      body: tr('staff.you_ll_be_clocked_in_now'),
      confirmLabel: tr('staff.cover_action'),
      cancelLabel: tr('staff.not_now'),
    );
    if (ok) {
      await attempt(
        ref,
        () => ref.read(dawamProvider).openCover(s),
        ok: tr('staff.you_re_covering_manager_notified'),
      );
    }
  }
}

/// One shift today: its window, the state it's in, and the punch.
class ShiftCard extends ConsumerWidget {
  const ShiftCard(this.s, {super.key});

  final Shift s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(dawamProvider);
    final c = context.madarColors;
    final tp = s.template;
    final b = store.branches[tp.branch];
    final now = store.now;
    final opens = s.startAt.subtract(Duration(minutes: tp.window));
    // A cover is my own row naming whose shift it covers (CV-7).
    final coverOf = s.coverOf;
    final status = s.outAt != null
        ? MadarStatus(
            tr('staff.done', {'time': hm(s.inAt!), 'time2': hm(s.outAt!)}),
            tone: MadarTone.success,
            glyph: MadarGlyph.check,
          )
        : s.inAt != null
        ? MadarStatus(
            tr('staff.clocked_in_at', {'time': hm(s.inAt!)}),
            tone: MadarTone.success,
          )
        : s.leave != null
        ? MadarStatus(tr('staff.on_leave'))
        : now.isAfter(s.endAt)
        ? MadarStatus(tr('staff.missed'), tone: MadarTone.danger)
        : now.isBefore(opens)
        ? MadarStatus(
            tr('staff.opens_at', {'time': hm(opens)}),
            glyph: MadarGlyph.clock,
          )
        : now.isAfter(s.startAt.add(Duration(minutes: tp.grace)))
        ? MadarStatus(tr('staff.late_clock_in_now'), tone: MadarTone.danger)
        : MadarStatus(tr('staff.open_for_check_in'), tone: MadarTone.accent);
    final canIn = s.inAt == null && s.leave == null && now.isBefore(s.endAt);
    final canOut = s.inAt != null && s.outAt == null;
    final elapsed = s.inAt != null
        ? (s.outAt ?? now).difference(s.inAt!)
        : Duration.zero;
    final length = shiftLength(s);
    final progress = canOut && length > 0
        ? (elapsed.inMinutes / length).clamp(0.0, 1.0)
        : null;

    return MadarCard.column(
      spacing: Space.lg,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                coverOf != null
                    ? tr('staff.covering', {'name': name(store.emp(coverOf))})
                    : '${tplName(tp)}${b == null ? '' : ' · ${loc(b)}'}',
                style: MadarType.label.copyWith(
                  color: c.textMuted,
                  letterSpacing: MadarType.tracking,
                ),
              ),
            ),
            MadarStatusPill(status),
          ],
        ),
        Text(
          shiftWindow(s),
          style: MadarType.h1.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (progress != null) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  '${elapsed.inHours}:'
                  '${(elapsed.inMinutes % 60).toString().padLeft(2, '0')}',
                  style: MadarType.numDisplay.copyWith(color: c.brand),
                  textDirection: TextDirection.ltr,
                ),
              ),
              Text(
                mins(length),
                style: MadarType.bodySm.copyWith(color: c.textMuted),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: progress,
              semanticsLabel: tr('staff.shift_progress'),
              minHeight: 8,
              color: c.brand,
              backgroundColor: c.surfaceAlt,
            ),
          ),
        ],
        if (canIn) ...[
          _FenceLine(store.fenceAt(tp.branch), b == null ? '—' : loc(b)),
          if (!store.alwaysLocation)
            _Check(
              tone: MadarTone.warning,
              glyph: MadarGlyph.wifiOff,
              text: tr('staff.always_location_is_off_you_can'),
            ),
          MadarButton(
            label: tr('staff.clock_in'),
            glyph: MadarGlyph.clock,
            onTap: () => attempt(
              ref,
              () => store.clockIn(s),
              ok: tr('staff.clocked_in_toast', {'time': hm(store.now)}),
            ),
          ),
        ],
        if (canOut)
          MadarButton(
            label: tr('staff.clock_out'),
            glyph: MadarGlyph.signOut,
            variant: MadarButtonVariant.ink,
            onTap: () async {
              final ok = await showMadarConfirm(
                context,
                title: tr('staff.clock_out_now'),
                body: tr('staff.location_tracking_stops_when_you_clock'),
                confirmLabel: tr('staff.clock_out_confirm'),
                cancelLabel: tr('staff.stay'),
              );
              if (ok) {
                await attempt(
                  ref,
                  () => store.clockOut(s),
                  ok: tr('staff.see_you_next_shift'),
                );
              }
            },
          ),
      ],
    );
  }
}

/// Where the phone is against this shift's branch, from a fresh reading
/// (06 B4): the real distance, or "not known yet" — never a made-up
/// "inside".
class _FenceLine extends StatelessWidget {
  const _FenceLine(this.fence, this.branch);

  final Fence fence;
  final String branch;

  @override
  Widget build(BuildContext context) {
    final args = {
      'name': branch,
      'distance': fence.distance ?? 0,
      'radius': fence.radius,
    };
    return switch (fence.state) {
      FenceState.inside => _Check(
        tone: MadarTone.success,
        glyph: MadarGlyph.globe,
        text: tr('staff.fence_inside', args),
      ),
      FenceState.outside => _Check(
        tone: MadarTone.danger,
        glyph: MadarGlyph.globe,
        text: tr('staff.fence_outside', args),
      ),
      FenceState.unknown => _Check(
        tone: MadarTone.warning,
        glyph: MadarGlyph.globe,
        text: tr('staff.fence_unknown'),
      ),
    };
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.tone, required this.glyph, required this.text});

  final MadarTone tone;
  final MadarGlyph glyph;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        MadarGlyphIcon(glyph, color: tone.color(c), size: IconSize.md),
        Expanded(
          child: Text(
            text,
            style: MadarType.bodySm.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// While on shift: are the 15-minute pings running, and the battery.
class _Tracking extends ConsumerWidget {
  const _Tracking(this.s);

  final Shift s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final battery = ref.watch(dawamProvider.select((d) => d.battery));
    final on = !s.trackingOff;
    final c = context.madarColors;
    // The sentence wraps across the row: beside the battery and the pill it
    // was cut to "Location on —…" on a phone (E2E S2).
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: Space.sm,
      children: [
        MadarGlyphIcon(
          on ? MadarGlyph.globe : MadarGlyph.wifiOff,
          color: c.textSecondary,
          size: IconSize.md,
        ),
        Expanded(
          child: Text(
            on
                ? tr('staff.location_on_checked_every_15_min')
                : tr('staff.tracking_off_your_manager_was_told'),
            style: MadarType.bodySm.copyWith(color: c.textSecondary),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: Space.xs,
          children: [
            MadarStatusPill.of(
              on ? tr('staff.tracking_on') : tr('staff.tracking_off'),
              tone: on ? MadarTone.success : MadarTone.warning,
            ),
            Text(
              '$battery%',
              style: MadarType.bodySm.copyWith(color: c.textMuted),
              textDirection: TextDirection.ltr,
            ),
          ],
        ),
      ],
    );
  }
}

/// A shift's own length in minutes: its own times when it has them, never
/// the block's default (a 18:45–22:45 evening is 4 h, not 8), and a cover's
/// own window from the core (M-CV-2: a 20-minute cover is 20 minutes).
int shiftLength(Shift s) => s.endAt.difference(s.startAt).inMinutes;
