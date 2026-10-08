/// The limits on one capability (the web's `features/access/limits-button.tsx`),
/// shared by the person access sheet (ADM-USR-048) and the Roles page
/// (ADM-ROL-016): a money ceiling, a percent ceiling, a value ceiling, "only
/// their own" and "within N minutes". Money and value are typed in pounds and
/// stored in minor units; a percent is typed in % and stored in basis points;
/// minutes are stored as typed; blank is no limit.
library;

import 'package:dashboard_api/dashboard_api.dart' show LimitsView;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'tax_rate.dart' show jsNumber;

/// The numeric limit keys, in the registry's order.
const List<String> numericLimitKeys = [
  'max_amount',
  'max_percent',
  'max_value',
  'max_age_minutes',
];

/// Stored units per typed unit.
const Map<String, int> limitScale = {
  'max_amount': 100,
  'max_percent': 100,
  'max_value': 100,
  'max_age_minutes': 1,
};

int? limitValue(LimitsView? v, String key) => switch (key) {
  'max_amount' => v?.maxAmount,
  'max_percent' => v?.maxPercent,
  'max_value' => v?.maxValue,
  'max_age_minutes' => v?.maxAgeMinutes,
  _ => null,
};

/// Stored → typed (`5000` minor → `"50"`); null → `""`.
String limitToDraft(String key, int? stored) =>
    stored == null ? '' : jsNumber(stored / limitScale[key]!);

/// Typed → stored (`"50"` → `5000`); blank or not a number → null (no limit).
int? limitFromDraft(String key, String typed) {
  if (typed.trim().isEmpty) return null;
  final n = double.tryParse(typed.trim());
  if (n == null || !n.isFinite) return null;
  return (n * limitScale[key]!).round();
}

/// Whether any limit is set ("Limited"): own-only, or a numeric ceiling.
bool hasLimits(LimitsView? v) =>
    v != null &&
    (v.own == true || numericLimitKeys.any((k) => limitValue(v, k) != null));

/// What happens above the limit for [meta]: the till asks a manager (a POS
/// capability), the act waits for a higher limit (an approval capability),
/// or it is refused.
String overLimitHint(CapabilityMeta meta, Translator t) => meta.pos
    ? t('access.overLimitHint')
    : meta.approval
    ? t('access.overLimitWaits')
    : t('access.overLimitRefused');

/// The "Limit" / "Limited" ghost button and its popover. Save hands the
/// limits to [onSave] and closes the popover (the label turning "Limited" is
/// the feedback).
class LimitsButton extends ConsumerStatefulWidget {
  const LimitsButton({
    required this.meta,
    required this.value,
    required this.onSave,
    this.disabled = false,
    super.key,
  });

  final CapabilityMeta meta;
  final LimitsView? value;
  final bool disabled;
  final ValueChanged<LimitsView> onSave;

  @override
  ConsumerState<LimitsButton> createState() => _LimitsButtonState();
}

class _LimitsButtonState extends ConsumerState<LimitsButton> {
  final _popover = DashPopoverController();
  Map<String, String> _draft = {};
  bool _own = false;

  List<String> get _numeric => [
    for (final k in widget.meta.limits)
      if (k != 'own') k,
  ];

  bool get _hasOwn => widget.meta.limits.contains('own');

  @override
  void dispose() {
    _popover.dispose();
    super.dispose();
  }

  void _open() {
    setState(() {
      _draft = {
        for (final k in _numeric)
          k: limitToDraft(k, limitValue(widget.value, k)),
      };
      _own = widget.value?.own == true;
    });
    _popover.open();
  }

  void _save() {
    int? v(String k) =>
        _numeric.contains(k) ? limitFromDraft(k, _draft[k] ?? '') : null;
    widget.onSave(
      LimitsView(
        maxAmount: v('max_amount'),
        maxPercent: v('max_percent'),
        maxValue: v('max_value'),
        maxAgeMinutes: v('max_age_minutes'),
        own: _hasOwn ? _own : null,
      ),
    );
    _popover.close();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final labels = {
      'max_amount': t('access.maxAmount'),
      'max_percent': t('access.maxPercent'),
      'max_value': t('access.maxValue'),
      'max_age_minutes': t('access.maxAgeMinutes'),
    };
    return DashPopover(
      controller: _popover,
      align: DashPopoverAlign.end,
      anchor: (context, _) => DashButton(
        label: hasLimits(widget.value)
            ? t('access.limited')
            : t('access.limit'),
        variant: DashButtonVariant.ghost,
        size: DashButtonSize.compact,
        onPressed: widget.disabled ? null : _open,
      ),
      content: (context, _) => Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: Space.md,
          children: [
            if (_hasOwn)
              Row(
                children: [
                  Expanded(
                    child: Text(
                      t('access.ownOnly'),
                      style: DashType.body.copyWith(color: c.textPrimary),
                    ),
                  ),
                  DashSwitch(
                    value: _own,
                    semanticLabel: t('access.ownOnly'),
                    onChanged: (v) => setState(() => _own = v),
                  ),
                ],
              ),
            for (final k in _numeric)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                spacing: Space.xs,
                children: [
                  Text(
                    labels[k] ?? k,
                    style: DashType.smallMedium.copyWith(color: c.textPrimary),
                  ),
                  DashTextInput(
                    value: _draft[k] ?? '',
                    placeholder: t('access.noLimit'),
                    semanticLabel: labels[k],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-9.]')),
                    ],
                    onChanged: (v) => setState(() => _draft[k] = v),
                  ),
                ],
              ),
            Text(
              overLimitHint(widget.meta, t),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
            DashButton(
              label: t('common.save'),
              size: DashButtonSize.compact,
              expand: true,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}
