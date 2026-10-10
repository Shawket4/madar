/// "Try the ladder" (`staff/rules-preview-card.tsx`, TEAM-RUL-020/021): the
/// late ladder read back as money. Pick how late someone was and an example
/// salary; the card says which rung that lands on and what it docks, worked
/// out the way payroll does (`rules_preview.dart`). Every rung also gets a
/// worked example, so "0.25 of a day" is never left as arithmetic to do.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../shared/team_format.dart';
import 'rules_form.dart';
import 'rules_parts.dart';
import 'rules_preview.dart';

/// The keys the tests find the preview's fields by.
abstract final class RulesPreviewKeys {
  static const ValueKey<String> late = ValueKey('rules-preview-late');
  static const ValueKey<String> salary = ValueKey('rules-preview-salary');
  static const ValueKey<String> shift = ValueKey('rules-preview-shift');
  static const ValueKey<String> result = ValueKey('rules-preview-result');
  static ValueKey<String> sample(int i) => ValueKey('rules-preview-sample-$i');
}

class RulesPreviewCard extends StatefulWidget {
  const RulesPreviewCard({
    required this.tiers,
    required this.example,
    required this.onExample,
    required this.t,
    required this.f,
    super.key,
  });

  final List<RuleTier> tiers;
  final PayExample example;
  final ValueChanged<PayExample> onExample;
  final Translator t;
  final DashFormat f;

  @override
  State<RulesPreviewCard> createState() => _RulesPreviewCardState();
}

class _RulesPreviewCardState extends State<RulesPreviewCard> {
  double? _late = 20;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = widget.t;
    final f = widget.f;
    final tiers = widget.tiers;
    final example = widget.example;
    final late = _late;
    final minutes = late != null && late.isFinite ? late : 0.0;
    final tier = selectTier(tiers, minutes);
    final amount = tier == null ? 0 : tierPiastres(tier, example);
    final index = tier == null ? -1 : tiers.indexOf(tier);
    // One sample per rung: its first minute, so each row reads "from here,
    // this".
    final samples = [
      for (final r in tiers)
        r.from.isNaN ? double.nan : (r.from < 1 ? 1.0 : r.from),
    ];
    final unitMin = t('inputs.unitMin');
    final unitHour = t('inputs.unitHour');

    String presetLabel(double p) =>
        p >= 60 ? formatSpan(p, t.lang) : '${jsNum(p)} $unitMin';

    final lateField = RulesLabeled(
      label: t('staff.previewLate'),
      child: DashNumberInput(
        key: RulesPreviewKeys.late,
        value: late,
        onChanged: (v) => setState(() => _late = v),
        max: 1440,
        step: 5,
        decimals: 0,
        stepper: true,
        center: true,
        suffix: unitMin,
        unitWord: unitMin,
        presets: const [5, 20, 45, 90],
        presetLabel: presetLabel,
        hint: late != null && late.isFinite && late >= 60
            ? '= ${formatSpan(late, t.lang)}'
            : null,
        semanticLabel: t('staff.previewLate'),
      ),
    );
    final salaryField = RulesLabeled(
      label: t('staff.previewSalary'),
      child: DashNumberInput(
        key: RulesPreviewKeys.salary,
        value: example.salary / 100,
        onChanged: (egp) {
          if (egp == null || !egp.isFinite) return;
          widget.onExample(example.copyWith(salary: (egp * 100).round()));
        },
        step: 500,
        decimals: 2,
        minDecimals: 2,
        suffix: f.currencyLabel(),
        unitWord: f.currencyLabel(),
        semanticLabel: t('staff.previewSalary'),
      ),
    );
    final shiftField = RulesLabeled(
      label: t('staff.previewShift'),
      child: DashNumberInput(
        key: RulesPreviewKeys.shift,
        value: example.shiftMinutes / 60,
        onChanged: (h) {
          if (h == null || !h.isFinite || h < 1) return;
          widget.onExample(example.copyWith(shiftMinutes: (h * 60).round()));
        },
        min: 1,
        max: 24,
        step: 0.5,
        decimals: 2,
        stepper: true,
        center: true,
        suffix: unitHour,
        unitWord: unitHour,
        semanticLabel: t('staff.previewShift'),
      ),
    );

    final strong = DashType.bodyMedium.copyWith(
      color: c.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final plain = DashType.body.copyWith(color: c.textPrimary);
    final Widget verdict;
    if (minutes <= 0) {
      verdict = Text(t('staff.previewOnTime'), style: plain);
    } else if (tier != null) {
      verdict = Text.rich(
        TextSpan(
          children: [
            TextSpan(text: t('staff.previewRung', args: {'n': index + 1})),
            const TextSpan(text: ': '),
            TextSpan(
              text: t(
                'staff.previewDocks',
                args: {'amount': f.fmtMoney(amount)},
              ),
              style: plain.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        style: plain,
      );
    } else {
      verdict = Text(t('staff.previewNoRung'), style: plain);
    }

    return RulesCardFrame(
      children: [
        RulesCardHead(
          icon: 'flask-conical',
          title: t('staff.ladderPreviewTitle'),
          description: t('staff.ladderPreviewHint'),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.lg,
          children: [
            RulesGrid(
              columns: rulesSm(context) ? 3 : 1,
              children: [lateField, salaryField, shiftField],
            ),
            Semantics(
              key: RulesPreviewKeys.result,
              liveRegion: true,
              container: true,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.md,
                  vertical: Space.sm + 2,
                ),
                decoration: BoxDecoration(
                  color: c.muted.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      t('staff.previewLateN', args: {'n': jsNum(minutes)}),
                      style: strong,
                    ),
                    DashIcon(
                      DashIcon.arrowForward(context),
                      size: IconSize.sm,
                      color: c.textSecondary,
                    ),
                    verdict,
                  ],
                ),
              ),
            ),
            if (tiers.isNotEmpty)
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: c.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < samples.length; i++) ...[
                      if (i > 0) Container(height: 1, color: c.hairline),
                      _SampleRow(
                        key: RulesPreviewKeys.sample(i),
                        range: tiers[i].to == null
                            ? t(
                                'staff.tierFromOnly',
                                args: {'from': jsNum(tiers[i].from)},
                              )
                            : t(
                                'staff.tierRange',
                                args: {
                                  'from': jsNum(tiers[i].from),
                                  'to': jsNum(tiers[i].to),
                                },
                              ),
                        amount: () {
                          final r = selectTier(tiers, samples[i]);
                          return r == null
                              ? '—'
                              : f.fmtMoney(tierPiastres(r, example));
                        }(),
                        hit: i == index,
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SampleRow extends StatelessWidget {
  const _SampleRow({
    required this.range,
    required this.amount,
    required this.hit,
    super.key,
  });

  final String range;
  final String amount;
  final bool hit;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Semantics(
      selected: hit,
      container: true,
      child: Container(
        color: hit ? c.accent.withValues(alpha: 0.05) : null,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        child: Row(
          spacing: Space.md,
          children: [
            Expanded(
              child: Text(
                range,
                style: DashType.body.copyWith(
                  color: c.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            Text(
              amount,
              style: DashType.bodyMedium.copyWith(
                color: c.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
