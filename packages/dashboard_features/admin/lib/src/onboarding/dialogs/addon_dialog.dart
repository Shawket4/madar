/// "New add-on" (ADM-ONB-019; the web's `features/menu/addon-dialog.tsx` with
/// `addon={null}`, the only mode onboarding opens). On the unified model an
/// add-on is an option inside a reusable choice group: it is created in an
/// EXISTING shared group picked by name (`POST /modifier-groups/{gid}/options`);
/// a missing group is made in the choice-group editor ("New group", for a
/// person who may edit menu items), which then becomes the pick.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show CreateOptionRequest, GroupOptionOut, GroupOut;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'group_editor_dialog.dart';
import 'menu_reads.dart';
import 'menu_text.dart';

/// Opens the dialog; resolves with the created option, or null.
Future<GroupOptionOut?> showAddonDialog(
  BuildContext context, {
  required String orgId,
}) => showDashDialog<GroupOptionOut>(
  context,
  builder: (_) => AddonDialog(orgId: orgId),
);

/// The form's messages (zod's schema), keyed by field; empty = valid.
Map<String, String> validateAddon({
  required String name,
  required String groupId,
  required String price,
  required Translator t,
}) {
  final p = jsNumber(price);
  return {
    if (name.isEmpty) 'name': t('common.requiredField'),
    if (groupId.isEmpty) 'group_id': t('common.requiredField'),
    if (p.isNaN)
      'default_price': t('onboarding.form.notANumber')
    else if (p < 0)
      'default_price': t('onboarding.form.priceMin'),
  };
}

class AddonDialog extends ConsumerStatefulWidget {
  const AddonDialog({required this.orgId, super.key});

  final String orgId;

  @override
  ConsumerState<AddonDialog> createState() => _AddonDialogState();
}

class _AddonDialogState extends ConsumerState<AddonDialog> {
  String _name = '';
  String _nameAr = '';
  String _groupId = '';
  String _price = '0';
  bool _active = true;
  bool _submitted = false;
  bool _busy = false;

  Future<void> _save() async {
    final t = ref.read(tProvider);
    setState(() => _submitted = true);
    if (validateAddon(
      name: _name,
      groupId: _groupId,
      price: _price,
      t: t,
    ).isNotEmpty) {
      return;
    }
    setState(() => _busy = true);
    final invalidate = ref.menuInvalidate;
    try {
      final created = await ref
          .read(apiProvider)
          .menu
          .createOption(
            gid: _groupId,
            body: CreateOptionRequest(
              name: _name,
              nameTranslations: _nameAr.isEmpty ? null : {'ar': _nameAr},
              price: egpToPiastres(jsNumber(_price)),
              isActive: _active,
            ),
          );
      invalidate.catalog();
      if (!mounted) return;
      DashToast.success(context, t('common.savedChanges'));
      Navigator.of(context).pop(created);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  Future<void> _newGroup() async {
    final container = ProviderScope.containerOf(context, listen: false);
    final g = await showGroupEditorDialog(context, orgId: widget.orgId);
    if (g == null) return;
    // The web's `groupsQ.refetch()`, then the new group is the pick.
    container.invalidate(modifierGroupsProvider(widget.orgId));
    if (mounted) setState(() => _groupId = g.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final groups =
        ref.watch(modifierGroupsProvider(widget.orgId)).value ??
        const <GroupOut>[];
    // Shared groups only; an item's private "Options" set has no legacy type.
    final choices = [
      for (final g in groups)
        if (g.legacyAddonType != null) g,
    ];
    final canEditGroups = ref.watch(
      authzProvider.select((a) => a.can(Cap.menuItemsEdit)),
    );
    final errors = _submitted
        ? validateAddon(name: _name, groupId: _groupId, price: _price, t: t)
        : const <String, String>{};
    final twoUp = !DashBreakpoints.isPhone(context);

    final group = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xs,
      children: [
        DashSelectField<String>(
          key: const ValueKey('addon-group'),
          label: t('menu.groups.addonGroup'),
          placeholder: t('common.select'),
          value: _groupId.isEmpty ? null : _groupId,
          errorText: errors['group_id'],
          options: [
            for (final g in choices) DashOption(value: g.id, label: g.name),
          ],
          onChanged: (v) => setState(() => _groupId = v),
        ),
        if (canEditGroups)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashButton(
              label: t('menu.groups.new'),
              icon: 'plus',
              variant: DashButtonVariant.link,
              size: DashButtonSize.compact,
              onPressed: _newGroup,
            ),
          ),
      ],
    );
    final price = DashTextField(
      key: const ValueKey('addon-price'),
      label: t('menu.defaultPrice'),
      value: _price,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      errorText: errors['default_price'],
      onChanged: (v) => setState(() => _price = cleanDecimal(v)),
    );

    return DashSurface(
      title: t('menu.newAddon'),
      description: t('menu.addonDesc'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          DashBilingualField(
            label: t('common.name'),
            en: _name,
            ar: _nameAr,
            enError: errors['name'],
            onEnChanged: (v) => setState(() => _name = v),
            onArChanged: (v) => setState(() => _nameAr = v),
          ),
          if (twoUp)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Expanded(child: group),
                Expanded(child: price),
              ],
            )
          else ...[
            group,
            price,
          ],
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.sm,
            children: [
              Text(
                t('common.active'),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              DashSwitch(
                value: _active,
                semanticLabel: t('common.active'),
                onChanged: (v) => setState(() => _active = v),
              ),
            ],
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(label: t('common.save'), loading: _busy, onPressed: _save),
      ],
    );
  }
}
