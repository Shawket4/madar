import 'dart:async';
import 'dart:io';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/cart_anchor.dart';
import 'package:feature_order/src/item_sheet_header_extras.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:feature_order/src/words.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Family TYPE annotations moved to the misc library in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:lottie/lottie.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Whether the size row is a real choice. One `one_size` row is a
/// placeholder (see the importer), not something to render.
bool _hasSizeChoice(List<ItemSizeView> sizes) =>
    sizes.length > 1 ||
    (sizes.length == 1 &&
        sizes.first.label.toLowerCase().replaceAll(' ', '_') != 'one_size');

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

  /// The addon type this group is about, for ordering. A slot group and a
  /// `type:` bucket both hold addons of one type, so the first option answers
  /// it; an empty group never reaches the sheet.
  String get addonType => addons.isEmpty ? '' : addons.first.addonType;
}

/// The owner's order for the item sheet: **required groups first**, and within
/// the required set and the optional set alike, sizes, then milk, then coffee
/// type, then extras, then anything else.
///
/// Sizes are the item's own chips and are already rendered above these cards,
/// which is why the rank starts at milk.
///
/// The sort is STABLE, so groups that tie — two slots of the same type, or any
/// type not named here — keep the order the core sent, which is the order the
/// shop authored them in.
int _groupRank(AddonGroup g) => switch (g.addonType) {
  'milk_type' => 0,
  'coffee_type' => 1,
  'extra' => 2,
  _ => 3,
};

List<AddonGroup> orderGroupsForSheet(List<AddonGroup> groups) {
  // `List.sort` is NOT stable in Dart, so the original index is carried as the
  // final tiebreak rather than relying on the sort to preserve it.
  final indexed =
      <(int, AddonGroup)>[
        for (var i = 0; i < groups.length; i++) (i, groups[i]),
      ]..sort((a, b) {
        // Required first: a person must answer these to add anything, so making
        // them hunt past optional extras to find what is blocking the button is
        // the one ordering that is certainly wrong.
        if (a.$2.isRequired != b.$2.isRequired) return a.$2.isRequired ? -1 : 1;
        final rank = _groupRank(a.$2).compareTo(_groupRank(b.$2));
        return rank != 0 ? rank : a.$1.compareTo(b.$1);
      });
  return [for (final e in indexed) e.$2];
}

/// The DATA one item-customization presentation is seeded from. Identity
/// equality on purpose: each sheet instance creates its own args once, so
/// its [itemConfigProvider] member is private to that presentation and
/// auto-disposes with it (no stale selection can leak into the next open).
class ItemSheetArgs {
  ItemSheetArgs({
    required this.item,
    required this.addons,
    this.groups = const [],
    this.editLine,
    this.tableId,
    this.pick,
  });

  /// Pick mode: customising one item of a combo on the combo sheet. The
  /// sheet then hands the selection back instead of touching the cart.
  final ComboPickInput? pick;

  /// The cart a commit lands in (null = takeaway).
  final String? tableId;

  final MenuItemView item;

  /// The item's addons with charged prices resolved by the core.
  final List<ItemAddonView> addons;

  /// The core's modifier groups — the groups the sheet RENDERS by default, so
  /// a seeded or rehydrated selection must be keyed by these ids.
  final List<ModifierGroupView> groups;

  /// Edit mode: the cart line being reconfigured (null = adding fresh).
  final CartLineView? editLine;
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
    this.price,
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

  /// The core's price for this selection (unit, extras, whole line). Null
  /// until the first answer — the sheet never adds prices up itself.
  final LinePreviewView? price;

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
    LinePreviewView? price,
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
    price: price ?? this.price,
  );

  static const Object _unset = Object();
}

/// Selection notifier for one sheet presentation — seeded from the args
/// (edit line / defaults), mutated by the chip taps.
class ItemConfigNotifier extends Notifier<ItemConfigState> {
  /// Creates the notifier for one family [arg].
  ItemConfigNotifier(this.arg);

  /// The sheet arguments (item + optional edit line).
  final ItemSheetArgs arg;

  bool _disposed = false;

  @override
  ItemConfigState build() {
    ref.onDispose(() => _disposed = true);
    return _seed(arg);
  }

  int _priceSeq = 0;

  /// Whether a sheet is showing this selection's price. Pricing follows the
  /// view: the sheet starts it, and a selection nobody is looking at (the
  /// pure selection tests) never reaches for the core.
  bool _pricing = false;

  /// Begin pricing — the sheet calls this once it is up.
  Future<void> startPricing() {
    _pricing = true;
    return refreshPrice();
  }

  /// Re-price the selection through the core. Sequenced: a slow answer for
  /// an older selection never overwrites a newer one.
  Future<void> refreshPrice() async {
    if (_disposed || !_pricing) return;
    final seq = ++_priceSeq;
    final s = state;
    final price = await ref
        .read(orderProvider.notifier)
        .previewConfiguredLine(
          itemId: arg.item.id,
          sizeLabel: s.size,
          addons: s.selectedAddons,
          optionalIds: s.optionals.toList(growable: false),
          qty: s.qty,
        );
    if (_disposed || seq != _priceSeq || price == null) return;
    state = state.copyWith(price: price);
  }

  /// Restore a saved addon (id + qty) into the right group.
  ///
  /// With core groups (the default, rendered view) the addon goes to the
  /// group that lists it — that is the key the sheet reads. Keying by slot id
  /// or `type:milk_type` there parked the recipe's full-fat in a bucket
  /// nothing rendered, so the milk group showed no choice and a pick of oat
  /// was sent beside it. Without core groups (legacy catalog) it goes by TYPE
  /// → slot / global `type:` bucket.
  static void _placeAddon(
    ItemSheetArgs args,
    Map<String, String> single,
    Map<String, Map<String, int>> multi,
    String addonItemId,
    int qty,
  ) {
    final core = args.groups
        .where(
          (g) =>
              g.kind == ModifierGroupKind.addon &&
              g.options.any((o) => o.id == addonItemId),
        )
        .firstOrNull;
    if (core != null) {
      if (coreGroupIsSingle(core, args.addons)) {
        single[core.groupId] = addonItemId;
      } else {
        multi.putIfAbsent(core.groupId, () => {})[addonItemId] = qty;
      }
      return;
    }
    final type = args.addons
        .where((a) => a.addonItemId == addonItemId)
        .firstOrNull
        ?.addonType;
    if (type == null) return;
    final slot = args.item.addonSlots
        .where((s) => s.addonType == type)
        .firstOrNull;
    if (slot != null) {
      // A swap family is single-select whatever the slot says: `?? 2` meant an
      // unset maximum made milk MULTI, so rehydrating a line put the recipe's
      // default in the additive bucket and the next pick landed beside it
      // rather than replacing it.
      if (!isSwapFamily(type) && (slot.maxSelections ?? 2) > 1) {
        multi.putIfAbsent(slot.id, () => {})[addonItemId] = qty;
      } else {
        single[slot.id] = addonItemId;
      }
    } else {
      final gid = 'type:$type';
      if (!isSwapFamily(type)) {
        multi.putIfAbsent(gid, () => {})[addonItemId] = qty;
      } else {
        single[gid] = addonItemId;
      }
    }
  }

  /// Where the recipe's default milk belongs in the selection map.
  ///
  /// The group is keyed by the SLOT when the item configures one and by
  /// `type:milk_type` when it does not. Seeding the unslotted key
  /// unconditionally — which is what this used to do — dropped the
  /// preselection into a group the sheet never renders for a slotted item:
  /// the milk group showed nothing chosen while the line still carried
  /// full-fat, so picking oat added a second milk instead of replacing it.
  /// Open every swap group on the choice the item's recipe already names — the
  /// teller taps only to CHANGE the drink, not to confirm how it is made. The
  /// core decides which option that is (`defaultOptionId`), from the recipe
  /// line of the group's ingredient family.
  static void _seedSwapDefaults(
    ItemSheetArgs args,
    Map<String, String> single,
  ) {
    for (final g in args.groups) {
      final id = g.defaultOptionId;
      if (id == null || single.containsKey(g.groupId)) continue;
      if (g.options.any((o) => o.id == id)) single[g.groupId] = id;
    }
  }

