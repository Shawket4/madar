// Fast mode's Extras step (owner, 2026-09-26): "for Extras on the fast mode
// make it open a full sized page view as a step to see more extras at once
// and for it to be easy also add a alphabetical sort like the one in android
// launchers or contacts app."
//
// In Fast mode (the item's choices drawn in the Sell panel) the Extras group
// is a single row — what is chosen, and a way in. Tapping it pushes a page
// over the item's choices, in the same panel: every extra at once in a grid,
// A–Z with a letter over each run, and an index rail on the end edge that
// jumps to a letter on a tap or a drag, as a contacts list does. Done (or
// back) returns to the item. The page reads and writes the item's own
// selection (itemConfigProvider), so the rules are the group card's: a tap
// adds an extra, the group's maximum still holds, and the stepper sets how
// many.
//
// The standard sheet keeps the Extras card as it was.
import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/item_detail_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Whether Fast mode shows [g] as the Extras step: the item's extras, a
/// many-option pick-several group.
bool opensAsExtrasPage(AddonGroup g) => g.isMulti && g.addonType == 'extra';

/// The letter [name] files under on the index. Latin letters upper-cased;
/// Arabic alef forms (أ إ آ ٱ) under ا, as a dictionary files them; a digit or
/// a symbol under '#'.
String extrasIndexLetter(String name) {
  final t = name.trim();
  if (t.isEmpty) return '#';
  final ch = String.fromCharCode(t.runes.first);
  const alef = {'أ', 'إ', 'آ', 'ٱ'};
  if (alef.contains(ch)) return 'ا';
  final up = ch.toUpperCase();
  final isLatin = RegExp('[A-Z]').hasMatch(up);
  final isArabic = RegExp('[ء-ي]').hasMatch(ch);
  return isLatin ? up : (isArabic ? ch : '#');
}

/// The sort key: the name folded the way its letter is.
String _sortKey(String name) => name
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[أإآٱ]'), 'ا')
    .replaceAll('ـ', '');

/// [addons] A–Z, split into runs under their letter ('#' first).
List<(String, List<ItemAddonView>)> extrasSections(List<ItemAddonView> addons) {
  final sorted = [...addons]
    ..sort((a, b) {
      final k = _sortKey(a.name).compareTo(_sortKey(b.name));
      return k != 0 ? k : a.addonItemId.compareTo(b.addonItemId);
    });
  // Insertion-ordered: letters in the order their first name sorted.
  final runs = <String, List<ItemAddonView>>{};
  for (final a in sorted) {
    runs.putIfAbsent(extrasIndexLetter(a.name), () => []).add(a);
  }
  return [
    if (runs['#'] case final digits?) ('#', digits),
    for (final e in runs.entries)
      if (e.key != '#') (e.key, e.value),
  ];
}

/// "Vanilla syrup ×2, Honey" in the group's own order, or "None chosen".
String _chosenSummary(
  MadarBridge bridge,
  AddonGroup g,
  Map<String, int> chosen,
) {
  final names = [
    for (final a in g.addons)
      if (chosen[a.addonItemId] case final qty? when qty > 1)
        '${a.name} ×$qty'
      else if (chosen.containsKey(a.addonItemId))
        a.name,
  ];
  return names.isEmpty ? bridge.tr(key: 'order.none_chosen') : names.join(', ');
}

/// Push the Extras page for [group] of the item [args] configures. Under the
/// Sell panel it stacks on the item's choices; anywhere else it is a sheet.
Future<void> openExtrasPage(
  BuildContext context, {
  required ItemSheetArgs args,
  required AddonGroup group,
  required String currency,
  required int Function(String addonItemId) charged,
}) => showMadarSheet<void>(
  context,
  size: SheetSize.large,
  builder: (_) => ExtrasPage(
    args: args,
    group: group,
    currency: currency,
    charged: charged,
  ),
);

// ── The row on the item's choices ───────────────────────────────────────────

/// The Extras group as one row in Fast mode: its name, how many are chosen,
/// the chosen names, and a chevron. The whole row opens the page.
class ExtrasStepRow extends ConsumerWidget {
  const ExtrasStepRow({
    required this.args,
    required this.group,
    required this.currency,
    required this.charged,
    this.highlighted = false,
    super.key,
  });

