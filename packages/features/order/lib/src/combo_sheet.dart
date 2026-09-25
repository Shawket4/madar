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
// Every figure is the core's (`comboQuote`); the sheet only keeps the picks
// and hands them back. A refusal to save is the core's sentence, on the
// toast.

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
    size: SheetSize.large,
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
  /// picked, let it go); larger slots add it while there is room.
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
      _setPicks([
        for (final p in _picks)
          if (p.slotId != slot.id) p,
        _fresh(slot, c),
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
    _setPicks([..._picks, _fresh(slot, c)]);
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
    final label = !_detail.availableNow
        ? (_detail.whyUnavailable ?? bridge.tr(key: 'combo.not_now'))
        : quote != null && !quote.complete && quote.refusalText != null
        ? quote.refusalText!
        : bridge.tr(key: editing ? 'combo.update' : 'combo.add');
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ComboHeader(detail: _detail, currency: currency),
        Expanded(
          child: ColoredBox(
            color: colors.surfaceAlt,
            // Not lazy: a combo has a handful of slots, and every one of
            // them is part of the picture the teller checks before saving.
            child: SingleChildScrollView(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Space.xl,
                vertical: Space.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    _SlotSection(
                      key: ValueKey('slot-${slot.id}'),
                      slot: slot,
                      picks: _picksOf(slot),
                      currency: currency,
                      money: _money,
                      addonNames: _addonNames,
                      onTapChoice: (c) => _tapChoice(slot, c),
                      onSize: (p, size) => _replace(
                        p,
                        _with(
                          p,
                          sizeLabel: size.isIncluded ? null : size.label,
                        ),
                      ),
                      onQty: (p, q) =>
                          _replace(p, q < 1 ? null : _with(p, qty: q)),
                      roomLeft: slot.max - _countOf(slot),
                      onCustomise: (p) => unawaited(_customise(p)),
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
        _ComboFooter(
          currency: currency,
          totalMinor: quote?.lineTotalMinor ?? _detail.priceMinor * _qty,
          savingMinor: quote?.savingMinor ?? 0,
          qty: _qty,
          label: label,
          canSave: canSave,
          saving: _saving,
          onQty: (q) {
            setState(() => _qty = q);
            unawaited(_requote());
          },
          onSave: () => unawaited(_save()),
        ),
      ],
    );
  }

  static const Object _keep = Object();
}

class _ComboHeader extends ConsumerWidget {
  const _ComboHeader({required this.detail, required this.currency});

  final ComboDetail detail;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final description = detail.description;
    return ColoredBox(
      color: colors.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.xl,
              vertical: Space.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: Space.md,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: Space.xs,
                    children: [
                      MadarTag(
                        label: bridge.tr(key: 'combo.badge'),
                        tone: MadarTone.accent,
                      ),
                      Text(
                        detail.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.h3.copyWith(
                          fontWeight: FontWeight.w900,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (description != null && description.isNotEmpty)
                        Text(
                          description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: MadarType.bodySm.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                MoneyText(
                  detail.priceMinor,
                  currency: currency,
                  color: colors.navy,
                ),
                MadarGlyphTile(
                  glyph: MadarGlyph.close,
                  semanticLabel: bridge.tr(key: 'common.close'),
                  onTap: () => MadarSheet.close<void>(context),
                ),
              ],
            ),
          ),
          const MadarHairline(),
        ],
      ),
    );
  }
}

/// One slot: its rule ("Choose 1 item"), the choices, and under them each
/// pick's size chips and "Customise".
class _SlotSection extends ConsumerWidget {
  const _SlotSection({
    required this.slot,
    required this.picks,
    required this.currency,
    required this.money,
    required this.addonNames,
    required this.onTapChoice,
    required this.onSize,
    required this.onQty,
    required this.roomLeft,
    required this.onCustomise,
    super.key,
  });

  final ComboSlotDetail slot;
  final List<ComboPickInput> picks;
  final String currency;
  final String Function(int minor) money;
  final Map<String, List<ItemAddonView>> addonNames;
  final ValueChanged<ComboChoiceDetail> onTapChoice;
  final void Function(ComboPickInput pick, ComboSizeOption size) onSize;
  final void Function(ComboPickInput pick, int qty) onQty;
  final int roomLeft;
  final ValueChanged<ComboPickInput> onCustomise;

  ComboChoiceDetail? _choice(String itemId) =>
      slot.choices.where((c) => c.itemId == itemId).firstOrNull;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        MadarSectionHeader(
          text: slot.name,
          trailing: Flexible(
            child: Text(
              slot.ruleLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        if (slot.choices.isEmpty)
          Text(
            bridge.tr(key: 'combo.nothing_to_choose'),
            style: MadarType.bodySm.copyWith(color: colors.textMuted),
          )
        else
          LayoutBuilder(
            builder: (context, c) {
              final cols = c.maxWidth >= 560
                  ? 3
                  : c.maxWidth >= 340
                  ? 2
                  : 1;
              final w = (c.maxWidth - Space.sm * (cols - 1)) / cols;
              return Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final choice in slot.choices)
                    SizedBox(
                      width: w,
                      child: _ChoiceTile(
                        key: ValueKey('choice-${slot.id}-${choice.itemId}'),
                        choice: choice,
                        selected: picks.any((p) => p.itemId == choice.itemId),
                        money: money,
                        onTap: () => onTapChoice(choice),
                      ),
                    ),
                ],
              );
            },
          ),
        for (final pick in picks)
          if (_choice(pick.itemId) case final choice?)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: Space.sm),
              child: _PickCard(
                key: ValueKey('pick-${slot.id}-${pick.itemId}'),
                pick: pick,
                choice: choice,
                multi: slot.max > 1,
                maxQty: pick.qty + (roomLeft < 0 ? 0 : roomLeft),
                money: money,
                addonNames: addonNames[pick.itemId] ?? const [],
                onSize: (s) => onSize(pick, s),
                onQty: (q) => onQty(pick, q),
                onCustomise: () => onCustomise(pick),
              ),
            ),
      ],
    );
  }
}

