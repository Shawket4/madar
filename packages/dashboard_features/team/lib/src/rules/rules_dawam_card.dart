/// The Dawam rules beside the attendance ladder (`dawam/rules-card.tsx`,
/// TEAM-RUL-030 … 038): overtime off / paid automatically / paid when a
/// manager approves, its day and night rates, the public-holiday rate, the
/// cap on outstanding salary advances, the day a pay period starts, how
/// half-day leave counts, the night window, labour limits that warn and
/// never block, POS-derived coverage, the owner's gender mode, and how a
/// confirmed cover is paid (owner decision D5). Saved with the rest of the
/// page's rules in one request.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'night_range_field.dart';
import 'rules_form.dart';
import 'rules_parts.dart';

/// A branch's cover-pay choice: the business's way, or a mode of its own.
const String coverBusiness = 'business';

/// The keys the tests find the card's fields by.
abstract final class RulesDawamKeys {
  static ValueKey<String> number(String field) =>
      ValueKey('rules-dawam-$field');
  static const ValueKey<String> nightStart = ValueKey('rules-night-start');
  static const ValueKey<String> nightEnd = ValueKey('rules-night-end');
  static ValueKey<String> cover(String value) => ValueKey('rules-cover-$value');
}

/// How each number of the card is typed: its step and unit, and the same
/// range `rulesRequest` enforces (`NUM_FIELDS`).
typedef _NumSpec = ({
  double min,
  double? max,
  double step,
  int decimals,
  String? unit,
});

const Map<String, _NumSpec> _numFields = {
  'otDay': (min: 1, max: null, step: 0.05, decimals: 2, unit: 'x'),
  'otNight': (min: 1, max: null, step: 0.05, decimals: 2, unit: 'x'),
  'holidayMult': (min: 1, max: null, step: 0.25, decimals: 2, unit: 'x'),
  'advanceCap': (min: 0, max: 100, step: 5, decimals: 0, unit: '%'),
  'periodStartDay': (min: 1, max: 28, step: 1, decimals: 0, unit: null),
  'limitDay': (min: 0, max: 168, step: 0.5, decimals: 2, unit: 'h'),
  'limitWeek': (min: 0, max: 168, step: 1, decimals: 2, unit: 'h'),
  'limitPresence': (min: 0, max: 168, step: 0.5, decimals: 2, unit: 'h'),
  'limitRest': (min: 0, max: 168, step: 0.5, decimals: 2, unit: 'h'),
  'limitOtDay': (min: 0, max: 168, step: 0.5, decimals: 2, unit: 'h'),
  'ordersPerStaff': (min: 1, max: null, step: 1, decimals: 0, unit: null),
};

double? _get(DawamRules r, String k) => switch (k) {
  'otDay' => r.otDay,
  'otNight' => r.otNight,
  'holidayMult' => r.holidayMult,
  'advanceCap' => r.advanceCap,
  'periodStartDay' => r.periodStartDay,
  'limitDay' => r.limitDay,
  'limitWeek' => r.limitWeek,
  'limitPresence' => r.limitPresence,
  'limitRest' => r.limitRest,
  'limitOtDay' => r.limitOtDay,
  'ordersPerStaff' => r.ordersPerStaff,
  _ => throw ArgumentError(k),
};

DawamRules _set(DawamRules r, String k, double? v) => switch (k) {
  'otDay' => r.copyWith(otDay: () => v),
  'otNight' => r.copyWith(otNight: () => v),
  'holidayMult' => r.copyWith(holidayMult: () => v),
  'advanceCap' => r.copyWith(advanceCap: () => v),
  'periodStartDay' => r.copyWith(periodStartDay: () => v),
  'limitDay' => r.copyWith(limitDay: () => v),
  'limitWeek' => r.copyWith(limitWeek: () => v),
  'limitPresence' => r.copyWith(limitPresence: () => v),
  'limitRest' => r.copyWith(limitRest: () => v),
  'limitOtDay' => r.copyWith(limitOtDay: () => v),
  'ordersPerStaff' => r.copyWith(ordersPerStaff: () => v),
  _ => throw ArgumentError(k),
};

/// `readOnly`: a manager who may see the rules but not change them
/// (`hr.rules.view`). `branch`: a branch's rules, which never carry the
/// business-only settings (the pay period start, the advance cap, gender
/// mode).
class DawamRulesCard extends StatelessWidget {
  const DawamRulesCard({
    required this.value,
    required this.onChanged,
    required this.t,
    this.canGender = false,
    this.readOnly = false,
    this.branch = false,
    this.coverFollows = false,
    this.onCoverChoice,
    super.key,
  });

