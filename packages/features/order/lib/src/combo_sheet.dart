import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/cart_anchor.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

// The combo sheet (COMBOS_CONTRACT §6): one section per slot, the choices to
// pick from, the size chips of each pick (the included size free, a bigger
// one at its "+extra"), "Customise" for an item's add-ons at their normal
// prices (the item sheet in pick mode), and the core's live total and saving.
//
// It is built from the item sheet's own parts (header, group cards, chips,
// footer) so a combo reads like any other item: a slot is a group, its
// choices are option chips.
//
// Every figure is the core's (`comboQuote`); the sheet only keeps the picks
// and hands them back. A pick whose item has a required choice with no
// default (a sandwich's bread) opens its sheet at once; until the choice is
// made the slot says so and the core keeps Add off with the reason. A
// refusal to save is the core's sentence, on the toast.

/// Open the combo sheet for [comboId]: a fresh combo, or [draft] (a combo
/// line being edited, or "make it a meal" pre-filled with the item).
Future<void> showComboSheet(
  BuildContext context,
  WidgetRef ref, {
  required String comboId,
  required String? tableId,
  ComboDraft? draft,
  CartAnchors? anchors,
}) async {
  final bridge = ref.read(bridgeProvider);
  ComboDetail? detail;
  ComboDraft? start;
  try {
    detail = bridge.comboDetail(itemId: comboId);
    start = draft ?? bridge.comboNewDraft(itemId: comboId);
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
  if (detail == null || !context.mounted) return;
  final sheet = ComboSheet(
    detail: detail,
    draft:
        start ??
        ComboDraft(comboId: comboId, qty: 1, picks: const <ComboPickInput>[]),
    tableId: tableId,
  );
  await showMadarSheet<void>(
    context,
    // The item sheet's container: hugs its content, scrolls on overflow.
    size: SheetSize.hug,
    builder: (_) => anchors == null
        ? sheet
        : CartAnchorScope(anchors: anchors, child: sheet),
  );
}

/// The combo sheet. Pure data in ([detail], [draft]); the picks live here
/// until the teller saves them into the cart.
class ComboSheet extends ConsumerStatefulWidget {
  const ComboSheet({
    required this.detail,
    required this.draft,
    required this.tableId,
    super.key,
  });

  final ComboDetail detail;

  /// Where the sheet starts: the defaults, a cart line, or a meal.
  final ComboDraft draft;

  /// The cart a save lands in (null = takeaway).
  final String? tableId;

  @override
  ConsumerState<ComboSheet> createState() => _ComboSheetState();
}

class _ComboSheetState extends ConsumerState<ComboSheet> {
  late List<ComboPickInput> _picks = List.of(widget.draft.picks);
  late int _qty = widget.draft.qty < 1 ? 1 : widget.draft.qty;
  late final TextEditingController _notes = TextEditingController(
    text: widget.draft.notes ?? '',
  );
  ComboQuoteView? _quote;
  bool _saving = false;
  int _quoteSeq = 0;

  /// The add-ons an item offers, by item id — read once a pick is
  /// customised, so the pick's add-ons show by name.
  final Map<String, List<ItemAddonView>> _addonNames = {};

  ComboDetail get _detail => widget.detail;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_requote());
      for (final p in _picks) {
        if (p.addons.isNotEmpty) unawaited(_loadAddonNames(p.itemId));
      }
    });
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadAddonNames(String itemId) async {
    if (_addonNames.containsKey(itemId)) return;
    final addons = await ref
        .read(orderProvider.notifier)
        .loadItemAddons(itemId);
    if (!mounted) return;
    setState(() => _addonNames[itemId] = addons);
  }

  /// Re-price the picks through the core. Sequenced: a slow answer for an
  /// older selection never overwrites a newer one.
  Future<void> _requote() async {
    final seq = ++_quoteSeq;
    try {
      final q = await ref
          .read(bridgeProvider)
          .comboQuote(
            tableId: widget.tableId,
            comboId: _detail.id,
            picks: _picks,
            qty: _qty,
          );
      if (!mounted || seq != _quoteSeq) return;
      setState(() => _quote = q);
    } on MadarError {
      return;
    }
  }

  void _setPicks(List<ComboPickInput> next) {
    setState(() => _picks = next);
    unawaited(_requote());
  }

  List<ComboPickInput> _picksOf(ComboSlotDetail slot) =>
      _picks.where((p) => p.slotId == slot.id).toList(growable: false);

  int _countOf(ComboSlotDetail slot) =>
      _picksOf(slot).fold(0, (n, p) => n + p.qty);

  ComboPickInput _fresh(ComboSlotDetail slot, ComboChoiceDetail c) =>
      ComboPickInput(
        slotId: slot.id,
        itemId: c.itemId,
        qty: 1,
        addons: const [],
        optionalFieldIds: const [],
      );

  /// A choice tapped: one-pick slots swap to it (or, optional and already
  /// picked, let it go); larger slots add it while there is room. An item
  /// with a required choice and no default opens its sheet at once.
  void _tapChoice(ComboSlotDetail slot, ComboChoiceDetail c) {
    final mine = _picksOf(slot);
    final picked = mine.any((p) => p.itemId == c.itemId);
    if (slot.max <= 1) {
      if (picked && slot.min == 0) {
        _setPicks([
          for (final p in _picks)
            if (p.slotId != slot.id) p,
        ]);
        return;
      }
      if (picked) return;
      _addPick(slot, c, [
        for (final p in _picks)
          if (p.slotId != slot.id) p,
      ]);
      return;
    }
    if (picked) {
      _setPicks([
        for (final p in _picks)
          if (!(p.slotId == slot.id && p.itemId == c.itemId)) p,
      ]);
      return;
    }
    if (_countOf(slot) >= slot.max) {
      MadarHaptics.selection();
      return;
    }
    _addPick(slot, c, _picks);
  }

  void _addPick(
    ComboSlotDetail slot,
    ComboChoiceDetail c,
    List<ComboPickInput> others,
  ) {
    final pick = _fresh(slot, c);
    _setPicks([...others, pick]);
    if (c.mustCustomise) unawaited(_customise(pick));
  }

  /// A multi-pick slot's "+" on a chosen item, while the slot has room.
  void _more(ComboSlotDetail slot, ComboPickInput pick) {
    if (_countOf(slot) >= slot.max) {
      MadarHaptics.selection();
      return;
    }
    _replace(pick, _with(pick, qty: pick.qty + 1));
  }

  ComboPickInput _with(
    ComboPickInput p, {
    Object? sizeLabel = _keep,
    int? qty,
  }) => ComboPickInput(
    slotId: p.slotId,
    itemId: p.itemId,
    sizeLabel: identical(sizeLabel, _keep) ? p.sizeLabel : sizeLabel as String?,
    qty: qty ?? p.qty,
    addons: p.addons,
    optionalFieldIds: p.optionalFieldIds,
    notes: p.notes,
  );

  void _replace(ComboPickInput old, ComboPickInput? next) => _setPicks([
    for (final p in _picks)
      if (identical(p, old)) ?next else p,
  ]);

  /// "Customise": the item sheet in pick mode — the item's add-ons and
  /// options at their normal prices (C10). The pick comes back customised.
  Future<void> _customise(ComboPickInput pick) async {
    final order = ref.read(orderProvider.notifier);
    final item = ref.read(orderProvider).menuItemById(pick.itemId);
    if (item == null) return;
    final addons = await order.loadItemAddons(item.id);
    final groups = await order.loadItemModifierGroups(item.id);
    if (!mounted) return;
    _addonNames[item.id] = addons;
    final next = await showMadarSheet<ComboPickInput>(
      context,
      size: SheetSize.hug,
      builder: (_) => ItemDetailSheet(
        key: ValueKey('customise-sheet-${item.id}'),
        item: item,
        addons: addons,
        groups: groups,
        tableId: widget.tableId,
        pick: pick,
      ),
    );
    if (next == null || !mounted) return;
    _replace(pick, next);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final notes = _notes.text.trim();
    final ok = await ref
        .read(cartProvider(widget.tableId).notifier)
        .saveCombo(
          comboId: _detail.id,
          picks: _picks,
          qty: _qty,
          notes: notes.isEmpty ? null : notes,
          replaceLineKey: widget.draft.lineKey,
        );
    if (!mounted) return;
    if (ok) {
      MadarSheet.close<void>(context);
      return;
    }
    // Refused (the toast says why): the picks stay, ready to try again.
    setState(() => _saving = false);
  }

  String _money(int minor) => Money.format(
    minor,
    currency: ref.read(orderProvider).currency,
    locale: MadarFormat.localeOf(context),
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final currency = ref.watch(orderProvider.select((s) => s.currency));
    final quote = _quote;
    final editing = widget.draft.lineKey != null;
    final canSave =
        _detail.availableNow && (quote?.complete ?? false) && !_saving;
    final needs = quote?.pickNeeds ?? const <ComboPickNeed>[];
    // A pick still wanting its choice: the button says it short ("Choose
    // Bread", as the item sheet's "Select Bread"); the slot marks which pick.
    final label = !_detail.availableNow
        ? (_detail.whyUnavailable ?? bridge.tr(key: 'combo.not_now'))
        : quote != null &&
              !quote.complete &&
              quote.refusal == 'COMBO_PICK_CHOICE_REQUIRED' &&
              needs.isNotEmpty
        ? needs.first.text
        : quote != null && !quote.complete && quote.refusalText != null
        ? quote.refusalText!
        : bridge.tr(key: editing ? 'combo.update' : 'combo.add');
    final saving = quote?.savingMinor ?? 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ItemSheetHeader(
          title: _detail.name,
          description: _detail.description,
          tag: bridge.tr(key: 'combo.badge'),
          totalMinor: quote?.unitTotalMinor ?? _detail.priceMinor,
          currency: currency,
        ),
        // Hug content when it fits; scroll when the slots overflow — the
        // footer stays pinned and visible (the item sheet's body).
        // In a panel (the Sell screen's Fast mode) the body fills it instead, so
        // the footer sits at the panel's foot, not under the last group.
        Flexible(
          fit: MadarPanelHost.isPanelPage(context)
              ? FlexFit.tight
              : FlexFit.loose,
          child: ColoredBox(
            color: colors.surfaceAlt,
            // Not lazy: a combo has a handful of slots, and every one of
            // them is part of the picture the teller checks before saving.
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
                  if (!_detail.availableNow) ...[
                    MadarTag(
                      label:
                          _detail.whyUnavailable ??
                          bridge.tr(key: 'combo.not_now'),
                      tone: MadarTone.warning,
                    ),
                    const SizedBox(height: Space.md),
                  ],
                  for (final slot in _detail.slots) ...[
                    _SlotCard(
                      key: ValueKey('slot-${slot.id}'),
                      slot: slot,
                      picks: _picksOf(slot),
                      needs: needs,
                      currency: currency,
                      money: _money,
                      addonNames: _addonNames,
                      onTapChoice: (c) => _tapChoice(slot, c),
                      onMore: (p) => _more(slot, p),
                      onLess: (p) => _replace(
                        p,
                        p.qty <= 1 ? null : _with(p, qty: p.qty - 1),
                      ),
                      onSize: (p, size) => _replace(
                        p,
                        _with(
                          p,
                          sizeLabel: size.isIncluded ? null : size.label,
                        ),
                      ),
                      onCustomise: (p) => unawaited(_customise(p)),
                    ),
                    const SizedBox(height: Space.md),
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
        ItemSheetFooter(
          currency: currency,
          totalMinor: quote?.lineTotalMinor ?? _detail.priceMinor * _qty,
          totalLabel: bridge.tr(key: 'combo.total'),
          note: saving > 0
              ? Text(
                  bridge
                      .tr(key: 'combo.you_save')
                      .replaceAll('{amount}', _money(saving)),
                  key: const ValueKey('combo-saving'),
                  textAlign: TextAlign.center,
                  style: MadarType.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.success,
                  ),
                )
              : null,
          label: label,
          canAdd: canSave,
          loading: _saving,
          qty: _qty,
          onDec: () => _setQty(_qty - 1),
          onInc: () => _setQty(_qty + 1),
          onCommit: () => unawaited(_save()),
          ctaKey: const ValueKey('combo-save'),
        ),
      ],
    );
  }

  void _setQty(int qty) {
    final next = qty.clamp(1, 99);
    if (next == _qty) return;
    setState(() => _qty = next);
    unawaited(_requote());
  }

  static const Object _keep = Object();
}

