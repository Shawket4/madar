/// What the pricing matrix computes in the browser, as pure rules
/// (`pricing-availability-page.tsx`: `resolveCell`, `pristineDraft`,
/// `isDirty`, `planCell`, `firstInvalid`, `fmtNumberPlaceholder`, the target
/// builders). MENU-PRC-014..018, -025..029 and the area's computation 17.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';

import '../shared/menu_text.dart';

/// Rows per page on both tabs (`PER_PAGE`).
const int pricingPerPage = 24;

/// The four delivery channels a `branch_channel` override can name.
const List<String> pricingChannels = [
  'in_mall',
  'outside',
  'umbrella',
  'pickup',
];

/// An editable scope column: In-store (`branch`, [channel] null) or one
/// delivery channel (`branch_channel`).
typedef PricingCol = ({String? channel});

/// The editable columns, start to end: In-store, then the four channels.
const List<PricingCol> pricingCols = [
  (channel: null),
  (channel: 'in_mall'),
  (channel: 'outside'),
  (channel: 'umbrella'),
  (channel: 'pickup'),
];

/// The column header key (`menu.pricing.col_*`).
String pricingColKey(PricingCol col) =>
    'menu.pricing.col_${col.channel ?? 'in_store'}';

/// `colId`: `in_store` or `channel:<channel>`.
String pricingColId(PricingCol col) =>
    col.channel == null ? 'in_store' : 'channel:${col.channel}';

/// `cellKey`: one cell per target × editable scope across the whole page.
String pricingCellKey(PricingCol col, String targetId) =>
    '$targetId|${pricingColId(col)}';

/// What the server stores for a target at one scope.
typedef RawOverride = ({int? price, bool? isAvailable});

const RawOverride emptyRaw = (price: null, isAvailable: null);

/// One priceable target (a size or an add-on) with its overrides at the
/// scoped branch (`RowTarget`).
class PricingTarget {
  const PricingTarget({
    required this.targetType,
    required this.targetId,
    required this.catalogPrice,
    int? inherited,
    required this.branch,
    required this.byChannel,
  }) : inherited = inherited ?? catalogPrice;

  /// `menu_item_size` or `modifier_option`.
  final String targetType;
  final String targetId;

  /// The catalog price in piastres (the size's price / the add-on's default).
  final int catalogPrice;

  /// What its cells inherit with no override here: a size's [unitPrice] (an
  /// inactive size falls back to the item's lowest, as on the till); else
  /// [catalogPrice].
  final int inherited;

  /// The `branch`-scope override.
  final RawOverride branch;

  /// Channel → its `branch_channel` override.
  final Map<String, RawOverride> byChannel;

  ResolvedCell resolve(PricingCol col) => resolveCell(
    col,
    inherited,
    branch,
    col.channel == null ? emptyRaw : (byChannel[col.channel] ?? emptyRaw),
  );
}

/// A size as `madar_catalog::price::unit_price` reads it (`PricedSize`).
typedef PricedSize = ({
  String label,
  int? price,
  bool isActive,
  int? branchPrice,
});

/// `unitPrice` (unit-price.ts, pinned by catalog_vectors.json): what one unit
/// costs at [label] as the server and the till price it: the branch's price
/// for the size, else its catalogue price while it is active, else the item's
/// branch price, else the item's lowest active catalogue price. Null when no
/// active size has a price.
int? unitPrice(
  List<PricedSize> sizes,
  String? label, [
  int? itemBranchPrice,
]) {
  final active = [
    for (final s in sizes)
      if (s.isActive && s.price != null) s.price!,
  ];
  if (active.isEmpty) return null;
  final fallback = itemBranchPrice ?? active.reduce((a, b) => a < b ? a : b);
  if (label == null) return fallback;
  return sizes.where((s) => s.label == label).firstOrNull?.branchPrice ??
      sizes.where((s) => s.label == label && s.isActive).firstOrNull?.price ??
      fallback;
}

/// One editable cell resolved (`ResolvedCell`).
class ResolvedCell {
  const ResolvedCell({
    required this.effectivePrice,
    required this.priceExplicit,
    required this.priceFromBranch,
    required this.availEffective,
    required this.availExplicit,
    required this.hadOverride,
    required this.availInherited,
  });

  /// Piastres; always resolves.
  final int effectivePrice;

  /// This scope sets the price.
  final bool priceExplicit;