  final DawamRules value;
  final ValueChanged<DawamRules> onChanged;
  final Translator t;
  final bool canGender;
  final bool readOnly;
  final bool branch;

  /// A branch: whether it pays covers the business's way (no override of
  /// its own).
  final bool coverFollows;

  /// A branch's choice: [coverBusiness], or a mode of its own.
  final ValueChanged<String>? onCoverChoice;

  @override
  Widget build(BuildContext context) {
    final f = context.dashFormats;
    final wide = rulesSm(context);

    Widget num(String k, String label, [String? hint]) {
      final spec = _numFields[k]!;
      return RulesLabeled(
        label: label,
        child: DashNumberInput(
          key: RulesDawamKeys.number(k),
          value: _get(value, k),
          onChanged: (v) => onChanged(_set(value, k, v)),
          enabled: !readOnly,
          min: spec.min,
          max: spec.max,
          step: spec.step,
          decimals: spec.decimals,
          prefix: spec.unit == 'x' ? '×' : null,
          suffix: spec.unit == '%'
              ? '%'
              : spec.unit == 'h'
              ? t('inputs.unitHour')
              : null,
          hint: hint,
          semanticLabel: label,
        ),
      );
    }

    String rate(double? n) => t(
      'dawam.rateExample',
      args: {'n': n == null ? '—' : jsNum(n)},
    );

    Widget segmented(
      String label,
      String current,
      List<(String, String)> options,
      ValueChanged<String> onPick, {
      bool enabled = true,
    }) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        RulesLabelText(label),
        DashSegmentedControl<String>(
          options: [
            for (final (v, l) in options) DashOption(value: v, label: l),
          ],
          value: current,
          onChanged: onPick,
          enabled: enabled && !readOnly,
          semanticLabel: label,
        ),
      ],
    );

    final nightHint =
        '${rate(value.otNight)} · ${f.time(value.nightStart)} – ${f.time(value.nightEnd)}';

    return RulesCardFrame(
      children: [
        RulesCardHead(
          title: t('dawam.rulesTitle'),
          // Only while it is off: the card never says overtime is off when
          // it is on.
          description:
              '${value.overtimeMode == 'off' ? '${t('dawam.setupOtOff')} ' : ''}'
              '${t('dawam.rulesHintRates')}',
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            segmented(t('dawam.overtime'), value.overtimeMode, [
              ('off', t('dawam.otOff')),
              ('automatic', t('dawam.otAutomatic')),
              ('approval', t('dawam.otApproval')),
            ], (v) => onChanged(value.copyWith(overtimeMode: v))),
            RulesGrid(
              columns: wide ? 3 : 1,
              children: [
                num('otDay', t('dawam.otDay'), rate(value.otDay)),
                num('otNight', t('dawam.otNight'), nightHint),
                num(
                  'holidayMult',
                  t('dawam.holidayRate'),
                  rate(value.holidayMult),
                ),
              ],
            ),
            if (!branch)
              RulesGrid(
                columns: wide ? 2 : 1,
                children: [
                  num(
                    'advanceCap',
                    t('dawam.advanceCap'),
                    t('dawam.advanceCapHint'),
                  ),
                  num(
                    'periodStartDay',
                    t('dawam.periodStartDay'),
                    t('dawam.periodStartDayHint'),
                  ),
                ],
              ),
            segmented(t('dawam.halfDayLeave'), value.halfDay, [
              ('half_shift', t('dawam.halfShift')),
              ('whole_day', t('dawam.wholeDay')),
            ], (v) => onChanged(value.copyWith(halfDay: v))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs + DashMetrics.hair,
              children: [
                NightRangeField(
                  startKey: RulesDawamKeys.nightStart,
                  endKey: RulesDawamKeys.nightEnd,
                  start: value.nightStart,
                  end: value.nightEnd,
                  enabled: !readOnly,
                  onChanged: (s, e) =>
                      onChanged(value.copyWith(nightStart: s, nightEnd: e)),
                  groupLabel: t('dawam.nightWindow'),
                  startLabel: t('dawam.nightStart'),
                  endLabel: t('dawam.nightEnd'),
                  lang: t.lang,
                  sameTimeText: t('inputs.sameTime'),
                  endsNextDayText: t('inputs.endsNextDay'),
                  nextDayShortText: t('inputs.nextDayShort'),
                  longOvernightText: (l) =>
                      t('inputs.longOvernight', args: {'length': l}),
                  didYouMeanText: (time) =>
                      t('inputs.didYouMean', args: {'time': time}),
                ),
                RulesHintText(t('dawam.nightUnconfirmed')),
              ],
            ),
            _CoverPayChoice(
              t: t,
              value: branch && coverFollows ? coverBusiness : value.coverPayMode,
              branch: branch,
              enabled: !readOnly,
              onChanged: (c) {
                if (branch && onCoverChoice != null) {
                  onCoverChoice!(c);
                } else if (c != coverBusiness) {
                  onChanged(value.copyWith(coverPayMode: c));
                }
              },
            ),
          ],
        ),
        RulesCardHead(
          title: t('dawam.limitsTitle'),
          description: t('dawam.limitsHint'),
        ),
        RulesGrid(
          columns: wide ? 3 : 1,
          children: [
            num('limitDay', t('dawam.limitDay')),
            num('limitWeek', t('dawam.limitWeek')),
            num('limitPresence', t('dawam.limitPresence')),
            num('limitRest', t('dawam.limitRest')),
            num('limitOtDay', t('dawam.limitOtDay')),
            num(
              'ordersPerStaff',
              t('dawam.ordersPerStaff'),
              t('dawam.ordersPerStaffHint'),
            ),
          ],
        ),
        if (!branch) ...[
          RulesCardHead(
            title: t('dawam.genderTitle'),
            description: t('dawam.genderHint'),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashSegmentedControl<String>(
              options: [
                DashOption(value: 'off', label: t('dawam.genderOff')),
                DashOption(value: 'soft', label: t('dawam.genderSoft')),
                DashOption(value: 'hard', label: t('dawam.genderHard')),
              ],
              value: value.genderMode,
              onChanged: (v) => onChanged(value.copyWith(genderMode: v)),
              enabled: !readOnly && canGender,
              semanticLabel: t('dawam.genderTitle'),
            ),
          ),
        ],
      ],
    );
  }
}