  static void _seedDefaultMilk(ItemSheetArgs args, Map<String, String> single) {
    final milk = args.item.defaultMilkAddonId;
    if (milk == null) return;
    // The rendered core group that offers this milk (or, failing that, the
    // one typed milk) — see [_placeAddon].
    final core =
        args.groups
            .where(
              (g) =>
                  g.kind == ModifierGroupKind.addon &&
                  g.options.any((o) => o.id == milk),
            )
            .firstOrNull ??
        args.groups
            .where(
              (g) =>
                  g.kind == ModifierGroupKind.addon &&
                  g.addonType == 'milk_type',
            )
            .firstOrNull;
    if (core != null) {
      single[core.groupId] = milk;
      return;
    }
    if (args.groups.isNotEmpty) {
      // Core groups but none offers milk: nothing renders it, so don't seed
      // a hidden selection (the core applies the recipe's milk anyway).
      return;
    }
    final slot = args.item.addonSlots
        .where((s) => s.addonType == 'milk_type')
        .firstOrNull;
    single[slot?.id ?? 'type:milk_type'] = milk;
  }

  static ItemConfigState _seed(ItemSheetArgs args) {
    final item = args.item;
    final single = <String, String>{};
    final multi = <String, Map<String, int>>{};
    var optionals = const <String>{};
    var size = baseSizeLabel(item);
    var qty = 1;
    final editLine = args.editLine;
    final pick = args.pick;
    if (pick != null && pick.addons.isNotEmpty) {
      // A combo pick already customised: reopen on what it holds.
      size = pick.sizeLabel ?? size;
      for (final a in pick.addons) {
        _placeAddon(args, single, multi, a.addonItemId, a.qty);
      }
      return ItemConfigState(
        size: size,
        single: single,
        multi: multi,
        optionals: pick.optionalFieldIds.toSet(),
        qty: 1,
      );
    }
    if (pick != null) size = pick.sizeLabel ?? size;
    if (editLine == null) {
      _seedSwapDefaults(args, single);
    }
    if (editLine != null) {
      // Edit mode: reconstruct the selection from the existing line.
      size = editLine.sizeLabel ?? size;
      for (final a in editLine.addons) {
        _placeAddon(args, single, multi, a.addonItemId, a.qty);
      }
      optionals = editLine.optionals.map((o) => o.optionalFieldId).toSet();
      qty = editLine.qty < 1 ? 1 : editLine.qty;
    } else {
      _seedDefaultMilk(args, single);
    }
    return ItemConfigState(
      size: size,
      single: single,
      multi: multi,
      optionals: pick?.optionalFieldIds.toSet() ?? optionals,
      qty: qty,
    );
  }

  // ── mutations ────────────────────────────────────────────────────────────
  void selectSize(String label) {
    state = state.copyWith(size: label);
    _maybeRefreshRecipe();
    unawaited(refreshPrice());
  }

  /// The swap family [addonId] belongs to, or null when it is additive.
  String? _familyOf(String addonId, [AddonGroup? g]) {
    final type =
        arg.addons
            .where((a) => a.addonItemId == addonId)
            .firstOrNull
            ?.addonType ??
        g?.addons.where((a) => a.addonItemId == addonId).firstOrNull?.addonType;
    return type != null && isSwapFamily(type) ? type : null;
  }

  void toggleSingle(AddonGroup g, String addonId) {
    final single = {...state.single};
    final family = _familyOf(addonId, g);
    if (single[g.id] == addonId) {
      // A swap family is a radio: the drink always has its one milk, so
      // tapping the chosen one again keeps it (pick another to change it).
      if (!g.isRequired && family == null) single.remove(g.id);
    } else {
      single[g.id] = addonId;
    }
    var multi = state.multi;
    if (family != null) {
      // ONE bucket per family across every group key (core group, slot,
      // `type:` bucket in "show all"): the new pick REPLACES the old milk.
      single.removeWhere((k, v) => k != g.id && _familyOf(v) == family);
      multi = {
        for (final e in multi.entries)
          e.key: {
            for (final a in e.value.entries)
              if (_familyOf(a.key) != family) a.key: a.value,
          },
      }..removeWhere((_, v) => v.isEmpty);
    }
    state = state.copyWith(single: single, multi: multi);
    _maybeRefreshRecipe();
    unawaited(refreshPrice());
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
            '${g.title}: ${tr(key: 'order.max_reached')} · '
            '${tr(key: 'order.at_most').replaceAll('{count}', '${g.maxSel}')}',
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
    unawaited(refreshPrice());
  }

  void toggleOptional(String fieldId) {
    state = state.copyWith(
      optionals: state.optionals.contains(fieldId)
          ? (state.optionals.toSet()..remove(fieldId))
          : {...state.optionals, fieldId},
    );
    _maybeRefreshRecipe();
    unawaited(refreshPrice());
  }

  void toggleShowAll() => state = state.copyWith(showAll: !state.showAll);

  /// Apply the item as this device last sold it (the header's "Last: …"
  /// chip): its size, add-ons and optional fields replace the selection, and
  /// a swap group it leaves unanswered opens on the recipe's choice, as a
  /// fresh sheet does. The quantity stays.
  void applyLast(LastItemConfig last) {
    final single = <String, String>{};
    final multi = <String, Map<String, int>>{};
    for (final a in last.addons) {
      _placeAddon(arg, single, multi, a.addonItemId, a.qty);
    }
    _seedSwapDefaults(arg, single);
    state = state.copyWith(
      size: last.sizeLabel ?? baseSizeLabel(arg.item),
      single: single,
      multi: multi,
      optionals: last.optionalFieldIds.toSet(),
    );
    _maybeRefreshRecipe();
    unawaited(refreshPrice());
  }

  void setQty(int qty) {
    state = state.copyWith(qty: qty.clamp(1, 99));
    unawaited(refreshPrice());
  }

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
  /// sheet pops only on true. [stay] (long-press on Add) keeps the sheet up
  /// on the same picks, ready for another.
  Future<bool> commit({required String? notes, bool stay = false}) async {
    if (state.committing) return false;
    state = state.copyWith(committing: true);
    final ok = await ref
        .read(cartProvider(arg.tableId).notifier)
        .addConfigured(
          itemId: arg.item.id,
          sizeLabel: state.size,
          addons: state.selectedAddons,
          optionalIds: state.optionals.toList(growable: false),
          qty: state.qty,
          notes: notes,
          replaceLineKey: arg.editLine?.key,
        );
    // A refused add or edit keeps the sheet open (the toast says why) with
    // the teller's picks intact, ready to try again.
    if ((!ok || stay) && !_disposed) state = state.copyWith(committing: false);
    return ok;
  }
}

/// One sheet presentation's selection state, keyed by its (identity) args.
final NotifierProviderFamily<ItemConfigNotifier, ItemConfigState, ItemSheetArgs>
itemConfigProvider = NotifierProvider.autoDispose
    .family<ItemConfigNotifier, ItemConfigState, ItemSheetArgs>(
      ItemConfigNotifier.new,
    );

/// The addon families that REPLACE part of the recipe rather than adding to
/// it — mirrors `SWAP_FAMILIES` in the core's cart.rs, which charges them as
/// a delta over the base and caps their groups at one selection.
///
/// A latte already has milk; choosing oat changes which milk, it does not put
/// two in the cup. Anywhere this app decides whether a family is single- or
/// multi-select, it asks this and not the slot config — a milk slot with no
/// maximum set used to mean "no cap", which made milk additive and sent a
/// line out carrying the recipe's full-fat AND the oat the teller picked.
bool isSwapFamily(String addonType) =>
    addonType == 'milk_type' || addonType == 'coffee_type';

/// Whether a core modifier group renders as ONE choice (radio, no stepper).
///
/// The core already caps swap-family groups at one; this re-derives it from
/// the group's type and its options' addon types so an older core (or a group
/// the wire mis-typed as multi with no max) can never render milk as a
/// multi-select with a quantity stepper.
bool coreGroupIsSingle(ModifierGroupView g, List<ItemAddonView> addons) {
  if (g.maxSelections == 1) return true;
  if (g.addonType != null && isSwapFamily(g.addonType!)) return true;
  return g.options.any(
    (o) =>
        addons.any((a) => a.addonItemId == o.id && isSwapFamily(a.addonType)),
  );
}

/// Item customization — size, addons (per slot + global types), optional
/// fields, live recipe preview, notes, qty. Prices come pre-resolved from
/// the core; this only displays and sums.
class ItemDetailSheet extends ConsumerStatefulWidget {
  const ItemDetailSheet({
    required this.item,
    required this.addons,
    this.groups = const [],
    this.editLine,
    this.tableId,
    this.pick,
    super.key,
  });

  /// The cart the sheet adds to (null = takeaway, else that table's).
  final String? tableId;