  /// Inherited from the branch price (else from the catalog).
  final bool priceFromBranch;
  final bool availEffective;
  final bool availExplicit;

  /// Any row exists at this scope (Save deletes it when cleared).
  final bool hadOverride;

  /// What the cell would show with no row at this scope: the branch's for a
  /// channel, available for In-store. Used to tell a person's "show here"
  /// on a channel the branch hides apart from inheriting (MENU-PRC-029).
  final bool availInherited;
}

/// `resolveCell` (CONTRACT §3, the org-wide `channel` scope treated as
/// absent): In-store = branch → catalog; a channel = channel → branch →
/// catalog, price and availability independently.
ResolvedCell resolveCell(
  PricingCol col,
  int catalog,
  RawOverride branch,
  RawOverride channel,
) {
  if (col.channel == null) {
    return ResolvedCell(
      effectivePrice: branch.price ?? catalog,
      priceExplicit: branch.price != null,
      priceFromBranch: false,
      availEffective: branch.isAvailable ?? true,
      availExplicit: branch.isAvailable != null,
      hadOverride: branch.price != null || branch.isAvailable != null,
      availInherited: true,
    );
  }
  return ResolvedCell(
    effectivePrice: channel.price ?? branch.price ?? catalog,
    priceExplicit: channel.price != null,
    priceFromBranch: branch.price != null,
    availEffective: channel.isAvailable ?? branch.isAvailable ?? true,
    availExplicit: channel.isAvailable != null,
    hadOverride: channel.price != null || channel.isAvailable != null,
    availInherited: branch.isAvailable ?? true,
  );
}

/// A cell's unsaved edit: the price as typed in pounds ("" = inherit) and
/// the availability toggle.
typedef DraftCell = ({String price, bool available});

/// `pristineDraft`: the typed price only when explicit here (`String(egp)`),
/// the effective availability.
DraftCell pristineDraft(ResolvedCell r) => (
  price: r.priceExplicit ? jsNumberText(piastresToEgp(r.effectivePrice)) : '',
  available: r.availEffective,
);

/// `isDirty`: the draft differs from what the server resolves.
bool isDirtyCell(DraftCell d, ResolvedCell r) {
  final base = pristineDraft(r);
  return d.price.trim() != base.price.trim() || d.available != base.available;
}

/// What "Remove override" shows while staged: a blank price and the
/// availability the cell will inherit once its row is gone. The page marks
/// the cell as cleared ([PendingCell.cleared]) so Save deletes the row, as
/// the web's × does.
DraftCell clearedDraft(ResolvedCell r) =>
    (price: '', available: r.availInherited);

/// `fmtNumberPlaceholder`: the effective price in pounds, an integer or up to
/// two decimals with trailing zeros dropped.
String pricePlaceholder(int piastres) {
  final egp = piastresToEgp(piastres);
  if (egp == egp.truncateToDouble()) return egp.toInt().toString();
  return egp.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
}

/// The pounds typed, or NaN when not a number (`parseFloat`).
double typedEgp(String price) => jsParseFloat(price.trim());

/// A typed price Save refuses: not a number, or below zero.
bool invalidPrice(String price) {
  final s = price.trim();
  if (s.isEmpty) return false;
  final egp = typedEgp(s);
  return !egp.isFinite || egp < 0;
}

/// One dirty cell ready for Save (`PendingCell`).
class PendingCell {
  const PendingCell({
    required this.key,
    required this.col,
    required this.target,
    required this.draft,
    required this.resolved,
    required this.label,
    this.cleared = false,
  });

  final String key;
  final PricingCol col;
  final PricingTarget target;
  final DraftCell draft;
  final ResolvedCell resolved;

  /// The item or add-on name, for the invalid-price toast.
  final String label;

  /// Staged by "Remove override" and not edited since: Save deletes the row.
  final bool cleared;
}

/// `firstInvalid`: the label of the first cell with a bad price.
String? firstInvalidLabel(Iterable<PendingCell> cells) {
  for (final c in cells) {
    if (invalidPrice(c.draft.price)) return c.label;
  }
  return null;
}

/// The write one pending cell needs (`planCell`): PUT the row, DELETE it,
/// or nothing.
typedef CellPlan = ({bool put, PriceOverrideRequest body});

