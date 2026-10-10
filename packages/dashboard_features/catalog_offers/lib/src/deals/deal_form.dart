/// The deal dialog's form (the web's `features/deals/form-schema.ts`): the
/// values as typed (numbers stay text until Save, as the web's inputs keep
/// them), the rules that refuse a Save on the field, the wire body, and the
/// branch calls a Save sends after the deal itself.
///
/// The shape rule is the database's, applied on the fields:
/// - N for a price: N from 2 to 20 and a price of 0 or more; no "get";
/// - Buy X get Y: X and Y from 1 to 20 and a percent off from 1 to 100
///   (100 = free).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show DealPoolEntry, DealRule, DealWrite;
import 'package:flutter/foundation.dart';

import '../shared/offers_format.dart';
import '../shared/sale_window_form.dart';

/// The two deal kinds as the wire names them.
abstract final class DealKind {
  static const String nForPrice = 'n_for_price';
  static const String buyGet = 'buy_get';
}

/// What a pool entry names: one item or a whole category.
enum PoolTarget { item, category }

/// One entry of "Items that count" or "Reward items". Empty strings mean
/// "not chosen" ([sizeLabel] '' = any size).
@immutable
class PoolEntryDraft {
  const PoolEntryDraft({
    required this.key,
    this.target = PoolTarget.item,
    this.menuItemId = '',
    this.categoryId = '',
    this.sizeLabel = '',
  });

  /// A new empty entry (`emptyEntry`).
  factory PoolEntryDraft.empty([PoolTarget target = PoolTarget.item]) =>
      PoolEntryDraft(key: newOffersKey('p'), target: target);

  factory PoolEntryDraft.fromWire(DealPoolEntry e) => PoolEntryDraft(
    key: newOffersKey('p'),
    target: e.categoryId != null && e.categoryId!.isNotEmpty
        ? PoolTarget.category
        : PoolTarget.item,
    menuItemId: e.menuItemId ?? '',
    categoryId: e.categoryId ?? '',
    sizeLabel: e.sizeLabel ?? '',
  );

  /// A client key for the list (never sent).
  final String key;
  final PoolTarget target;
  final String menuItemId;
  final String categoryId;
  final String sizeLabel;

  PoolEntryDraft copyWith({
    PoolTarget? target,
    String? menuItemId,
    String? categoryId,
    String? sizeLabel,
  }) => PoolEntryDraft(
    key: key,
    target: target ?? this.target,
    menuItemId: menuItemId ?? this.menuItemId,
    categoryId: categoryId ?? this.categoryId,
    sizeLabel: sizeLabel ?? this.sizeLabel,
  );

  /// Whether the entry names its item or category.
  bool get chosen =>
      (target == PoolTarget.item ? menuItemId : categoryId).isNotEmpty;

  /// The wire entry: the side not chosen as an explicit null, as the web
  /// sends every field.
  DealPoolEntry toWire() => DealPoolEntry(
    menuItemId: target == PoolTarget.item ? menuItemId : null,
    categoryId: target == PoolTarget.category ? categoryId : null,
    sizeLabel: sizeLabel.isEmpty ? null : sizeLabel,
    explicitNulls: const {'menu_item_id', 'category_id', 'size_label'},
  );
}

/// A branch's switch for the deal.
enum BranchState {
  /// Follow the deal's own switch (no override).
  inherit,

  /// On here.
  on,

  /// Off here.
  off,
}

/// Everything the dialog edits.
@immutable
class DealDraft {
  const DealDraft({
    this.name = '',
    this.nameAr = '',
    this.kind = DealKind.nForPrice,
    this.qty = '2',
    this.price = '',
    this.getQty = '1',
    this.getPercent = '100',
    this.maxPerOrder = '',
    this.isActive = true,
    required this.pool,
    this.useRewardPool = false,
    this.rewardPool = const [],
    this.windows = const [],
    this.branches = const {},
  });

  /// A new deal (`EMPTY_DEAL`): N for a price, 2 for a blank price, one
  /// empty item entry, on, no windows, every branch following the deal.
  factory DealDraft.empty() => DealDraft(pool: [PoolEntryDraft.empty()]);

  /// The form for an existing deal (`dealFromWire`).
  factory DealDraft.fromWire(DealRule d) {
    final nFor = d.kind != DealKind.buyGet;
    final max = d.maxPerOrder;
    return DealDraft(
      name: d.name,
      nameAr: arabicOf(d.nameTranslations) ?? '',
      kind: nFor ? DealKind.nForPrice : DealKind.buyGet,
      qty: '${d.qty}',
      price: nFor ? moneyOut(d.price) : '',
      getQty: '${d.getQty ?? 1}',
      getPercent: '${d.getPercent ?? 100}',
      maxPerOrder: max != null && max != 0 ? '$max' : '',
      isActive: d.isActive,
      pool: [for (final e in d.pool) PoolEntryDraft.fromWire(e)],
      useRewardPool: !nFor && d.rewardPool.isNotEmpty,
      rewardPool: [for (final e in d.rewardPool) PoolEntryDraft.fromWire(e)],
      windows: [for (final w in d.windows) WindowDraft.fromWire(w)],
      branches: {
        for (final o in d.branchOverrides)
          o.branchId: o.isActive ? BranchState.on : BranchState.off,
      },
    );
  }