class _ChoiceTile extends ConsumerWidget {
  const _ChoiceTile({
    required this.choice,
    required this.selected,
    required this.money,
    required this.onTap,
    super.key,
  });

  final ComboChoiceDetail choice;
  final bool selected;
  final String Function(int minor) money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final sub = choice.surchargeMinor > 0
        ? '+${money(choice.surchargeMinor)}'
        : switch (choice.includedSizeLabel) {
            final size? when choice.sizes.length > 1 =>
              bridge.tr(key: 'combo.included_size').replaceAll('{size}', size),
            _ => null,
          };
    return Semantics(
      button: true,
      selected: selected,
      label: sub == null ? choice.name : '${choice.name}, $sub',
      excludeSemantics: true,
      child: MadarCard(
        onTap: onTap,
        selected: selected,
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: Metrics.buttonHeight),
          child: Row(
            spacing: Space.sm,
            children: [
              MadarGlyphIcon(
                selected ? MadarGlyph.check : MadarGlyph.plus,
                size: IconSize.sm,
                color: selected ? colors.accent : colors.textMuted,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      choice.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.title.copyWith(
                        color: colors.textPrimary,
                      ),
                    ),
                    if (sub != null)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.bodySm.copyWith(
                          color: choice.surchargeMinor > 0
                              ? colors.accent
                              : colors.textMuted,
                        ),
                      ),
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

/// One pick: its sizes (the included one free, bigger ones at "+extra"),
/// its count in a slot that takes several, and "Customise".
class _PickCard extends ConsumerWidget {
  const _PickCard({
    required this.pick,
    required this.choice,
    required this.multi,
    required this.maxQty,
    required this.money,
    required this.addonNames,
    required this.onSize,
    required this.onQty,
    required this.onCustomise,
    super.key,
  });

  final ComboPickInput pick;
  final ComboChoiceDetail choice;
  final bool multi;
  final int maxQty;
  final String Function(int minor) money;
  final List<ItemAddonView> addonNames;
  final ValueChanged<ComboSizeOption> onSize;
  final ValueChanged<int> onQty;
  final VoidCallback onCustomise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final chosen = pick.sizeLabel ?? choice.includedSizeLabel;
    final extras = [
      for (final a in pick.addons)
        if (addonNames.where((n) => n.addonItemId == a.addonItemId).firstOrNull
            case final n?)
          if (a.qty > 1) '${n.name} ×${a.qty}' else n.name,
    ];
    final showSizes = choice.sizes.length > 1;
    if (!showSizes && !multi && !choice.customisable) {
      return const SizedBox.shrink();
    }
    return MadarCard.column(
      spacing: Space.sm,
      padding: const EdgeInsetsDirectional.all(Space.md),
      children: [
        Row(
          spacing: Space.sm,
          children: [
            Expanded(
              child: Text(
                choice.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.title.copyWith(color: colors.textPrimary),
              ),
            ),
            if (multi)
              MadarStepper(value: pick.qty, max: maxQty, onChanged: onQty),
          ],
        ),
        if (showSizes)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: Space.sm,
              children: [
                for (final size in choice.sizes)
                  MadarChip(
                    key: ValueKey('size-${pick.itemId}-${size.label}'),
                    label: size.extraMinor > 0
                        ? '${size.label} +${money(size.extraMinor)}'
                        : size.label,
                    selected: chosen == size.label,
                    onTap: () => onSize(size),
                  ),
              ],
            ),
          ),
        if (extras.isNotEmpty || (pick.notes?.isNotEmpty ?? false))
          Text(
            [...extras, ?pick.notes].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: MadarType.bodySm.copyWith(color: colors.textSecondary),
          ),
        if (choice.customisable)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: MadarButton(
              key: ValueKey('customise-${pick.itemId}'),
              label: bridge.tr(key: 'combo.customise'),
              variant: MadarButtonVariant.ghost,
              size: MadarButtonSize.compact,
              glyph: MadarGlyph.plus,
              onTap: onCustomise,
            ),
          ),
      ],
    );
  }
}

class _ComboFooter extends ConsumerWidget {
  const _ComboFooter({
    required this.currency,
    required this.totalMinor,
    required this.savingMinor,
    required this.qty,
    required this.label,
    required this.canSave,
    required this.saving,
    required this.onQty,
    required this.onSave,
  });

  final String currency;
  final int totalMinor;
  final int savingMinor;
  final int qty;
  final String label;
  final bool canSave;
  final bool saving;
  final ValueChanged<int> onQty;
  final VoidCallback onSave;

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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.sm,
          children: [
            GrandTotalBlock(
              label: bridge.tr(key: 'combo.total'),
              totalMinor: totalMinor,
              currency: currency,
            ),
            if (savingMinor > 0)
              Text(
                bridge
                    .tr(key: 'combo.you_save')
                    .replaceAll(
                      '{amount}',
                      Money.format(
                        savingMinor,
                        currency: currency,
                        locale: MadarFormat.localeOf(context),
                      ),
                    ),
                key: const ValueKey('combo-saving'),
                textAlign: TextAlign.center,
                style: MadarType.bodySm.copyWith(color: colors.success),
              ),
            Row(
              spacing: Space.md,
              children: [
                MadarStepper(value: qty, min: 1, onChanged: onQty),
                Expanded(
                  child: MadarButton(
                    key: const ValueKey('combo-save'),
                    label: label,
                    enabled: canSave,
                    loading: saving,
                    onTap: onSave,
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
