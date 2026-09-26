import 'package:design_system/design_system.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One chip in the held-orders strip. Shared by the teller (parked drafts +
/// the live cart) and the waiter (a "New" tab + open tickets). [sortKey] is
/// an RFC3339 creation timestamp — the DEFAULT start→end order is
/// oldest→newest by [sortKey] (RFC3339 sorts chronologically as a plain
/// string). Dragging overrides that order.
@immutable
class HeldOrderTab {
  const HeldOrderTab({
    required this.key,
    required this.sortKey,
    required this.count,
    required this.selected,
    required this.onTap,
    this.title,
    this.glyph,
    this.onClose,
    this.onRename,
    this.author,
    this.authorLabel,
  });

  /// Who started this order, when it is not the person signed in: shown on
  /// the chip so the next teller sees whose work it is.
  final String? author;

  /// The spoken form of [author] ("Started by Ali").
  final String? authorLabel;

  final String key;

  /// RFC3339 creation time — the default (pre-drag) order.
  final String sortKey;

  /// Free-text order name; null/empty falls back to the order's number
  /// ("#2") by creation order.
  final String? title;

  /// Opens the rename affordance — rendered as a pencil on the SELECTED
  /// chip only (the live order), so the strip stays uncluttered.
  final VoidCallback? onRename;

  /// Count-badge glyph override (e.g. "plus" for the waiter New tab).
  final String? glyph;

  final int count;
  final bool selected;
  final VoidCallback onTap;

  /// Close ✕ — only when the tab is closable (parked drafts).
  final VoidCallback? onClose;
}

/// How much a held-order chip says. The cart column picks it from its OWN
/// width (see `cartDensityFor` in sell_cart.dart).
enum HeldChipStyle {
  /// The item-count badge, the order's name (or number), who started it.
  full,

  /// Just the order's number ("#2"), with its pencil / ✕: a 320–380 column.
  /// The order IN HAND keeps its name (the customer's, once attached): with
  /// the Customer chip gone from the cart, it is where the name shows.
  number,
}

/// Each tab's number: its place in creation order (the oldest is #1), so a
/// drag never renumbers the chips and two orders never share one. Shared by
/// the strip and the folded list a narrow cart opens.
Map<String, int> heldTabNumbers(List<HeldOrderTab> tabs) {
  final byAge = [...tabs]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
  return {for (var i = 0; i < byAge.length; i++) byAge[i].key: i + 1};
}

/// The drag-chosen chip order (a list of tab keys). Kept in a provider so a
/// teller's arrangement survives layout flips and strip remounts; keys that
/// vanish are filtered out per build, new keys slot in at their
/// creation-time position.
class HeldStripOrderNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  /// Persist the full display order after a drag.
  void setOrder(List<String> keys) => state = List.unmodifiable(keys);
}

/// The held-orders strip's persisted drag order.
final heldStripOrderProvider =
    NotifierProvider<HeldStripOrderNotifier, List<String>>(
      HeldStripOrderNotifier.new,
    );

/// Reconcile the persisted key order with the tabs currently present: the
/// DEFAULT order is creation-time (oldest→newest) by [HeldOrderTab.sortKey];
/// vanished keys fall out, NEW keys drop in just after their nearest
/// already-placed predecessor in creation-time order. Pure — never mutates
/// the provider during build.
List<HeldOrderTab> _reconcile(List<String> saved, List<HeldOrderTab> tabs) {
  final byKey = {for (final tab in tabs) tab.key: tab};
  final sorted = [...tabs]..sort((a, b) => a.sortKey.compareTo(b.sortKey));
  final order = [...saved]..removeWhere((key) => !byKey.containsKey(key));
  for (var i = 0; i < sorted.length; i++) {
    final tab = sorted[i];
    if (order.contains(tab.key)) continue;
    // Land the new key just after its nearest already-placed predecessor
    // in creation-time order (so it slots into its own time position).
    var insertAt = 0;
    for (var j = i - 1; j >= 0; j--) {
      final placed = order.indexOf(sorted[j].key);
      if (placed >= 0) {
        insertAt = placed + 1;
        break;
      }
    }
    order.insert(insertAt.clamp(0, order.length), tab.key);
  }
  return [for (final key in order) byKey[key]!];
}