  final String name;
  final String nameAr;
  final String kind;

  /// "How many" (N for a price) or "Buy" (buy X get Y), as typed.
  final String qty;

  /// EGP as typed (N for a price).
  final String price;
  final String getQty;
  final String getPercent;

  /// Blank = no limit.
  final String maxPerOrder;
  final bool isActive;
  final List<PoolEntryDraft> pool;

  /// Buy X get Y: the reward comes from its own list.
  final bool useRewardPool;
  final List<PoolEntryDraft> rewardPool;
  final List<WindowDraft> windows;

  /// Branch id → its switch; a branch not listed follows the deal.
  final Map<String, BranchState> branches;

  bool get isNForPrice => kind == DealKind.nForPrice;

  DealDraft copyWith({
    String? name,
    String? nameAr,
    String? kind,
    String? qty,
    String? price,
    String? getQty,
    String? getPercent,
    String? maxPerOrder,
    bool? isActive,
    List<PoolEntryDraft>? pool,
    bool? useRewardPool,
    List<PoolEntryDraft>? rewardPool,
    List<WindowDraft>? windows,
    Map<String, BranchState>? branches,
  }) => DealDraft(
    name: name ?? this.name,
    nameAr: nameAr ?? this.nameAr,
    kind: kind ?? this.kind,
    qty: qty ?? this.qty,
    price: price ?? this.price,
    getQty: getQty ?? this.getQty,
    getPercent: getPercent ?? this.getPercent,
    maxPerOrder: maxPerOrder ?? this.maxPerOrder,
    isActive: isActive ?? this.isActive,
    pool: pool ?? this.pool,
    useRewardPool: useRewardPool ?? this.useRewardPool,
    rewardPool: rewardPool ?? this.rewardPool,
    windows: windows ?? this.windows,
    branches: branches ?? this.branches,
  );

  /// The branch's switch in this form.
  BranchState branch(String id) => branches[id] ?? BranchState.inherit;

  /// The wire body (`dealToWire`), [sort] being the deal's own (or the
  /// number of deals listed, for a new one). Call only on a form that
  /// passed [validateDeal].
  DealWrite toWire({required int sort}) {
    final nFor = isNForPrice;
    final max = maxPerOrder.trim();
    final ar = nameAr.trim();
    return DealWrite(
      name: name.trim(),
      nameTranslations: ar.isEmpty ? const {} : {'ar': ar},
      kind: kind,
      qty: wholeNumber(qty)!,
      price: nFor ? (moneyIn(price)?.toInt() ?? 0) : null,
      getQty: nFor ? null : wholeNumber(getQty),
      getPercent: nFor ? null : wholeNumber(getPercent),
      maxPerOrder: max.isEmpty ? null : wholeNumber(max),
      sort: sort,
      isActive: isActive,
      pool: [for (final e in pool) e.toWire()],
      // [] = the reward comes from the same pool.
      rewardPool: !nFor && useRewardPool
          ? [for (final e in rewardPool) e.toWire()]
          : const [],
      windows: [for (final w in windows) w.toWire()],
      explicitNulls: const {'price', 'get_qty', 'get_percent', 'max_per_order'},
    );
  }
}

/// A whole number typed into a number box (the web's `int`): blank or not
/// whole → null.
int? wholeNumber(String text) {
  final s = text.trim();
  if (s.isEmpty) return null;
  final n = jsNumber(s);
  if (!n.isFinite || n != n.truncateToDouble()) return null;
  return n.toInt();
}

/// The form's refusals, as i18n keys, by the field they show under.
@immutable
class DealErrors {
  const DealErrors({
    this.name,
    this.qty,
    this.price,
    this.getQty,
    this.getPercent,
    this.maxPerOrder,
    this.pool,
    this.poolEntries = const [],
    this.rewardPool,
    this.rewardEntries = const [],
    this.windows = const [],
  });

  final String? name;
  final String? qty;
  final String? price;
  final String? getQty;
  final String? getPercent;
  final String? maxPerOrder;

  /// The list's own error ("Add at least one item or category.").
  final String? pool;

  /// One per pool entry ("Choose an item or a category.").
  final List<String?> poolEntries;
  final String? rewardPool;
  final List<String?> rewardEntries;