  /// Pick mode (the combo sheet's "Customise"): the item's add-ons and
  /// options at their normal prices (C10), handed back as the pick — no
  /// size row (the combo sheet prices the size), no quantity, no cart.
  final ComboPickInput? pick;

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

  @override
  ConsumerState<ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends ConsumerState<ItemDetailSheet> {
  /// Created once per presentation — the identity key that gives this sheet
  /// its own [itemConfigProvider] member.
  @override
  void initState() {
    super.initState();
    // Post-frame: a notifier write during initState lands mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(itemConfigProvider(_args).notifier).startPricing());
      _claimKeys();
    });
    FocusManager.instance.addListener(_reclaimKeys);
  }

  late final ItemSheetArgs _args = ItemSheetArgs(
    item: widget.item,
    addons: widget.addons,
    groups: widget.groups,
    editLine: widget.editLine,
    tableId: widget.tableId,
    pick: widget.pick,
  );

  /// The item as this device last sold it, read once per presentation (local
  /// rows only). Never offered while editing a line or customising a pick.
  late final LastItemConfig? _last = () {
    if (widget.pick != null || widget.editLine != null) return null;
    try {
      return ref.read(bridgeProvider).lastItemConfig(itemId: widget.item.id);
    } on Object {
      return null;
    }
  }();

  late final TextEditingController _notes = TextEditingController(
    text: widget.pick?.notes ?? widget.editLine?.notes ?? '',
  );

  /// Anchors the footer CTA — the add-to-cart flight launches from here.
  final GlobalKey _footerKey = GlobalKey();

  static const _baseTypes = ['milk_type', 'coffee_type', 'extra'];

  MenuItemView get _item => widget.item;

  @override
  void dispose() {
    FocusManager.instance.removeListener(_reclaimKeys);
    _flashTimer?.cancel();
    _keys.dispose();
    _notes.dispose();
    super.dispose();
  }

  // ── guided picks (Fast mode) ─────────────────────────────────────────────
  /// Each group card's key, to scroll it into view.
  final Map<String, GlobalKey> _groupKeys = {};
  GlobalKey _groupKey(String id) => _groupKeys.putIfAbsent(id, GlobalKey.new);

  /// The group flashed last, until the flash fades.
  String? _flash;
  Timer? _flashTimer;
  static const _flashFor = Duration(milliseconds: 1400);

  /// The last build's groups, in the order shown, and the first required one
  /// still unanswered — what a key press or a disabled tap acts on.
  List<AddonGroup> _shown = const [];
  AddonGroup? _open;

  /// Fast mode: the sheet is a page of the Sell screen's menu panel. Only
  /// there is it guided; the standard sheet behaves as it always has.
  bool get _guided => MadarPanelHost.isPanelPage(context);

  /// The required groups [config] leaves unanswered, in [groups]' order.
  static List<AddonGroup> _unanswered(
    List<AddonGroup> groups,
    ItemConfigState config,
  ) => [
    for (final g in groups)
      if (g.isRequired &&
          (g.isMulti
                  ? (config.multi[g.id]?.length ?? 0)
                  : (config.single[g.id] != null ? 1 : 0)) <
              (g.minSel > 1 ? g.minSel : 1))
        g,
  ];

  /// A pick-one required group was just answered: on to the next one still
  /// open (after it, else the first), if any.
  void _answered(AddonGroup g) {
    if (!_guided || !g.isRequired || g.isMulti) return;
    final open = _unanswered(_shown, ref.read(itemConfigProvider(_args)));
    if (open.isEmpty) return;
    final at = _shown.indexOf(g);
    _guideTo(
      open.firstWhere((o) => _shown.indexOf(o) > at, orElse: () => open.first),
    );
  }

  /// Scroll [g] into view and flash it. Fast mode's guide, and Enter with a
  /// required group open on either sheet.
  void _guideTo(AddonGroup g) {
    _flashTimer?.cancel();
    setState(() => _flash = g.id);
    _flashTimer = Timer(_flashFor, () {
      if (mounted) setState(() => _flash = null);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _groupKeys[g.id]?.currentContext;
      if (!mounted || target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.05,
        duration: motionReduced(context)
            ? Duration.zero
            : MotionSpec.standardDuration,
        curve: MotionSpec.standardCurve,
      );
    });
  }

  // ── a hardware keyboard ──────────────────────────────────────────────────
  /// Holds the sheet's keys: 1–9 set the quantity, + and − step it, Enter
  /// adds, Esc closes. It never shows anything: without a keyboard attached
  /// the sheet looks and works as before.
  final FocusNode _keys = FocusNode(debugLabel: 'item-sheet-keys');

  /// Whether a text field (the note, a group's search) has the keyboard:
  /// its keys are its own.
  static bool _typing() {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  void _claimKeys() {
    if (!mounted || _typing()) return;
    _keys.requestFocus();
  }

  /// Focus that fell back to the sheet itself (a note field let go) comes
  /// back to the keys. Focus anywhere else — a surface opened over the
  /// sheet — is left alone.
  void _reclaimKeys() {
    final primary = FocusManager.instance.primaryFocus;
    if (!mounted || _keys.hasPrimaryFocus || primary == null) return;
    if (_keys.ancestors.contains(primary)) _claimKeys();
  }

  static final _digitKeys = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.digit9: 9,
    LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.numpad2: 2,
    LogicalKeyboardKey.numpad3: 3,
    LogicalKeyboardKey.numpad4: 4,
    LogicalKeyboardKey.numpad5: 5,
    LogicalKeyboardKey.numpad6: 6,
    LogicalKeyboardKey.numpad7: 7,
    LogicalKeyboardKey.numpad8: 8,
    LogicalKeyboardKey.numpad9: 9,
  };

  /// 1–9 as typed on any layout: the digit row, the numpad, or an Arabic
  /// keyboard's Arabic-Indic digits.
  static int? _digitOf(KeyEvent event) {
    final char = event.character;
    if (char != null && char.length == 1) {
      final unit = char.codeUnitAt(0);
      for (final zero in const [0x30, 0x660, 0x6F0]) {
        if (unit > zero && unit <= zero + 9) return unit - zero;
      }
    }
    return _digitKeys[event.logicalKey];
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final repeat = event is KeyRepeatEvent;
    if (key == LogicalKeyboardKey.escape) {
      if (!repeat) MadarSheet.close<void>(context);
      return KeyEventResult.handled;
    }
    if (_typing()) return KeyEventResult.ignored;
    final config = ref.read(itemConfigProvider(_args));
    final notifier = ref.read(itemConfigProvider(_args).notifier);
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      // Never twice from a held key: a repeat would add the line again.
      if (repeat || config.committing) return KeyEventResult.handled;
      if (_open case final open?) {
        // Never a silent key: Enter shows the group still to answer, in the
        // standard sheet as in Fast mode (a tap on the disabled Add).
        _guideTo(open);
      } else {
        unawaited(_commit(config));
      }
      return KeyEventResult.handled;
    }
    // Pick mode has no quantity: the combo's count is the pick's.
    if (widget.pick != null) return KeyEventResult.ignored;
    if (!repeat) {
      if (_digitOf(event) case final digit?) {
        notifier.setQty(digit);
        return KeyEventResult.handled;
      }
    }
    final char = event.character;
    if (key == LogicalKeyboardKey.numpadAdd ||
        key == LogicalKeyboardKey.add ||
        char == '+') {
      notifier.setQty(config.qty + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.numpadSubtract ||
        key == LogicalKeyboardKey.minus ||
        char == '-' ||
        char == '−') {
      notifier.setQty(config.qty - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ── group derivation ─────────────────────────────────────────────────────
  String _typeLabel(MadarBridge bridge, String type) => switch (type) {
    'milk_type' => bridge.tr(key: 'order.addon_milk_type'),
    'coffee_type' => bridge.tr(key: 'order.addon_coffee_type'),
    'extra' => bridge.tr(key: 'order.addon_extra'),
    // A type the core has words for reads in the till's language; one it
    // does not is "Options" — never the raw English type name title-cased,
    // which an Arabic teller used to get.
    _ => switch (bridge.tr(key: 'order.addon_$type')) {
      final word when word != 'order.addon_$type' => word,
      _ => bridge.tr(key: 'order.addon_other'),
    },
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
          isMulti: !coreGroupIsSingle(g, widget.addons),
          maxSel: coreGroupIsSingle(g, widget.addons) ? 1 : g.maxSelections,
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
      final isMulti =
          !isSwapFamily(slot.addonType) && (slot.maxSelections ?? 2) > 1;
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
          isMulti: !isSwapFamily(type),
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
        ? '${tr(key: 'order.required')} · '
              '${tr(key: 'order.at_least').replaceAll('{count}', '${v.minRequired}')}'
        : '${tr(key: 'order.max_reached')} · '
              '${tr(key: 'order.at_most').replaceAll('{count}', '${v.maxAllowed}')}';
    ref
        .read(orderProvider.notifier)
        .showToast(
          '${v.groupName}: $detail',
          tone: ChipTone.warning,
          icon: 'hand.raised',
        );
    return false;
  }

  Future<void> _commit(ItemConfigState config, {bool stay = false}) async {
    if (!await _selectionValid(config)) return;
    if (!mounted) return;
    final notes = _notes.text.trim();
    final pick = widget.pick;
    if (pick != null) {
      // Pick mode: the selection goes back to the combo sheet as the pick.
      await Navigator.of(context).maybePop(
        ComboPickInput(
          slotId: pick.slotId,
          itemId: pick.itemId,
          sizeLabel: pick.sizeLabel,
          qty: pick.qty,
          addons: config.selectedAddons,
          optionalFieldIds: config.optionals.toList(growable: false),
          notes: notes.isEmpty ? null : notes,
        ),
      );
      return;
    }
    final committed = await ref
        .read(itemConfigProvider(_args).notifier)
        .commit(notes: notes.isEmpty ? null : notes, stay: stay);
    if (committed && mounted && stay) {
      // Long-press: the line is in, the sheet stays on the same picks.
      ref
          .read(orderProvider.notifier)
          .showToast(
            ref.read(bridgeProvider).tr(key: 'order.added_add_another'),
            tone: ChipTone.success,
            icon: 'checkmark.circle',
          );
      return;
    }
    if (committed && mounted) {
      // Fresh adds fly a dot to the cart; updates aren't an "add" moment.
      final fly = widget.editLine == null ? _flight() : null;
      await Navigator.of(context).maybePop();
      if (fly != null) unawaited(fly());
    }
  }

  /// "Make it a meal": the core builds the combo draft with this item in its
  /// slot (from the line in the cart when editing one, else from the sheet's
  /// selection) and the sheet closes with it; the screen opens the combo
  /// sheet on it.
  Future<void> _makeItAMeal(ItemConfigState config) async {
    final bridge = ref.read(bridgeProvider);
    final edit = widget.editLine;
    final notes = _notes.text.trim();
    final ComboDraft draft;
    try {
      draft = edit != null
          ? await bridge.cartMakeItAMeal(
              tableId: widget.tableId,
              lineKey: edit.key,
            )
          : await bridge.itemMealDraft(
              itemId: _item.id,
              sizeLabel: config.size,
              addons: config.selectedAddons,
              optionalFieldIds: config.optionals.toList(growable: false),
              qty: config.qty,
              notes: notes.isEmpty ? null : notes,
            );
    } on MadarError catch (e) {
      ref
          .read(orderProvider.notifier)
          .showToast(
            bridge.humanMessage(e),
            tone: ChipTone.danger,
            icon: 'xmark.circle',
          );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).maybePop(draft);
  }

  /// The add-to-cart flight from the footer CTA, captured while the sheet
  /// is still laid out and launched once it is gone: the dot flies in the
  /// screen's own overlay, under where this root-navigator sheet was, and
  /// would otherwise be hidden by it. Null when either end is missing —
  /// pure chrome on top of the already-committed add (reduced motion gets
  /// the short pulse at the cart).
  Future<void> Function()? _flight() {
    final render = _footerKey.currentContext?.findRenderObject();
    final anchors = CartAnchors.maybeOf(context);
    if (render is! RenderBox || !render.hasSize || anchors == null) return null;
    final from = render.localToGlobal(render.size.center(Offset.zero));
    return () => anchors.fly(from);
  }

  // ── footer summary ───────────────────────────────────────────────────────
  /// The core's summary words as footer chips. Each word finds the group it
  /// came from — the sheet only sequences: a tap scrolls there, and ✕ runs
  /// the same toggle the group's own chip runs. ✕ only on an OPTIONAL choice:
  /// never the size, never a required group's pick, never a swap family (the
  /// drink always has its one milk; pick another to change it).
  Widget? _summaryLine(
    LinePreviewView? price,
    List<AddonGroup> groups,
    ItemConfigState config,
    ItemConfigNotifier notifier,
  ) {
    final parts = price?.summary ?? const <LineSummaryPartView>[];
    if (parts.isEmpty) return null;
    final words = <ItemSummaryWord>[];
    for (final p in parts) {
      switch (p.kind) {
        case 'addon':
          final g = groups
              .where(
                (g) =>
                    config.single[g.id] == p.refId ||
                    (config.multi[g.id]?.containsKey(p.refId) ?? false),
              )
              .firstOrNull;
          final swap = [
            ...?g?.addons,
            ...widget.addons,
          ].any((a) => a.addonItemId == p.refId && isSwapFamily(a.addonType));
          words.add(
            ItemSummaryWord(
              part: p,
              onTap: g == null
                  ? null
                  : () => _reveal(
                      (w) => w is ItemSheetGroupCard && w.group.id == g.id,
                    ),
              onRemove: g == null || g.isRequired || swap
                  ? null
                  : () => g.isMulti
                        ? notifier.toggleMulti(g, p.refId)
                        : notifier.toggleSingle(g, p.refId),
            ),
          );
        case 'optional':
          words.add(
            ItemSummaryWord(
              part: p,
              onTap: () => _reveal((w) => w is _OptionalsSection),
              onRemove: () => notifier.toggleOptional(p.refId),
            ),
          );
        default:
          words.add(
            ItemSummaryWord(
              part: p,
              onTap: () =>
                  _reveal((w) => w is ItemSheetChip && w.label == p.refId),
            ),
          );
      }
    }
    return ItemSummaryLine(words: words);
  }

  /// Scroll the sheet's body to the first widget under it that [match]es.
  /// Found by walking this sheet's own subtree on the tap — the body's
  /// layout keeps no handles for the footer to hold.
  void _reveal(bool Function(Widget widget) match) {
    Element? found;
    void visit(Element e) {
      if (found != null) return;
      if (match(e.widget)) {
        found = e;
        return;
      }
      e.visitChildElements(visit);
    }

    (context as Element).visitChildElements(visit);
    final target = found;
    if (target == null) return;
    final still = MediaQuery.disableAnimationsOf(context);
    Scrollable.ensureVisible(
      target,
      alignment: 0.1,
      duration: still ? Duration.zero : MotionSpec.standardDuration,
      curve: MotionSpec.standardCurve,
    );
  }

  /// The keys (see [_keys]) around the sheet itself.
  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: _keys, onKeyEvent: _onKey, child: _sheet(context));

  Widget _sheet(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final currency = ref.watch(orderProvider.select((s) => s.currency));
    final config = ref.watch(itemConfigProvider(_args));
    final notifier = ref.read(itemConfigProvider(_args).notifier);

    final addonsByType = <String, List<ItemAddonView>>{};
    for (final addon in widget.addons) {
      addonsByType.putIfAbsent(addon.addonType, () => []).add(addon);
    }
    final groups = orderGroupsForSheet(
      _buildGroups(bridge, addonsByType, showAll: config.showAll),
    );
    final slotTypes = _item.addonSlots.map((s) => s.addonType).toSet();
    // True when "Show all" would reveal more than the default view.
    final hasMore =
        _item.allowedAddonIds.isNotEmpty ||
        addonsByType.keys.any(
          (t) => !slotTypes.contains(t) && !_baseTypes.contains(t),
        );

    // Pricing — the core's, for exactly this selection (swap families
    // collapsed the way the cart will collapse them). Until the first answer
    // the header shows the item's own price and the footer no extras.
    final price = config.price;
    final headerTotal = price?.unitTotalMinor ?? _item.basePriceMinor;

    final firstUnsatisfied = _unanswered(groups, config).firstOrNull;
    final canAdd = firstUnsatisfied == null;
    _shown = groups;
    _open = firstUnsatisfied;
    final guided = _guided;

    final footerLabel = !canAdd
        ? '${bridge.tr(key: 'order.select_prefix')} ${firstUnsatisfied.title}'
        : widget.editLine == null
        ? bridge.tr(key: 'order.add_to_cart')
        : bridge.tr(key: 'order.update_item');
    final footerPrice = price?.lineTotalMinor ?? headerTotal;
    final picking = widget.pick != null;
    // "Make it a meal": the core says whether this item has a meal on sale
    // now, what it adds and what it saves — for the picks as they stand;
    // never in pick mode (already in a combo).
    MealOffer? meal;
    if (!picking) {
      try {
        meal = bridge.mealOfferFor(
          itemId: _item.id,
          sizeLabel: config.size,
          addons: config.selectedAddons,
          optionalFieldIds: config.optionals.toList(growable: false),
        );
      } on Object {
        meal = null;
      }
    }
    final last = _last;
    final extras = ItemSheetHeaderExtras(
      currency: currency,
      last: last,
      onApplyLast: last == null ? null : () => notifier.applyLast(last),
      meal: meal,
      onMeal: () => unawaited(_makeItAMeal(config)),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ItemSheetHeader(
          title: _item.name,
          description: _item.description,
          totalMinor: picking ? null : headerTotal,
          currency: currency,
          showRecipe: config.showRecipe,
          onToggleRecipe: _item.recipes.isNotEmpty
              ? notifier.toggleRecipe
              : null,
          bottom: extras.isEmpty ? null : extras,
        ),
        // Hug content when it fits (short sheet for a sparse item); scroll
        // when the options overflow — the footer stays pinned + visible.
        // In a panel (the Sell screen's Fast mode) the body fills it instead, so
        // the footer sits at the panel's foot, not under the last group.
        Flexible(
          fit: MadarPanelHost.isPanelPage(context)
              ? FlexFit.tight
              : FlexFit.loose,
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
                              MadarSectionHeader(
                                text: bridge.tr(key: 'order.recipe'),
                              ),
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
                  // A single `one_size` is a placeholder the dashboard needs so
                  // a recipe has a column to hang on — never a choice to make.
                  if (!picking && _hasSizeChoice(_item.sizes)) ...[
                    MadarSectionHeader(text: bridge.tr(key: 'order.size')),
                    const SizedBox(height: Space.sm),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final size in _item.sizes) ...[
                            ItemSheetChip(
                              label: size.label,
                              sub: Money.format(
                                size.priceMinor,
                                currency: currency,
                                locale: MadarFormat.localeOf(context),
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
                    KeyedSubtree(
                      // Where a guided sheet scrolls to.
                      key: _groupKey(g.id),
                      child: ItemSheetGroupCard(
                        // Stable identity: the "show all" toggle inserts /
                        // removes groups, and each card carries its own
                        // search-field state.
                        key: ValueKey(g.id),
                        group: g,
                        currency: currency,
                        charged: _charged,
                        selectedSingle: config.single[g.id],
                        selectedMulti: config.multi[g.id] ?? const {},
                        // Flashed by Fast mode's guide, or by Enter.
                        highlighted: _flash == g.id,
                        onToggleSingle: (id) {
                          notifier.toggleSingle(g, id);
                          _answered(g);
                        },
                        onToggleMulti: (id) => notifier.toggleMulti(g, id),
                        onInc: (id) => notifier.incMulti(g, id),
                        onDec: (id) => notifier.decMulti(g, id),
                      ),
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
                  // How it's made — after the choices, not hidden behind the
                  // amounts toggle, and shown for an item with steps but no
                  // costed recipe. Animations were cached by the last sync.
                  if (_item.recipeSteps.isNotEmpty) ...[
                    MadarSectionHeader(text: bridge.tr(key: 'order.steps')),
                    const SizedBox(height: Space.sm),
                    _StepList(steps: _item.recipeSteps),
                    const SizedBox(height: Space.lg),
                  ],
                  // Editing a line of the cart: its recipe card (ingredients
                  // for one and these steps) to the kitchen, from where the
                  // recipe is being read. It prints the line as it is in the
                  // cart — what the kitchen is making.
                  if (widget.editLine case final line?
                      when widget.pick == null &&
                          (_item.recipes.isNotEmpty ||
                              _item.recipeSteps.isNotEmpty)) ...[
                    MadarButton(
                      key: const ValueKey('item-send-recipe'),
                      label: orderWord(bridge, 'sell.send_recipe'),
                      glyph: MadarGlyph.list,
                      variant: MadarButtonVariant.secondary,
                      size: MadarButtonSize.compact,
                      onTap: () => unawaited(
                        ref
                            .read(orderProvider.notifier)
                            .printRecipeChit(line, tableId: widget.tableId),
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                  ],
                  MadarSectionHeader(text: bridge.tr(key: 'order.notes')),
                  const SizedBox(height: Space.sm),
                  MadarField(
                    controller: _notes,
                    placeholder: bridge.tr(key: 'sell.item_note_hint'),
                    kind: MadarFieldKind.note,
                    icon: 'text.bubble',
                  ),
                ],
              ),
            ),
          ),
        ),
        KeyedSubtree(
          key: _footerKey,
          child: ItemSheetFooter(
            summary: _summaryLine(price, groups, config, notifier),
            // Pick mode's figure is the extras only; the combo prices the rest.
            breakdown: picking ? null : price,
            currency: currency,
            totalMinor: picking ? (price?.extrasMinor ?? 0) : footerPrice,
            totalLabel: picking ? bridge.tr(key: 'combo.extras') : null,
            showQty: !picking,
            label: picking && canAdd
                ? bridge.tr(key: 'combo.done')
                : footerLabel,
            canAdd: canAdd,
            loading: config.committing,
            qty: config.qty,
            onDec: () => notifier.setQty(config.qty - 1),
            onInc: () => notifier.setQty(config.qty + 1),
            onCommit: () => unawaited(_commit(config)),
            // Fast mode: Add says it is ready once every required group is
            // answered, and "Choose X" shows where X is.
            emphasize: guided && canAdd && groups.any((g) => g.isRequired),
            onTapDisabled: guided && firstUnsatisfied != null
                ? () => _guideTo(firstUnsatisfied)
                : null,
            // Long-press adds and keeps the sheet up; a fresh add only.
            onCommitHold: picking || widget.editLine != null
                ? null
                : () => unawaited(_commit(config, stay: true)),
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
    final bridge = ref.bridge;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Space.md),
        MadarSectionHeader(text: bridge.tr(key: 'order.optionals')),
        const SizedBox(height: Space.sm),
        if (fields.length > 4) ...[
          MadarField(
            controller: _search,
            placeholder: bridge.tr(key: 'order.search_addons'),
            kind: MadarFieldKind.search,
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

/// The item sheet's header — the title, a line of description, the price
/// badge, the recipe toggle and close. Shared by every sheet that configures
/// something to sell (the item sheet, the combo sheet), so they read as one.
class ItemSheetHeader extends StatelessWidget {
  const ItemSheetHeader({
    required this.title,
    required this.currency,
    this.description,
    this.totalMinor,
    this.tag,
    this.showRecipe = false,
    this.onToggleRecipe,
    this.bottom,
    super.key,
  });

  final String title;
  final String? description;

  /// Under the title row, above the rule: the item sheet's "Last: …" chip
  /// and meal banner.
  final Widget? bottom;

  /// Null hides the price badge (pick mode: the combo prices the item).
  final int? totalMinor;
  final String currency;

  /// A small label above the title ("Combo").
  final String? tag;
  final bool showRecipe;

  /// Null hides the recipe button (nothing to show).
  final VoidCallback? onToggleRecipe;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final description = this.description;
    final tag = this.tag;
    final onToggleRecipe = this.onToggleRecipe;
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
                      if (tag != null)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(
                            bottom: Space.xs,
                          ),
                          child: StatusChip(label: tag, tone: ChipTone.accent),
                        ),
                      Text(
                        title,
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
                if (totalMinor case final total?)
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
                      total,
                      currency: currency,
                      color: colors.navy,
                    ),
                  ),
                if (onToggleRecipe != null) ...[
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
                  onTap: () => Navigator.of(context).maybePop(),
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
          if (bottom case final bottom?)
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: Space.xl,
                end: Space.xl,
                bottom: Space.md,
              ),
              child: SizedBox(width: double.infinity, child: bottom),
            ),
          Container(height: 1, color: colors.border),
        ],
      ),
    );
  }
}

// ── Footer ─────────────────────────────────────────────────────────────────────

/// The item sheet's footer — the total, the quantity and the commit button.
/// Shared with the combo sheet.
class ItemSheetFooter extends ConsumerWidget {
  const ItemSheetFooter({
    required this.currency,
    required this.totalMinor,
    required this.label,
    required this.canAdd,
    required this.loading,
    required this.qty,
    required this.onDec,
    required this.onInc,
    required this.onCommit,
    this.totalLabel,
    this.showQty = true,
    this.note,
    this.ctaKey,
    this.emphasize = false,
    this.onTapDisabled,
    this.summary,
    this.breakdown,
    this.onCommitHold,
    super.key,
  });

  /// Add is ready and says so.
  final bool emphasize;

  /// A tap on the disabled button.
  final VoidCallback? onTapDisabled;

  /// Long-press on the commit button (the item sheet's add-and-stay); null =
  /// none.
  final VoidCallback? onCommitHold;

  /// A line under the total (the combo's saving).
  final Widget? note;

  /// The selection in words, above the total (the item sheet's summary line).
  final Widget? summary;

  /// The core's figures for this line: when set, tapping the total opens
  /// their breakdown (base, size, each paid option, each, × qty).
  final LinePreviewView? breakdown;

  /// The commit button's key.
  final Key? ctaKey;

  final String currency;
  final int totalMinor;

  /// The figure's label; null = "Total".
  final String? totalLabel;

  /// The quantity stepper (hidden in pick mode: a pick's count is the
  /// combo's).
  final bool showQty;
  final String label;
  final bool canAdd;

  /// The commit is in flight — spinner on, taps blocked (double-tap guard).
  final bool loading;
  final int qty;
  final VoidCallback onDec;
  final VoidCallback onInc;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
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
            if (summary case final summary?) ...[
              const SizedBox(height: Space.sm),
              summary,
            ],
            const SizedBox(height: Space.md),
            _TotalWithBreakdown(
              breakdown: breakdown,
              currency: currency,
              child: GrandTotalBlock(
                label: totalLabel ?? bridge.tr(key: 'order.total'),
                totalMinor: totalMinor,
                currency: currency,
              ),
            ),
            if (note case final note?) ...[
              const SizedBox(height: Space.sm),
              note,
            ],
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
                  child: _AddEmphasis(
                    on: emphasize && canAdd && !loading,
                    child: _disabledTap(
                      MadarButton(
                        key: ctaKey,
                        label: label,
                        enabled: canAdd,
                        loading: loading,
                        onTap: onCommit,
                        onLongPress: onCommitHold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// A disabled button takes no taps; [onTapDisabled] (Fast mode) catches
  /// them to show which group still wants an answer.
  Widget _disabledTap(Widget button) {
    final tap = onTapDisabled;
    if (tap == null || canAdd || loading) return button;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        MadarHaptics.selection();
        tap();
      },
      child: button,
    );
  }
}

/// Add, ready: an accent ring around the button and one small beat as it
/// turns on (none under reduced motion). Paint only — the button keeps its
/// fixed height.
class _AddEmphasis extends StatelessWidget {
  const _AddEmphasis({required this.on, required this.child});

  final bool on;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final reduced = motionReduced(context);
    return TweenAnimationBuilder<double>(
      // Keyed on the state: turning on plays the beat once, from the start.
      key: ValueKey(on),
      tween: Tween(begin: on && !reduced ? 0 : 1, end: 1),
      duration: reduced ? Duration.zero : MotionSpec.gentleDuration * 2,
      curve: Curves.easeOut,
      builder: (context, t, child) => Transform.scale(
        // Up to 4% and back.
        scale: on ? 1 + 0.04 * (1 - (2 * t - 1).abs()) : 1,
        child: child,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.control),
          boxShadow: on
              ? [
                  BoxShadow(
                    color: colors.accent.withValues(alpha: 0.35),
                    blurRadius: Space.md,
                    spreadRadius: 2,
                  ),
                ]
              : const [],
        ),
        child: child,
      ),
    );
  }
}

