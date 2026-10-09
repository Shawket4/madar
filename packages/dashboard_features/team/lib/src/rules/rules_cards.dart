/// The Rules page's cards (`staff/attendance-rules-page.tsx`): the branch's
/// own rules (TEAM-RUL-007/008/009), the late ladder (010–015), the pay basis
/// (025) and the policies (026). Stateless: the page owns the form and hands
/// each card its values and what to do on a change.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'rules_form.dart';
import 'rules_parts.dart';
import 'rules_preview.dart';

/// The keys the tests find the page's controls by.
abstract final class RulesKeys {
  static const ValueKey<String> scope = ValueKey('rules-scope');
  static ValueKey<String> tier(int i) => ValueKey('rules-tier-$i');
  static ValueKey<String> tierFrom(int i) => ValueKey('rules-tier-$i-from');
  static ValueKey<String> tierTo(int i) => ValueKey('rules-tier-$i-to');
  static ValueKey<String> tierKind(int i) => ValueKey('rules-tier-$i-kind');
  static ValueKey<String> tierAmount(int i) => ValueKey('rules-tier-$i-amount');
  static ValueKey<String> tierRemove(int i) => ValueKey('rules-tier-$i-remove');
  static ValueKey<String> chip(String rule) => ValueKey('rules-chip-$rule');
  static const ValueKey<String> addTier = ValueKey('rules-add-tier');
  static const ValueKey<String> workingDays = ValueKey('rules-working-days');
  static const ValueKey<String> absenceDays = ValueKey('rules-absence-days');
  static const ValueKey<String> autoBuffer = ValueKey('rules-auto-buffer');
  static const ValueKey<String> excused = ValueKey('rules-excused');
  static const ValueKey<String> follow = ValueKey('rules-follow-business');
  static const ValueKey<String> saveBar = ValueKey('rules-save-bar');
  static const ValueKey<String> save = ValueKey('rules-save');
  static const ValueKey<String> discard = ValueKey('rules-discard');
}

/// "This branch's own rules": a chip per rule the branch sets itself, each
/// (for an editor) handed back to the business or kept, and "Follow the
/// business" for all of them at once.
class RulesBranchCard extends StatelessWidget {
  const RulesBranchCard({
    required this.overridden,
    required this.inherit,
    required this.readOnly,
    required this.onToggle,
    required this.onFollow,
    required this.t,
    super.key,
  });

  final List<String> overridden;
  final List<String> inherit;
  final bool readOnly;
  final ValueChanged<String> onToggle;
  final VoidCallback onFollow;
  final Translator t;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return RulesCardFrame(
      children: [
        RulesCardHead(
          title: t('staff.rulesBranchTitle'),
          description: t('staff.rulesBranchHint'),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.md,
          children: [
            if (overridden.isEmpty)
              Text(
                t('staff.rulesBranchNone'),
                style: DashType.body.copyWith(color: c.textSecondary),
              )
            else
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                children: [
                  for (final name in overridden)
                    _RuleChip(
                      key: RulesKeys.chip(name),
                      label: ruleLabel(name, t),
                      going: inherit.contains(name),
                      action: readOnly
                          ? null
                          : inherit.contains(name)
                          ? t(
                              'staff.rulesKeepOwn',
                              args: {'rule': ruleLabel(name, t)},
                            )
                          : t(
                              'staff.rulesInherit',
                              args: {'rule': ruleLabel(name, t)},
                            ),
                      onPressed: () => onToggle(name),
                    ),
                ],
              ),
            if (!readOnly && overridden.isNotEmpty)
              DashButton(
                key: RulesKeys.follow,
                label: t('staff.rulesFollowBusiness'),
                icon: 'rotate-ccw',
                variant: DashButtonVariant.outline,
                size: DashButtonSize.compact,
                onPressed: onFollow,
              ),
          ],
        ),
      ],
    );
  }
}

