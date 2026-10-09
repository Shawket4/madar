/// `dawam.schedule` page: the port of the web's dawam/schedule-page.tsx
/// `SchedulePage`; TEAM-SCH rows (+ TEAM-ALL-011 Saturday-first weeks and
/// TEAM-ALL-016 the rules-first banner).
///
/// One branch's dated week: the standing pattern fills it (edited on Work
/// shifts); here a manager changes single days, posts open shifts, accepts
/// or rejects the week's suggestions, sees the public holidays (the owner
/// decides them) and publishes the week so staff see it. Labour-limit
/// warnings sit on the person and day and never block; coverage needs are
/// typed per hour; the owner sees who works the nights.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Branch, DecideSuggestion, HolidayDecision, HolidayView, OpenShift, PostOpenShift, PublishWeek, RosterView, Suggestion, WorkShiftBrief;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashRoutePrefetch;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/attendance_errors.dart';
import '../shared/page_gate.dart';
import '../shared/refresh_button.dart';
import '../shared/rules_banner.dart';
import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import '../shared/week.dart';
import 'coverage_card.dart';
import 'day_editor.dart';
import 'fairness_card.dart';
import 'preferences_dialog.dart';
import 'refresh_listener.dart';
import 'schedule_data.dart';
import 'schedule_grid.dart';
import 'schedule_providers.dart';
import 'schedule_week_bar.dart';

/// The branch select (`w-44`).
const double _branchSelectWidth = 176;

/// The suggestions skeleton (`h-20`).
const double _suggestionsSkeleton = Space.xxl * 2 + Space.lg;

class SchedulePage extends ConsumerWidget {
  const SchedulePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => TeamPageGate(
    allowed: (a) => a.can(Cap.hrScheduleRead),
    titleKey: 'dawam.schedule',
    whoKey: 'dawam.scheduleNoAccess',
    child: const ScheduleView(),
  );
}

class ScheduleView extends ConsumerStatefulWidget {
  const ScheduleView({super.key});

  @override
  ConsumerState<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends ConsumerState<ScheduleView> {
  late String _week = weekStartOf(teamTodayIsoOf(ref));
  String? _picked;
  bool _showCoverage = false;

  /// The page action in flight: `publish`, `open|<id>`, `open|<date>`,
  /// `g|<id>`, `h|<date>`.
  String? _busy;
  late final AppLifecycleListener _lifecycle;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  /// The branch on show: the scope bar's, else the page's own pick, else the
  /// first branch (TEAM-SCH-004).
  String? _branchOf(String? scoped, List<Branch>? branches) =>
      scoped ??
      _picked ??
      (branches == null || branches.isEmpty ? null : branches.first.id);

  RosterKey _weekKey(String branch) =>
      (branchId: branch, from: _week, to: addDays(_week, 6));

  RosterKey _upcomingKey(String branch) => (
    branchId: branch,
    from: teamTodayIsoOf(ref),
    to: teamTodayIsoOf(ref, 45),
  );

  /// Refetch on focus (`dawamQuery`): back after the reads went stale (30 s)
  /// asks again; sooner does nothing. The coverage editor does not opt in.
  void _onResume() {
    final at = _loadedAt;
    if (at == null || !mounted) return;
    final now = ref.read(clockProvider)();
    if (now.difference(at) < kQueryStaleTime) return;
    _loadedAt = now;
    final branch = _branchOf(
      ref.read(scopeProvider).branchId,
      ref.read(branchesProvider).value,
    );
    if (branch == null) return;
    ref
      ..invalidate(scheduleRosterProvider(_weekKey(branch)))
      ..invalidate(scheduleRosterProvider(_upcomingKey(branch)))
      ..invalidate(
        scheduleSuggestionsProvider((branchId: branch, weekStart: _week)),
      )
      ..invalidate(scheduleFairnessProvider(monthOf(_week)))
      ..invalidate(scheduleFairnessAuditsProvider);
  }

  /// Warms what showing [week] at [branch] reads (a week stepper's intent).
  void _warmWeek(String branch, String week) {
    final authz = ref.read(authzProvider);
    ref.warm(
      scheduleRosterProvider((
        branchId: branch,
        from: week,
        to: addDays(week, 6),
      )),
    );
    if (authz.can(Cap.hrScheduleEdit)) {
      ref.warm(
        scheduleSuggestionsProvider((branchId: branch, weekStart: week)),
      );
    }
    if (authz.can(Cap.hrRosterSettings)) {
      ref.warm(scheduleFairnessProvider(monthOf(week)));
    }
  }

  /// Warms what picking [branch] reads (the branch select's intent).
  void _warmBranch(String branch) {
    _warmWeek(branch, _week);
    ref.warm(scheduleRosterProvider(_upcomingKey(branch)));
  }

  String _err(Object? e) =>
      attendanceErrorText(e, ref.read(tProvider), ref.read(formatProvider));

  /// The page's one runner (TEAM-SCH-026): the action's own button waits,
  /// success toasts and refreshes `/staff`, a refusal toasts its words.
  Future<void> _run(String key, Future<void> Function() fn, String ok) async {
    final staff = ref.read(staffRevisionsProvider.notifier);
    setState(() => _busy = key);
    try {
      await fn();
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(context, _err(e));
        setState(() => _busy = null);
      }
      return;
    }
    staff.invalidateStaff();
    if (!mounted) return;
    DashToast.success(context, ok);
    setState(() => _busy = null);
  }