/// One slot, as the item sheet draws a group: its name and rule, the
/// choices as option chips ("+X" where a choice costs more), and under them
/// each pick's sizes, "Customise", and what it still needs.
class _SlotCard extends ConsumerWidget {
  const _SlotCard({
    required this.slot,
    required this.picks,
    required this.needs,
    required this.currency,
    required this.money,
    required this.addonNames,
    required this.onTapChoice,
    required this.onMore,
    required this.onLess,
    required this.onSize,
    required this.onCustomise,
    super.key,
  });

  final ComboSlotDetail slot;
  final List<ComboPickInput> picks;
  final List<ComboPickNeed> needs;
  final String currency;
  final String Function(int minor) money;
  final Map<String, List<ItemAddonView>> addonNames;
  final ValueChanged<ComboChoiceDetail> onTapChoice;
  final ValueChanged<ComboPickInput> onMore;
  final ValueChanged<ComboPickInput> onLess;
  final void Function(ComboPickInput pick, ComboSizeOption size) onSize;
  final ValueChanged<ComboPickInput> onCustomise;

  ComboChoiceDetail? _choice(String itemId) =>
      slot.choices.where((c) => c.itemId == itemId).firstOrNull;

  ComboPickInput? _pick(String itemId) =>
      picks.where((p) => p.itemId == itemId).firstOrNull;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final multi = slot.max > 1;
    void tap(String id) {
      if (_choice(id) case final c?) onTapChoice(c);
    }

