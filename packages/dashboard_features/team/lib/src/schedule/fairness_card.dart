/// Owner only (`dawam/fairness-card.tsx`, TEAM-SCH-065…067): who works the
/// nights, by gender, against who said they want them, for the business and
/// branch by branch (each with its gap flag and learning state), and the
/// kept monthly audits. The server computes every figure.
library;

import 'package:dashboard_api/dashboard_api.dart' show FairnessAudit;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/attendance_errors.dart';
import '../shared/refresh_toast.dart';
import 'schedule_providers.dart';

/// The table skeleton (`h-24`).
const double _skeleton = Space.xxl * 3;

class FairnessCard extends ConsumerWidget {
  const FairnessCard({required this.month, super.key});

  /// `YYYY-MM-01`: the viewed week's Saturday's month.
  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final q = ref.watch(scheduleFairnessProvider(month));
    final auditsQ = ref.watch(scheduleFairnessAuditsProvider);
    listenStaffRefreshFailure(ref, context, scheduleFairnessProvider(month));
    listenStaffRefreshFailure(ref, context, scheduleFairnessAuditsProvider);
    final v = q.value;
    final muted = DashType.body.copyWith(color: c.textSecondary);
    final error = DashType.body.copyWith(color: c.errorText);
    final head = DashType.smallStrong.copyWith(color: c.textSecondary);
    final cell = DashType.body.copyWith(color: c.textPrimary);
    String gender(String? g) => g == 'm'
        ? t('dawam.gender_m')
        : g == 'f'
        ? t('dawam.gender_f')
        : t('dawam.notSet');

    TableRow headRow(List<String> labels) => TableRow(
      children: [
        for (final (i, l) in labels.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs),
            child: Text(
              l,
              textAlign: i == 0 ? TextAlign.start : TextAlign.end,
              style: head,
            ),
          ),
      ],
    );
    TableRow bodyRow(List<Widget> cells) => TableRow(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      children: [
        for (final (i, w) in cells.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.xs + 2),
            child: Align(
              alignment: i == 0
                  ? AlignmentDirectional.centerStart
                  : AlignmentDirectional.centerEnd,
              child: w,
            ),
          ),
      ],
    );
    Widget n(Object v) => Text(ltr('$v'), style: cell);
    Widget sectionTitle(String s) =>
        Semantics(header: true, child: Text(s, style: head));

    final List<Widget> figures;
    if (q.failedFirst) {
      figures = [Text(attendanceErrorText(q.error, t, f), style: error)];
    } else if (v == null) {
      figures = [const DashSkeleton(height: _skeleton)];
    } else {
      figures = [
        Table(
          key: const Key('fairness-genders'),
          columnWidths: const {0: FlexColumnWidth(1.4)},
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            headRow([
              t('dawam.gender'),
              t('dawam.people'),
              t('dawam.willing'),
              t('dawam.shifts'),
              t('dawam.nightShifts'),
            ]),
            for (final r in v.rows)
              bodyRow([
                Text(gender(r.gender), style: cell),
                n(r.people),
                n(r.willing),
                n(r.shifts),
                n(r.nightShifts),
              ]),
          ],
        ),
        Text(
          [
            t(
              'dawam.fairnessDecided',
              args: {'accepted': v.accepted4w, 'decided': v.decided4w},
            ),
            if (v.learningFrozen) t('dawam.learningFrozen'),
          ].join(' '),
          style: muted,
        ),
        if (v.branches.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.xs + 2,
            children: [
              sectionTitle(t('dawam.byBranch')),
              Semantics(
                container: true,
                label: t('dawam.byBranch'),
                explicitChildNodes: true,
                child: Table(
                  key: const Key('fairness-branches'),
                  columnWidths: const {
                    0: FlexColumnWidth(1.4),
                    4: FlexColumnWidth(1.6),
                  },
                  defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                  children: [
                    headRow([
                      t('dawam.branch'),
                      t('dawam.gapPoints'),
                      t('dawam.accepted'),
                      t('dawam.byDefaultDecided'),
                      '',
                    ]),
                    for (final b in v.branches)
                      bodyRow([
                        Text(b.branchName, style: cell),
                        n(b.gapPoints),
                        n('${b.accepted}/${b.decided}'),
                        n(b.byDefaultDecided),
                        Semantics(
                          label: t('dawam.state'),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: Space.xs,
                            runSpacing: Space.xs,
                            children: [
                              if (b.flagged)
                                DashStatusPill(
                                  label: t('dawam.flagged'),
                                  tone: DashTone.danger,
                                  small: true,
                                ),
                              if (b.learningFrozen)
                                DashStatusPill(
                                  label: t('dawam.frozen'),
                                  tone: DashTone.warning,
                                  small: true,
                                ),
                            ],
                          ),
                        ),
                      ]),
                  ],
                ),
              ),
            ],
          ),
      ];
    }

    final audits = auditsQ.value ?? const <FairnessAudit>[];
    final Widget auditBody;
    if (auditsQ.failedFirst) {
      auditBody = Text(attendanceErrorText(auditsQ.error, t, f), style: error);
    } else if (!auditsQ.hasValue) {
      auditBody = const DashSkeleton(height: Space.xxl);
    } else if (audits.isEmpty) {
      auditBody = Text(t('dawam.noAudits'), style: muted);
    } else {
      auditBody = Semantics(
        container: true,
        label: t('dawam.audits'),
        explicitChildNodes: true,
        child: Column(
          key: const Key('fairness-audits'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final a in audits)
              Container(
                padding: const EdgeInsets.symmetric(vertical: Space.xs + 2),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.hairline)),
                ),
                child: Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      a.report.branchName,
                      style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                    ),
                    Text(f.fmtDate(a.month), style: muted),
                    Text(
                      t('dawam.gapOf', args: {'n': a.report.gapPoints}),
                      style: muted,
                    ),
                    if (a.flagged)
                      DashStatusPill(
                        label: t('dawam.flagged'),
                        tone: DashTone.danger,
                        small: true,
                      )
                    else
                      DashStatusPill(
                        label: t('dawam.fair'),
                        tone: DashTone.success,
                        small: true,
                      ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return DashCard(
      key: const Key('fairness-card'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.xs + 2,
            children: [
              Semantics(
                header: true,
                child: Row(
                  spacing: Space.sm,
                  children: [
                    DashIcon('scale', size: IconSize.xs, color: c.textPrimary),
                    Flexible(
                      child: Text(
                        t('dawam.fairnessTitle'),
                        style: DashType.sectionTitle.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Text(t('dawam.fairnessHint'), style: muted),
            ],
          ),
          ...figures,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.xs + 2,
            children: [sectionTitle(t('dawam.audits')), auditBody],
          ),
        ],
      ),
    );
  }
}
