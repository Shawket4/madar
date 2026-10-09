/// `staff.attendance` page: the port of the web's staff/attendance-page.tsx
/// `AttendancePage`; TEAM-ATT rows (+ the area-wide TEAM-ALL rows it
/// carries). No in-page guard (TEAM-ALL-007): the reads 403 into the
/// table's error state and the cards' "—".
///
/// The window (last 7 days by default), one person or everyone, a status,
/// the scope bar's branch; the headline cards from the per-employee summary;
/// what the words mean; the records with each punch on its own branch's
/// clock; Add record and Correct (`attendance_dialogs.dart`); the Excel
/// export of the window.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show AttendanceRecord, AttendanceSummary, Branch, Employee;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show publicBrandProvider;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../employees/employees_providers.dart' show employeesListProvider;
import '../shared/attendance_errors.dart';
import '../shared/refresh_button.dart';
import '../shared/refresh_toast.dart';
import '../shared/staff_query.dart';
import '../shared/team_format.dart';
import '../shared/team_util.dart';
import '../shared/week.dart' show addDays;
import 'attendance_data.dart';
import 'attendance_dialogs.dart';
import 'attendance_providers.dart';

/// `listEmployees()` with no filter: everyone, every status (the picker).
const _everyone = (status: null, departmentId: null);

/// The picker's "Everyone" (`ALL`).
const String _all = '__all__';

abstract final class AttendanceMetrics {
  /// The date range's cap (`max-w-md`).
  static const double range = 448;

  /// The employee picker (`w-52`).
  static const double picker = 208;

  /// The status select (`w-40`).
  static const double status = 160;

  /// The picker row sits level with the date fields, under their labels
  /// (`sm:pt-[1.625rem]`).
  static const double labelRow = Space.lg + Space.sm + DashMetrics.hair;
}

class AttendancePage extends ConsumerStatefulWidget {
  const AttendancePage({super.key});

  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  late String _from;
  late String _to;
  String? _status;
  String? _person;
  bool _exporting = false;
  late final AppLifecycleListener _lifecycle;
  DateTime? _loadedAt;

