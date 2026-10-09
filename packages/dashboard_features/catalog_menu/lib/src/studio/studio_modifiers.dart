/// Studio section 4, Modifiers (the web's `section-modifiers.tsx`): the
/// item's attached reusable groups. Chips toggle each option in or out of
/// the attachment's allowlist; Required / Min / Max are per-item overrides;
/// attaching and detaching are drafts the save replace-sets in order.
/// "New group" opens the choice-group editor and attaches what it saves.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show GroupOut;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../groups/group_editor_dialog.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import 'studio_model.dart';
import 'studio_widgets.dart';

class StudioModifiersSection extends ConsumerWidget {
  const StudioModifiersSection({
    required this.orgId,
    required this.itemId,
    required this.attached,
    required this.onChanged,
    super.key,
  });

  final String? orgId;
  final String itemId;
  final List<AttachDraft> attached;
  final ValueChanged<List<AttachDraft>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final fmt = ref.watch(formatProvider);
    final org = orgId;
    final canEditGroups = ref.watch(
      authzProvider.select((a) => a.can(Cap.menuItemsEdit)),
    );
    final all = org == null
        ? const <GroupOut>[]
        : ref
                  .watch(
                    modifierGroupsProvider((
                      orgId: org,
                      includeInactive: false,
                    )),
                  )
                  .value ??
              const <GroupOut>[];
    final attachedIds = {for (final a in attached) a.groupId};
    // Another item's own options set is not a reusable group.
    final pickable = [
      for (final g in all)
        if (g.isActive && g.isItemOptions != true && !attachedIds.contains(g.id))
          g,
    ];

    void update(int i, AttachDraft a) =>
        onChanged([for (final (j, x) in attached.indexed) j == i ? a : x]);

