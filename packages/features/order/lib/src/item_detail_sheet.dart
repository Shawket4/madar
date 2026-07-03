import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/cart_anchor.dart';
import 'package:feature_order/src/cart_panel.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
class AddonGroup {
  const AddonGroup({
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

/// The DATA one item-customization presentation is seeded from. Identity
/// equality on purpose: each sheet instance creates its own args once, so
/// its [itemConfigProvider] member is private to that presentation and
/// auto-disposes with it (no stale selection can leak into the next open).
class ItemSheetArgs {
  ItemSheetArgs({
    required this.item,
    required this.addons,
    this.editLine,
    this.configureSeed,
    this.isConfiguring = false,
  });

  final MenuItemView item;

  /// The item's addons with charged prices resolved by the core.
  final List<ItemAddonView> addons;

  /// Edit mode: the cart line being reconfigured (null = adding fresh).
  final CartLineView? editLine;

  /// Configure mode: the previously saved component draft to seed from.
  final BundleComponentDraft? configureSeed;
  final bool isConfiguring;
}

/// The live selection inside one item-customization sheet.
@immutable
class ItemConfigState {
  const ItemConfigState({
    required this.size,
    required this.single,
    required this.multi,
    required this.optionals,
    required this.qty,
    this.showAll = false,
    this.showRecipe = false,
    this.recipeLines = const [],
    this.committing = false,
  });

  final String? size;

  /// groupId → addonId (single-select groups).
  final Map<String, String> single;

  /// groupId → addonId → qty (multi-select groups).
  final Map<String, Map<String, int>> multi;
  final Set<String> optionals;
  final int qty;

  /// Reveal the FULL org addon catalog (every type), not just the item's
  /// assigned slots + global types.
  final bool showAll;

  /// The recipe section, revealed by the header recipe button.
  final bool showRecipe;
  final List<ComputedRecipeLineView> recipeLines;

  /// Latches the footer while the add/update commit is in flight so a
  /// double-tap can't record the configured line twice (in edit mode the
  /// second pass would remove-then-re-add, duplicating the line).
  final bool committing;

  List<AddonSelection> get selectedAddons => [
    for (final id in single.values) AddonSelection(addonItemId: id, qty: 1),
    for (final group in multi.values)
      for (final entry in group.entries)
        AddonSelection(addonItemId: entry.key, qty: entry.value),
  ];

  ItemConfigState copyWith({
    Object? size = _unset,
    Map<String, String>? single,
    Map<String, Map<String, int>>? multi,
    Set<String>? optionals,
    int? qty,
    bool? showAll,
    bool? showRecipe,
    List<ComputedRecipeLineView>? recipeLines,
    bool? committing,
  }) => ItemConfigState(
    size: identical(size, _unset) ? this.size : size as String?,
    single: single ?? this.single,
    multi: multi ?? this.multi,
    optionals: optionals ?? this.optionals,
    qty: qty ?? this.qty,
    showAll: showAll ?? this.showAll,
    showRecipe: showRecipe ?? this.showRecipe,
    recipeLines: recipeLines ?? this.recipeLines,
    committing: committing ?? this.committing,
  );

  static const Object _unset = Object();
}

/// Selection notifier for one sheet presentation — seeded from the args
/// (edit line / configure seed / defaults), mutated by the chip taps.
class ItemConfigNotifier
    extends AutoDisposeFamilyNotifier<ItemConfigState, ItemSheetArgs> {
  bool _disposed = false;

  @override
  ItemConfigState build(ItemSheetArgs arg) {
    ref.onDispose(() => _disposed = true);
    return _seed(arg);
  }

  /// Restore a saved addon (id + qty) into the right group — by its TYPE →
  /// slot / global `type:` bucket, NOT the on-screen groups (which the
  /// allowlist / "show all" filter may hide), so a selection never drops.
  static void _placeAddon(
    ItemSheetArgs args,
    Map<String, String> single,
    Map<String, Map<String, int>> multi,
    String addonItemId,
    int qty,
  ) {
    final type = args.addons
        .where((a) => a.addonItemId == addonItemId)
        .firstOrNull
        ?.addonType;
    if (type == null) return;
    final slot = args.item.addonSlots
        .where((s) => s.addonType == type)
        .firstOrNull;
    if (slot != null) {
      if ((slot.maxSelections ?? 2) > 1) {
        multi.putIfAbsent(slot.id, () => {})[addonItemId] = qty;
      } else {
        single[slot.id] = addonItemId;
      }
    } else {
      final gid = 'type:$type';
      if (type != 'milk_type') {
        multi.putIfAbsent(gid, () => {})[addonItemId] = qty;
      } else {
        single[gid] = addonItemId;
      }
    }
  }

  static ItemConfigState _seed(ItemSheetArgs args) {
    final item = args.item;
    final single = <String, String>{};
    final multi = <String, Map<String, int>>{};
    var optionals = const <String>{};
    var size = item.sizes.firstOrNull?.label;
    var qty = 1;
    final seed = args.configureSeed;
    final editLine = args.editLine;
    if (args.isConfiguring) {
      if (seed != null) {
        size = seed.sizeLabel ?? size;
        for (final a in seed.addons) {
          _placeAddon(args, single, multi, a.addonItemId, a.qty);
        }
        optionals = seed.optionalIds.toSet();
      } else {
        final milk = item.defaultMilkAddonId;
        if (milk != null) single['type:milk_type'] = milk;
      }
    } else if (editLine != null) {
      // Edit mode: reconstruct the selection from the existing line.
      size = editLine.sizeLabel ?? size;
      for (final a in editLine.addons) {
        _placeAddon(args, single, multi, a.addonItemId, a.qty);
      }
      optionals = editLine.optionals.map((o) => o.optionalFieldId).toSet();
      qty = editLine.qty < 1 ? 1 : editLine.qty;
    } else {
      final milk = item.defaultMilkAddonId;
      if (milk != null) single['type:milk_type'] = milk;
    }
    return ItemConfigState(
      size: size,
      single: single,
      multi: multi,
      optionals: optionals,
      qty: qty,
    );
  }

  // ── mutations ────────────────────────────────────────────────────────────
  void selectSize(String label) {
    state = state.copyWith(size: label);
    _maybeRefreshRecipe();
  }

  void toggleSingle(AddonGroup g, String addonId) {
    final single = {...state.single};
    if (single[g.id] == addonId) {
      if (!g.isRequired) single.remove(g.id);
    } else {
      single[g.id] = addonId;
    }
    state = state.copyWith(single: single);
    _maybeRefreshRecipe();
  }

  void toggleMulti(AddonGroup g, String addonId) {
    final m = {...?state.multi[g.id]};
    if (m.containsKey(addonId)) {
      m.remove(addonId);
    } else if (g.maxSel == null || m.length < g.maxSel!) {
      m[addonId] = 1;
    } else {
      final tr = ref.read(bridgeProvider).tr;
      ref
          .read(orderProvider.notifier)
          .showToast(
            '${g.title}: ${tr(key: 'order.max_reached')} (≤${g.maxSel})',
            tone: ChipTone.warning,
            icon: 'hand.raised',
          );
      return;
    }
    _writeMulti(g.id, m);
  }

  void incMulti(AddonGroup g, String addonId) {
    final m = {...?state.multi[g.id]};
    m[addonId] = (m[addonId] ?? 1) + 1;
    _writeMulti(g.id, m);
  }

  void decMulti(AddonGroup g, String addonId) {
    final m = {...?state.multi[g.id]};
    final cur = m[addonId] ?? 1;
    if (cur <= 1) {
      m.remove(addonId);
    } else {
      m[addonId] = cur - 1;
    }
    _writeMulti(g.id, m);
  }

  void _writeMulti(String groupId, Map<String, int> m) {
    final multi = {...state.multi};
    if (m.isEmpty) {
      multi.remove(groupId);
    } else {
      multi[groupId] = m;
    }
    state = state.copyWith(multi: multi);
    _maybeRefreshRecipe();
  }

  void toggleOptional(String fieldId) {
    state = state.copyWith(
      optionals: state.optionals.contains(fieldId)
          ? (state.optionals.toSet()..remove(fieldId))
          : {...state.optionals, fieldId},
    );
    _maybeRefreshRecipe();
  }

  void toggleShowAll() => state = state.copyWith(showAll: !state.showAll);

  void setQty(int qty) => state = state.copyWith(qty: qty.clamp(1, 99));

  void toggleRecipe() {
    state = state.copyWith(showRecipe: !state.showRecipe);
    if (state.showRecipe) unawaited(refreshRecipe());
  }

  // ── recipe preview ───────────────────────────────────────────────────────
  void _maybeRefreshRecipe() {
    if (!state.showRecipe) return;
    unawaited(refreshRecipe());
  }

  Future<void> refreshRecipe() async {
    final lines = await ref
        .read(orderProvider.notifier)
        .recipePreview(
          itemId: arg.item.id,
          sizeLabel: state.size,
          addons: state.selectedAddons,
          optionalIds: state.optionals.toList(growable: false),
        );
    if (_disposed) return;
    state = state.copyWith(recipeLines: lines);
  }

  // ── commit ───────────────────────────────────────────────────────────────
  /// Record the configured line (add, or replace in edit mode). Returns
  /// false when a commit is already in flight (the double-tap guard) — the
  /// sheet pops only on true.
  Future<bool> commit({required String? notes}) async {
    if (state.committing) return false;
    state = state.copyWith(committing: true);
    await ref
        .read(orderProvider.notifier)
        .addConfigured(
          itemId: arg.item.id,
          sizeLabel: state.size,
          addons: state.selectedAddons,
          optionalIds: state.optionals.toList(growable: false),
          qty: state.qty,
          notes: notes,
          replaceLineKey: arg.editLine?.key,
        );
    return true;
  }
}

/// One sheet presentation's selection state, keyed by its (identity) args.
final AutoDisposeNotifierProviderFamily<
  ItemConfigNotifier,
  ItemConfigState,
  ItemSheetArgs
>
itemConfigProvider = NotifierProvider.autoDispose
    .family<ItemConfigNotifier, ItemConfigState, ItemSheetArgs>(
      ItemConfigNotifier.new,
    );

/// Item customization — size, addons (per slot + global types), optional
/// fields, live recipe preview, notes, qty. Prices come pre-resolved from
/// the core; this only displays and sums.
///
/// Bundle-component configure mode: when [isConfiguring] the footer SAVES
/// the selection back (pops a [BundleComponentDraft], no cart write), seeded
/// from [configureSeed], and the qty stepper is hidden.
class ItemDetailSheet extends ConsumerStatefulWidget {
  const ItemDetailSheet({
    required this.item,
    required this.addons,
    this.groups = const [],
    this.editLine,
    this.configureSeed,
    this.isConfiguring = false,
    super.key,
  });

  final MenuItemView item;

  /// The item's addons with charged prices resolved by the core.
  final List<ItemAddonView> addons;

  /// The item's modifier groups from the core (unified model) — the DEFAULT
  /// view renders these verbatim (constraints included). Empty = fall back to
  /// the local slot/type derivation; "show all" always uses the local
  /// full-catalog derivation (a UI affordance the core doesn't model).
  final List<ModifierGroupView> groups;

  /// Edit mode: the cart line being reconfigured (null = adding fresh).
  final CartLineView? editLine;

  /// Configure mode: the previously saved component draft to seed from.
  final BundleComponentDraft? configureSeed;
  final bool isConfiguring;

  @override
  ConsumerState<ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends ConsumerState<ItemDetailSheet> {
  /// Created once per presentation — the identity key that gives this sheet
  /// its own [itemConfigProvider] member.
  late final ItemSheetArgs _args = ItemSheetArgs(
    item: widget.item,
    addons: widget.addons,
    editLine: widget.editLine,
    configureSeed: widget.configureSeed,
    isConfiguring: widget.isConfiguring,
  );

  late final TextEditingController _notes = TextEditingController(
    text: widget.editLine?.notes ?? '',
  );

  /// Anchors the footer CTA — the add-to-cart flight launches from here.
  final GlobalKey _footerKey = GlobalKey();

  static const _baseTypes = ['milk_type', 'coffee_type', 'extra'];

  MenuItemView get _item => widget.item;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  // ── group derivation ─────────────────────────────────────────────────────
  String _typeLabel(MadarBridge bridge, String type) => switch (type) {
    'milk_type' => bridge.tr(key: 'order.addon_milk_type'),
    'coffee_type' => bridge.tr(key: 'order.addon_coffee_type'),
    'extra' => bridge.tr(key: 'order.addon_extra'),
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
    required bool showAll,
    required bool isSlot,
  }) {
    if (showAll || isSlot) return all;
    final allowed = _item.allowedAddonIds;
    if (allowed.isEmpty) return all;
    final set = allowed.toSet();
    return all
        .where((a) => set.contains(a.addonItemId))
        .toList(growable: false);
  }

  /// Map the core's unified-model groups into the sheet's display shape. Only
  /// Addon-kind groups render here — the item's priced optionals keep their own
  /// dedicated section below (driven by `item.optionalFields`, same ids).
  List<AddonGroup> _fromCoreGroups(MadarBridge bridge) => [
    for (final g in widget.groups)
      if (g.kind == ModifierGroupKind.addon && g.options.isNotEmpty)
        AddonGroup(
          id: g.groupId,
          // The core hands raw type names for unlabelled/type-derived groups —
          // localize those; keep authored slot labels verbatim.
          title:
              (g.addonType != null &&
                  (g.groupId.startsWith('type:') || g.name == g.addonType))
              ? _typeLabel(bridge, g.addonType!)
              : g.name,
          addons: [
            for (final o in g.options)
              ItemAddonView(
                addonItemId: o.id,
                name: o.name,
                addonType: g.addonType ?? '',
                chargedPriceMinor: o.chargedPriceMinor,
              ),
          ],
          isMulti: (g.maxSelections ?? 2) > 1,
          maxSel: g.maxSelections,
          isRequired: g.isRequired,
          minSel: g.minSelections,
        ),
  ];

  List<AddonGroup> _buildGroups(
    MadarBridge bridge,
    Map<String, List<ItemAddonView>> addonsByType, {
    required bool showAll,
  }) {
    // Default view: the core's groups verbatim (single source of truth for
    // allowlist, constraints and swap pricing). "Show all" falls through to
    // the local full-catalog derivation below.
    if (!showAll && widget.groups.isNotEmpty) return _fromCoreGroups(bridge);
    final groups = <AddonGroup>[];
    final slotTypes = _item.addonSlots.map((s) => s.addonType).toSet();
    for (final slot in _item.addonSlots) {
      final addons = _visibleAddons(
        addonsByType[slot.addonType] ?? const [],
        showAll: showAll,
        isSlot: true,
      );
      if (addons.isEmpty) continue;
      final isMulti = (slot.maxSelections ?? 2) > 1;
      groups.add(
        AddonGroup(
          id: slot.id,
          title: slot.label ?? _typeLabel(bridge, slot.addonType),
          addons: addons,
          isMulti: isMulti,
          maxSel: slot.maxSelections,
          isRequired: slot.isRequired,
          minSel: slot.minSelections,
        ),
      );
    }
    final extraTypes = showAll
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
        showAll: showAll,
        isSlot: false,
      );
      if (addons.isEmpty) continue;
      groups.add(
        AddonGroup(
          id: 'type:$type',
          title: _typeLabel(bridge, type),
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

  // ── pricing ──────────────────────────────────────────────────────────────
  int _charged(String addonItemId) =>
      widget.addons
          .where((a) => a.addonItemId == addonItemId)
          .firstOrNull
          ?.chargedPriceMinor ??
      0;

  // ── commit ───────────────────────────────────────────────────────────────
  /// Enforce the item's group constraints (min/required — max is blocked at
  /// tap time) via the core. Returns true when the selection is valid; else
  /// toasts the first violated group and blocks the commit.
  Future<bool> _selectionValid(ItemConfigState config) async {
    final violations = await ref
        .read(orderProvider.notifier)
        .validateItemSelections(
          itemId: _item.id,
          addons: config.selectedAddons,
          optionalIds: config.optionals.toList(growable: false),
        );
    if (violations.isEmpty) return true;
    final v = violations.first;
    final tr = ref.read(bridgeProvider).tr;
    final detail = v.selected < v.minRequired
        ? '${tr(key: 'order.required')} (≥${v.minRequired})'
        : '${tr(key: 'order.max_reached')} (≤${v.maxAllowed})';
    ref
        .read(orderProvider.notifier)
        .showToast(
          '${v.groupName}: $detail',
          tone: ChipTone.warning,
          icon: 'hand.raised',
        );
    return false;
  }

  Future<void> _commit(ItemConfigState config, int extrasMinor) async {
    if (!await _selectionValid(config)) return;
    if (!mounted) return;
    if (widget.isConfiguring) {
      if (config.committing) return;
      await Navigator.of(context).maybePop(
        BundleComponentDraft(
          sizeLabel: config.size,
          addons: config.selectedAddons,
          optionalIds: config.optionals.toList(growable: false),
          extrasMinor: extrasMinor,
        ),
      );
      return;
    }
    final notes = _notes.text.trim();
    final committed = await ref
        .read(itemConfigProvider(_args).notifier)
        .commit(notes: notes.isEmpty ? null : notes);
    if (committed && mounted) {
      // Fresh adds fly a dot to the cart; updates aren't an "add" moment.
      if (widget.editLine == null) _flyToCart();
      await Navigator.of(context).maybePop();
    }
  }

  /// Fly the add-to-cart dot from the footer CTA to the mounted cart anchor
  /// — pure chrome on top of the already-committed add; skipped when either
  /// end is missing.
  void _flyToCart() {
    final render = _footerKey.currentContext?.findRenderObject();
    final to = cartAnchorCenter();
    if (render is! RenderBox || !render.hasSize || to == null) return;
    playCartFlight(
      context,
      from: render.localToGlobal(render.size.center(Offset.zero)),
      to: to,
      onArrive: () => cartCatchTick.value++,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final currency = ref.watch(orderProvider.select((s) => s.currency));
    final config = ref.watch(itemConfigProvider(_args));
    final notifier = ref.read(itemConfigProvider(_args).notifier);

    final addonsByType = <String, List<ItemAddonView>>{};
    for (final addon in widget.addons) {
      addonsByType.putIfAbsent(addon.addonType, () => []).add(addon);
    }
    final groups = _buildGroups(bridge, addonsByType, showAll: config.showAll);
    final slotTypes = _item.addonSlots.map((s) => s.addonType).toSet();
    // True when "Show all" would reveal more than the default view.
    final hasMore =
        _item.allowedAddonIds.isNotEmpty ||
        addonsByType.keys.any(
          (t) => !slotTypes.contains(t) && !_baseTypes.contains(t),
        );

    // Pricing (display only) — the core re-resolves on add.
    final unitPrice =
        _item.sizes
            .where((s) => s.label == config.size)
            .firstOrNull
            ?.priceMinor ??
        _item.basePriceMinor;
    final selectedAddons = config.selectedAddons;
    final addonsTotal = selectedAddons.fold(
      0,
      (sum, sel) => sum + _charged(sel.addonItemId) * sel.qty,
    );
    final optionalsTotal = _item.optionalFields
        .where((f) => config.optionals.contains(f.id))
        .fold(0, (sum, f) => sum + f.priceMinor);
    final headerTotal = unitPrice + addonsTotal + optionalsTotal;
    final extrasMinor = addonsTotal + optionalsTotal;

    AddonGroup? firstUnsatisfied;
    for (final g in groups) {
      final count = g.isMulti
          ? (config.multi[g.id]?.length ?? 0)
          : (config.single[g.id] != null ? 1 : 0);
      final needed = g.minSel > 1 ? g.minSel : 1;
      if (g.isRequired && count < needed) {
        firstUnsatisfied = g;
        break;
      }
    }
    final canAdd = firstUnsatisfied == null;

    final footerLabel = !canAdd
        ? '${bridge.tr(key: 'order.select_prefix')} ${firstUnsatisfied.title}'
        : widget.isConfiguring
        ? bridge.tr(key: 'order.save_component')
        : widget.editLine == null
        ? bridge.tr(key: 'order.add_to_cart')
        : bridge.tr(key: 'order.update_item');
    // Configure mode sums only the extras (the bundle covers the base).
    final footerPrice = widget.isConfiguring
        ? extrasMinor
        : headerTotal * config.qty;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SheetHeader(
          item: _item,
          headerTotalMinor: headerTotal,
          currency: currency,
          showRecipe: config.showRecipe,
          onToggleRecipe: notifier.toggleRecipe,
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
                  // The header recipe button reveals this with a gentle
                  // expand/collapse (AnimatedSize) instead of an instant pop.
                  AnimatedSize(
                    duration: MotionSpec.gentleDuration,
                    curve: MotionSpec.gentleCurve,
                    alignment: AlignmentDirectional.topStart,
                    child: config.showRecipe && config.recipeLines.isNotEmpty
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SectionTitle(bridge.tr(key: 'order.recipe')),
                              const SizedBox(height: Space.sm),
                              for (final line in config.recipeLines) ...[
                                _RecipeRow(line: line),
                                const SizedBox(height: Space.sm),
                              ],
                              const SizedBox(height: Space.xs),
                            ],
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                  if (_item.sizes.isNotEmpty) ...[
                    SectionTitle(bridge.tr(key: 'order.size')),
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
                              active: config.size == size.label,
                              onTap: () => notifier.selectSize(size.label),
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
                      currency: currency,
                      charged: _charged,
                      selectedSingle: config.single[g.id],
                      selectedMulti: config.multi[g.id] ?? const {},
                      onToggleSingle: (id) => notifier.toggleSingle(g, id),
                      onToggleMulti: (id) => notifier.toggleMulti(g, id),
                      onInc: (id) => notifier.incMulti(g, id),
                      onDec: (id) => notifier.decMulti(g, id),
                    ),
                    const SizedBox(height: Space.md),
                  ],
                  if (hasMore)
                    _ShowAllToggle(
                      showAll: config.showAll,
                      label: bridge.tr(
                        key: config.showAll
                            ? 'order.show_assigned_addons'
                            : 'order.show_all_addons',
                      ),
                      onToggle: notifier.toggleShowAll,
                    ),
                  _OptionalsSection(
                    currency: currency,
                    fields: _item.optionalFields
                        .where((f) => f.isActive)
                        .toList(growable: false),
                    selected: config.optionals,
                    onToggle: notifier.toggleOptional,
                  ),
                  if (!widget.isConfiguring) ...[
                    SectionTitle(bridge.tr(key: 'order.notes')),
                    const SizedBox(height: Space.sm),
                    OrderTextField(
                      controller: _notes,
                      placeholder: bridge.tr(key: 'order.notes_hint'),
                      icon: 'text.bubble',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        KeyedSubtree(
          key: _footerKey,
          child: _SheetFooter(
            currency: currency,
            totalMinor: footerPrice,
            label: footerLabel,
            canAdd: canAdd,
            loading: config.committing,
            showQty: !widget.isConfiguring,
            qty: config.qty,
            onDec: () => notifier.setQty(config.qty - 1),
            onInc: () => notifier.setQty(config.qty + 1),
            onCommit: () => unawaited(_commit(config, extrasMinor)),
          ),
        ),
      ],
    );
  }
}

// ── Optional fields section ────────────────────────────────────────────────────

/// The optional-fields block — owns its search field; the chip Wrap
/// refilters through a [ValueListenableBuilder] on the controller so a
/// keystroke never rebuilds the whole sheet.
class _OptionalsSection extends ConsumerStatefulWidget {
  const _OptionalsSection({
    required this.currency,
    required this.fields,
    required this.selected,
    required this.onToggle,
  });

  final String currency;

  /// The item's ACTIVE optional fields (pre-filtered by the sheet).
  final List<OptionalFieldView> fields;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  ConsumerState<_OptionalsSection> createState() => _OptionalsSectionState();
}

class _OptionalsSectionState extends ConsumerState<_OptionalsSection> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.fields;
    if (fields.isEmpty) return const SizedBox.shrink();
    final bridge = ref.watch(bridgeProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Space.md),
        SectionTitle(bridge.tr(key: 'order.optionals')),
        const SizedBox(height: Space.sm),
        if (fields.length > 4) ...[
          OrderTextField(
            controller: _search,
            placeholder: bridge.tr(key: 'order.search_addons'),
            icon: 'magnifyingglass',
          ),
          const SizedBox(height: Space.sm),
        ],
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _search,
          builder: (context, search, _) {
            final q = search.text.trim().toLowerCase();
            // Selected chips always stay visible so a filter never hides an
            // active selection.
            final shown = q.isEmpty
                ? fields
                : fields
                      .where(
                        (f) =>
                            f.name.toLowerCase().contains(q) ||
                            widget.selected.contains(f.id),
                      )
                      .toList(growable: false);
            return Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final field in shown)
                  _OptionalChip(
                    name: field.name,
                    priceMinor: field.priceMinor,
                    on: widget.selected.contains(field.id),
                    currency: widget.currency,
                    onTap: () => widget.onToggle(field.id),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: Space.md),
      ],
    );
  }
}

// ── Header ─────────────────────────────────────────────────────────────────────

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.item,
    required this.headerTotalMinor,
    required this.currency,
    required this.showRecipe,
    required this.onToggleRecipe,
  });

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