  @override
  void initState() {
    super.initState();
    // The last 7 days on the active zone's calendar (TEAM-ALL-012).
    _from = teamTodayIsoOf(ref, -6);
    _to = teamTodayIsoOf(ref);
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  AttendanceQuery _keyFor(String? branchId) => (
    from: _from,
    to: _to,
    branchId: branchId,
    status: _status,
    employeeId: _person,
  );

  /// Warms the rows and the cards a filter option would show.
  void _warm(AttendanceQuery k) => ref
    ..warm(attendanceListProvider(k))
    ..warm(attendanceSummaryProvider(k));

  AttendanceQuery get _key =>
      _keyFor(ref.read(scopeProvider.select((s) => s.branchId)));

  /// Refetch on focus (`dawamQuery`): back after the reads went stale (30 s)
  /// asks again; sooner does nothing.
  void _onResume() {
    final at = _loadedAt;
    if (at == null || !mounted) return;
    final now = ref.read(clockProvider)();
    if (now.difference(at) < kQueryStaleTime) return;
    _loadedAt = now;
    ref
      ..invalidate(attendanceListProvider(_key))
      ..invalidate(attendanceSummaryProvider(_key))
      ..invalidate(employeesListProvider(_everyone));
  }

  String _err(Object? e) =>
      attendanceErrorText(e, ref.read(tProvider), ref.read(formatProvider));

  /// TEAM-ATT-021 / TEAM-ALL-024: the page's query again, as an export.
  Future<void> _export() async {
    final t = ref.read(tProvider);
    final exporter = ref.read(exporterProvider);
    final transport = ref.read(transportProvider);
    final brand = ref.read(publicBrandProvider).value;
    final key = _key;
    setState(() => _exporting = true);
    try {
      final rows = await exportAttendance(transport, key);
      if (!mounted) return;
      if (rows.isEmpty) {
        DashToast.error(context, const ExportNothing().message(t));
        return;
      }
      final toast = DashToast.loading(context, t('excel.generating'));
      final outcome = await exporter.exportToExcel(
        attendanceExcel(
          t,
          rows: rows,
          from: key.from,
          to: key.to,
          status: key.status,
          logoUrl: brand != null && brand.customBranding ? brand.logoUrl : null,
        ),
      );
      toast.update(
        outcome is ExportDone ? DashToastKind.success : DashToastKind.error,
        outcome.message(t),
      );
      Future<void>.delayed(DashToast.duration, toast.dismiss);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, _err(e));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final authz = ref.watch(authzProvider);
    // The server checks each at the record's branch; a person without them
    // is never offered the button (TEAM-ATT-022).
    final canAdd = authz.can(Cap.hrAttendanceCreate);
    final canCorrect = authz.can(Cap.hrAttendanceEdit);
    final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
    final key = _keyFor(branchId);
    final recordsQ = ref.watch(attendanceListProvider(key));
    final summaryQ = ref.watch(attendanceSummaryProvider(key));
    final employeesQ = ref.watch(employeesListProvider(_everyone));
    final settingsQ = ref.watch(staffAttendanceSettingsProvider);
    final branches = ref.watch(branchesProvider).value ?? const <Branch>[];
    listenStaffRefreshFailure(ref, context, attendanceListProvider(key));
    listenStaffRefreshFailure(ref, context, attendanceSummaryProvider(key));
    listenStaffRefreshFailure(ref, context, employeesListProvider(_everyone));
    listenStaffRefreshFailure(ref, context, staffAttendanceSettingsProvider);
    ref.listen(attendanceListProvider(key), (_, next) {
      if (next.hasValue && !next.isLoading) {
        _loadedAt = ref.read(clockProvider)();
      }
    });
    if (recordsQ.hasValue) _loadedAt ??= ref.read(clockProvider)();

    final records = recordsQ.value ?? const <AttendanceRecord>[];
    final day = settingsQ.value?.periodStartDay;
    // As the server (pay::period_window): a start day past 28 is the 28th.
    final periodStartDay = (day ?? 1).clamp(1, 28);
    // Each punch reads on its own branch's clock, also under All branches.
    final zones = {
      for (final b in branches) b.id: b.timezone.isEmpty ? null : b.timezone,
    };

    return DashPageScaffold(
      title: t('staff.attendance'),
      subtitle: t('staff.attendanceSubtitle'),
      actions: [
        DawamRefreshButton(
          busy: anyFetching([recordsQ, summaryQ, employeesQ, settingsQ]),
        ),
        DashExportButton(
          onExport: _export,
          loading: _exporting,
          enabled: records.isNotEmpty,
        ),
        if (canAdd)
          DashButton(
            label: t('staff.addRecord'),
            icon: 'plus',
            // The add dialog's reads: who, their shifts, and the 40 days
            // ahead of today (its first date).
            onIntent: () {
              final d = teamTodayIsoOf(ref);
              ref
                ..warm(staffActiveEmployeesProvider)
                ..warm(staffWorkShiftsProvider)
                ..warm(
                  attendanceListProvider(attendanceWindow(d, addDays(d, 40))),
                );
            },
            onPressed: () => showAttendanceAddDialog(context, branchId),
          ),
      ],
      filters: _Filters(
        from: _from,
        to: _to,
        periodStartDay: periodStartDay,
        person: _person,
        status: _status,
        employees: employeesQ.value ?? const <Employee>[],
        onRange: (from, to) => setState(() {
          _from = from;
          _to = to;
        }),
        onPerson: (v) => setState(() => _person = v),
        onStatus: (v) => setState(() => _status = v),
        onPersonIntent: (v) => _warm((
          from: _from,
          to: _to,
          branchId: branchId,
          status: _status,
          employeeId: v,
        )),
        onStatusIntent: (v) => _warm((
          from: _from,
          to: _to,
          branchId: branchId,
          status: v,
          employeeId: _person,
        )),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          _StatCards(summary: summaryQ),
          const _AttendanceWords(),
          DashDataTable<AttendanceRecord>(
            columns: _columns(context, records, zones),
            rows: records,
            rowKey: (r) => r.id,
            loading: recordsQ.awaitingFirst,
            // A failed refresh replaces the rows (the web's table takes the
            // raw query error, TEAM-ALL-010); the cards keep their figures.
            // An attempt Riverpod will retry is still loading.
            errorMessage: recordsQ.hasError && !recordsQ.retrying
                ? _err(recordsQ.error)
                : null,
            onRetry: () => ref.invalidate(attendanceListProvider(key)),
            searchPlaceholder: t('staff.searchEmployees'),
            rowActions: canCorrect
                ? (context, r) => r.monthClosed == true
                      ? const SizedBox.shrink()
                      : DashIconButton(
                          icon: 'pencil-line',
                          semanticLabel: t('staff.correct'),
                          onPressed: () =>
                              showAttendanceCorrectDialog(context, r, key),
                        )
                : null,
            empty: DashEmptyState(
              icon: 'calendar-clock',
              title: t('staff.noAttendance'),
              description: t('staff.noAttendanceHint'),
            ),
          ),
        ],
      ),
    );
  }