  final ItemSheetArgs args;
  final AddonGroup group;
  final String currency;
  final int Function(String addonItemId) charged;

  /// Flashed by Fast mode's guide, like a card.
  final bool highlighted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final chosen =
        ref.watch(itemConfigProvider(args).select((s) => s.multi[group.id])) ??
        const <String, int>{};
    return Semantics(
      button: true,
      label: group.title,
      child: TactileScale(
        key: ValueKey('extras-step-${group.id}'),
        scale: 0.99,
        onTap: () {
          MadarHaptics.selection();
          unawaited(
            openExtrasPage(
              context,
              args: args,
              group: group,
              currency: currency,
              charged: charged,
            ),
          );
        },
        child: AnimatedContainer(
          duration: motionReduced(context)
              ? Duration.zero
              : MotionSpec.gentleDuration,
          padding: const EdgeInsetsDirectional.all(Space.md),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: highlighted ? colors.accent : colors.border,
              width: highlighted ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.xs,
                  children: [
                    Row(
                      spacing: Space.sm,
                      children: [
                        Flexible(
                          child: MadarClippedText(
                            group.title.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MadarType.labelSm.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.textSecondary,
                              letterSpacing: MadarType.tracking,
                            ),
                          ),
                        ),
                        if (chosen.isNotEmpty)
                          StatusChip(
                            label: '${chosen.length}',
                            tone: ChipTone.accent,
                          ),
                      ],
                    ),
                    MadarClippedText(
                      _chosenSummary(bridge, group, chosen),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.bodySm.copyWith(
                        color: chosen.isEmpty
                            ? colors.textMuted
                            : colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              Text(
                bridge
                    .tr(key: 'order.extras_see_all')
                    .replaceAll('{count}', '${group.addons.length}'),
                style: MadarType.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: Space.xs),
              MadarGlyphIcon(
                MadarGlyph.chevronForward,
                size: IconSize.sm,
                color: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── The page ────────────────────────────────────────────────────────────────

/// Every extra of [group] at once, A–Z, with an index rail. See the file
/// header.
class ExtrasPage extends ConsumerStatefulWidget {
  const ExtrasPage({
    required this.args,
    required this.group,
    required this.currency,
    required this.charged,
    super.key,
  });

  final ItemSheetArgs args;
  final AddonGroup group;
  final String currency;
  final int Function(String addonItemId) charged;

  @override
  ConsumerState<ExtrasPage> createState() => _ExtrasPageState();
}

class _ExtrasPageState extends ConsumerState<ExtrasPage> {
  late final List<(String, List<ItemAddonView>)> _sections = extrasSections(
    widget.group.addons,
  );
  late final Map<String, GlobalKey> _letterKeys = {
    for (final s in _sections) s.$1: GlobalKey(debugLabel: 'extras-${s.$1}'),
  };
  final ScrollController _scroll = ScrollController();

  /// The letter the rail is on while a finger is on it.
  String? _touched;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jumpTo(String letter) {
    if (_touched != letter) {
      MadarHaptics.selection();
      setState(() => _touched = letter);
    }
    final target = _letterKeys[letter]?.currentContext;
    if (target == null) return;
    // A jump, not a glide: a contacts scrubber lands where the finger is.
    Scrollable.ensureVisible(target);
  }

  void _tap(_Tap t, Map<String, int> chosen) {
    final notifier = ref.read(itemConfigProvider(widget.args).notifier);
    final id = t.id;
    MadarHaptics.selection();
    switch (t.kind) {
      case _TapKind.cell:
        // Unchosen: add one (the group's maximum is the notifier's to hold).
        // Chosen: one more.
        if (chosen.containsKey(id)) {
          notifier.incMulti(widget.group, id);
        } else {
          notifier.toggleMulti(widget.group, id);
        }
      case _TapKind.less:
        notifier.decMulti(widget.group, id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final g = widget.group;
    final chosen =
        ref.watch(
          itemConfigProvider(widget.args).select((s) => s.multi[g.id]),
        ) ??
        const <String, int>{};
    final letters = [for (final s in _sections) s.$1];

    return ColoredBox(
      color: colors.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: back, the group and the item, what is chosen.
          ColoredBox(
            color: colors.surface,
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                Space.md,
                Space.md,
                Space.xl,
                Space.md,
              ),
              child: Row(
                spacing: Space.md,
                children: [
                  MadarGlyphTile(
                    key: const ValueKey('extras-back'),
                    glyph: MadarGlyph.chevronBack,
                    semanticLabel: bridge.tr(key: 'order.extras_back'),
                    onTap: () => MadarSheet.close<void>(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.title,
                          style: MadarType.h3.copyWith(
                            color: colors.textPrimary,
                          ),
                        ),
                        MadarClippedText(
                          widget.args.item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: MadarType.bodySm.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (g.maxSel != null) StatusChip(label: '≤${g.maxSel}'),
                  StatusChip(
                    key: const ValueKey('extras-count'),
                    label: bridge
                        .tr(key: 'order.extras_chosen')
                        .replaceAll('{count}', '${chosen.length}'),
                    tone: chosen.isEmpty ? ChipTone.neutral : ChipTone.accent,
                  ),
                ],
              ),
            ),
          ),
          Container(height: 1, color: colors.borderLight),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('extras-scroll'),
                    controller: _scroll,
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      Space.xl,
                      Space.md,
                      Space.md,
                      Space.xl,
                    ),
                    child: LayoutBuilder(
                      builder: (context, box) {
                        // As many columns as fit at 150, between 2 and 5.
                        final cols = (box.maxWidth / 150).floor().clamp(2, 5);
                        final cell =
                            (box.maxWidth - Space.sm * (cols - 1)) / cols;
                        // ONE continuous grid, A–Z, as a launcher's app
                        // drawer: runs never break a row, so the page shows
                        // as many extras as fit. The first cell of each run
                        // carries its letter, and is where the rail jumps.
                        return Wrap(
                          spacing: Space.sm,
                          runSpacing: Space.sm,
                          children: [
                            for (final (letter, items) in _sections)
                              for (final (i, a) in items.indexed)
                                SizedBox(
                                  key: i == 0 ? _letterKeys[letter] : null,
                                  width: cell,
                                  child: _ExtraCell(
                                    key: ValueKey('extra-${a.addonItemId}'),
                                    addon: a,
                                    letter: i == 0 ? letter : null,
                                    priceMinor: widget.charged(a.addonItemId),
                                    currency: widget.currency,
                                    qty: chosen[a.addonItemId] ?? 0,
                                    onTap: () => _tap(
                                      _Tap(a.addonItemId, _TapKind.cell),
                                      chosen,
                                    ),
                                    onLess: () => _tap(
                                      _Tap(a.addonItemId, _TapKind.less),
                                      chosen,
                                    ),
                                  ),
                                ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                if (letters.length > 1)
                  _IndexRail(
                    letters: letters,
                    touched: _touched,
                    onLetter: _jumpTo,
                    onRelease: () => setState(() => _touched = null),
                  ),
              ],
            ),
          ),
          // Footer: the one ink action.
          ColoredBox(
            color: colors.surface,
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: Space.xl,
                vertical: Space.md,
              ),
              child: MadarButton(
                key: const ValueKey('extras-done'),
                label: bridge.tr(key: 'common.done'),
                onTap: () => MadarSheet.close<void>(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _TapKind { cell, less }

/// A tap on one extra: the cell (add / one more) or its minus.
class _Tap {
  const _Tap(this.id, this.kind);
  final String id;
  final _TapKind kind;
}

/// One extra: its name (whole on a long press when it is cut short), its
/// price, and — chosen — a 2px accent border, the count, and a minus.
class _ExtraCell extends StatelessWidget {
  const _ExtraCell({
    required this.addon,
    required this.letter,
    required this.priceMinor,
    required this.currency,
    required this.qty,
    required this.onTap,
    required this.onLess,
    super.key,
  });

  final ItemAddonView addon;

  /// The run's letter, on the first cell of each run; null on the others.
  final String? letter;
  final int priceMinor;
  final String currency;
  final int qty;
  final VoidCallback onTap;
  final VoidCallback onLess;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final on = qty > 0;
    final price = priceMinor > 0
        ? '+${Money.format(priceMinor, currency: currency, locale: MadarFormat.localeOf(context))}'
        : null;
    return Semantics(
      button: true,
      selected: on,
      label: addon.name,
      child: SizedBox(
        height: 96,
        child: Stack(
          children: [
            Positioned.fill(
              child: TactileScale(
                onTap: onTap,
                child: Container(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    Space.md,
                    Space.sm,
                    Space.md,
                    Space.sm,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(Radii.control),
                    border: Border.all(
                      color: on ? colors.accent : colors.borderLight,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // The run's letter (every cell keeps the line, so the
                      // names line up across a row).
                      Text(
                        letter ?? '',
                        key: letter == null
                            ? null
                            : ValueKey('extras-letter-$letter'),
                        style: MadarType.labelSm.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.textMuted,
                          height: 1,
                        ),
                      ),
                      Padding(
                        // Clear of the count badge.
                        padding: EdgeInsetsDirectional.only(
                          end: on ? Space.xl : 0,
                        ),
                        child: _HoldForFullName(
                          text: addon.name,
                          style: MadarType.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                            height: 1.2,
                          ),
                        ),
                      ),
                      // A free extra keeps the line, so its name sits
                      // where every other name does.
                      Text(
                        price ?? '',
                        textDirection: TextDirection.ltr,
                        style: MadarType.num.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (on) ...[
              PositionedDirectional(
                top: Space.sm,
                end: Space.sm,
                child: IgnorePointer(
                  child: Container(
                    key: ValueKey('extra-qty-${addon.addonItemId}'),
                    constraints: const BoxConstraints(minWidth: 24),
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: Text(
                      '$qty',
                      style: MadarType.num.copyWith(
                        color: colors.textOnAccent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                bottom: 0,
                end: 0,
                child: Semantics(
                  button: true,
                  label: '− ${addon.name}',
                  child: TactileScale(
                    key: ValueKey('extra-less-${addon.addonItemId}'),
                    scale: 0.9,
                    onTap: onLess,
                    child: SizedBox.square(
                      // A 44pt target over the cell's corner.
                      dimension: Metrics.stepper,
                      child: Center(
                        child: Container(
                          width: 28,
                          height: 28,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.surfaceAlt,
                            shape: BoxShape.circle,
                            border: Border.all(color: colors.border),
                          ),
                          child: MadarGlyphIcon(
                            MadarGlyph.minus,
                            size: IconSize.xs,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A name in two lines at most; when it is cut short, a long press shows it
/// whole (the owner's rule for every truncated text: the kit's
/// [MadarClippedText]).
class _HoldForFullName extends StatelessWidget {
  const _HoldForFullName({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => MadarClippedText(
    text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: style,
  );
}

/// The contacts-style index: the letters present, top to bottom on the end
/// edge. A tap or a drag lands on the letter under the finger.
class _IndexRail extends StatelessWidget {
  const _IndexRail({
    required this.letters,
    required this.touched,
    required this.onLetter,
    required this.onRelease,
  });

  final List<String> letters;
  final String? touched;
  final ValueChanged<String> onLetter;
  final VoidCallback onRelease;

  static const double _width = 36;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return LayoutBuilder(
      builder: (context, box) {
        // Each letter's band, at most 36 tall, centred as a column.
        final band = (box.maxHeight / letters.length).clamp(14.0, 36.0);
        final top = (box.maxHeight - band * letters.length) / 2;
        void hit(double dy) {
          final i = ((dy - top) / band).floor().clamp(0, letters.length - 1);
          onLetter(letters[i]);
        }

        return GestureDetector(
          key: const ValueKey('extras-index'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => hit(d.localPosition.dy),
          onTapUp: (_) => onRelease(),
          onVerticalDragStart: (d) => hit(d.localPosition.dy),
          onVerticalDragUpdate: (d) => hit(d.localPosition.dy),
          onVerticalDragEnd: (_) => onRelease(),
          child: Container(
            width: _width,
            margin: const EdgeInsetsDirectional.only(end: Space.xs),
            decoration: BoxDecoration(
              color: touched == null ? Colors.transparent : colors.surfaceAlt,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final l in letters)
                  SizedBox(
                    height: band,
                    child: Center(
                      child: Text(
                        l,
                        key: ValueKey('extras-index-$l'),
                        style: MadarType.labelSm.copyWith(
                          fontWeight: FontWeight.w700,
                          color: l == touched
                              ? colors.accent
                              : colors.textSecondary,
                          fontSize: l == touched ? 15 : 12,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