/// Horizontal strip of polished order chips above the cart. The DEFAULT
/// start→end order is creation-time (oldest→newest) by each tab's
/// [HeldOrderTab.sortKey]; the chips are then draggable (long-press to pick
/// up) to override that order, and the chosen order sticks (via
/// [heldStripOrderProvider]).
///
/// That long press is the drag's, so a chip's cut name shows no hold hint of
/// its own; the chip it LIFTS says it instead ([MadarRevealHints] on the drag
/// proxy): hold a parked order and its whole name (and who started it) shows
/// over it while the drag keeps the press.
class HeldOrdersStrip extends ConsumerWidget {
  const HeldOrdersStrip({
    required this.tabs,
    required this.newLabel,
    this.style = HeldChipStyle.full,
    this.inline = false,
    super.key,
  });

  final List<HeldOrderTab> tabs;

  /// How much each chip says.
  final HeldChipStyle style;

  /// Laid INSIDE a row (the cart's header): no band of its own, no gutter,
  /// no hairline under it — just the scrolling chips.
  final bool inline;

  /// Localized label for the glyph tab ("New order") — resolved by the
  /// caller so the strip stays string-free.
  final String newLabel;

  /// Lift the dragged chip: scale ~1.05 + a raised shadow above its siblings
  /// — and say the whole of a name cut on it, over it, while it is held.
  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    return MadarRevealHints(
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final colors = context.madarColors;
          final dark = Theme.of(context).brightness == Brightness.dark;
          final t = Curves.easeOut.transform(animation.value);
          return Transform.scale(
            scale: 1 + 0.05 * t,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.md),
                boxShadow: MadarElevation.raised.shadows(colors, dark: dark),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final saved = ref.watch(heldStripOrderProvider);
    final display = _reconcile(saved, tabs);
    // Each order's number: its place in creation order (oldest is #1), so a
    // drag never renumbers the chips and two orders never share one.
    final numbers = heldTabNumbers(tabs);
    // onReorderItem (3.44+) hands a PRE-adjusted newIndex — no manual
    // removed-item offset like the old onReorder required.
    void handleReorder(int from, int to) {
      final keys = [for (final tab in display) tab.key];
      final key = keys.removeAt(from);
      keys.insert(to.clamp(0, keys.length), key);
      ref.read(heldStripOrderProvider.notifier).setOrder(keys);
    }

    final list = ReorderableListView(
      scrollDirection: Axis.horizontal,
      buildDefaultDragHandles: false,
      onReorderItem: handleReorder,
      proxyDecorator: _proxyDecorator,
      padding: inline
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.sm,
            ),
      children: [
        for (var i = 0; i < display.length; i++)
          ReorderableDelayedDragStartListener(
            key: ValueKey(display[i].key),
            index: i,
            child: Padding(
              padding: EdgeInsetsDirectional.only(
                end: inline
                    ? (i == display.length - 1 ? 0 : _inlineChipGap)
                    : Space.sm,
              ),
              child: inline
                  ? _InlineChip(
                      tab: display[i],
                      number: numbers[display[i].key] ?? 0,
                      style: style,
                    )
                  : _HeldOrderChip(
                      tab: display[i],
                      newLabel: newLabel,
                      number: numbers[display[i].key] ?? 0,
                      style: style,
                    ),
            ),
          ),
      ],
    );
    if (inline) {
      // The chips scroll under the header's ⋯: fade the end edge so a chip
      // cut there reads as "more this way", never as a broken chip.
      final rtl = Directionality.of(context) == TextDirection.rtl;
      return SizedBox(
        height: Metrics.buttonSmallHeight,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => LinearGradient(
            begin: rtl ? Alignment.centerRight : Alignment.centerLeft,
            end: rtl ? Alignment.centerLeft : Alignment.centerRight,
            colors: const [Colors.black, Colors.black, Colors.transparent],
            stops: [0, 1 - (Space.xl / rect.width).clamp(0, 1), 1],
          ).createShader(rect),
          child: list,
        ),
      );
    }
    return ColoredBox(
      color: colors.bg,
      child: Column(
        children: [
          SizedBox(height: kHeldChipHeight + Space.sm * 2, child: list),
          Container(height: 1, color: colors.borderLight),
        ],
      ),
    );
  }
}