/// A rule's badge; marked to hand back it is outlined and struck through.
/// The whole chip is the button (a 44-point target around the pill).
class _RuleChip extends StatelessWidget {
  const _RuleChip({
    required this.label,
    required this.going,
    required this.action,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool going;

  /// The button's words; null for a read-only viewer (no button).
  final String? action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    Widget pill(bool hovered) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.sm,
        vertical: Space.xs / 2,
      ),
      decoration: BoxDecoration(
        color: going ? null : c.muted,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: going ? c.hairline : c.muted),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          Flexible(
            child: Text(
              label,
              style: DashType.smallMedium.copyWith(
                color: c.textPrimary,
                decoration: going ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (action != null)
            Container(
              padding: const EdgeInsets.all(DashMetrics.hair * 2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: hovered ? c.hairline : null,
              ),
              child: DashIcon(
                going ? 'rotate-ccw' : 'x',
                size: IconSize.xs,
                color: c.textSecondary,
              ),
            ),
        ],
      ),
    );
    if (action == null) return pill(false);
    return DashPressable(
      semanticLabel: action,
      tooltip: action,
      onTap: onPressed,
      excludeChildSemantics: true,
      builder: (context, s) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        child: Center(widthFactor: 1, child: pill(s.hovered)),
      ),
    );
  }
}

/// "Late arrival penalties": the ladder's rungs, each with its read-back
/// line, the ladder's one error, and "Add a rung".
class RulesLadderCard extends StatelessWidget {
  const RulesLadderCard({
    required this.tiers,
    required this.example,
    required this.error,
    required this.readOnly,
    required this.onChanged,
    required this.t,
    required this.f,
    super.key,
  });

  final List<RuleTier> tiers;
  final PayExample example;

  /// The ladder's problem in words, once the ladder was checked.
  final String? error;
  final bool readOnly;
  final ValueChanged<List<RuleTier>> onChanged;
  final Translator t;
  final DashFormat f;

