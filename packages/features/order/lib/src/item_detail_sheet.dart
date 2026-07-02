import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:feature_order/src/cart_panel.dart';
import 'package:feature_order/src/order_controller.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// A host-only draft of one configured bundle component (what the
/// per-component sheet pops in configure mode). [extrasMinor] is the
/// resolved addon/optional up-charge, summed into the bundle's live total.
@immutable
class BundleComponentDraft {
  const BundleComponentDraft({
    required this.sizeLabel,
    required this.addons,
    required this.optionalIds,
    required this.extrasMinor,
  });

  final String? sizeLabel;
  final List<AddonSelection> addons;
  final List<String> optionalIds;
  final int extrasMinor;
}

/// An addon group shown in the sheet — a slot (labelled, min/max, required)
/// or a global `type:` bucket.
class _Group {
  const _Group({
    required this.id,
    required this.title,
    required this.addons,
    required this.isMulti,
    required this.maxSel,
    required this.isRequired,
    required this.minSel,
  });

  final String id;
  final String title;
  final List<ItemAddonView> addons;
  final bool isMulti;
  final int? maxSel;
  final bool isRequired;
  final int minSel;
}

/// Item customization — size, addons (per slot + global types), optional
/// fields, live recipe preview, notes, qty. Prices come pre-resolved from
/// the core; this only displays and sums.
///
/// Bundle-component configure mode: when [isConfiguring] the footer SAVES
/// the selection back (pops a [BundleComponentDraft], no cart write), seeded
/// from [configureSeed], and the qty stepper is hidden.
class ItemDetailSheet extends StatefulWidget {
  const ItemDetailSheet({
    required this.model,
    required this.item,
    required this.addons,
    this.editLine,
    this.configureSeed,
    this.isConfiguring = false,
    super.key,
  });

  final OrderController model;
  final MenuItemView item;

  /// The item's addons with charged prices resolved by the core.
  final List<ItemAddonView> addons;

  /// Edit mode: the cart line being reconfigured (null = adding fresh).
  final CartLineView? editLine;

  /// Configure mode: the previously saved component draft to seed from.
  final BundleComponentDraft? configureSeed;
  final bool isConfiguring;