  Future<void> _publish(String branch) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final api = ref.read(apiProvider);
    final week = _week;
    final ok = await showDashConfirm(
      context,
      title: t('dawam.publishTitle', args: {'from': f.fmtDate(week)}),
      description: t('dawam.publishHint'),
      confirmLabel: t('dawam.publish'),
    );
    if (!ok || !mounted) return;
    await _run(
      'publish',
      () => api.staff.publish(
        body: PublishWeek(branchId: branch, weekStart: week),
      ),
      t('dawam.published'),
    );
  }

  Future<void> _cancelOpen(OpenShift o) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final api = ref.read(apiProvider);
    final args = {'shift': o.shiftName, 'date': f.fmtDate(o.onDate)};
    final ok = await showDashConfirm(
      context,
      title: t('dawam.cancelOpenTitle', args: args),
      description: o.claimedByName != null
          ? t('dawam.cancelOpenClaimed', args: {'name': o.claimedByName})
          : t('dawam.cancelOpenHint'),
      confirmLabel: t('dawam.cancelOpen'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(
      'open|${o.id}',
      () => api.staff.cancelOpenShift(id: o.id),
      t('dawam.openCancelled'),
    );
  }

  Future<void> _postOpen(
    String branch,
    String date,
    WorkShiftBrief block,
    bool published,
  ) {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    return _run(
      'open|$date',
      () => api.staff.postOpenShift(
        body: PostOpenShift(
          branchId: branch,
          onDate: date,
          workShiftId: block.id,
        ),
      ),
      // Staff can't see or claim it until the week is published (H2-D3).
      published ? t('dawam.openPosted') : t('dawam.openPostedUnpublished'),
    );
  }

  /// A pattern suggestion changes the person's standing week: said first.
  Future<void> _decide(String branch, Suggestion g, bool accept) async {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    if (accept && g.id.startsWith('pattern|')) {
      final ok = await showDashConfirm(
        context,
        title: t('dawam.patternTitle', args: {'name': g.employeeName}),
        description: t('dawam.patternHint'),
        confirmLabel: t('dawam.accept'),
      );
      if (!ok || !mounted) return;
    }
    await _run(
      'g|${g.id}',
      () => api.staff.decideSuggestion(
        body: DecideSuggestion(branchId: branch, id: g.id, accept: accept),
      ),
      accept ? t('dawam.suggestionAccepted') : t('dawam.suggestionRejected'),
    );
  }

  Future<void> _decideHoliday(HolidayView h, String decision) {
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider);
    return _run(
      'h|${h.onDate}',
      () async {
        await api.staff.decideHoliday(
          date: h.onDate,
          body: HolidayDecision(decision: decision),
        );
      },
      decision == 'holiday' ? t('dawam.holidaySet') : t('dawam.holidayDismissed'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final authz = ref.watch(authzProvider);
    final canRead = authz.can(Cap.hrScheduleRead);
    final canEdit = authz.can(Cap.hrScheduleEdit);
    final canPublish = authz.can(Cap.hrSchedulePublish);
    final canSettings = authz.can(Cap.hrRosterSettings);
    final canStaffEdit = authz.can(Cap.hrStaffEdit);
    // Public holidays are the owner's, like the rules (D3).
    final canDecideHoliday = authz.canEverywhere(Cap.hrRulesEdit);
    final scoped = ref.watch(scopeProvider.select((s) => s.branchId));
    final branchesQ = ref.watch(branchesProvider);
    final branches = branchesQ.value;
    final branch = canRead ? _branchOf(scoped, branches) : null;
    final today = teamTodayIsoOf(ref);
    final days = weekDays(_week);

    final weekKey = branch == null ? null : _weekKey(branch);
    final upKey = branch == null ? null : _upcomingKey(branch);
    final sgKey = branch == null || !canEdit
        ? null
        : (branchId: branch, weekStart: _week);
    final rosterQ = weekKey == null
        ? const AsyncValue<RosterView>.loading()
        : ref.watch(scheduleRosterProvider(weekKey));
    final upcomingQ = upKey == null
        ? null
        : ref.watch(scheduleRosterProvider(upKey));
    final suggestionsQ = sgKey == null
        ? null
        : ref.watch(scheduleSuggestionsProvider(sgKey));
    if (rosterQ.hasValue) _loadedAt ??= ref.read(clockProvider)();

    final view = rosterQ.value;
    final published = view?.publishedWeeks.contains(_week) ?? false;
    final index = RosterIndex(view, branch ?? '');
    final branchNames = {for (final b in branches ?? const <Branch>[]) b.id: b.name};
    final holidays = mergeHolidays(upcomingQ?.value?.holidays, view?.holidays);

    final actions = <Widget>[
      DawamRefreshButton(
        busy: anyFetching([
          if (weekKey != null) rosterQ,
          ?upcomingQ,
          ?suggestionsQ,
        ]),
      ),
      if (canEdit)
        Semantics(
          toggled: _showCoverage,
          child: DashButton(
          label: t('dawam.coverageTitle'),
          icon: 'grid-3x3',
          variant: _showCoverage
              ? DashButtonVariant.secondary
              : DashButtonVariant.outline,
          semanticLabel: t('dawam.coverageTitle'),
          onIntent: _showCoverage || branch == null
              ? null
              : () => ref.warm(scheduleCoverageProvider(branch)),
          onPressed: () => setState(() => _showCoverage = !_showCoverage),
          key: const Key('schedule-coverage-toggle'),
        ),
        ),
      if (scoped == null && (branches?.length ?? 0) > 1)
        SizedBox(
          width: _branchSelectWidth,
          child: DashSelect<String>(
            key: const Key('schedule-branch'),
            value: branch,
            semanticLabel: t('dawam.branch'),
            options: [
              for (final b in branches!)
                DashOption(value: b.id, label: b.name),
            ],
            onOptionIntent: _warmBranch,
            onChanged: (v) => setState(() => _picked = v),
          ),
        ),
    ];

    Widget main;
    if (branch == null && branchesQ.failedFirst) {
      // With no branch the roster never loads: say why (H2-D2).
      main = DashErrorState(
        title: t('dawam.branchesLoadError'),
        message: _err(branchesQ.error),
        retryLabel: t('common.retry'),
        retrying: branchesQ.isLoading,
        onRetry: () => ref.invalidate(branchesProvider),
      );
    } else if (branch == null && branches != null) {
      main = DashEmptyState(
        icon: 'calendar-check',
        title: t('dawam.noBranchYet'),
      );
    } else if (rosterQ.failedFirst) {
      main = DashErrorState(
        title: t('staff.rosterLoadError'),
        message: _err(rosterQ.error),
        retryLabel: t('common.retry'),
        retrying: rosterQ.isLoading,
        onRetry: () => ref.invalidate(scheduleRosterProvider(weekKey!)),
      );
    } else if (view == null) {
      main = const DashSkeleton(
        key: Key('schedule-skeleton'),
        height: ScheduleMetrics.skeleton,
        radius: Radii.card,
      );
    } else if (view.staff.isEmpty) {
      main = DashEmptyState(
        icon: 'users-round',
        title: t('staff.noEmployeesYet'),
        description: t('dawamOps.noStaffHint'),
        action: DashButton(
          label: t('dawamOps.openEmployees'),
          variant: DashButtonVariant.outline,
          size: DashButtonSize.compact,
          onIntent: () => ref.prefetchRoute('/staff/employees'),
          onPressed: () => context.go('/staff/employees'),
        ),
      );
    } else {
      main = ScheduleGrid(
        view: view,
        index: index,
        days: days,
        today: today,
        branchId: branch!,
        branchNames: branchNames,
        canEdit: canEdit,
        busy: _busy,
        onOpenDay: (p, d) => showDayEditor(
          context,
          key: weekKey!,
          person: p,
          date: d,
        ),
        onPrefs: (p) => showPreferencesDialog(
          context,
          key: weekKey!,
          person: p,
          canEdit: canStaffEdit,
        ),
        onCancelOpen: _cancelOpen,
        onPostOpen: (d, b) => _postOpen(branch, d, b, published),
      );
    }

    final note = DashType.body.copyWith(color: c.textSecondary);
    Widget body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          const RulesFirstBanner(),
          if (branch != null)
            ScheduleWeekBar(
              week: _week,
              today: today,
              onWeek: (w) => setState(() => _week = w),
              onWeekIntent: (w) => _warmWeek(branch, w),
              published: published,
              canPublish: canPublish,
              publishing: _busy == 'publish',
              ready: view != null,
              changedCount: index.changedDays,
              onPublish: () => _publish(branch),
            ),
          if (view != null && view.staff.isNotEmpty)
            _Note(
              icon: 'repeat',
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: t('dawamOps.patternNote')),
                    if (canEdit) ...[
                      const TextSpan(text: ' '),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.baseline,
                        baseline: TextBaseline.alphabetic,
                        child: _Link(
                          label: t('dawamOps.editPattern'),
                          onIntent: () => ref.prefetchRoute('/staff/shifts'),
                          onTap: () => context.go('/staff/shifts'),
                        ),
                      ),
                    ],
                  ],
                ),
                style: note,
              ),
            ),
          if (view != null && view.staff.isNotEmpty && index.templates.isEmpty)
            _NoBlocksBanner(
              onOpen: () => context.go('/staff/shifts'),
              onIntent: () => ref.prefetchRoute('/staff/shifts'),
            ),
          if (canEdit && _showCoverage && branch != null)
            CoverageCard(branchId: branch),
          if (view != null && view.warnings.isNotEmpty)
            _Note(
              icon: 'triangle-alert',
              iconColor: DashTone.warning.foreground(c),
              child: Text(
                view.limitsUnconfirmed
                    ? t('dawam.warningsUnconfirmed')
                    : t('dawam.warningsNote'),
                style: note,
              ),
            ),
          main,
          if (canEdit && suggestionsQ != null)
            _Suggestions(
              q: suggestionsQ,
              busy: _busy,
              onRetry: () => ref.invalidate(scheduleSuggestionsProvider(sgKey!)),
              onDecide: (g, accept) => _decide(branch!, g, accept),
              err: _err,
            ),
          if (holidays.isNotEmpty)
            _Holidays(
              holidays: holidays,
              canDecide: canDecideHoliday,
              busy: _busy,
              onDecide: _decideHoliday,
            ),
          if (canSettings) FairnessCard(month: monthOf(_week)),
        ],
    );
    // Failed refreshes toast (TEAM-ALL-022); each read subscribed once.
    body = ScheduleRefreshListener<RosterView>(
      read: weekKey == null ? null : scheduleRosterProvider(weekKey),
      onAnswer: () => _loadedAt = ref.read(clockProvider)(),
      child: ScheduleRefreshListener<RosterView>(
        read: upKey == null ? null : scheduleRosterProvider(upKey),
        child: ScheduleRefreshListener<List<Suggestion>>(
          read: sgKey == null ? null : scheduleSuggestionsProvider(sgKey),
          child: body,
        ),
      ),
    );
    return DashPageScaffold(
      title: t('dawam.schedule'),
      subtitle: t('dawam.scheduleSubtitle'),
      actions: actions,
      body: body,
    );
  }
}

