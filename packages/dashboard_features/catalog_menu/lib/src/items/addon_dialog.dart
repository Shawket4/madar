/// The add-on dialog (the web's `addon-dialog.tsx`, MENU-ITEMS-093..101,
/// 113): an add-on is an option inside a shared choice group. Create picks
/// the group (or makes one with "New group", `menu.items.edit` only); edit
/// shows the group, locked. Save → `POST /modifier-groups/{gid}/options` or
/// `PATCH /modifier-options/{oid}`, then the catalog is invalidated.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show AddonItem, CreateOptionRequest, GroupOut, PatchOptionRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../groups/group_editor_dialog.dart';
import '../shared/menu_bilingual_field.dart';
import '../shared/menu_providers.dart';
import '../shared/menu_queries.dart';
import '../shared/menu_text.dart';
import 'items_data.dart';
import 'items_widgets.dart';

Future<void> showAddonDialog(
  BuildContext context, {
  required String orgId,
  AddonItem? addon,
}) => showDashDialog<void>(
  context,
  builder: (_) => AddonDialog(orgId: orgId, addon: addon),
);

class AddonDialog extends ConsumerStatefulWidget {
  const AddonDialog({required this.orgId, this.addon, super.key});

  final String orgId;

  /// Null = a new add-on.
  final AddonItem? addon;

  @override
  ConsumerState<AddonDialog> createState() => _AddonDialogState();
}

class _AddonDialogState extends ConsumerState<AddonDialog> {
  late String _name = widget.addon?.name ?? '';
  late String _nameAr = arOf(widget.addon?.nameTranslations);
  String? _groupId;
  late String _price = widget.addon == null
      ? '0'
      : egpText(widget.addon!.defaultPrice);
  late bool _active = widget.addon?.isActive ?? true;
  String? _nameError;
  String? _groupError;
  bool _busy = false;

  /// The person has changed the form: fresh reads stop re-seeding it.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    final a = widget.addon;
    if (a == null) return;
    // The add-on came from the (possibly older) list: each fresh read of it
    // re-seeds the form until the person edits it.
    ref.listenManual(addonItemsProvider(widget.orgId), (prev, next) {
      final list = next.value;
      if (list == null || _touched || identical(list, prev?.value)) return;
      final fresh = list.where((x) => x.id == a.id).firstOrNull;
      if (fresh == null) return;
      setState(() {
        _name = fresh.name;
        _nameAr = arOf(fresh.nameTranslations);
        _price = egpText(fresh.defaultPrice);
        _active = fresh.isActive;
      });
    });
  }

  void _edit(VoidCallback change) => setState(() {
    _touched = true;
    change();
  });

  GroupsQuery get _groupsKey => (orgId: widget.orgId, includeInactive: false);

  /// Editing: the option's group, once the groups are in.
  String? _groupOf(List<GroupOut> groups) {
    final a = widget.addon;
    if (a == null) return _groupId;
    for (final g in groups) {
      if (g.options.any((o) => o.id == a.id)) return g.id;
    }
    return null;
  }

  Future<void> _newGroup() async {
    final g = await showGroupEditorDialog(context, orgId: widget.orgId);
    if (g == null || !mounted) return;
    ref.invalidate(modifierGroupsProvider(_groupsKey));
    setState(() {
      _groupId = g.id;
      _groupError = null;
    });
  }

  Future<void> _save() async {
    if (_busy) return;
    final t = ref.read(tProvider);
    final groups = ref.read(modifierGroupsProvider(_groupsKey)).value ?? [];
    final groupId = _groupOf(groups);
    setState(() {
      // zod `min(1)` on the raw text.
      _nameError = _name.isEmpty ? t('common.requiredField') : null;
      _groupError = (groupId ?? '').isEmpty ? t('common.requiredField') : null;
    });
    if (_nameError != null || _groupError != null) return;
    setState(() => _busy = true);
    final translations = _nameAr.isEmpty
        ? null
        : <String, Object?>{'ar': _nameAr};
    final price = egpTextToPiastres(_price) ?? 0;
    final api = ref.read(apiProvider).menu;
    final invalidate = ref.menuInvalidate;
    try {
      final a = widget.addon;
      if (a != null) {
        await api.patchOption(
          oid: a.id,
          body: PatchOptionRequest(
            name: _name,
            nameTranslations: translations,
            price: price,
            isActive: _active,
          ),
        );
      } else {
        await api.createOption(
          gid: groupId!,
          body: CreateOptionRequest(
            name: _name,
            nameTranslations: translations,
            price: price,
            isActive: _active,
          ),
        );
      }
      invalidate.catalog();
      if (!mounted) return;
      DashToast.success(context, t('common.savedChanges'));
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final editing = widget.addon != null;
    final canEditGroups = ref.watch(
      authzProvider.select((a) => a.can(Cap.menuItemsEdit)),
    );
    final groups =
        ref.watch(modifierGroupsProvider(_groupsKey)).value ??
        const <GroupOut>[];
    final choices = [
      for (final g in groups)
        if (g.legacyAddonType != null) g,
    ];
    final groupField = DashSelectField<String>(
      label: t('menu.groups.addonGroup'),
      placeholder: t('common.select'),
      enabled: !editing,
      errorText: _groupError,
      value: _groupOf(groups),
      options: [
        for (final g in choices)
          DashOption(
            value: g.id,
            label: translatedName(g.name, g.nameTranslations, t.lang),
          ),
      ],
      onChanged: (v) => _edit(() {
        _groupId = v;
        _groupError = null;
      }),
    );
    final groupColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        groupField,
        if (editing)
          Text(
            t('menu.addonTypeLocked'),
            style: DashType.small.copyWith(color: c.textSecondary),
          )
        else if (canEditGroups)
          DashButton(
            label: t('menu.groups.new'),
            icon: 'plus',
            variant: DashButtonVariant.link,
            size: DashButtonSize.compact,
            onPressed: _newGroup,
          ),
      ],
    );
    final priceField = MenuPriceField(
      label: t('menu.defaultPrice'),
      value: _price,
      onChanged: (v) => _edit(() => _price = v),
      onSubmit: _save,
    );
    return DashSurface(
      title: editing ? t('menu.editAddon') : t('menu.newAddon'),
      description: t('menu.addonDesc'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          MenuBilingualField(
            label: t('common.name'),
            en: _name,
            ar: _nameAr,
            enError: _nameError,
            onEnChanged: (v) => _edit(() => _name = v),
            onArChanged: (v) => _edit(() => _nameAr = v),
            onSubmit: _save,
          ),
          LayoutBuilder(
            builder: (context, box) =>
                box.maxWidth >= DashBreakpoints.sm - Space.xxl * 4
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.md,
                    children: [
                      Expanded(child: groupColumn),
                      Expanded(child: priceField),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: Space.md,
                    children: [groupColumn, priceField],
                  ),
          ),
          DashSwitchField(
            label: t('common.active'),
            value: _active,
            onChanged: (v) => _edit(() => _active = v),
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
