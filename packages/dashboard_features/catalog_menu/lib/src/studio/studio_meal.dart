/// Studio section 6, Make it a meal (the web's `section-meal.tsx`): point
/// this item at a combo and the slot it fills; the till then offers "Make
/// it a meal +X". Applies at once (`PUT /menu-items/{id}/meal`), outside the
/// studio's save. Only slots whose choices admit this item are offered.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ComboSlot, ComboSummary, MealLink, MealLinkWrite, MenuItemFull;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show DashRoutePrefetch;
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/menu_text.dart';
import 'meal_model.dart';
import 'studio_providers.dart';
import 'studio_widgets.dart';

const String _none = '__none__';

class StudioMealSection extends ConsumerStatefulWidget {
  const StudioMealSection({
    required this.itemId,
    required this.categoryId,
    super.key,
  });

  final String itemId;
  final String? categoryId;

  @override
  ConsumerState<StudioMealSection> createState() => _StudioMealSectionState();
}

class _StudioMealSectionState extends ConsumerState<StudioMealSection> {
  /// The picked combo and slot (`''` = none); follow the saved target.
  String _comboId = '';
  String _slotId = '';
  bool _busy = false;
  ({String? combo, String? slot})? _seeded;

  void _follow(MealLink? current) {
    final key = (combo: current?.comboId, slot: current?.slotId);
    if (_seeded == key) return;
    _seeded = key;
    _comboId = current?.comboId ?? '';
    _slotId = current?.slotId ?? '';
  }