/// A muted line with its glyph (the pattern note, the warnings note).
class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.child, this.iconColor});

  final String icon;
  final Widget child;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    spacing: Space.sm,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: DashMetrics.hair),
        child: DashIcon(
          icon,
          size: IconSize.xs,
          color: iconColor ?? context.madarColors.textSecondary,
        ),
      ),
      Expanded(child: child),
    ],
  );
}

/// An underlined in-text link (`font-medium text-foreground underline`).
class _Link extends StatelessWidget {
  const _Link({required this.label, required this.onTap, this.onIntent});

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onIntent;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      onIntent: onIntent,
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Text(
        label,
        style: DashType.bodyMedium.copyWith(
          color: c.textPrimary,
          decoration: s.hovered ? TextDecoration.none : TextDecoration.underline,
        ),
      ),
    );
  }
}

/// No work shifts for this branch yet (TEAM-SCH-012).
class _NoBlocksBanner extends ConsumerWidget {
  const _NoBlocksBanner({required this.onOpen, required this.onIntent});

  final VoidCallback onOpen;
  final VoidCallback onIntent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    const tone = DashTone.warning;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: tone.wash(c),
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: tone.solid(c).withValues(alpha: 0.4)),
        ),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: t('dawamOps.noBlocksTitle'),
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  const TextSpan(text: ' '),
                  TextSpan(text: t('dawamOps.noBlocksHint')),
                ],
              ),
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
            DashButton(
              label: t('dawamOps.openWorkShifts'),
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              onIntent: onIntent,
              onPressed: onOpen,
            ),
          ],
        ),
      ),
    );
  }
}