/// `planCell`, with the null convention: a cleared cell DELETEs its row (or
/// does nothing without one); otherwise a blank price is null, else
/// piastres; hidden is `false`; available is null (inherit), except on a
/// channel whose branch hides the target, where showing it here must be
/// written as `true` (the web sends null and the edit is lost:
/// MENU-PRC-029). PUT when a price or an availability is set; else DELETE
/// when a row existed; else nothing.
CellPlan? planCell(PendingCell cell, String branchId) {
  final inStore = cell.col.channel == null;
  final cleared = cell.cleared;
  final s = cell.draft.price.trim();
  int? price;
  if (!cleared && s.isNotEmpty) {
    final egp = typedEgp(s);
    if (!egp.isFinite || egp < 0) return null;
    price = egpToPiastres(egp);
  }
  final bool? available = cleared
      ? null
      : !cell.draft.available
      ? false
      : (cell.resolved.availInherited ? null : true);
  PriceOverrideRequest body(int? p, bool? a) => PriceOverrideRequest(
    scope: inStore ? 'branch' : 'branch_channel',
    branchId: branchId,
    channel: cell.col.channel,
    targetType: cell.target.targetType,
    targetId: cell.target.targetId,
    price: p,
    isAvailable: a,
    explicitNulls: const {'price', 'is_available', 'channel'},
  );
  if (price != null || available != null) {
    return (put: true, body: body(price, available));
  }
  if (cell.resolved.hadOverride) return (put: false, body: body(null, null));
  return null;
}

/// The size targets of one item at [branchId], from its studio aggregate
/// (`useItemSizeTargets`): every size by `sort`, inactive ones too
/// (MENU-PRC-033).
List<(SizeOut, PricingTarget)> sizeTargets(
  StudioAggregate studio,
  String branchId,
) {
  final sizes = [...studio.sizes]..sort((a, b) => a.sort - b.sort);
  final branch = studio.availability.branches
      .where((b) => b.branchId == branchId)
      .firstOrNull;
  final branchBySize = {for (final r in branch?.sizes ?? []) r.sizeId: r};
  final channelBySize = <String, Map<String, SizeOverrideOut>>{
    for (final ch in branch?.channels ?? <ChannelOverrideOut>[])
      if (pricingChannels.contains(ch.channel))
        ch.channel: {for (final r in ch.sizes) r.sizeId: r},
  };
  final priced = [
    for (final s in sizes)
      (label: s.label, price: s.price, isActive: s.isActive, branchPrice: null),
  ];
  return [
    for (final size in sizes)
      (
        size,
        PricingTarget(
          targetType: 'menu_item_size',
          targetId: size.id,
          catalogPrice: size.price,
          inherited: unitPrice(priced, size.label) ?? size.price,
          branch: (
            price: branchBySize[size.id]?.price,
            isAvailable: branchBySize[size.id]?.isAvailable,
          ),
          byChannel: {
            for (final ch in pricingChannels)
              ch: (
                price: channelBySize[ch]?[size.id]?.price,
                isAvailable: channelBySize[ch]?[size.id]?.isAvailable,
              ),
          },
        ),
      ),
  ];
}

/// One add-on's target from the branch and channel override reads.
PricingTarget addonTarget(
  AddonItem addon,
  Map<String, BranchAddonOverride> branch,
  Map<String, Map<String, ChannelAddonOverride>> byChannel,
) {
  final b = branch[addon.id];
  return PricingTarget(
    targetType: 'modifier_option',
    targetId: addon.id,
    catalogPrice: addon.defaultPrice,
    branch: (price: b?.priceOverride, isAvailable: b?.isAvailable),
    byChannel: {
      for (final ch in pricingChannels)
        ch: (
          price: byChannel[ch]?[addon.id]?.priceOverride,
          isAvailable: byChannel[ch]?[addon.id]?.isAvailable,
        ),
    },
  );
}

/// The dirty cells of [targets] (`collectPending`).
List<PendingCell> collectPending(
  Iterable<PricingTarget> targets,
  String label,
  Map<String, DraftCell> drafts, {
  Set<String> cleared = const {},
}) => [
  for (final t in targets)
    for (final col in pricingCols)
      if (drafts[pricingCellKey(col, t.targetId)] case final d?)
        if (isDirtyCell(d, t.resolve(col)))
          PendingCell(
            key: pricingCellKey(col, t.targetId),
            col: col,
            target: t,
            draft: d,
            resolved: t.resolve(col),
            label: label,
            cleared: cleared.contains(pricingCellKey(col, t.targetId)),
          ),
];