  List<DashColumn<AttendanceRecord>> _columns(
    BuildContext context,
    List<AttendanceRecord> records,
    Map<String, String?> zones,
  ) {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final c = context.madarColors;
    final muted = DashType.small.copyWith(color: c.textSecondary);
    final warn = DashType.mono.copyWith(color: DashTone.warning.foreground(c));
    String? zoneOf(AttendanceRecord r) => zones[r.branchId];

    Widget punch(
      DateTime? at,
      AttendanceRecord r,
      List<Widget> badges,
      String? reason,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DashMetrics.hair,
      children: [
        Wrap(
          spacing: Space.xs + DashMetrics.hair,
          runSpacing: DashMetrics.hair,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(at == null ? '—' : f.fmtDateTime(at, zoneOf(r))),
            ...badges,
          ],
        ),
        // Its own line under the punch, wrapping whole on a narrow card.
        if (reason != null && reason.isNotEmpty)
          Tooltip(
            message: reason,
            child: Text(reason, style: muted),
          ),
      ],
    );

    Widget method(String? m) {
      final text = punchMethodText(t, m);
      return text.isEmpty ? const SizedBox.shrink() : _OutlineBadge(text);
    }

    // `text` is what the web's search reads (the accessor: the name, the ISO
    // date and the status KEY); `cell` is what shows (TEAM-ATT-039).
    return [
      DashColumn(
        id: 'name',
        label: t('staff.name'),
        phone: DashPhoneRole.title,
        flex: 2,
        minWidth: 120,
        text: (r) => r.employeeName ?? '',
        cell: (context, r) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            MadarClippedText(
              r.employeeName ?? '—',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.bodyMedium.copyWith(color: c.textPrimary),
            ),
            MadarClippedText(
              r.workShiftName ?? t('staff.unscheduled'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: muted,
            ),
          ],
        ),
      ),
      DashColumn(
        id: 'date',
        label: t('staff.date'),
        numeric: true,
        align: DashAlign.start,
        minWidth: 120,
        text: (r) => r.businessDate,
        cell: (context, r) => MadarClippedText(
          f.fmtDate(r.businessDate),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      DashColumn(
        id: 'status',
        label: t('staff.attendanceStatus'),
        minWidth: 136,
        text: (r) => r.status,
        cell: (context, r) {
          final coverer = recordCoverer(records, r);
          return Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DashStatusPill(
                tone: attendanceStatusTone[r.status] ?? DashTone.neutral,
                label: attendanceStatusText(t, r.status),
              ),
              // Its month is approved or paid: the server refuses a
              // correction (PERIOD_CLOSED).
              if (r.monthClosed == true) _OutlineBadge(t('staff.monthClosed')),
              // A colleague covers this shift: no punch goes on it (D1).
              if (coverer != null)
                _OutlineBadge(t('dawam.coveredBy', args: {'name': coverer})),
            ],
          );
        },
      ),
      DashColumn(
        id: 'in',
        label: t('staff.checkIn'),
        numeric: true,
        align: DashAlign.start,
        flex: 2,
        minWidth: 160,
        searchable: false,
        cell: (context, r) => punch(r.checkInAt, r, [
          method(r.checkInMethod),
          if (r.checkInDistanceMeters != null)
            Tooltip(
              message: t('staff.distanceFromBranch'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: DashMetrics.hair,
                children: [
                  DashIcon(
                    'map-pin',
                    size: IconSize.xs - DashMetrics.hair,
                    color: c.textSecondary,
                  ),
                  Text(
                    t(
                      'staff.metres',
                      args: {
                        'n': f.fmtNumber(r.checkInDistanceMeters!.round()),
                      },
                    ),
                    style: muted,
                  ),
                ],
              ),
            ),
        ], r.punchReason),
      ),
      DashColumn(
        id: 'out',
        label: t('staff.checkOut'),
        numeric: true,
        align: DashAlign.start,
        flex: 2,
        minWidth: 160,
        searchable: false,
        cell: (context, r) => punch(r.checkOutAt, r, [
          if (r.checkOutMethod == 'auto')
            DashBadge(t('staff.autoClosed'))
          else
            method(r.checkOutMethod),
        ], r.checkOutReason),
      ),
      DashColumn(
        id: 'worked',
        label: t('staff.worked'),
        numeric: true,
        minWidth: 96,
        searchable: false,
        text: (r) => fmtMinutes(f, r.workedMinutes),
      ),
      DashColumn(
        // Late and left early in one column: both are time charged against
        // the shift, each with what it is measured from (the branch clock).
        id: 'late',
        label: t('dawamOps.lateEarly'),
        numeric: true,
        minWidth: 168,
        searchable: false,
        cell: (context, r) {
          if (r.lateMinutes <= 0 && r.earlyLeaveMinutes <= 0) {
            return const Text('—');
          }
          Widget line(int minutes, DateTime? at, String key) => Wrap(
            spacing: Space.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(fmtMinutes(f, minutes), style: warn),
              if (at != null)
                Text(
                  t(key, args: {'time': f.fmtTime(at, zoneOf(r))}),
                  style: muted,
                ),
            ],
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            spacing: DashMetrics.hair,
            children: [
              if (r.lateMinutes > 0)
                line(r.lateMinutes, r.scheduledStartAt, 'dawamOps.lateAfter'),
              if (r.earlyLeaveMinutes > 0)
                line(
                  r.earlyLeaveMinutes,
                  r.scheduledEndAt,
                  'dawamOps.earlyBefore',
                ),
            ],
          );
        },
      ),
      DashColumn(
        id: 'overtime',
        label: t('staff.overtime'),
        numeric: true,
        minWidth: 88,
        searchable: false,
        cell: (context, r) => r.overtimeMinutes > 0
            ? Text(
                fmtMinutes(f, r.overtimeMinutes),
                style: DashType.mono.copyWith(
                  color: DashTone.success.foreground(c),
                ),
              )
            : const Text('—'),
      ),
    ];
  }
}