    final details = [
      for (final pick in picks)
        if (_choice(pick.itemId) case final choice?)
          if (choice.sizes.length > 1 ||
              choice.customisable ||
              needs.any((n) => n.slotId == slot.id && n.itemId == pick.itemId))
            _PickDetails(
              key: ValueKey('pick-${slot.id}-${pick.itemId}'),
              pick: pick,
              choice: choice,
              need: needs
                  .where((n) => n.slotId == slot.id && n.itemId == pick.itemId)
                  .firstOrNull,
              money: money,
              addonNames: addonNames[pick.itemId] ?? const [],
              onSize: (s) => onSize(pick, s),
              onCustomise: () => onCustomise(pick),
            ),
    ];
    return ItemSheetGroupCard(
      group: AddonGroup(
        id: slot.id,
        title: slot.name,
        addons: [
          for (final c in slot.choices)
            ItemAddonView(
              addonItemId: c.itemId,
              name: c.name,
              addonType: '',
              chargedPriceMinor: c.surchargeMinor,
            ),
        ],
        isMulti: multi,
        maxSel: multi ? slot.max : 1,
        isRequired: slot.min > 0,
        minSel: slot.min,
      ),
      subtitle: slot.ruleLabel,
      currency: currency,
      charged: (id) => _choice(id)?.surchargeMinor ?? 0,
      selectedSingle: multi ? null : picks.firstOrNull?.itemId,
      selectedMulti: multi
          ? {for (final p in picks) p.itemId: p.qty}
          : const <String, int>{},
      onToggleSingle: tap,
      onToggleMulti: tap,
      onInc: (id) {
        if (_pick(id) case final p?) onMore(p);
      },
      onDec: (id) {
        if (_pick(id) case final p?) onLess(p);
      },
      optionKey: (id) => ValueKey('choice-${slot.id}-$id'),
      below: slot.choices.isEmpty
          ? Padding(
              padding: const EdgeInsetsDirectional.only(top: Space.sm),
              child: Text(
                bridge.tr(key: 'combo.nothing_to_choose'),
                style: MadarType.bodySm.copyWith(color: colors.textMuted),
              ),
            )
          : details.isEmpty
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: details,
            ),
    );
  }
}

