/// The editor's "Price check" (the web's `economics-panel.tsx`): what the
/// default picks would cost bought separately, what the customer saves, the
/// cost and margin in the default and the costliest case against the
/// owner's minimum, and the server's warnings. It informs; it never blocks
/// a Save.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ComboEconomics, ComboWarning;
import 'package:dashboard_core/dashboard_core.dart' hide rateOf;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/offers_format.dart';
import 'combo_editor_providers.dart';

/// A warning's words (`warningText`): items from the pick list, slots from
/// the form, a fallback when either is unknown.
String comboWarningText(
  Translator t,
  DashFormat f,
  ComboWarning w, {
  required String? Function(String id) itemName,
  required String? Function(String id) slotName,
}) {
  final v = w.vars ?? const <String, Object?>{};
  String? named(String key, String? Function(String) lookup) {
    final id = v[key];
    return id is String && id.isNotEmpty ? lookup(id) : null;
  }

  final anItem = t('combos.warnings.anItem');
  return switch (w.code) {
    'MARGIN_BELOW_MIN' => t(
      'combos.warnings.MARGIN_BELOW_MIN',
      args: {'margin': fmtRate(f, v['margin']), 'min': fmtRate(f, v['min'])},
    ),
    'NO_SAVING' => t('combos.warnings.NO_SAVING'),
    'COST_UNKNOWN' => t(
      'combos.warnings.COST_UNKNOWN',
      args: {'item': named('menu_item_id', itemName) ?? anItem},
    ),
    'SLOT_EMPTY_NOW' => t(
      'combos.warnings.SLOT_EMPTY_NOW',
      args: {'slot': named('slot_id', slotName) ?? t('combos.warnings.aSlot')},
    ),
    'CHOICE_INACTIVE' => t(
      'combos.warnings.CHOICE_INACTIVE',
      args: {'item': named('menu_item_id', itemName) ?? anItem},
    ),
    _ => t('combos.warnings.unknown', args: {'code': w.code}),
  };
}

class ComboPriceCheck extends ConsumerWidget {
  const ComboPriceCheck({
    required this.requestKey,
    required this.branchLabel,
    required this.itemName,
    required this.slotName,
    super.key,
  });

  /// The request (see [comboEconomicsKey]); null while the form cannot
  /// describe a combo yet.
  final String? requestKey;

  /// "organisation prices" or the scope's branch.
  final String branchLabel;
  final String? Function(String id) itemName;
  final String? Function(String id) slotName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final key = requestKey;

    Widget body;
    if (key == null) {
      body = _Muted(t('combos.econ.needsInput'));
    } else {
      final q = ref.watch(comboEconomicsProvider(key));
      if (q.isLoading && !q.hasValue && !q.hasError) {
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            for (var i = 0; i < 5; i++) const DashSkeleton(height: Space.xl),
          ],
        );
      } else if (q.hasError || !q.hasValue) {
        body = Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _Muted(t('combos.econ.failed')),
              if (q.hasError)
                Text(
                  errorMessage(q.error, t),
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
            ],
          ),
        );
      } else {
        body = _Figures(
          econ: q.requireValue,
          itemName: itemName,
          slotName: slotName,
        );
      }
    }

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: t('combos.econ.title'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: c.hairline),
        ),
        child: Padding(
          padding: const EdgeInsetsDirectional.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.md,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                spacing: DashMetrics.hair,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      t('combos.econ.title'),
                      style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                    ),
                  ),
                  Text(
                    t('combos.econ.pricesAt', args: {'scope': branchLabel}),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: DashType.body.copyWith(color: context.madarColors.textSecondary),
  );
}

/// The figures, the warnings (or "No warnings.") and the reassurance.
class _Figures extends ConsumerWidget {
  const _Figures({
    required this.econ,
    required this.itemName,
    required this.slotName,
  });

  final ComboEconomics econ;
  final String? Function(String id) itemName;
  final String? Function(String id) slotName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final e = econ;
    final min = rateOf(e.minMargin);
    bool below(String? r) {
      final v = rateOf(r);
      return min != null && v != null && v < min;
    }

    final rows = <Widget>[
      _Figure(label: t('combos.econ.price'), value: f.fmtMoney(e.price)),
      _Figure(
        label: t('combos.econ.listValue'),
        value: f.fmtMoney(e.listDefault),
        hint: e.listMin != e.listMax
            ? t(
                'combos.econ.range',
                args: {
                  'min': f.fmtMoney(e.listMin),
                  'max': f.fmtMoney(e.listMax),
                },
              )
            : null,
      ),
      _Figure(
        label: t('combos.econ.saving'),
        value: f.fmtMoney(e.savingDefault),
        tone: e.savingDefault > 0 ? DashTone.success : DashTone.warning,
      ),
      _Figure(
        label: t('combos.econ.cost'),
        value: e.costDefault == null
            ? t('combos.econ.unknown')
            : f.fmtMoney(e.costDefault),
        hint: e.costMax != null && e.costMax != e.costDefault
            ? t(
                'combos.econ.worstCost',
                args: {'amount': f.fmtMoney(e.costMax)},
              )
            : null,
      ),
      _Figure(
        label: t('combos.econ.margin'),
        value: fmtRate(f, e.marginDefault),
        tone: below(e.marginDefault) ? DashTone.warning : null,
      ),
      _Figure(
        label: t('combos.econ.marginWorst'),
        value: fmtRate(f, e.marginWorst),
        tone: below(e.marginWorst) ? DashTone.warning : null,
      ),
      _Figure(
        label: t('combos.econ.minMargin'),
        value: min == null
            ? t('combos.econ.noMinimum')
            : fmtRate(f, e.minMargin),
      ),
    ];

    final warning = DashTone.warning.foreground(c);
    final success = DashTone.success.foreground(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.md,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, color: c.hairline),
              rows[i],
            ],
          ],
        ),
        if (e.warnings.isNotEmpty)
          Semantics(
            container: true,
            explicitChildNodes: true,
            label: t('combos.econ.warnings'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs + DashMetrics.hair,
              children: [
                for (final w in e.warnings)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: DashTone.warning.wash(c),
                      borderRadius: BorderRadius.circular(Radii.xs),
                    ),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.all(
                        Space.sm + DashMetrics.hair,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        spacing: Space.sm,
                        children: [
                          DashIcon('alert-triangle', color: warning),
                          Expanded(
                            child: Text(
                              comboWarningText(
                                t,
                                f,
                                w,
                                itemName: itemName,
                                slotName: slotName,
                              ),
                              style: DashType.body.copyWith(color: warning),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          )
        else
          Row(
            spacing: Space.sm,
            children: [
              DashIcon('check-circle-2', color: success),
              Expanded(
                child: Text(
                  t('combos.econ.noWarnings'),
                  style: DashType.body.copyWith(color: success),
                ),
              ),
            ],
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.sm,
          children: [
            DashIcon('info', size: IconSize.xs, color: c.textSecondary),
            Expanded(
              child: Text(
                t('combos.econ.neverBlocks'),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One figure: the label at the start, the mono value (and a quiet hint
/// under it) at the end.
class _Figure extends StatelessWidget {
  const _Figure({
    required this.label,
    required this.value,
    this.hint,
    this.tone,
  });

  final String label;
  final String value;
  final String? hint;
  final DashTone? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        vertical: Space.xs + DashMetrics.hair,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          Expanded(
            child: Text(
              label,
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                textDirection: TextDirection.ltr,
                style: DashType.monoStrong.copyWith(
                  color: tone?.foreground(c) ?? c.textPrimary,
                ),
              ),
              if (hint != null)
                Text(
                  hint!,
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