/// A section's small heading with its glyph (`h2 text-sm text-muted`).
class ScheduleSectionTitle extends StatelessWidget {
  const ScheduleSectionTitle({
    required this.icon,
    required this.title,
    super.key,
  });

  final String icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Semantics(
      header: true,
      child: Row(
        spacing: Space.sm,
        children: [
          DashIcon(icon, size: IconSize.xs, color: c.textSecondary),
          Flexible(
            child: Text(
              title,
              style: DashType.smallStrong.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A list row whose trailing controls wrap under the words on a phone
/// (`ListRow` with a trailing slot).
class ScheduleListRow extends StatelessWidget {
  const ScheduleListRow({
    required this.icon,
    required this.title,
    required this.meta,
    required this.trailing,
    super.key,
  });

  final String icon;
  final String title;
  final String meta;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final phone = DashBreakpoints.isPhone(context);
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: DashType.bodyStrong.copyWith(color: c.textPrimary),
        ),
        Text(meta, style: DashType.meta.copyWith(color: c.textSecondary)),
      ],
    );
    final glyph = Container(
      width: Space.xxl + Space.xs,
      height: Space.xxl + Space.xs,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: DashIcon(icon, size: IconSize.sm, color: c.textSecondary),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: phone ? Space.lg : Space.card,
        vertical: Space.sm + DashMetrics.hair,
      ),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.sm,
              children: [
                Row(
                  spacing: Space.md,
                  children: [glyph, Expanded(child: words)],
                ),
                Align(alignment: AlignmentDirectional.centerEnd, child: trailing),
              ],
            )
          : Row(
              spacing: Space.md,
              children: [glyph, Expanded(child: words), trailing],
            ),
    );
  }
}