/// A pick's own choices under its slot: the sizes (the included one free,
/// a bigger one at "+extra"), its add-ons so far, "Customise", and — when
/// its item has a required choice still unmade — what to choose.
class _PickDetails extends ConsumerWidget {
  const _PickDetails({
    required this.pick,
    required this.choice,
    required this.need,
    required this.money,
    required this.addonNames,
    required this.onSize,
    required this.onCustomise,
    super.key,
  });

  final ComboPickInput pick;
  final ComboChoiceDetail choice;
  final ComboPickNeed? need;
  final String Function(int minor) money;
  final List<ItemAddonView> addonNames;
  final ValueChanged<ComboSizeOption> onSize;
  final VoidCallback onCustomise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final need = this.need;
    final chosen = pick.sizeLabel ?? choice.includedSizeLabel;
    final extras = [
      for (final a in pick.addons)
        if (addonNames.where((n) => n.addonItemId == a.addonItemId).firstOrNull
            case final n?)
          if (a.qty > 1) '${n.name} ×${a.qty}' else n.name,
    ];
    final summary = [...extras, ?pick.notes].join(' · ');
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: Space.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: colors.borderLight),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  choice.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.bodySm.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              if (need != null) ...[
                const SizedBox(width: Space.sm),
                StatusChip(
                  key: ValueKey('need-${pick.slotId}-${pick.itemId}'),
                  label: need.text,
                  tone: ChipTone.danger,
                ),
              ],
            ],
          ),
          if (choice.sizes.length > 1) ...[
            const SizedBox(height: Space.sm),
            ItemSheetOptionGrid(
              children: [
                for (final size in choice.sizes)
                  ItemSheetChip(
                    key: ValueKey('size-${pick.itemId}-${size.label}'),
                    label: size.label,
                    sub: size.extraMinor > 0
                        ? '+${money(size.extraMinor)}'
                        : bridge.tr(key: 'combo.included'),
                    active: chosen == size.label,
                    onTap: () => onSize(size),
                  ),
              ],
            ),
          ],
          if (summary.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Text(
              summary,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: MadarType.bodySm.copyWith(color: colors.textSecondary),
            ),
          ],
          if (choice.customisable) ...[
            const SizedBox(height: Space.sm),
            MadarButton(
              key: ValueKey('customise-${pick.itemId}'),
              label: bridge.tr(key: 'combo.customise'),
              // Wanting a choice, it is the thing to do next.
              variant: need != null
                  ? MadarButtonVariant.primary
                  : MadarButtonVariant.outline,
              size: MadarButtonSize.compact,
              glyph: MadarGlyph.plus,
              onTap: onCustomise,
            ),
          ],
        ],
      ),
    );
  }
}