  Future<void> _apply(bool on) async {
    final t = ref.read(tProvider);
    // Captured before the await: the refresh runs even if the page closed.
    final container = ProviderScope.containerOf(context, listen: false);
    setState(() => _busy = true);
    try {
      await ref
          .read(apiProvider)
          .menu
          .putMeal(
            id: widget.itemId,
            body: on
                ? MealLinkWrite(comboId: _comboId, slotId: _slotId)
                : const MealLinkWrite(explicitNulls: {'combo_id', 'slot_id'}),
          );
      // The web invalidates only this item's read.
      container.invalidate(studioMenuItemProvider(widget.itemId));
      if (!mounted) return;
      DashToast.success(
        context,
        on ? t('combos.meal.saved') : t('combos.meal.cleared'),
      );
    } on Object catch (e) {
      if (mounted) DashToast.error(context, errorMessage(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final lang = ref.watch(localeProvider);
    final canEdit = ref.watch(
      authzProvider.select((a) => a.can(Cap.menuCombosEdit)),
    );
    final itemQ = ref.watch(studioMenuItemProvider(widget.itemId));
    final current = itemQ.value?.meal;
    _follow(current);
    final combosQ = ref.watch(studioCombosProvider);
    final orgId = ref.watch(orgIdProvider);
    final full = orgId == null
        ? const <MenuItemFull>[]
        : ref.watch(studioMenuOptionsProvider(orgId)).value ??
              const <MenuItemFull>[];
    // The branches the web's menu options also read: the shell's list.
    ref.watch(branchesProvider);
    final items = mealItemsOf(full);
    final item = items[widget.itemId];
    final comboQ = _comboId.isEmpty
        ? null
        : ref.watch(studioComboProvider(_comboId));
    final combo = comboQ?.value;
    final slots = combo == null
        ? const <ComboSlot>[]
        : slotsAdmitting(combo, widget.itemId, widget.categoryId);
    // A combo with exactly one slot for this item needs no second choice.
    if (_comboId.isNotEmpty && slots.length == 1 && _slotId != slots.first.id) {
      _slotId = slots.first.id;
    }
    final delta = combo != null && _slotId.isNotEmpty && item != null
        ? mealDelta(combo, _slotId, item, (id) => items[id])
        : null;
    final dirty =
        (current?.comboId ?? '') != _comboId ||
        (current?.slotId ?? '') != _slotId;
    final combos = combosQ.value?.data ?? const <ComboSummary>[];

    Widget note(
      String text, {
      String? icon,
      required String link,
      required String to,
    }) => StudioDashedBox(
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.md,
        runSpacing: Space.sm,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              if (icon != null)
                DashIcon(icon, size: IconSize.sm, color: c.textSecondary),
              Flexible(
                child: Text(
                  text,
                  style: DashType.body.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
          DashButton(
            label: link,
            variant: DashButtonVariant.ghost,
            size: DashButtonSize.compact,
            trailingIcon: DashIcon.arrowForward(context),
            onIntent: () => ref.prefetchRoute(to),
            onPressed: () => context.go(to),
          ),
        ],
      ),
    );

    // A combo is not made a meal; its slots live in the combo editor.
    if (itemQ.value?.kind == 'combo') {
      return note(
        t('combos.meal.isCombo'),
        link: t('combos.meal.openEditor'),
        to: '/menu/combos/${widget.itemId}',
      );
    }
    if (combosQ.hasValue && combos.isEmpty) {
      return note(
        t('combos.meal.noCombos'),
        icon: 'utensils-crossed',
        link: t('combos.title'),
        to: '/menu/combos',
      );
    }

    final wide = MediaQuery.sizeOf(context).width >= StudioMetrics.sm;
    // DashSelectField has no option intent: its label and select, unrolled.
    final comboField = DashFormField<String>(
      label: t('combos.meal.combo'),
      builder: (context, invalid) => DashSelect<String>(
        options: [
          DashOption(value: _none, label: t('combos.meal.none')),
          for (final cb in combos)
            DashOption(
              value: cb.id,
              label: translatedName(cb.name, cb.nameTranslations, lang),
            ),
        ],
        value: _comboId.isEmpty ? _none : _comboId,
        semanticLabel: t('combos.meal.combo'),
        enabled: canEdit && !_busy,
        // Picking a combo reads it (its slots).
        onOptionIntent: (v) {
          if (v != _none) ref.warm(studioComboProvider(v));
        },
        onChanged: (v) => setState(() {
          _comboId = v == _none ? '' : v;
          _slotId = '';
        }),
      ),
    );
    final slotField = _comboId.isEmpty
        ? null
        : DashFormField<String>(
            label: t('combos.meal.slot'),
            builder: (context, invalid) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.xs,
              children: [
                DashSelect<String>(
                  options: [
                    for (final s in slots)
                      DashOption(
                        value: s.id,
                        label: translatedName(s.name, s.nameTranslations, lang),
                      ),
                  ],
                  value: _slotId.isEmpty ? null : _slotId,
                  semanticLabel: t('combos.meal.slot'),
                  placeholder: comboQ?.isLoading == true && combo == null
                      ? t('common.loading')
                      : t('combos.meal.pickSlot'),
                  enabled: canEdit && !_busy && slots.isNotEmpty,
                  onChanged: (v) => setState(() => _slotId = v),
                ),
                if (combo != null && slots.isEmpty)
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      t('errors.codes.MEAL_TARGET_INVALID'),
                      style: DashType.small.copyWith(color: c.errorText),
                    ),
                  ),
              ],
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(child: comboField),
              Expanded(child: slotField ?? const SizedBox.shrink()),
            ],
          )
        else ...[
          comboField,
          ?slotField,
        ],
        if (delta != null)
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: Space.sm,
            ),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: Text(
              t(
                'combos.meal.preview',
                args: {'delta': fmt.fmtMoney(delta, signed: true)},
              ),
              style: DashType.body.copyWith(color: c.textPrimary),
            ),
          ),
        if (canEdit)
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              DashButton(
                label: _comboId.isNotEmpty
                    ? t('combos.meal.apply')
                    : t('combos.meal.turnOff'),
                size: DashButtonSize.compact,
                loading: _busy,
                onPressed:
                    !dirty || _busy || (_comboId.isNotEmpty && _slotId.isEmpty)
                    ? null
                    : () => _apply(_comboId.isNotEmpty && _slotId.isNotEmpty),
              ),
              if (dirty)
                DashButton(
                  label: t('combos.discard'),
                  variant: DashButtonVariant.ghost,
                  size: DashButtonSize.compact,
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          _comboId = current?.comboId ?? '';
                          _slotId = current?.slotId ?? '';
                        }),
                ),
            ],
          ),
      ],
    );
  }
}