class _Suggestions extends ConsumerWidget {
  const _Suggestions({
    required this.q,
    required this.busy,
    required this.onRetry,
    required this.onDecide,
    required this.err,
  });

  final AsyncValue<List<Suggestion>> q;
  final String? busy;
  final VoidCallback onRetry;
  final void Function(Suggestion g, bool accept) onDecide;
  final String Function(Object? e) err;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final list = q.value ?? const <Suggestion>[];
    Widget body;
    if (q.failedFirst) {
      // A failed read is not "nothing to suggest" (H2-D1).
      body = DashErrorState(
        title: t('dawam.suggestionsLoadError'),
        message: err(q.error),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: onRetry,
      );
    } else if (q.awaitingFirst || !q.hasValue) {
      body = const DashSkeleton(
        height: _suggestionsSkeleton,
        radius: Radii.card,
      );
    } else if (list.isEmpty) {
      body = Text(
        t('dawam.noSuggestions'),
        style: DashType.body.copyWith(color: c.textSecondary),
      );
    } else {
      body = DashListCard(
        children: [
          for (final g in list)
            () {
              final args = <String, Object?>{
                if (g.reasonArgs case final Map<String, Object?> m) ...m,
              };
              final key = g.reasonKey.replaceFirst(RegExp(r'^staff\.'), 'dawam.');
              final why = t.exists(key) ? t(key, args: args) : g.reasonKey;
              final wait = busy == 'g|${g.id}';
              return ScheduleListRow(
                key: ValueKey('suggestion-${g.id}'),
                icon: 'sparkles',
                title: g.fromEmployeeName != null
                    ? '${g.employeeName} ↔ ${g.fromEmployeeName}'
                    : '${g.employeeName} → ${g.shiftName}',
                meta: [
                  f.fmtDate(g.date),
                  why,
                  if (g.byDefault) t('dawam.byDefault'),
                ].join(' · '),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: Space.xs,
                  children: [
                    DashBadge(ltr('${g.confidence}%'), mono: true),
                    DashButton(
                      label: t('dawam.accept'),
                      variant: DashButtonVariant.outline,
                      size: DashButtonSize.compact,
                      onPressed: wait ? null : () => onDecide(g, true),
                    ),
                    DashButton(
                      label: t('common.reject'),
                      variant: DashButtonVariant.ghost,
                      size: DashButtonSize.compact,
                      onPressed: wait ? null : () => onDecide(g, false),
                    ),
                  ],
                ),
              );
            }(),
        ],
      );
    }
    return Column(
      key: const Key('schedule-suggestions'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        ScheduleSectionTitle(icon: 'sparkles', title: t('dawam.suggestions')),
        body,
      ],
    );
  }
}

