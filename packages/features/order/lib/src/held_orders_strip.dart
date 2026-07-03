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
  });

  final String key;

  /// RFC3339 creation time — the default (pre-drag) order.
  final String sortKey;

  /// Free-text order name; null/empty falls back to the "HH:MM" time label
  /// derived from [sortKey].
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
class HeldOrdersStrip extends ConsumerWidget {
  const HeldOrdersStrip({
    required this.tabs,
    required this.newLabel,
    super.key,
  });

  final List<HeldOrderTab> tabs;

  /// Localized label for the glyph tab ("New order") — resolved by the
  /// caller so the strip stays string-free.
  final String newLabel;

  /// Lift the dragged chip: scale ~1.05 + a raised shadow above its siblings.
  Widget _proxyDecorator(
    Widget child,
    int index,
    Animation<double> animation,
  ) {
    return AnimatedBuilder(
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
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final saved = ref.watch(heldStripOrderProvider);
    final display = _reconcile(saved, tabs);
    // onReorderItem (3.44+) hands a PRE-adjusted newIndex — no manual
    // removed-item offset like the old onReorder required.
    void handleReorder(int from, int to) {
      final keys = [for (final tab in display) tab.key];
      final key = keys.removeAt(from);
      keys.insert(to.clamp(0, keys.length), key);
      ref.read(heldStripOrderProvider.notifier).setOrder(keys);
    }

    return ColoredBox(
      color: colors.surface,
      child: Column(
        children: [
          SizedBox(
            height: kHeldChipHeight + Space.sm * 2,
            child: ReorderableListView(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              onReorderItem: handleReorder,
              proxyDecorator: _proxyDecorator,
              padding: const EdgeInsets.symmetric(
                horizontal: Space.lg,
                vertical: Space.sm,
              ),
              children: [
                for (var i = 0; i < display.length; i++)
                  ReorderableDelayedDragStartListener(
                    key: ValueKey(display[i].key),
                    index: i,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(end: Space.sm),
                      child: _HeldOrderChip(
                        tab: display[i],
                        newLabel: newLabel,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(height: 1, color: colors.borderLight),
        ],
      ),
    );
  }
}

/// Count-badge circle diameter inside a chip (natives: 24.dp).
const double _badgeSize = 24;

/// Close ✕ hit circle inside a chip (natives: 18.dp).
const double _closeSize = 18;

/// One polished order chip: count badge · time · close ✕. Inactive =
/// surface + hairline border; active = accent fill with a soft raised shadow.
class _HeldOrderChip extends StatelessWidget {
  const _HeldOrderChip({required this.tab, required this.newLabel});

  final HeldOrderTab tab;
  final String newLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final active = tab.selected;
    final badgeFg = active ? colors.textOnAccent : colors.accent;
    final onClose = tab.onClose;

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
          border: active ? null : Border.all(color: colors.border),
          boxShadow: active
              ? MadarElevation.raised.shadows(colors, dark: dark)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Count badge — the waiter "New" tab shows a plus glyph instead.
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
            // The order's NAME when the teller set one, else "HH:MM" from
            // the (immutable) creation stamp; the New tab reads "new".
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                tab.glyph != null
                    ? newLabel
                    : (tab.title?.trim().isNotEmpty ?? false)
                    ? tab.title!.trim()
                    : formatHHMM(tab.sortKey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MadarType.bodySm.copyWith(
                  fontWeight: FontWeight.w600,
                  color: active ? colors.textOnAccent : colors.textPrimary,
                ),
              ),
            ),
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