    Widget card(int i, AttachDraft a) {
      final type = a.legacyAddonType == null || a.legacyAddonType!.isEmpty
          ? null
          : humanizeAddonType(a.legacyAddonType!);
      final withRecipes = a.allOptions.any(
        (o) => (o.recipe ?? const []).isNotEmpty,
      );
      return Container(
        key: ValueKey('studio-group-${a.groupId}'),
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.md,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        a.name,
                        style: DashType.bodyMedium.copyWith(
                          color: c.textPrimary,
                        ),
                      ),
                      if (type != null) DashBadge(type),
                      StudioOutlineBadge(
                        a.selectionType == 'single'
                            ? t('menu.studio.modifiers.single')
                            : t('menu.studio.modifiers.multi'),
                      ),
                    ],
                  ),
                ),
                if (canEditGroups)
                  DashButton(
                    label: t('menu.groups.editGroup'),
                    icon: 'pencil',
                    variant: DashButtonVariant.ghost,
                    size: DashButtonSize.compact,
                    onPressed: () => context.go(
                      Uri(
                        path: '/menu/groups',
                        queryParameters: {'edit': a.groupId},
                      ).toString(),
                    ),
                  ),
                DashIconButton(
                  icon: 'trash-2',
                  color: c.danger,
                  semanticLabel: t('menu.studio.modifiers.detach'),
                  onPressed: () => onChanged([
                    for (final (j, x) in attached.indexed)
                      if (j != i) x,
                  ]),
                ),
              ],
            ),
            if (a.allOptions.isEmpty)
              StudioHint(t('menu.studio.modifiers.noOptions'))
            else
              Wrap(
                spacing: Space.xs + DashMetrics.hair,
                runSpacing: Space.xs + DashMetrics.hair,
                children: [
                  for (final o in a.allOptions)
                    _OptionChip(
                      key: ValueKey('chip-${a.groupId}-${o.id}'),
                      label: o.name,
                      price: o.price > 0 ? fmt.fmtMoney(o.price, signed: true) : null,
                      offered: a.offers(o.id),
                      onTap: () => update(i, a.toggle(o.id)),
                    ),
                ],
              ),
            if (withRecipes)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.xs,
                children: [
                  for (final o in a.allOptions)
                    Wrap(
                      spacing: Space.sm,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        Text(
                          o.name,
                          style: DashType.smallMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          // The web prints "+" before any price, 0 too.
                          o.price > 0
                              ? fmt.fmtMoney(o.price, signed: true)
                              : '+${fmt.fmtMoney(o.price)}',
                          style: DashType.small.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                        Text(
                          (o.recipe ?? const []).isNotEmpty
                              ? [
                                  for (final r in o.recipe!)
                                    '${r.name} ${ltr(jsNumberText(jsParseFloat(r.quantity)))} ${unitWord(t, r.unit)}',
                                ].join(' · ')
                              : t('menu.groups.studio.noStock'),
                          style: DashType.small.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                        if (o.cost != null)
                          Text(
                            '${t('menu.groups.studio.cost')} '
                            '${fmt.fmtMoney(o.cost)}${o.costIncomplete ? '+' : ''}',
                            style: DashType.small.copyWith(
                              color: c.textSecondary,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            Container(
              padding: const EdgeInsets.only(top: Space.md),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.hairline)),
              ),
              child: Wrap(
                spacing: Space.xl,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: Space.xs,
                    children: [
                      DashSwitch(
                        value: a.isRequired,
                        semanticLabel: t('menu.studio.modifiers.required'),
                        onChanged: (v) =>
                            update(i, a.copyWith(isRequired: v)),
                      ),
                      Text(
                        t('menu.studio.modifiers.required'),
                        style: DashType.body.copyWith(color: c.textPrimary),
                      ),
                    ],
                  ),
                  _CountField(
                    label: t('menu.studio.modifiers.min'),
                    value: '${a.min}',
                    onChanged: (v) => update(
                      i,
                      a.copyWith(min: v.isEmpty ? 0 : int.tryParse(v) ?? 0),
                    ),
                  ),
                  _CountField(
                    label: t('menu.studio.modifiers.max'),
                    value: a.max == null ? '' : '${a.max}',
                    placeholder: t('menu.studio.modifiers.unlimited'),
                    onChanged: (v) => update(
                      i,
                      a.copyWith(
                        max: () => v.isEmpty ? null : int.tryParse(v) ?? 0,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        if (attached.isEmpty)
          DashEmptyState(
            icon: 'layers',
            title: t('menu.studio.modifiers.empty'),
          )
        else
          for (final (i, a) in attached.indexed) card(i, a),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: Space.xxl * 8,
              child: DashSelect<String>(
                key: const ValueKey('studio-attach-group'),
                options: [
                  for (final g in pickable)
                    DashOption(
                      value: g.id,
                      label: g.name,
                      hint: g.legacyAddonType == null ||
                              g.legacyAddonType!.isEmpty
                          ? t('menu.studio.modifiers.option')
                          : humanizeAddonType(g.legacyAddonType!),
                    ),
                ],
                value: null,
                searchable: true,
                enabled: pickable.isNotEmpty,
                placeholder: t('menu.studio.modifiers.attach'),
                semanticLabel: t('menu.studio.modifiers.attach'),
                searchPlaceholder: t('common.search'),
                emptyText: t('common.noResults'),
                onChanged: (id) {
                  final g = all.where((x) => x.id == id).firstOrNull;
                  if (g != null) onChanged([...attached, attachFromGroup(g)]);
                },
              ),
            ),
            if (canEditGroups)
              DashButton(
                label: t('menu.groups.new'),
                icon: 'plus',
                variant: DashButtonVariant.outline,
                onPressed: org == null
                    ? null
                    : () async {
                        final invalidate = ref.menuInvalidate;
                        final saved = await showGroupEditorDialog(
                          context,
                          orgId: org,
                        );
                        if (saved != null) {
                          onChanged([...attached, attachFromGroup(saved)]);
                        }
                        // Closing the editor refreshes the studio.
                        invalidate.studio(itemId);
                      },
              ),
          ],
        ),
      ],
    );
  }
}

/// An allowlist chip: filled with a check while offered.
class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.offered,
    required this.onTap,
    this.price,
    super.key,
  });

  final String label;
  final String? price;
  final bool offered;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      checked: offered,
      isButton: true,
      semanticLabel: price == null ? label : '$label $price',
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => SizedBox(
        height: DashMetrics.target,
        child: Center(
          widthFactor: 1,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.sm + DashMetrics.hair,
              vertical: DashMetrics.hair,
            ),
            decoration: BoxDecoration(
              color: offered ? c.muted : null,
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(
                color: offered || s.hovered
                    ? c.hairline
                    : c.hairline.withValues(alpha: 0.7),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: Space.xs,
              children: [
                if (offered)
                  DashIcon('check', size: IconSize.xs - 2, color: c.textPrimary),
                Text(
                  label,
                  style: DashType.smallMedium.copyWith(
                    color: offered || s.hovered
                        ? c.textPrimary
                        : c.textSecondary,
                  ),
                ),
                if (price != null)
                  Text(
                    price!,
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Min [0]" / "Max [∞]": a whole number box (blank allowed).
class _CountField extends StatelessWidget {
  const _CountField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.placeholder,
  });

  final String label;
  final String value;
  final String? placeholder;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        Text(label, style: DashType.smallMedium.copyWith(color: c.textSecondary)),
        SizedBox(
          width: Space.xxl * 2 + Space.lg,
          child: DashTextInput(
            value: value,
            mono: true,
            placeholder: placeholder,
            semanticLabel: label,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