/// The window, the person and the status (the header's `below`).
class _Filters extends ConsumerWidget {
  const _Filters({
    required this.from,
    required this.to,
    required this.periodStartDay,
    required this.person,
    required this.status,
    required this.employees,
    required this.onRange,
    required this.onPerson,
    required this.onStatus,
    required this.onPersonIntent,
    required this.onStatusIntent,
  });

  final String from;
  final String to;
  final int periodStartDay;
  final String? person;
  final String? status;
  final List<Employee> employees;
  final void Function(String from, String to) onRange;
  final ValueChanged<String?> onPerson;
  final ValueChanged<String?> onStatus;

  /// Warm the window a person / status option would show (null: all).
  final ValueChanged<String?> onPersonIntent;
  final ValueChanged<String?> onStatusIntent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    return LayoutBuilder(
      builder: (context, box) {
        // Level with the date fields only when beside them (the web pads
        // it at >= sm even once it has wrapped under them).
        final beside =
            wide &&
            box.maxWidth >=
                AttendanceMetrics.range +
                    AttendanceMetrics.picker +
                    AttendanceMetrics.status +
                    Space.md * 2;
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.sm,
          children: [
            SizedBox(
              width: box.maxWidth < AttendanceMetrics.range
                  ? box.maxWidth
                  : AttendanceMetrics.range,
              child: DashDateRangeField(
                from: dashParseYmd(from),
                to: dashParseYmd(to),
                today: dashParseYmd(teamTodayIsoOf(ref)),
                quick: const [
                  DashQuickRange.thisWeek,
                  DashQuickRange.lastWeek,
                  DashQuickRange.thisPeriod,
                  DashQuickRange.lastPeriod,
                ],
                periodStartDay: periodStartDay,
                fromLabel: t('staff.from'),
                toLabel: t('staff.to'),
                onChanged: (f, to) => onRange(
                  f == null ? from : dashYmd(f),
                  to == null ? this.to : dashYmd(to),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                top: beside ? AttendanceMetrics.labelRow : 0,
              ),
              child: Wrap(
                spacing: Space.md,
                runSpacing: Space.md,
                children: [
                  DashSelect<String>(
                    semanticLabel: t('staff.employee'),
                    sheetTitle: t('staff.employee'),
                    width: AttendanceMetrics.picker,
                    expand: false,
                    searchable: true,
                    searchPlaceholder: t('inputs.searchName'),
                    emptyText: t('inputs.noOneMatches'),
                    placeholder: t('inputs.pickEmployee'),
                    active: person != null,
                    value: person ?? _all,
                    options: [
                      DashOption(value: _all, label: t('dawamOps.everyone')),
                      for (final e in employees)
                        DashOption(value: e.id, label: e.name),
                    ],
                    onChanged: (v) => onPerson(v == _all ? null : v),
                    onOptionIntent: (v) => onPersonIntent(v == _all ? null : v),
                  ),
                  DashFilterSelect<String>(
                    label: t('staff.attendanceStatus'),
                    allLabel: t('staff.allStatuses'),
                    minWidth: AttendanceMetrics.status,
                    value: status,
                    options: [
                      for (final s in attendanceStatuses)
                        DashOption(value: s, label: attendanceStatusText(t, s)),
                    ],
                    onChanged: onStatus,
                    onOptionIntent: onStatusIntent,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// TEAM-ATT-007/008: the window's headline, summed over the summary; a
/// failed summary has no counts: a dash, never a reassuring 0.
class _StatCards extends ConsumerWidget {
  const _StatCards({required this.summary});

  final AsyncValue<List<AttendanceSummary>> summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final loading = summary.awaitingFirst;
    final failed = summary.failedFirst;
    final totals = attendanceTotals(summary.value ?? const []);
    final cols = MediaQuery.sizeOf(context).width >= DashBreakpoints.lg ? 4 : 2;
    final cards = [
      ('calendar-check', t('staff.presentDays'), totals.present),
      ('alarm-clock', t('staff.lateDays'), totals.late),
      ('calendar-x', t('staff.absentDays'), totals.absent),
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - Space.md * (cols - 1)) / cols;
        return Wrap(
          spacing: Space.md,
          runSpacing: Space.md,
          children: [
            for (final (icon, label, n) in cards)
              SizedBox(
                width: w,
                child: DashStatCard(
                  icon: icon,
                  label: label,
                  loading: loading,
                  value: failed ? null : n,
                  valueText: failed ? '—' : null,
                ),
              ),
            SizedBox(
              width: w,
              child: DashStatCard(
                icon: 'timer',
                label: t('staff.overtime'),
                loading: loading,
                valueText: failed ? '—' : fmtHours(lang, totals.overtime),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// TEAM-ATT-009: what late, left early and absent mean, said once above the
/// rows that use them; closed until tapped (`<details>`).
class _AttendanceWords extends ConsumerStatefulWidget {
  const _AttendanceWords();

  @override
  ConsumerState<_AttendanceWords> createState() => _AttendanceWordsState();
}

class _AttendanceWordsState extends ConsumerState<_AttendanceWords> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final words = [
      (t('staff.late'), t('dawamOps.wordLate')),
      (t('dawamOps.leftEarly'), t('dawamOps.wordEarly')),
      (t('staff.att_absent'), t('dawamOps.wordAbsent')),
      (t('staff.att_half_day'), t('dawamOps.wordHalf')),
    ];
    final term = DashType.bodyMedium.copyWith(color: c.textPrimary);
    final def = DashType.body.copyWith(color: c.textSecondary);
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: c.hairline),
      ),
      padding: const EdgeInsets.symmetric(horizontal: Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DashPressable(
            onTap: () => setState(() => _open = !_open),
            semanticLabel: t('dawamOps.wordsTitle'),
            expanded: _open,
            excludeChildSemantics: true,
            pressScale: false,
            builder: (context, s) => SizedBox(
              height: DashMetrics.target,
              child: Row(
                spacing: Space.sm,
                children: [
                  DashIcon('info', size: IconSize.sm, color: c.textSecondary),
                  Flexible(child: Text(t('dawamOps.wordsTitle'), style: term)),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: wide
                  ? Table(
                      columnWidths: const {
                        0: IntrinsicColumnWidth(),
                        1: FlexColumnWidth(),
                      },
                      children: [
                        for (final (word, meaning) in words)
                          TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: Space.lg,
                                  bottom: Space.xs + DashMetrics.hair,
                                ),
                                child: Text(word, style: term),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(
                                  bottom: Space.xs + DashMetrics.hair,
                                ),
                                child: Text(meaning, style: def),
                              ),
                            ],
                          ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Space.xs + DashMetrics.hair,
                      children: [
                        for (final (word, meaning) in words) ...[
                          Text(word, style: term),
                          Text(meaning, style: def),
                        ],
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

/// The web's `<Badge variant="outline">`: a hairline pill.
class _OutlineBadge extends StatelessWidget {
  const _OutlineBadge(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: c.hairline),
      ),
      child: Text(
        label,
        style: DashType.smallMedium.copyWith(color: c.textPrimary),
      ),
    );
  }
}