// ── Footer: summary line + price breakdown ─────────────────────────────────────

/// One word of the footer's summary line, wired by the sheet.
@immutable
class ItemSummaryWord {
  const ItemSummaryWord({required this.part, this.onTap, this.onRemove});

  /// The core's word (its text is shown verbatim).
  final LineSummaryPartView part;

  /// Scroll to the group this word came from (null: nothing to show).
  final VoidCallback? onTap;

  /// Take the choice off — only set for an optional choice.
  final VoidCallback? onRemove;
}

/// The selection in the cart line's own words — "Large · Oat · Extra shot ·
/// Less ice" — one chip per word on a single scrolling row, so the footer
/// never grows with the selection.
class ItemSummaryLine extends StatelessWidget {
  const ItemSummaryLine({required this.words, super.key});

  final List<ItemSummaryWord> words;

  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('item-summary'),
    height: Metrics.chipHeight,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: words.length,
      separatorBuilder: (_, _) => const SizedBox(width: Space.xs),
      itemBuilder: (context, i) => _SummaryChip(word: words[i]),
    ),
  );
}

class _SummaryChip extends ConsumerWidget {
  const _SummaryChip({required this.word});

  final ItemSummaryWord word;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final part = word.part;
    final onTap = word.onTap;
    final onRemove = word.onRemove;
    final removable = onRemove != null;
    // A quiet pill drawn inside the row's full 44pt height: the pill stays
    // small, the two tap targets (the word, the ✕) take the whole height.
    return Stack(
      key: ValueKey('item-summary-${part.kind}-${part.refId}'),
      children: [
        Positioned.fill(
          top: (Metrics.chipHeight - Metrics.stepperDense) / 2,
          bottom: (Metrics.chipHeight - Metrics.stepperDense) / 2,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: colors.border),
            ),
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              button: onTap != null,
              child: InkWell(
                onTap: onTap == null
                    ? null
                    : () {
                        MadarHaptics.selection();
                        onTap();
                      },
                borderRadius: BorderRadius.circular(Radii.pill),
                child: Padding(
                  padding: EdgeInsetsDirectional.only(
                    start: Space.md,
                    end: removable ? Space.xs : Space.md,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                      part.text,
                      maxLines: 1,
                      style: MadarType.label.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (removable)
              Semantics(
                button: true,
                label: ref.bridge
                    .tr(key: 'order.summary_remove')
                    .replaceAll('{name}', part.text),
                excludeSemantics: true,
                child: InkWell(
                  key: ValueKey('item-summary-remove-${part.refId}'),
                  onTap: () {
                    MadarHaptics.selection();
                    onRemove();
                  },
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: SizedBox(
                    width: Metrics.chipHeight,
                    child: Center(
                      child: MadarIcon(
                        'xmark',
                        size: 12,
                        tint: colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// The footer total; with a [breakdown], tapping it opens the core's figures
/// in a small popover above it. A tap anywhere else puts it away.
class _TotalWithBreakdown extends StatefulWidget {
  const _TotalWithBreakdown({
    required this.breakdown,
    required this.currency,
    required this.child,
  });

  final LinePreviewView? breakdown;
  final String currency;
  final Widget child;

  @override
  State<_TotalWithBreakdown> createState() => _TotalWithBreakdownState();
}

class _TotalWithBreakdownState extends State<_TotalWithBreakdown> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final breakdown = widget.breakdown;
    if (breakdown == null) return widget.child;
    final dir = Directionality.of(context);
    return TapRegion(
      groupId: _link,
      child: CompositedTransformTarget(
        link: _link,
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => Positioned(
            width: 320,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: AlignmentDirectional.topEnd.resolve(dir),
              followerAnchor: AlignmentDirectional.bottomEnd.resolve(dir),
              offset: const Offset(0, -Space.sm),
              child: TapRegion(
                groupId: _link,
                onTapOutside: (_) => _portal.hide(),
                child: Directionality(
                  textDirection: dir,
                  child: ItemPriceBreakdown(
                    // Live: the figures follow the selection while it is open.
                    price: breakdown,
                    currency: widget.currency,
                  ),
                ),
              ),
            ),
          ),
          child: Semantics(
            button: true,
            child: InkWell(
              key: const ValueKey('item-total'),
              borderRadius: BorderRadius.circular(Radii.md),
              onTap: () {
                MadarHaptics.selection();
                _portal.toggle();
              },
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

/// The core's price for one configured line, laid out: the from price, what
/// the size adds, each paid option — the unit — then × the quantity = the
/// line. Every figure is the core's; nothing is added up here.
class ItemPriceBreakdown extends ConsumerWidget {
  const ItemPriceBreakdown({
    required this.price,
    required this.currency,
    super.key,
  });

  final LinePreviewView price;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final locale = MadarFormat.localeOf(context);
    String money(int minor, {bool signed = false}) =>
        Money.format(minor, currency: currency, locale: locale, signed: signed);
    Widget row(String label, String figure, {bool strong = false}) => Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 2),
      child: Row(
        spacing: Space.md,
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MadarType.bodySm.copyWith(
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
                color: strong ? colors.textPrimary : colors.textSecondary,
              ),
            ),
          ),
          Text(
            figure,
            style: MadarType.money.copyWith(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              color: strong ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ],
      ),
    );
    final size = price.sizeLabel;
    return Material(
      type: MaterialType.transparency,
      child: Container(
        key: const ValueKey('item-price-breakdown'),
        padding: const EdgeInsetsDirectional.all(Space.md),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: colors.border),
          boxShadow: MadarElevation.raised.shadows(colors, dark: dark),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              bridge.tr(key: 'order.price_breakdown'),
              style: MadarType.label.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: Space.sm),
            row(bridge.tr(key: 'order.price_base'), money(price.baseMinor)),
            if (size != null && price.sizeDeltaMinor != 0)
              row(size, money(price.sizeDeltaMinor, signed: true)),
            for (final r in price.paid)
              row(r.text, money(r.amountMinor, signed: true)),
            const SizedBox(height: Space.xs),
            const MadarHairline(),
            const SizedBox(height: Space.xs),
            row(
              bridge.tr(key: 'order.price_each'),
              money(price.unitTotalMinor),
              strong: true,
            ),
            row(
              bridge
                  .tr(key: 'order.price_times')
                  .replaceAll('{count}', '${price.qty}'),
              money(price.lineTotalMinor),
              strong: true,
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
class ItemSheetGroupCard extends ConsumerStatefulWidget {
  const ItemSheetGroupCard({
    required this.group,
    required this.currency,
    required this.charged,
    required this.selectedSingle,
    required this.selectedMulti,
    required this.onToggleSingle,
    required this.onToggleMulti,
    required this.onInc,
    required this.onDec,
    this.subtitle,
    this.optionKey,
    this.below,
    this.highlighted = false,
    super.key,
  });

  /// Flashed: the group a guided sheet just brought into view.
  final bool highlighted;

  /// A line under the title (a combo slot's rule: "Choose 1 item").
  final String? subtitle;

  /// Each option chip's key, by option id.
  final Key Function(String id)? optionKey;

  /// Shown under the options, open or folded (a combo pick's size and
  /// "Customise").
  final Widget? below;

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
  ConsumerState<ItemSheetGroupCard> createState() => _ItemSheetGroupCardState();
}

class _ItemSheetGroupCardState extends ConsumerState<ItemSheetGroupCard> {
  final _search = TextEditingController();

  /// Required groups open, optional groups closed (the owner's decision).
  ///
  /// A required group must be answered before the button works, so hiding it
  /// only hides the reason nothing happens. An optional one is almost always
  /// left alone, and a wall of extras between the person and Add is what made
  /// the sheet long enough to scroll on a busy morning. Closed, it still shows
  /// what is chosen, so nothing is hidden — only folded.
  late bool _expanded = widget.group.isRequired;

  @override
  void didUpdateWidget(ItemSheetGroupCard old) {
    super.didUpdateWidget(old);
    // A group the sheet points at is shown open, even one folded by hand.
    if (widget.highlighted && !old.highlighted && !_expanded) {
      setState(() => _expanded = true);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// What a closed group says about itself: the chosen options, or the
  /// invitation to open it. Never "3 selected" — the person wants to know it
  /// says oat and an extra shot, which is the whole reason a fold is safe.
  String _summary(MadarBridge bridge) {
    final g = widget.group;
    // Walked in the group's own option order, so the summary reads in the same
    // order as the chips behind the fold.
    final names = <String>[];
    for (final a in g.addons) {
      if (g.isMulti) {
        final qty = widget.selectedMulti[a.addonItemId];
        if (qty == null) continue;
        names.add(qty > 1 ? '${a.name} ×$qty' : a.name);
      } else if (widget.selectedSingle == a.addonItemId) {
        names.add(a.name);
      }
    }
    return names.isEmpty
        ? bridge.tr(key: 'order.none_chosen')
        : names.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final g = widget.group;
    final count = g.isMulti
        ? widget.selectedMulti.length
        : (widget.selectedSingle != null ? 1 : 0);

    final flash = widget.highlighted;
    return AnimatedContainer(
      duration: motionReduced(context)
          ? Duration.zero
          : MotionSpec.gentleDuration,
      curve: MotionSpec.gentleCurve,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        // Flashed: the accent ring and a wash, the group to answer next.
        color: flash
            ? Color.alphaBlend(
                colors.accent.withValues(alpha: 0.08),
                colors.surface,
              )
            : colors.surface,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(
          color: flash ? colors.accent : colors.border,
          width: flash ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The whole top of the card is the toggle — the title band, its
          // subtitle and, folded, the summary under it — padding and all. Only
          // the title row used to be: an 18pt strip, so a tap on the card's
          // edge or on the summary did nothing and people aimed for the arrow.
          Semantics(
            button: true,
            expanded: _expanded,
            // Its own transparent Material: an InkWell draws its ripple on the
            // nearest one, which is under this card's fill.
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () {
                  MadarHaptics.selection();
                  setState(() => _expanded = !_expanded);
                },
                child: Padding(
                  padding: EdgeInsetsDirectional.fromSTEB(
                    Space.md,
                    Space.md,
                    Space.md,
                    _expanded ? Space.sm : Space.md,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: Space.xl),
                        child: Row(
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
                              // Answered: a check in green. Still open: the
                              // warning dot, the thing between you and Add.
                              StatusChip(
                                key: ValueKey(
                                  'required-${g.id}-${count > 0 ? 'ok' : 'open'}',
                                ),
                                label: bridge.tr(key: 'order.required'),
                                tone: count > 0
                                    ? ChipTone.success
                                    : ChipTone.warning,
                                icon: count > 0 ? 'checkmark' : null,
                              ),
                            ],
                            if (g.isMulti && g.maxSel != null) ...[
                              const SizedBox(width: Space.sm),
                              StatusChip(label: '≤${g.maxSel}'),
                            ],
                            if (g.isMulti && count > 0) ...[
                              const SizedBox(width: Space.sm),
                              StatusChip(
                                label: '$count',
                                tone: ChipTone.accent,
                              ),
                            ],
                            const SizedBox(width: Space.sm),
                            AnimatedRotation(
                              turns: _expanded ? 0.5 : 0,
                              duration: MotionSpec.gentleDuration,
                              curve: MotionSpec.gentleCurve,
                              child: Icon(
                                Icons.keyboard_arrow_down,
                                size: 18,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.subtitle case final subtitle?) ...[
                        const SizedBox(height: Space.xs),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MadarType.bodySm.copyWith(
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                      // Folded: the selection, so nothing is hidden — only folded.
                      if (!_expanded) ...[
                        const SizedBox(height: Space.sm),
                        Text(
                          _summary(bridge),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: MadarType.bodySm.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              Space.md,
              0,
              Space.md,
              _expanded || widget.below != null ? Space.md : 0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_expanded) ...[
                  const SizedBox(height: Space.xs),
                  if (g.addons.length > 5) ...[
                    MadarField(
                      controller: _search,
                      placeholder: bridge.tr(key: 'order.search_addons'),
                      kind: MadarFieldKind.search,
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
                                          : widget.selectedSingle ==
                                                a.addonItemId),
                                )
                                .toList(growable: false);
                      Widget keyed(String id, Widget chip) =>
                          switch (widget.optionKey) {
                            final key? => KeyedSubtree(
                              key: key(id),
                              child: chip,
                            ),
                            null => chip,
                          };
                      return Wrap(
                        spacing: Space.sm,
                        runSpacing: Space.sm,
                        children: [
                          for (final addon in shown)
                            if (g.isMulti &&
                                widget.selectedMulti.containsKey(
                                  addon.addonItemId,
                                ))
                              keyed(
                                addon.addonItemId,
                                _AddonQtyChip(
                                  name: addon.name,
                                  priceMinor: widget.charged(addon.addonItemId),
                                  qty:
                                      widget.selectedMulti[addon.addonItemId] ??
                                      1,
                                  currency: widget.currency,
                                  onDec: () => widget.onDec(addon.addonItemId),
                                  onInc: () => widget.onInc(addon.addonItemId),
                                ),
                              )
                            else
                              keyed(
                                addon.addonItemId,
                                _AddonOptionChip(
                                  name: addon.name,
                                  priceMinor: widget.charged(addon.addonItemId),
                                  selected:
                                      !g.isMulti &&
                                      widget.selectedSingle ==
                                          addon.addonItemId,
                                  multi: g.isMulti,
                                  currency: widget.currency,
                                  onTap: () => g.isMulti
                                      ? widget.onToggleMulti(addon.addonItemId)
                                      : widget.onToggleSingle(
                                          addon.addonItemId,
                                        ),
                                ),
                              ),
                        ],
                      );
                    },
                  ),
                ],
                ?widget.below,
              ],
            ),
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
        constraints: const BoxConstraints(minHeight: kOptionChipMinHeight),
        padding: _chipPadding,
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
                size: IconSize.sm,
              ),
              const SizedBox(width: Space.sm),
            ],
            Text(name, style: _chipText.copyWith(color: fg)),
            if (priceMinor > 0) ...[
              const SizedBox(width: Space.sm),
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
        constraints: const BoxConstraints(minHeight: kOptionChipMinHeight),
        padding: _chipPadding,
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
              size: IconSize.sm,
            ),
            const SizedBox(width: Space.sm),
            Text(name, style: _chipText.copyWith(color: fg)),
            if (priceMinor > 0) ...[
              const SizedBox(width: Space.sm),
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
      constraints: const BoxConstraints(minHeight: kOptionChipMinHeight),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: Space.xs),
      decoration: BoxDecoration(
        color: colors.accent,
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ChipStep(glyph: 'minus', onTap: onDec),
          const SizedBox(width: Space.xs),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(name, style: _chipText.copyWith(color: colors.textOnAccent)),
              if (priceMinor > 0)
                Text(
                  '+${Money.format(priceMinor * qty, currency: currency, locale: MadarFormat.localeOf(context))}',
                  textDirection: TextDirection.ltr,
                  style: MadarType.labelSm.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.textOnAccent.withValues(alpha: 0.85),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          const SizedBox(width: Space.xs),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.textOnAccent.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Space.sm,
                vertical: 3,
              ),
              child: Text(
                '$qty',
                style: MadarType.label.copyWith(
                  fontWeight: FontWeight.w900,
                  color: colors.textOnAccent,
                ),
              ),
            ),
          ),
          const SizedBox(width: Space.xs),
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
        width: 36,
        height: kOptionChipMinHeight,
        child: Center(
          child: MadarIcon(glyph, tint: colors.textOnAccent, size: IconSize.sm),
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
          horizontal: Space.sm,
          vertical: 3,
        ),
        child: Text(
          '+${Money.format(priceMinor, currency: currency, locale: MadarFormat.localeOf(context))}',
          textDirection: TextDirection.ltr,
          style: MadarType.labelSm.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: on ? colors.textOnAccent : colors.accent,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// A choice's floor: the chips as they were before 0.11.0's tiles, a size
/// up — about the tiles' touch height, which the owner kept.
const double kOptionChipMinHeight = 56;

/// The chips' padding: the old chip's, scaled with its height.
const EdgeInsetsDirectional _chipPadding = EdgeInsetsDirectional.symmetric(
  horizontal: Space.lg,
  vertical: Space.md,
);

/// A chip's name, as big as the tiles' was.
final TextStyle _chipText = MadarType.bodySm.copyWith(
  fontSize: 15,
  fontWeight: FontWeight.w600,
);

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
class ItemSheetChip extends StatelessWidget {
  const ItemSheetChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.sub,
    super.key,
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
        constraints: const BoxConstraints(minHeight: kOptionChipMinHeight),
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.xl,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: active ? colors.accent : colors.surface,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: active ? null : Border.all(color: colors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: _chipText.copyWith(color: fg)),
            if (sub != null)
              Text(
                sub,
                textDirection: TextDirection.ltr,
                style: MadarType.label.copyWith(
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

/// The preparation steps, numbered, with one animation playing at a time.
///
/// A POS runs on cheap tablets, and a six-step recipe rendered as six looping
/// Lottie players is six render loops for a sheet the teller reads in a
/// glance. Only the step being looked at animates; the rest hold their first
/// frame, and tapping a row moves the spotlight. A step whose animation has
/// not been downloaded yet — or a written one, which never has an animation —
/// shows its name alone rather than a gap.
class _StepList extends StatefulWidget {
  const _StepList({required this.steps});

  final List<RecipeStepView> steps;

  @override
  State<_StepList> createState() => _StepListState();
}

class _StepListState extends State<_StepList> {
  /// The step currently animating. The first one with an animation, so the
  /// section is alive on open without every row competing for the CPU.
  int _playing = -1;

  @override
  void initState() {
    super.initState();
    _playing = widget.steps.indexWhere((s) => s.localAnimationPath != null);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < widget.steps.length; i++) ...[
          _StepRow(
            step: widget.steps[i],
            index: i + 1,
            playing: i == _playing,
            onTap: widget.steps[i].localAnimationPath == null
                ? null
                : () => setState(() => _playing = i),
            colors: colors,
          ),
          if (i != widget.steps.length - 1) const SizedBox(height: Space.sm),
        ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.index,
    required this.playing,
    required this.onTap,
    required this.colors,
  });

  final RecipeStepView step;
  final int index;
  final bool playing;
  final VoidCallback? onTap;
  final MadarColors colors;

  @override
  Widget build(BuildContext context) {
    final path = step.localAnimationPath;
    final reduceMotion = motionReduced(context);
    return Semantics(
      button: onTap != null,
      label: '$index. ${step.name}',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsetsDirectional.all(Space.md),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(Radii.sm),
            border: Border.all(color: playing ? colors.accent : colors.border),
          ),
          child: Row(
            children: [
              SizedBox.square(
                dimension: Metrics.ingredientBox,
                child: path == null
                    // No animation: the number carries the order instead.
                    ? Center(
                        child: Text(
                          '$index',
                          style: MadarType.body.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.textMuted,
                          ),
                        ),
                      )
                    : Lottie.file(
                        File(path),
                        // Only the spotlit row animates. Reduced motion plays
                        // it ONCE and holds the last frame — the step still
                        // shows how it's done, it just doesn't loop.
                        animate: playing,
                        repeat: !reduceMotion,
                        fit: BoxFit.contain,
                        // A file that went missing between the sync and now
                        // must not take the sheet down with it.
                        errorBuilder: (_, _, _) => Center(
                          child: Text(
                            '$index',
                            style: MadarType.body.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.textMuted,
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      // The number rides with the name while an animation
                      // holds the box, so the order never rests on the art.
                      path == null ? step.name : '$index. ${step.name}',
                      style: MadarType.label.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (step.note != null && step.note!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        step.note!,
                        style: MadarType.labelSm.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared pieces ──────────────────────────────────────────────────────────

/// A circular stepper button (natives: 30.dp, [MotionSpec.pressScaleKey]-deep
/// press).
class StepButton extends StatelessWidget {
  const StepButton({
    required this.glyph,
    required this.onTap,
    this.danger = false,
    super.key,
  });

  final String glyph;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      scale: 0.9,
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        width: Metrics.stepper,
        height: Metrics.stepper,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          shape: BoxShape.circle,
          border: Border.all(color: colors.border),
        ),
        child: MadarIcon(
          glyph,
          tint: danger ? colors.danger : colors.textPrimary,
          size: IconSize.sm,
        ),
      ),
    );
  }
}

/// Prominent tinted-teal total block — the figure tellers look at. The
/// amount cross-fades on change (the natives' Crossfade).
class GrandTotalBlock extends StatelessWidget {
  const GrandTotalBlock({
    required this.label,
    required this.totalMinor,
    required this.currency,
    super.key,
  });

  final String label;
  final int totalMinor;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final formatted = Money.format(
      totalMinor,
      currency: currency,
      locale: MadarFormat.localeOf(context),
    );
    return Container(
      padding: const EdgeInsetsDirectional.all(Space.md),
      decoration: BoxDecoration(
        color: colors.accentBg,
        borderRadius: BorderRadius.circular(Radii.md),
      ),
      child: Row(
        spacing: Space.sm,
        children: [
          // A long label (an Arabic one, a combo's) gives way to the figure.
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.body.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.accent,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: MotionSpec.standardDuration,
            switchInCurve: MotionSpec.standardCurve,
            switchOutCurve: MotionSpec.standardCurve,
            child: Text(
              formatted,
              key: ValueKey(formatted),
              textDirection: TextDirection.ltr,
              style: MadarType.moneyLg.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: colors.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