  @override
  State<ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<ItemDetailSheet> {
  String? _size;
  final Map<String, String> _single = {}; // groupId -> addonId
  Map<String, Map<String, int>> _multi = {}; // groupId -> addonId -> qty
  Set<String> _optionals = {};
  int _qty = 1;

  /// Reveal the FULL org addon catalog (every type), not just the item's
  /// assigned slots + global types.
  bool _showAll = false;

  /// The recipe section, revealed by the header recipe button.
  bool _showRecipe = false;
  List<ComputedRecipeLineView> _recipeLines = const [];

  /// Per-group search (only when a group has many addons) + the optional
  /// fields' own search.
  final Map<String, String> _addonSearch = {};
  final _optionalSearchField = TextEditingController();
  String _optionalSearch = '';

  final _notes = TextEditingController();

  static const _baseTypes = ['milk_type', 'coffee_type', 'extra'];

  MenuItemView get _item => widget.item;

  @override
  void initState() {
    super.initState();
    _seed();
  }

  @override
  void dispose() {
    _optionalSearchField.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// Restore a saved addon (id + qty) into the right group — by its TYPE →
  /// slot / global `type:` bucket, NOT the on-screen groups (which the
  /// allowlist / "show all" filter may hide), so a selection never drops.
  void _placeAddon(
    Map<String, Map<String, int>> multi,
    String addonItemId,
    int qty,
  ) {
    final type = widget.addons
        .where((a) => a.addonItemId == addonItemId)
        .firstOrNull
        ?.addonType;
    if (type == null) return;
    final slot = _item.addonSlots.where((s) => s.addonType == type).firstOrNull;
    if (slot != null) {
      if ((slot.maxSelections ?? 2) > 1) {
        multi.putIfAbsent(slot.id, () => {})[addonItemId] = qty;
      } else {
        _single[slot.id] = addonItemId;
      }
    } else {
      final gid = 'type:$type';
      if (type != 'milk_type') {
        multi.putIfAbsent(gid, () => {})[addonItemId] = qty;
      } else {
        _single[gid] = addonItemId;
      }
    }
  }

  void _seed() {
    final newMulti = <String, Map<String, int>>{};
    final seed = widget.configureSeed;
    final editLine = widget.editLine;
    if (widget.isConfiguring) {
      if (seed != null) {
        _size = seed.sizeLabel ?? _item.sizes.firstOrNull?.label;
        for (final a in seed.addons) {
          _placeAddon(newMulti, a.addonItemId, a.qty);
        }
        _multi = newMulti;
        _optionals = seed.optionalIds.toSet();
      } else {
        _size = _item.sizes.firstOrNull?.label;
        final milk = _item.defaultMilkAddonId;
        if (milk != null) _single['type:milk_type'] = milk;
      }
    } else if (editLine != null) {
      // Edit mode: reconstruct the selection from the existing line.
      _size = editLine.sizeLabel ?? _item.sizes.firstOrNull?.label;
      for (final a in editLine.addons) {
        _placeAddon(newMulti, a.addonItemId, a.qty);
      }
      _multi = newMulti;
      _optionals = editLine.optionals.map((o) => o.optionalFieldId).toSet();
      _notes.text = editLine.notes ?? '';
      _qty = editLine.qty < 1 ? 1 : editLine.qty;
    } else {
      _size = _item.sizes.firstOrNull?.label;
      final milk = _item.defaultMilkAddonId;
      if (milk != null) _single['type:milk_type'] = milk;
    }
  }

  // ── group derivation ─────────────────────────────────────────────────────
  String _typeLabel(String type) => switch (type) {
    'milk_type' => widget.model.tr('order.addon_milk_type'),
    'coffee_type' => widget.model.tr('order.addon_coffee_type'),
    'extra' => widget.model.tr('order.addon_extra'),
    _ =>
      type
          .split('_')
          .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
          .join(' '),
  };

  /// Default view = the item's AVAILABLE add-ons only. A SLOT always shows
  /// its options; an allow-listed item filters each type to those options;
  /// "show all" drops the filter entirely.
  List<ItemAddonView> _visibleAddons(
    List<ItemAddonView> all, {
    required bool isSlot,
  }) {
    if (_showAll || isSlot) return all;
    final allowed = _item.allowedAddonIds;
    if (allowed.isEmpty) return all;
    final set = allowed.toSet();
    return all
        .where((a) => set.contains(a.addonItemId))
        .toList(growable: false);
  }

  List<_Group> _buildGroups(Map<String, List<ItemAddonView>> addonsByType) {
    final groups = <_Group>[];
    final slotTypes = _item.addonSlots.map((s) => s.addonType).toSet();
    for (final slot in _item.addonSlots) {
      final addons = _visibleAddons(
        addonsByType[slot.addonType] ?? const [],
        isSlot: true,
      );
      if (addons.isEmpty) continue;
      final isMulti = (slot.maxSelections ?? 2) > 1;
      groups.add(
        _Group(
          id: slot.id,
          title: slot.label ?? _typeLabel(slot.addonType),
          addons: addons,
          isMulti: isMulti,
          maxSel: slot.maxSelections,
          isRequired: slot.isRequired,
          minSel: slot.minSelections,
        ),
      );
    }
    final extraTypes = _showAll
        ? [
            ..._baseTypes,
            ...addonsByType.keys.where((t) => !_baseTypes.contains(t)).toList()
              ..sort(),
          ]
        : _baseTypes;
    for (final type in extraTypes) {
      if (slotTypes.contains(type)) continue;
      final addons = _visibleAddons(
        addonsByType[type] ?? const [],
        isSlot: false,
      );
      if (addons.isEmpty) continue;
      groups.add(
        _Group(
          id: 'type:$type',
          title: _typeLabel(type),
          addons: addons,
          isMulti: type != 'milk_type',
          maxSel: null,
          isRequired: false,
          minSel: 0,
        ),
      );
    }
    return groups;
  }

  // ── selection + pricing ──────────────────────────────────────────────────
  int _charged(String addonItemId) =>
      widget.addons
          .where((a) => a.addonItemId == addonItemId)
          .firstOrNull
          ?.chargedPriceMinor ??
      0;

  List<AddonSelection> get _selectedAddons => [
    for (final id in _single.values) AddonSelection(addonItemId: id, qty: 1),
    for (final group in _multi.values)
      for (final entry in group.entries)
        AddonSelection(addonItemId: entry.key, qty: entry.value),
  ];

  // ── mutations ────────────────────────────────────────────────────────────
  void _toggleSingle(_Group g, String addonId) {
    setState(() {
      if (_single[g.id] == addonId) {
        if (!g.isRequired) _single.remove(g.id);
      } else {
        _single[g.id] = addonId;
      }
    });
    _maybeRefreshRecipe();
  }

  void _toggleMulti(_Group g, String addonId) {
    final m = {...?_multi[g.id]};
    if (m.containsKey(addonId)) {
      m.remove(addonId);
    } else if (g.maxSel == null || m.length < g.maxSel!) {
      m[addonId] = 1;
    } else {
      widget.model.showToast(
        '${g.title}: ${widget.model.tr('order.max_reached')} (≤${g.maxSel})',
        tone: ChipTone.warning,
        icon: 'hand.raised',
      );
      return;
    }
    setState(() {
      _multi = {..._multi};
      if (m.isEmpty) {
        _multi.remove(g.id);
      } else {
        _multi[g.id] = m;
      }
    });
    _maybeRefreshRecipe();
  }

  void _incMulti(_Group g, String addonId) {
    setState(() {
      final m = {...?_multi[g.id]};
      m[addonId] = (m[addonId] ?? 1) + 1;
      _multi = {..._multi, g.id: m};
    });
    _maybeRefreshRecipe();
  }

  void _decMulti(_Group g, String addonId) {
    setState(() {
      final m = {...?_multi[g.id]};
      final cur = m[addonId] ?? 1;
      if (cur <= 1) {
        m.remove(addonId);
      } else {
        m[addonId] = cur - 1;
      }
      _multi = {..._multi};
      if (m.isEmpty) {
        _multi.remove(g.id);
      } else {
        _multi[g.id] = m;
      }
    });
    _maybeRefreshRecipe();
  }

  void _toggleOptional(String fieldId) {
    setState(() {
      _optionals = _optionals.contains(fieldId)
          ? (_optionals.toSet()..remove(fieldId))
          : {..._optionals, fieldId};
    });
    _maybeRefreshRecipe();
  }

  // ── recipe preview ───────────────────────────────────────────────────────
  void _maybeRefreshRecipe() {
    if (!_showRecipe) return;
    unawaited(_refreshRecipe());
  }

  Future<void> _refreshRecipe() async {
    final lines = await widget.model.recipePreview(
      itemId: _item.id,
      sizeLabel: _size,
      addons: _selectedAddons,
      optionalIds: _optionals.toList(growable: false),
    );
    if (!mounted) return;
    setState(() => _recipeLines = lines);
  }

  // ── commit ───────────────────────────────────────────────────────────────
  Future<void> _commit(int extrasMinor) async {
    if (widget.isConfiguring) {
      await Navigator.of(context).maybePop(
        BundleComponentDraft(
          sizeLabel: _size,
          addons: _selectedAddons,
          optionalIds: _optionals.toList(growable: false),
          extrasMinor: extrasMinor,
        ),
      );
      return;
    }
    final notes = _notes.text.trim();
    await widget.model.addConfigured(
      itemId: _item.id,
      sizeLabel: _size,
      addons: _selectedAddons,
      optionalIds: _optionals.toList(growable: false),
      qty: _qty,
      notes: notes.isEmpty ? null : notes,
      replaceLineKey: widget.editLine?.key,
    );
    if (mounted) await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final colors = context.madarColors;
    final currency = model.currency;

    final addonsByType = <String, List<ItemAddonView>>{};
    for (final addon in widget.addons) {
      addonsByType.putIfAbsent(addon.addonType, () => []).add(addon);
    }
    final groups = _buildGroups(addonsByType);
    final slotTypes = _item.addonSlots.map((s) => s.addonType).toSet();
    // True when "Show all" would reveal more than the default view.
    final hasMore =
        _item.allowedAddonIds.isNotEmpty ||
        addonsByType.keys.any(
          (t) => !slotTypes.contains(t) && !_baseTypes.contains(t),
        );

    // Pricing (display only) — the core re-resolves on add.
    final unitPrice =
        _item.sizes.where((s) => s.label == _size).firstOrNull?.priceMinor ??
        _item.basePriceMinor;
    final addonsTotal = _selectedAddons.fold(
      0,
      (sum, sel) => sum + _charged(sel.addonItemId) * sel.qty,
    );
    final optionalsTotal = _item.optionalFields
        .where((f) => _optionals.contains(f.id))
        .fold(0, (sum, f) => sum + f.priceMinor);
    final headerTotal = unitPrice + addonsTotal + optionalsTotal;
    final extrasMinor = addonsTotal + optionalsTotal;

    _Group? firstUnsatisfied;
    for (final g in groups) {
      final count = g.isMulti
          ? (_multi[g.id]?.length ?? 0)
          : (_single[g.id] != null ? 1 : 0);
      final needed = g.minSel > 1 ? g.minSel : 1;
      if (g.isRequired && count < needed) {
        firstUnsatisfied = g;
        break;
      }
    }
    final canAdd = firstUnsatisfied == null;

    final footerLabel = !canAdd
        ? '${model.tr('order.select_prefix')} ${firstUnsatisfied.title}'
        : widget.isConfiguring
        ? model.tr('order.save_component')
        : widget.editLine == null
        ? model.tr('order.add_to_cart')
        : model.tr('order.update_item');
    // Configure mode sums only the extras (the bundle covers the base).
    final footerPrice = widget.isConfiguring ? extrasMinor : headerTotal * _qty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SheetHeader(
          model: model,
          item: _item,
          headerTotalMinor: headerTotal,
          currency: currency,
          showRecipe: _showRecipe,
          onToggleRecipe: () {
            setState(() => _showRecipe = !_showRecipe);
            if (_showRecipe) unawaited(_refreshRecipe());
          },
        ),
        // Hug content when it fits (short sheet for a sparse item); scroll
        // when the options overflow — the footer stays pinned + visible.
        Flexible(
          child: ColoredBox(
            color: colors.surfaceAlt,
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.only(
                start: Space.xl,
                end: Space.xl,
                top: Space.lg,
                bottom: Space.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_showRecipe && _recipeLines.isNotEmpty) ...[
                    SectionTitle(model.tr('order.recipe')),
                    const SizedBox(height: Space.sm),
                    for (final line in _recipeLines) ...[
                      _RecipeRow(line: line),
                      const SizedBox(height: Space.sm),
                    ],
                    const SizedBox(height: Space.xs),
                  ],
                  if (_item.sizes.isNotEmpty) ...[
                    SectionTitle(model.tr('order.size')),
                    const SizedBox(height: Space.sm),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final size in _item.sizes) ...[
                            _SelectChip(
                              label: size.label,
                              sub: Money.format(
                                size.priceMinor,
                                currency: currency,
                              ),
                              active: _size == size.label,
                              onTap: () {
                                setState(() => _size = size.label);
                                _maybeRefreshRecipe();
                              },
                            ),
                            const SizedBox(width: Space.sm),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.md),
                  ],
                  for (final g in groups) ...[
                    _AddonGroupCard(
                      // Stable identity: the "show all" toggle inserts /
                      // removes groups, and each card carries its own
                      // search-field state.
                      key: ValueKey(g.id),
                      group: g,
                      model: model,
                      currency: currency,
                      charged: _charged,
                      selectedSingle: _single[g.id],
                      selectedMulti: _multi[g.id] ?? const {},
                      query: _addonSearch[g.id] ?? '',
                      onQueryChange: (q) =>
                          setState(() => _addonSearch[g.id] = q),
                      onToggleSingle: (id) => _toggleSingle(g, id),
                      onToggleMulti: (id) => _toggleMulti(g, id),
                      onInc: (id) => _incMulti(g, id),
                      onDec: (id) => _decMulti(g, id),
                    ),
                    const SizedBox(height: Space.md),
                  ],
                  if (hasMore)
                    _ShowAllToggle(
                      showAll: _showAll,
                      label: model.tr(
                        _showAll
                            ? 'order.show_assigned_addons'
                            : 'order.show_all_addons',
                      ),
                      onToggle: () => setState(() => _showAll = !_showAll),
                    ),
                  ..._optionalsSection(model, currency),
                  if (!widget.isConfiguring) ...[
                    SectionTitle(model.tr('order.notes')),
                    const SizedBox(height: Space.sm),
                    OrderTextField(
                      controller: _notes,
                      placeholder: model.tr('order.notes_hint'),
                      icon: 'text.bubble',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        _SheetFooter(
          model: model,
          currency: currency,
          totalMinor: footerPrice,
          label: footerLabel,
          canAdd: canAdd,
          showQty: !widget.isConfiguring,
          qty: _qty,
          onDec: () => setState(() => _qty = _qty > 1 ? _qty - 1 : 1),
          onInc: () => setState(() => _qty = _qty < 99 ? _qty + 1 : 99),
          onCommit: () => unawaited(_commit(extrasMinor)),
        ),
      ],
    );
  }

  List<Widget> _optionalsSection(OrderController model, String currency) {
    final fields = _item.optionalFields
        .where((f) => f.isActive)
        .toList(growable: false);
    if (fields.isEmpty) return const [];
    final q = _optionalSearch.trim().toLowerCase();
    final shown = q.isEmpty
        ? fields
        : fields
              .where(
                (f) =>
                    f.name.toLowerCase().contains(q) ||
                    _optionals.contains(f.id),
              )
              .toList(growable: false);
    return [
      const SizedBox(height: Space.md),
      SectionTitle(model.tr('order.optionals')),
      const SizedBox(height: Space.sm),
      if (fields.length > 4) ...[
        OrderTextField(
          controller: _optionalSearchField,
          placeholder: model.tr('order.search_addons'),
          icon: 'magnifyingglass',
          onChanged: (v) => setState(() => _optionalSearch = v),
        ),
        const SizedBox(height: Space.sm),
      ],
      Wrap(
        spacing: Space.sm,
        runSpacing: Space.sm,
        children: [
          for (final field in shown)
            _OptionalChip(
              name: field.name,
              priceMinor: field.priceMinor,
              on: _optionals.contains(field.id),
              currency: currency,
              onTap: () => _toggleOptional(field.id),
            ),
        ],
      ),
      const SizedBox(height: Space.md),
    ];
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.model,
    required this.item,
    required this.headerTotalMinor,
    required this.currency,
    required this.showRecipe,
    required this.onToggleRecipe,
  });

  final OrderController model;
  final MenuItemView item;
  final int headerTotalMinor;
  final String currency;
  final bool showRecipe;
  final VoidCallback onToggleRecipe;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final description = item.description;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.xl,
              vertical: Space.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: MadarType.h3.copyWith(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (description != null && description.isNotEmpty)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(top: 2),
                          child: Text(
                            description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: MadarType.label.copyWith(
                              fontWeight: FontWeight.w400,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: Space.md),
                // Price badge · recipe chip · close, on a common baseline.
                Container(
                  height: Metrics.closeButton,
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: 10,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.navyBg,
                    borderRadius: BorderRadius.circular(Radii.sm),
                  ),
                  child: MoneyText(
                    headerTotalMinor,
                    currency: currency,
                    color: colors.navy,
                  ),
                ),
                if (item.recipes.isNotEmpty) ...[
                  const SizedBox(width: Space.sm),
                  TactileScale(
                    onTap: () {
                      MadarHaptics.selection();
                      onToggleRecipe();
                    },
                    child: Container(
                      width: Metrics.closeButton,
                      height: Metrics.closeButton,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: showRecipe ? colors.accent : colors.accentBg,
                        borderRadius: BorderRadius.circular(Radii.sm),
                      ),
                      child: MadarIcon(
                        'list.bullet.rectangle',
                        tint: showRecipe ? colors.textOnAccent : colors.accent,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: Space.sm),
                TactileScale(
                  onTap: () => unawaited(Navigator.of(context).maybePop()),
                  child: Container(
                    width: Metrics.closeButton,
                    height: Metrics.closeButton,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(Radii.sm),
                      border: Border.all(color: colors.borderLight),
                    ),
                    child: MadarIcon(
                      'xmark',
                      tint: colors.textMuted,
                      size: IconSize.sm,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: colors.border),
        ],
      ),
    );
  }
}

// ── Footer ─────────────────────────────────────────────────────────────────────

class _SheetFooter extends StatelessWidget {
  const _SheetFooter({
    required this.model,
    required this.currency,
    required this.totalMinor,
    required this.label,
    required this.canAdd,
    required this.showQty,
    required this.qty,
    required this.onDec,
    required this.onInc,
    required this.onCommit,
  });

  final OrderController model;
  final String currency;
  final int totalMinor;
  final String label;
  final bool canAdd;
  final bool showQty;
  final int qty;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return ColoredBox(
      color: colors.surface,
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.xl,
          vertical: Space.md,
        ),
        child: Column(
          children: [
            Container(height: 1, color: colors.border),
            const SizedBox(height: Space.md),
            GrandTotalBlock(
              label: model.tr('order.total'),
              totalMinor: totalMinor,
              currency: currency,
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                if (showQty) ...[
                  StepButton(glyph: 'minus', onTap: onDec),
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 24 + Space.sm * 2,
                    ),
                    child: Text(
                      '$qty',
                      textAlign: TextAlign.center,
                      style: MadarType.h3.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  StepButton(glyph: 'plus', onTap: onInc),
                  const SizedBox(width: Space.md),
                ],
                Expanded(
                  child: ActionButton(
                    label: label,
                    enabled: canAdd,
                    onTap: onCommit,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recipe row ─────────────────────────────────────────────────────────────────

/// One card per ingredient: a fixed quantity box on the start side, the name
/// in the middle, the source chip pinned to the end. Base = navy card.
class _RecipeRow extends StatelessWidget {
  const _RecipeRow({required this.line});

  final ComputedRecipeLineView line;

  /// Whole numbers without a decimal, else the shortest form.
  static String _fmtQty(double q) =>
      q == q.truncateToDouble() ? q.toInt().toString() : '$q';

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.md,
        vertical: Space.md,
      ),
      decoration: BoxDecoration(
        color: line.isBase ? colors.navyBg : colors.surface,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(
          color: line.isBase
              ? colors.navy.withValues(alpha: Opacities.border)
              : colors.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: Metrics.ingredientBox,
            padding: const EdgeInsetsDirectional.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(Radii.xs),
              border: Border.all(color: colors.borderLight),
            ),
            child: Column(
              children: [
                Text(
                  _fmtQty(line.quantity),
                  style: MadarType.body.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  line.unit,
                  style: MadarType.labelSm.copyWith(
                    fontSize: 10,
                    color: colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              line.ingredientName,
              style: MadarType.body.copyWith(
                fontWeight: line.isBase ? FontWeight.w700 : FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          StatusChip(
            label: line.sourceLabel.toUpperCase(),
            tone: line.isBase ? ChipTone.accent : ChipTone.neutral,
          ),
        ],
      ),
    );
  }
}

// ── Addon group card ───────────────────────────────────────────────────────────

/// A bordered surface card per group: a dotted uppercase header with
/// required / max / count chips, an optional search field (>5 options),
/// then the option chips.
class _AddonGroupCard extends StatefulWidget {
  const _AddonGroupCard({
    required this.group,
    required this.model,
    required this.currency,
    required this.charged,
    required this.selectedSingle,
    required this.selectedMulti,
    required this.query,
    required this.onQueryChange,
    required this.onToggleSingle,
    required this.onToggleMulti,
    required this.onInc,
    required this.onDec,
    super.key,
  });

  final _Group group;
  final OrderController model;
  final String currency;
  final int Function(String addonItemId) charged;
  final String? selectedSingle;
  final Map<String, int> selectedMulti;
  final String query;
  final ValueChanged<String> onQueryChange;
  final ValueChanged<String> onToggleSingle;
  final ValueChanged<String> onToggleMulti;
  final ValueChanged<String> onInc;
  final ValueChanged<String> onDec;

  @override
  State<_AddonGroupCard> createState() => _AddonGroupCardState();
}

class _AddonGroupCardState extends State<_AddonGroupCard> {
  late final _search = TextEditingController(text: widget.query);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final g = widget.group;
    final count = g.isMulti
        ? widget.selectedMulti.length
        : (widget.selectedSingle != null ? 1 : 0);
    // Filter by the live query; selected chips always stay visible so a
    // filter never hides an active selection.
    final q = widget.query.trim().toLowerCase();
    final shown = q.isEmpty
        ? g.addons
        : g.addons
              .where(
                (a) =>
                    a.name.toLowerCase().contains(q) ||
                    (g.isMulti
                        ? widget.selectedMulti.containsKey(a.addonItemId)
                        : widget.selectedSingle == a.addonItemId),
              )
              .toList(growable: false);

    return Container(
      padding: const EdgeInsetsDirectional.all(Space.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: Space.sm),
              ),
              const SizedBox(width: Space.sm),
              // Title flexes + ellipsizes so a long group name can't push
              // the chips off the end edge.
              Expanded(
                child: Text(
                  g.title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.labelSm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                    letterSpacing: MadarType.tracking,
                  ),
                ),
              ),
              if (g.isRequired) ...[
                const SizedBox(width: Space.sm),
                StatusChip(
                  label: widget.model.tr('order.required'),
                  tone: ChipTone.danger,
                ),
              ],
              if (g.isMulti && g.maxSel != null) ...[
                const SizedBox(width: Space.sm),
                StatusChip(label: '≤${g.maxSel}'),
              ],
              if (count > 0) ...[
                const SizedBox(width: Space.sm),
                StatusChip(label: '$count', tone: ChipTone.accent),
              ],
            ],
          ),
          const SizedBox(height: Space.md),
          if (g.addons.length > 5) ...[
            OrderTextField(
              controller: _search,
              placeholder: widget.model.tr('order.search_addons'),
              icon: 'magnifyingglass',
              onChanged: widget.onQueryChange,
            ),
            const SizedBox(height: Space.md),
          ],
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final addon in shown)
                if (g.isMulti &&
                    widget.selectedMulti.containsKey(addon.addonItemId))
                  _AddonQtyChip(
                    name: addon.name,
                    priceMinor: widget.charged(addon.addonItemId),
                    qty: widget.selectedMulti[addon.addonItemId] ?? 1,
                    currency: widget.currency,
                    onDec: () => widget.onDec(addon.addonItemId),
                    onInc: () => widget.onInc(addon.addonItemId),
                  )
                else
                  _AddonOptionChip(
                    name: addon.name,
                    priceMinor: widget.charged(addon.addonItemId),
                    selected:
                        !g.isMulti &&
                        widget.selectedSingle == addon.addonItemId,
                    multi: g.isMulti,
                    currency: widget.currency,
                    onTap: () => g.isMulti
                        ? widget.onToggleMulti(addon.addonItemId)
                        : widget.onToggleSingle(addon.addonItemId),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Chips ──────────────────────────────────────────────────────────────────────

/// A selectable addon chip: accent fill when selected; multi chips show a
/// leading plus while unselected.
class _AddonOptionChip extends StatelessWidget {
  const _AddonOptionChip({
    required this.name,
    required this.priceMinor,
    required this.selected,
    required this.multi,
    required this.currency,
    required this.onTap,
  });

  final String name;
  final int priceMinor;
  final bool selected;
  final bool multi;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = selected ? colors.textOnAccent : colors.textPrimary;
    return TactileScale(
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.md,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accent : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.xs),
          border: selected ? null : Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (multi && !selected) ...[
              MadarIcon(
                'plus',
                tint: colors.textPrimary.withValues(alpha: 0.6),
                size: IconSize.xs,
              ),
              const SizedBox(width: 6),
            ],
            Text(
              name,
              style: MadarType.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (priceMinor > 0) ...[
              const SizedBox(width: 6),
              _PricePill(
                priceMinor: priceMinor,
                on: selected,
                currency: currency,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// An optional-field toggle chip: check-circle leading glyph, accent fill
/// when on.
class _OptionalChip extends StatelessWidget {
  const _OptionalChip({
    required this.name,
    required this.priceMinor,
    required this.on,
    required this.currency,
    required this.onTap,
  });

  final String name;
  final int priceMinor;
  final bool on;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = on ? colors.textOnAccent : colors.textPrimary;
    return TactileScale(
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.md,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: on ? colors.accent : colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.xs),
          border: on ? null : Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MadarIcon(
              on ? 'checkmark.circle.fill' : 'circle',
              tint: fg,
              size: IconSize.xs,
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: MadarType.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (priceMinor > 0) ...[
              const SizedBox(width: 6),
              _PricePill(priceMinor: priceMinor, on: on, currency: currency),
            ],
          ],
        ),
      ),
    );
  }
}

/// A selected multi-select chip with an inline qty stepper.
class _AddonQtyChip extends StatelessWidget {
  const _AddonQtyChip({
    required this.name,
    required this.priceMinor,
    required this.qty,
    required this.currency,
    required this.onDec,
    required this.onInc,
  });

  final String name;
  final int priceMinor;
  final int qty;
  final String currency;
  final VoidCallback onDec;
  final VoidCallback onInc;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.xs,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChipStep(glyph: 'minus', onTap: onDec),
          const SizedBox(width: 2),
          Column(
            children: [
              Text(
                name,
                style: MadarType.label.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textOnAccent,
                ),
              ),
              if (priceMinor > 0)
                Text(
                  '+${Money.format(priceMinor * qty, currency: currency)}',
                  textDirection: TextDirection.ltr,
                  style: MadarType.labelSm.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: colors.textOnAccent.withValues(alpha: 0.85),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(width: 2),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.textOnAccent.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              child: Text(
                '$qty',
                style: MadarType.labelSm.copyWith(
                  fontWeight: FontWeight.w900,
                  color: colors.textOnAccent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          _ChipStep(glyph: 'plus', onTap: onInc),
        ],
      ),
    );
  }
}

class _ChipStep extends StatelessWidget {
  const _ChipStep({required this.glyph, required this.onTap});

  final String glyph;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return GestureDetector(
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 24,
        height: Metrics.stepper,
        child: Center(
          child: MadarIcon(
            glyph,
            tint: colors.textOnAccent,
            size: IconSize.sm,
          ),
        ),
      ),
    );
  }
}

/// The little "+price" pill inside a chip.
class _PricePill extends StatelessWidget {
  const _PricePill({
    required this.priceMinor,
    required this.on,
    required this.currency,
  });

  final int priceMinor;
  final bool on;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: on
            ? colors.textOnAccent.withValues(alpha: 0.2)
            : colors.accentBg,
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 6,
          vertical: 2,
        ),
        child: Text(
          '+${Money.format(priceMinor, currency: currency)}',
          textDirection: TextDirection.ltr,
          style: MadarType.labelSm.copyWith(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: on ? colors.textOnAccent : colors.accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Centered "Show all / show assigned add-ons" toggle.
class _ShowAllToggle extends StatelessWidget {
  const _ShowAllToggle({
    required this.showAll,
    required this.label,
    required this.onToggle,
  });

  final bool showAll;
  final String label;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      onTap: () {
        MadarHaptics.selection();
        onToggle();
      },
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(vertical: Space.sm),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            MadarIcon(
              showAll ? 'chevron.up' : 'plus',
              tint: colors.accent,
              size: IconSize.xs,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: MadarType.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A size chip: label over its price, accent fill when active.
class _SelectChip extends StatelessWidget {
  const _SelectChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.sub,
  });

  final String label;
  final String? sub;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final fg = active ? colors.textOnAccent : colors.textPrimary;
    final sub = this.sub;
    return TactileScale(
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.lg,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: active ? colors.accent : colors.surface,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: active ? null : Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: MadarType.bodySm.copyWith(
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
            if (sub != null)
              Text(
                sub,
                textDirection: TextDirection.ltr,
                style: MadarType.labelSm.copyWith(
                  fontWeight: FontWeight.w500,
                  color: active
                      ? colors.textOnAccent.withValues(alpha: 0.8)
                      : colors.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