class _Holidays extends ConsumerWidget {
  const _Holidays({
    required this.holidays,
    required this.canDecide,
    required this.busy,
    required this.onDecide,
  });

  final List<HolidayView> holidays;
  final bool canDecide;
  final String? busy;
  final void Function(HolidayView h, String decision) onDecide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    return Column(
      key: const Key('schedule-holidays'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        ScheduleSectionTitle(icon: 'party-popper', title: t('dawam.holidays')),
        if (!canDecide)
          Text(
            t('dawam.holidaysOwnerOnly'),
            style: DashType.body.copyWith(color: c.textSecondary),
          ),
        DashListCard(
          children: [
            for (final h in holidays)
              ScheduleListRow(
                key: ValueKey('holiday-${h.onDate}'),
                icon: 'party-popper',
                title: t.lang == 'ar' ? h.nameAr : h.nameEn,
                meta: t('dawam.holidayHint', args: {'date': f.fmtDate(h.onDate)}),
                trailing: h.decision != null
                    ? DashStatusPill(
                        label: h.decision == 'holiday'
                            ? t('dawam.holidayDecided')
                            : t('dawam.normalDay'),
                        tone: h.decision == 'holiday'
                            ? DashTone.info
                            : DashTone.neutral,
                      )
                    : !canDecide
                    ? DashStatusPill(
                        label: t('dawam.holidayUndecided'),
                        tone: DashTone.warning,
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: Space.xs,
                        children: [
                          DashButton(
                            label: t('dawam.makeHoliday'),
                            variant: DashButtonVariant.outline,
                            size: DashButtonSize.compact,
                            onPressed: busy == 'h|${h.onDate}'
                                ? null
                                : () => onDecide(h, 'holiday'),
                          ),
                          DashButton(
                            label: t('dawam.normalDay'),
                            variant: DashButtonVariant.ghost,
                            size: DashButtonSize.compact,
                            onPressed: busy == 'h|${h.onDate}'
                                ? null
                                : () => onDecide(h, 'dismissed'),
                          ),
                        ],
                      ),
              ),
          ],
        ),
      ],
    );
  }
}