/// An inline chip (the cart's header, look A): 36 to the eye inside a 44
/// target, 10 round, 10 in from its edges, 6 apart.
const double _inlineChipHeight = 36;
const double _inlineChipPad = 10;
const double _inlineChipGap = 6;

/// The cart header's chip. The order IN HAND is a soft accent wash with its
/// name (the customer's, once attached) and a pencil; a parked one is white
/// with a hairline, its number in mono and a quiet ✕.
class _InlineChip extends StatelessWidget {
  const _InlineChip({
    required this.tab,
    required this.number,
    required this.style,
  });

  final HeldOrderTab tab;
  final int number;
  final HeldChipStyle style;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final active = tab.selected;
    final name = tab.title?.trim();
    final named =
        (active || style == HeldChipStyle.full) &&
        name != null &&
        name.isNotEmpty;
    final onClose = tab.onClose;
    final onRename = tab.onRename;
    final label = MadarClippedText(
      named ? name : '#$number',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textDirection: named ? null : TextDirection.ltr,
      style: (named ? MadarType.buttonSm : MadarType.numMd).copyWith(
        color: active ? colors.accent : colors.textPrimary,
      ),
    );
    return Semantics(
      button: true,
      selected: active,
      label: named ? null : (name == null || name.isEmpty ? null : name),
      child: TactileScale(
        onTap: () {
          MadarHaptics.selection();
          tab.onTap();
        },
        // The target is the header's 44; the chip is 36 of it.
        child: SizedBox(
          height: Metrics.buttonSmallHeight,
          child: Center(
            child: Container(
              height: _inlineChipHeight,
              padding: EdgeInsetsDirectional.only(
                start: _inlineChipPad,
                end: onClose != null || (active && onRename != null)
                    ? Space.xs
                    : _inlineChipPad,
              ),
              decoration: BoxDecoration(
                color: active ? colors.accentBg : colors.surface,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(
                  color: active ? colors.accentBg : colors.border,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 112),
                    child: label,
                  ),
                  if (active && onRename != null)
                    _ChipAct(
                      key: ValueKey('held-rename-${tab.key}'),
                      glyph: MadarGlyph.edit,
                      color: colors.accent,
                      onTap: onRename,
                    ),
                  if (onClose != null)
                    _ChipAct(
                      key: ValueKey('held-close-${tab.key}'),
                      glyph: MadarGlyph.close,
                      color: colors.textMuted,
                      onTap: onClose,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A chip's pencil or ✕: a 14 glyph in a 24 x 36 target at the chip's end.
class _ChipAct extends StatelessWidget {
  const _ChipAct({
    required this.glyph,
    required this.color,
    required this.onTap,
    super.key,
  });

  final MadarGlyph glyph;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: SizedBox(
      width: Space.xl,
      height: _inlineChipHeight,
      child: Center(
        child: MadarGlyphIcon(glyph, size: IconSize.xs, color: color),
      ),
    ),
  );
}

/// Count-badge circle diameter inside a chip (natives: 24.dp).
const double _badgeSize = 24;

/// Close ✕ hit circle inside a chip (natives: 18.dp).
const double _closeSize = 18;

/// One polished order chip: count badge · time · close ✕. Inactive =
/// surface + hairline border; active = accent fill with a soft raised shadow.
class _HeldOrderChip extends StatelessWidget {
  const _HeldOrderChip({
    required this.tab,
    required this.newLabel,
    required this.number,
    this.style = HeldChipStyle.full,
  });

  final HeldOrderTab tab;
  final String newLabel;
  final HeldChipStyle style;

  /// The order's number among the held orders, oldest first.
  final int number;

  // A long press on a chip picks it up (the strip's drag): its cut name
  // hints nothing of its own here — the lifted chip says it.
  @override
  Widget build(BuildContext context) =>
      MadarHoldHints.off(child: _chip(context));

  Widget _chip(BuildContext context) {
    final colors = context.madarColors;
    final active = tab.selected;
    final badgeFg = active ? colors.textOnAccent : colors.accent;
    final onClose = tab.onClose;
    final full = style == HeldChipStyle.full;
    final named = full || active;

    return TactileScale(
      onTap: () {
        MadarHaptics.selection();
        tab.onTap();
      },
      child: Container(
        height: kHeldChipHeight,
        padding: const EdgeInsetsDirectional.only(start: Space.sm, end: 6),
        decoration: BoxDecoration(
          color: active ? colors.accent : colors.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          // Flat, like every other lit control: a raised shadow here was
          // clipped by the strip's own viewport into a grey tab under the
          // chip.
          border: Border.all(color: active ? colors.accent : colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Count badge — the waiter "New" tab shows a plus glyph instead.
            // A number-only chip drops it: the number IS the chip.
            if (full || tab.glyph != null) ...[
              Container(
                width: _badgeSize,
                height: _badgeSize,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: active
                      ? colors.textOnAccent.withValues(alpha: 0.22)
                      : colors.accentBg,
                  shape: BoxShape.circle,
                ),
                child: tab.glyph != null
                    ? MadarIcon(tab.glyph, tint: badgeFg, size: IconSize.xs)
                    : Text(
                        '${tab.count}',
                        maxLines: 1,
                        style: MadarType.labelSm.copyWith(
                          fontWeight: FontWeight.w700,
                          color: badgeFg,
                        ),
                      ),
              ),
              const SizedBox(width: Space.sm),
            ],
            // The order's NAME when the teller set one, else its number by
            // creation order; the New tab reads "new". The time the order
            // was started shows in the cart's footer.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: full ? 140 : 96),
              // A number-only chip still SAYS the order's name.
              child: Semantics(
                label: full ? null : tab.title?.trim(),
                child: MadarClippedText(
                  tab.glyph != null
                      ? newLabel
                      : named && (tab.title?.trim().isNotEmpty ?? false)
                      ? tab.title!.trim()
                      : '#$number',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MadarType.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: active ? colors.textOnAccent : colors.textPrimary,
                  ),
                ),
              ),
            ),
            if (tab.author case final author? when full) ...[
              const SizedBox(width: Space.xs),
              Semantics(
                label: tab.authorLabel ?? author,
                excludeSemantics: true,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MadarIcon(
                      'person',
                      tint: active ? colors.textOnAccent : colors.textMuted,
                      size: IconSize.xs,
                    ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 80),
                      child: MadarClippedText(
                        author,
                        // "Started by …", so the bubble says whose it is.
                        hint: tab.authorLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.labelSm.copyWith(
                          color: active
                              ? colors.textOnAccent
                              : colors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (active && tab.onRename != null) ...[
              const SizedBox(width: Space.xs),
              GestureDetector(
                onTap: tab.onRename,
                behavior: HitTestBehavior.opaque,
                child: SizedBox.square(
                  dimension: _closeSize,
                  child: Center(
                    child: MadarIcon(
                      'pencil',
                      tint: colors.textOnAccent.withValues(alpha: 0.85),
                      size: IconSize.xs,
                    ),
                  ),
                ),
              ),
            ],
            if (onClose != null) ...[
              const SizedBox(width: Space.xs),
              GestureDetector(
                onTap: onClose,
                behavior: HitTestBehavior.opaque,
                child: SizedBox.square(
                  dimension: _closeSize,
                  child: Center(
                    child: MadarIcon(
                      'xmark',
                      tint: active
                          ? colors.textOnAccent.withValues(alpha: 0.75)
                          : colors.textMuted,
                      size: IconSize.xs,
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