  /// One per window.
  final List<WindowErrors?> windows;

  bool get isEmpty =>
      name == null &&
      qty == null &&
      price == null &&
      getQty == null &&
      getPercent == null &&
      maxPerOrder == null &&
      pool == null &&
      poolEntries.every((e) => e == null) &&
      rewardPool == null &&
      rewardEntries.every((e) => e == null) &&
      windows.every((w) => w == null || w.isEmpty);
}

/// The i18n keys of the deal rules (`DE`).
abstract final class DealErrorKeys {
  static const String required = 'deals.errors.required';
  static const String qtyN = 'deals.errors.qtyN';
  static const String qtyBuy = 'deals.errors.qtyBuy';
  static const String getQty = 'deals.errors.getQty';
  static const String percent = 'deals.errors.percent';
  static const String price = 'deals.errors.price';
  static const String maxPerOrder = 'deals.errors.maxPerOrder';
  static const String poolEmpty = 'deals.errors.poolEmpty';
  static const String poolTarget = 'deals.errors.poolTarget';
  static const String rewardEmpty = 'deals.errors.rewardEmpty';
}

/// The web's `dealSchema` refinements.
DealErrors validateDeal(DealDraft v) {
  String? qty;
  String? price;
  String? getQty;
  String? getPercent;
  final q = wholeNumber(v.qty);
  if (v.isNForPrice) {
    if (q == null || q < 2 || q > 20) qty = DealErrorKeys.qtyN;
    final p = moneyIn(v.price);
    if (p == null || !p.isFinite || p < 0) price = DealErrorKeys.price;
  } else {
    if (q == null || q < 1 || q > 20) qty = DealErrorKeys.qtyBuy;
    final g = wholeNumber(v.getQty);
    if (g == null || g < 1 || g > 20) getQty = DealErrorKeys.getQty;
    final pct = wholeNumber(v.getPercent);
    if (pct == null || pct < 1 || pct > 100) getPercent = DealErrorKeys.percent;
  }
  String? max;
  if (v.maxPerOrder.trim().isNotEmpty) {
    final m = wholeNumber(v.maxPerOrder);
    if (m == null || m < 1) max = DealErrorKeys.maxPerOrder;
  }
  List<String?> targets(List<PoolEntryDraft> list) => [
    for (final e in list) e.chosen ? null : DealErrorKeys.poolTarget,
  ];
  final reward = !v.isNForPrice && v.useRewardPool;
  return DealErrors(
    name: v.name.trim().isEmpty ? DealErrorKeys.required : null,
    qty: qty,
    price: price,
    getQty: getQty,
    getPercent: getPercent,
    maxPerOrder: max,
    pool: v.pool.isEmpty ? DealErrorKeys.poolEmpty : null,
    poolEntries: targets(v.pool),
    rewardPool: reward && v.rewardPool.isEmpty
        ? DealErrorKeys.rewardEmpty
        : null,
    rewardEntries: reward ? targets(v.rewardPool) : const [],
    windows: [
      for (final w in v.windows)
        switch (validateWindow(w)) {
          final e when e.isEmpty => null,
          final e => e,
        },
    ],
  );
}

/// One branch call a Save sends after the deal: a PUT `{is_active}` or (when
/// [isActive] is null) a DELETE.
typedef BranchCall = ({String branchId, bool? isActive});

/// What the branch switches need after the deal is saved (`branchChanges`):
/// a PUT for every branch newly set (or flipped) on or off, a DELETE for
/// every branch that had an exception and now follows the deal again —
/// PUTs first, then DELETEs, as the web sends them.
List<BranchCall> branchChanges(
  Map<String, BranchState> before,
  Map<String, BranchState> after,
) {
  final put = <BranchCall>[];
  final clear = <BranchCall>[];
  final ids = <String>{...before.keys, ...after.keys};
  for (final id in ids) {
    final b = before[id] ?? BranchState.inherit;
    final a = after[id] ?? BranchState.inherit;
    if (a == b) continue;
    if (a == BranchState.inherit) {
      clear.add((branchId: id, isActive: null));
    } else {
      put.add((branchId: id, isActive: a == BranchState.on));
    }
  }
  return [...put, ...clear];
}

/// The server's field names in the dialog's words (`FIELD_KEYS`), for a
/// `DEAL_INVALID {field}` refusal.
const Map<String, String> dealFieldKeys = {
  'name': 'deals.fields.name',
  'qty': 'deals.fields.qty',
  'price': 'deals.fields.price',
  'get_qty': 'deals.fields.getQty',
  'get_percent': 'deals.fields.getPercent',
  'max_per_order': 'deals.fields.maxPerOrder',
  'pool': 'deals.fields.pool',
  'reward_pool': 'deals.fields.rewardPool',
  'windows': 'deals.fields.windows',
};