class _SheetFooter extends ConsumerWidget {
  const _SheetFooter({
    required this.currency,
    required this.totalMinor,
    required this.label,
    required this.canAdd,
    required this.loading,
    required this.showQty,
    required this.qty,
    required this.onDec,
    required this.onInc,
    required this.onCommit,
  });

  final String currency;
  final int totalMinor;
  final String label;
  final bool canAdd;

  /// The commit is in flight — spinner on, taps blocked (double-tap guard).
  final bool loading;
  final bool showQty;
  final int qty;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
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
              label: bridge.tr(key: 'order.total'),
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
                    loading: loading,
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
/// then the option chips. The card owns its search controller — the chip
/// Wrap refilters through a [ValueListenableBuilder], so a keystroke never
/// rebuilds the whole sheet (the sheet's ValueKey(g.id) keeps the state
/// stable across "show all" toggles).
class _AddonGroupCard extends ConsumerStatefulWidget {
  const _AddonGroupCard({
    required this.group,
    required this.currency,
    required this.charged,
    required this.selectedSingle,
    required this.selectedMulti,
    required this.onToggleSingle,
    required this.onToggleMulti,
    required this.onInc,
    required this.onDec,
    super.key,
  });

  final AddonGroup group;
  final String currency;
  final int Function(String addonItemId) charged;
  final String? selectedSingle;
  final Map<String, int> selectedMulti;
  final ValueChanged<String> onToggleSingle;
  final ValueChanged<String> onToggleMulti;
  final ValueChanged<String> onInc;
  final ValueChanged<String> onDec;

  @override
  ConsumerState<_AddonGroupCard> createState() => _AddonGroupCardState();
}

class _AddonGroupCardState extends ConsumerState<_AddonGroupCard> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final g = widget.group;
    final count = g.isMulti
        ? widget.selectedMulti.length
        : (widget.selectedSingle != null ? 1 : 0);

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
                  label: bridge.tr(key: 'order.required'),
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
              placeholder: bridge.tr(key: 'order.search_addons'),
              icon: 'magnifyingglass',
            ),
            const SizedBox(height: Space.md),
          ],
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _search,
            builder: (context, search, _) {
              // Filter by the live query; selected chips always stay
              // visible so a filter never hides an active selection.
              final q = search.text.trim().toLowerCase();
              final shown = q.isEmpty
                  ? g.addons
                  : g.addons
                        .where(
                          (a) =>
                              a.name.toLowerCase().contains(q) ||
                              (g.isMulti
                                  ? widget.selectedMulti.containsKey(
                                      a.addonItemId,
                                    )
                                  : widget.selectedSingle == a.addonItemId),
                        )
                        .toList(growable: false);
              return Wrap(
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
              );
            },
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