  void _patch(int i, RuleTier tier) =>
      onChanged([for (var j = 0; j < tiers.length; j++) j == i ? tier : tiers[j]]);

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return RulesCardFrame(
      children: [
        RulesCardHead(
          title: t('staff.lateLadder'),
          description: t('staff.lateLadderHint'),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.md,
          children: [
            if (tiers.isEmpty)
              Text(
                t('staff.noTiers'),
                style: DashType.body.copyWith(color: c.textSecondary),
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: Space.sm,
                children: [
                  for (var i = 0; i < tiers.length; i++)
                    _RungRow(
                      key: RulesKeys.tier(i),
                      index: i,
                      tier: tiers[i],
                      example: example,
                      invalid: error != null,
                      readOnly: readOnly,
                      onChanged: (tier) => _patch(i, tier),
                      onRemove: () =>
                          onChanged([...tiers]..removeAt(i)),
                      t: t,
                      f: f,
                    ),
                ],
              ),
            if (error != null) RulesErrorText(error!),
            if (!readOnly)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: DashButton(
                  key: RulesKeys.addTier,
                  label: t('staff.addTier'),
                  icon: 'plus',
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onPressed: () => onChanged([...tiers, nextTier(tiers)]),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One rung: its number (from `md`), its four fields (1 → 2 → 4 columns),
/// its read-back line, and "Remove rung".
class _RungRow extends StatelessWidget {
  const _RungRow({
    required this.index,
    required this.tier,
    required this.example,
    required this.invalid,
    required this.readOnly,
    required this.onChanged,
    required this.onRemove,
    required this.t,
    required this.f,
    super.key,
  });

  final int index;
  final RuleTier tier;
  final PayExample example;
  final bool invalid;
  final bool readOnly;
  final ValueChanged<RuleTier> onChanged;
  final VoidCallback onRemove;
  final Translator t;
  final DashFormat f;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final i = index;
    final unitMin = t('inputs.unitMin');
    final md = rulesMd(context);
    final from = RulesLabeled(
      small: true,
      label: t('staff.fromMinutes'),
      child: DashNumberInput(
        key: RulesKeys.tierFrom(i),
        value: tier.from,
        onChanged: (n) => onChanged(tier.copyWith(from: n ?? 0)),
        suffix: unitMin,
        invalid: invalid,
        enabled: !readOnly,
        semanticLabel: t('staff.fromMinutes'),
      ),
    );
    final to = RulesLabeled(
      small: true,
      label: t('staff.toMinutes'),
      child: DashNumberInput(
        key: RulesKeys.tierTo(i),
        value: tier.to,
        onChanged: (n) => onChanged(tier.copyWith(to: () => n)),
        suffix: unitMin,
        allowEmpty: true,
        emptyLabel: t('staff.noLimit'),
        invalid: invalid,
        enabled: !readOnly,
        semanticLabel: t('staff.toMinutes'),
      ),
    );
    final kind = RulesLabeled(
      small: true,
      label: t('staff.deduct'),
      child: DashSelect<TierKind>(
        key: RulesKeys.tierKind(i),
        value: tier.kind,
        enabled: !readOnly,
        semanticLabel: t('staff.deduct'),
        options: [
          DashOption(value: TierKind.minutes, label: t('staff.kindMinutes')),
          DashOption(
            value: TierKind.dayFraction,
            label: t('staff.kindDayFraction'),
          ),
          DashOption(value: TierKind.piastres, label: t('staff.kindFixed')),
        ],
        onChanged: (k) {
          if (k != tier.kind) {
            onChanged(tier.copyWith(kind: k, value: defaultTierValue(k)));
          }
        },
      ),
    );
    final fixed = tier.kind == TierKind.piastres;
    final day = tier.kind == TierKind.dayFraction;
    final amount = RulesLabeled(
      small: true,
      label: t('staff.amount'),
      child: fixed
          // The web's MoneyField: pounds typed, piastres kept.
          ? DashNumberInput(
              key: RulesKeys.tierAmount(i),
              value: tier.value.isFinite ? tier.value / 100 : tier.value,
              onChanged: (egp) => onChanged(
                tier.copyWith(
                  value: egp == null
                      ? 0
                      : egp.isFinite
                      ? (egp * 100).roundToDouble()
                      : double.nan,
                ),
              ),
              step: 50,
              decimals: 2,
              minDecimals: 2,
              suffix: f.currencyLabel(),
              unitWord: f.currencyLabel(),
              enabled: !readOnly,
              semanticLabel: t('staff.amount'),
            )
          : DashNumberInput(
              key: RulesKeys.tierAmount(i),
              value: tier.value,
              onChanged: (n) => onChanged(tier.copyWith(value: n ?? 0)),
              suffix: day ? t('staff.ofADay') : unitMin,
              step: day ? 0.25 : 5,
              decimals: day ? 2 : 0,
              enabled: !readOnly,
              semanticLabel: t('staff.amount'),
            ),
    );
    final cols = rulesLg(context) ? 4 : (rulesSm(context) ? 2 : 1);
    final readBack = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: describeTier(tier, t, f)),
          if (!fixed)
            TextSpan(
              text:
                  ' · ${t('staff.tierExample', args: {'amount': f.fmtMoney(tierPiastres(tier, example))})}',
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
      style: DashType.small.copyWith(color: c.textSecondary),
    );
    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        RulesGrid(columns: cols, children: [from, to, kind, amount]),
        readBack,
      ],
    );
    final remove = readOnly
        ? null
        : DashIconButton(
            key: RulesKeys.tierRemove(i),
            icon: 'trash-2',
            semanticLabel: t('staff.removeTier'),
            color: c.errorText,
            onPressed: onRemove,
          );
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.control),
        border: Border.all(color: c.hairline),
      ),
      child: md
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                ExcludeSemantics(
                  child: Container(
                    width: Space.xxl - Space.xs,
                    height: Space.xxl - Space.xs,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.muted,
                    ),
                    child: Text(
                      '${i + 1}',
                      style: DashType.smallMedium.copyWith(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
                Expanded(child: fields),
                ?remove,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.md,
              children: [
                fields,
                if (remove != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: remove,
                  ),
              ],
            ),
    );
  }
}

/// "Pay basis": how a monthly salary is divided (working days, the days an
/// absence docks) and the auto-close buffer.
class RulesPayBasisCard extends StatelessWidget {
  const RulesPayBasisCard({
    required this.values,
    required this.example,
    required this.errors,
    required this.readOnly,
    required this.onWorkingDays,
    required this.onAbsenceDays,
    required this.onAutoBuffer,
    required this.t,
    required this.f,
    super.key,
  });