/// How a confirmed cover is paid (D5): the coverer's plain minute rate
/// (CV-4, the default) or the covered block as a full day; a branch can
/// also follow the business. Each option says what it does.
class _CoverPayChoice extends StatelessWidget {
  const _CoverPayChoice({
    required this.t,
    required this.value,
    required this.onChanged,
    required this.branch,
    required this.enabled,
  });

  final Translator t;
  final String value;
  final ValueChanged<String> onChanged;
  final bool branch;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final options = [
      if (branch)
        (
          coverBusiness,
          t('dawam.coverPayBusiness'),
          t('dawam.coverPayBusinessHint'),
        ),
      (
        coverMinuteRate,
        t('dawam.coverPayMinute'),
        t('dawam.coverPayMinuteHint'),
      ),
      (coverFullBlock, t('dawam.coverPayBlock'), t('dawam.coverPayBlockHint')),
    ];
    final radius = BorderRadius.circular(Radii.sm);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        RulesLabelText(t('dawam.coverPay')),
        Semantics(
          container: true,
          label: t('dawam.coverPay'),
          explicitChildNodes: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              for (final (v, label, hint) in options)
                Semantics(
                  inMutuallyExclusiveGroup: true,
                  child: DashPressable(
                    key: RulesDawamKeys.cover(v),
                    onTap: enabled ? () => onChanged(v) : null,
                    enabled: enabled,
                    isButton: false,
                    checked: v == value,
                    selected: v == value,
                    semanticLabel: '$label. $hint',
                    excludeChildSemantics: true,
                    pressScale: false,
                    builder: (context, s) {
                      final on = v == value;
                      return Opacity(
                        opacity: enabled ? 1 : 0.6,
                        child: Container(
                          constraints: const BoxConstraints(
                            minHeight: DashMetrics.target,
                          ),
                          padding: const EdgeInsets.all(Space.md),
                          foregroundDecoration: dashFocusRing(context, s, radius),
                          decoration: BoxDecoration(
                            color: on
                                ? c.accent.withValues(alpha: 0.05)
                                : s.highlighted
                                ? c.hover
                                : null,
                            borderRadius: radius,
                            border: Border.all(
                              color: on ? c.accent : c.hairline,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                label,
                                style: DashType.bodyMedium.copyWith(
                                  color: c.textPrimary,
                                ),
                              ),
                              Text(
                                hint,
                                style: DashType.small.copyWith(
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