  final RulesValues values;
  final PayExample example;

  /// Each field's problem in words, once it was checked.
  final Map<RulesField, String> errors;
  final bool readOnly;
  final ValueChanged<double?> onWorkingDays;
  final ValueChanged<double?> onAbsenceDays;
  final ValueChanged<double?> onAutoBuffer;
  final Translator t;
  final DashFormat f;

  @override
  Widget build(BuildContext context) {
    final days = t('staff.daysUnit');
    final absence = values.absenceDays;
    final docked = dayPiastres(
      example,
      absence != null && absence.isFinite ? absence : 0,
    );
    Widget field(
      RulesField which,
      String label,
      Key key,
      double? value,
      ValueChanged<double?> onChanged, {
      required double step,
      int? decimals,
      required String suffix,
      String? hint,
    }) => RulesLabeled(
      label: label,
      error: errors[which],
      child: DashNumberInput(
        key: key,
        value: value,
        onChanged: onChanged,
        step: step,
        decimals: decimals,
        suffix: suffix,
        hint: hint,
        invalid: errors[which] != null,
        enabled: !readOnly,
        semanticLabel: label,
      ),
    );

    return RulesCardFrame(
      children: [
        RulesCardHead(
          title: t('staff.payBasis'),
          description: t('staff.payBasisHint'),
        ),
        RulesGrid(
          columns: rulesSm(context) ? 2 : 1,
          children: [
            field(
              RulesField.workingDays,
              t('staff.workingDays'),
              RulesKeys.workingDays,
              values.workingDays,
              onWorkingDays,
              step: 0.5,
              decimals: 2,
              suffix: days,
            ),
            field(
              RulesField.absenceDays,
              t('staff.absenceDays'),
              RulesKeys.absenceDays,
              absence,
              onAbsenceDays,
              step: 0.25,
              decimals: 2,
              suffix: days,
              hint: t(
                'staff.absenceExample',
                args: {'amount': f.fmtMoney(docked)},
              ),
            ),
            field(
              RulesField.autoBuffer,
              t('staff.autoBuffer'),
              RulesKeys.autoBuffer,
              values.autoBuffer,
              onAutoBuffer,
              step: 15,
              suffix: t('inputs.unitMin'),
            ),
          ],
        ),
      ],
    );
  }
}

/// "Policies": the always-on location check, and whether approved
/// permissions are paid by default.
class RulesPoliciesCard extends StatelessWidget {
  const RulesPoliciesCard({
    required this.excusedPaid,
    required this.readOnly,
    required this.onExcusedPaid,
    required this.t,
    super.key,
  });

  final bool excusedPaid;
  final bool readOnly;
  final ValueChanged<bool> onExcusedPaid;
  final Translator t;

  @override
  Widget build(BuildContext context) {
    return RulesCardFrame(
      children: [
        RulesCardHead(title: t('staff.policies')),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.lg,
          children: [
            RulesHintText(t('staff.fenceAlwaysOn')),
            Row(
              spacing: Space.md,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RulesLabelText(t('staff.excusedPaid')),
                      RulesHintText(t('staff.excusedPaidHint')),
                    ],
                  ),
                ),
                DashSwitch(
                  key: RulesKeys.excused,
                  value: excusedPaid,
                  enabled: !readOnly,
                  onChanged: readOnly ? null : onExcusedPaid,
                  semanticLabel: t('staff.excusedPaid'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
