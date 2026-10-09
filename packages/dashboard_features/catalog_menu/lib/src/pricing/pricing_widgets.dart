/// The pricing matrix's parts: the cell control both layouts share
/// (`PricingControl`), the desktop matrix with its sticky first column
/// (`Matrix`, `MatrixHead`, `ItemRow`, `AddonRow`), the phone cards
/// (`ItemCard`, `AddonCard`, `TargetScopeList`) and the legend.
library;

import 'package:dashboard_api/dashboard_api.dart' show MenuItemWithCosts;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../items/items_widgets.dart' show MenuImageTile, menuImageUrl;
import 'pricing_model.dart';

/// Fixed widths of the web's table (`min-w-56`, `min-w-28`, `min-w-36`).
abstract final class PricingMetrics {
  static const double first = Space.xxl * 7; // 224
  static const double catalog = Space.xxl * 3.5; // 112
  static const double cell = Space.xxl * 4.5; // 144
  static const double tile = Space.xxl + Space.xs; // 36
  static const double scopeLabel = Space.xxl * 2.5; // 80 (w-20)
  static const double toggleSmall = Space.xl + Space.xs; // 28
  static const double toggleTouch = Space.xxl + Space.xs; // 36
  static const double dot = Space.sm;
  static const double skeleton = Space.xxl * 8; // h-64
  static const double barSkeleton = 448; // max-w-md
}

/// The cell edit callbacks: a new price text and/or availability.
typedef DraftPatch = void Function({String? price, bool? available});

/// `PricingControl`: the price box (the effective price as a muted
/// placeholder; an explicit price bold, with a × to remove it), the "Set
/// here" / "↳ source" line and the availability switch. [touch] is the
/// phone row's larger switch.
class PricingControl extends StatelessWidget {
  const PricingControl({
    required this.resolved,
    required this.draft,
    required this.onChange,
    required this.onClear,
    required this.currencyLabel,
    this.touch = false,
    super.key,
  });

  final ResolvedCell resolved;
  final DraftCell draft;
  final DraftPatch onChange;
  final VoidCallback onClear;

  /// `currencyLabel()`, for the price box's name.
  final String currencyLabel;
  final bool touch;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.madarColors;
    final dirty = isDirtyCell(draft, resolved);
    final explicit = draft.price.trim().isNotEmpty;
    final hidden = !draft.available;
    final inherited = !resolved.availExplicit && !dirty;
    final from = resolved.priceFromBranch
        ? t('menu.pricing.fromBranch')
        : t('menu.pricing.fromCatalog');
    final box = touch
        ? PricingMetrics.toggleTouch
        : PricingMetrics.toggleSmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        PriceField(
          value: draft.price,
          onChanged: (v) => onChange(price: v),
          placeholder: pricePlaceholder(resolved.effectivePrice),
          label: t(
            'menu.pricing.priceAria',
            args: {'currency': currencyLabel},
          ),
          strong: explicit,
          clearLabel: resolved.priceExplicit && !dirty
              ? t('menu.pricing.clearOverride')
              : null,
          onClear: onClear,
        ),
        Row(
          children: [
            Expanded(
              child: explicit
                  ? Text(
                      t('menu.pricing.explicit'),
                      style: DashType.smallStrong.copyWith(
                        color: c.textPrimary,
                      ),
                    )
                  : MadarHoldHint(
                      message: from,
                      child: Row(
                        spacing: DashMetrics.hair,
                        children: [
                          Transform.flip(
                            flipX: context.isRtl,
                            child: DashIcon(
                              'corner-down-right',
                              size: IconSize.xs - 2,
                              color: c.textSecondary,
                            ),
                          ),
                          Flexible(
                            child: MadarClippedText(
                              resolved.priceFromBranch
                                  ? t('menu.pricing.branchPrice')
                                  : t('menu.pricing.catalogPrice'),
                              maxLines: 1,
                              style: DashType.small.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            DashPressable(
              key: const ValueKey('avail'),
              onTap: () => onChange(available: !draft.available),
              checked: draft.available,
              semanticLabel: draft.available
                  ? t('menu.pricing.available')
                  : t('menu.pricing.hidden'),
              tooltip: draft.available
                  ? t('menu.pricing.markHidden')
                  : t('menu.pricing.markAvailable'),
              excludeChildSemantics: true,
              pressScale: false,
              builder: (context, s) => SizedBox.square(
                dimension: DashMetrics.target,
                child: Center(
                  child: Container(
                    width: box,
                    height: box,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: hidden
                          ? c.danger.withValues(alpha: 0.1)
                          : s.highlighted
                          ? c.muted
                          : null,
                      borderRadius: BorderRadius.circular(Radii.xs - 2),
                      border: Border.all(
                        color: hidden
                            ? c.danger.withValues(alpha: 0.3)
                            : Colors.transparent,
                      ),
                    ),
                    child: DashIcon(
                      draft.available ? 'eye' : 'eye-off',
                      size: IconSize.xs,
                      color: hidden
                          ? c.danger
                          : inherited
                          ? c.textMuted
                          : c.textPrimary,
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

/// The price box: a number input in pounds (decimal keyboard), the typed
/// text bold when [strong], an optional × at the end.
class PriceField extends StatefulWidget {
  const PriceField({
    required this.value,
    required this.onChanged,
    required this.placeholder,
    required this.label,
    required this.onClear,
    this.strong = false,
    this.clearLabel,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String placeholder;
  final String label;
  final bool strong;

  /// "Remove override" when the × shows, else null.
  final String? clearLabel;
  final VoidCallback onClear;

  @override
  State<PriceField> createState() => _PriceFieldState();
}

class _PriceFieldState extends State<PriceField> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(PriceField old) {
    super.didUpdateWidget(old);
    if (widget.value != _controller.text) _controller.text = widget.value;
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final style = DashType.mono.copyWith(
      fontSize: 14,
      color: c.textPrimary,
      fontWeight: widget.strong ? FontWeight.w600 : FontWeight.w400,
    );
    final clear = widget.clearLabel;
    return DashFieldShell(
      focused: _focus.hasFocus,
      padding: EdgeInsetsDirectional.only(
        start: Space.sm + DashMetrics.hair,
        end: clear == null ? Space.sm : 0,
      ),
      trailing: clear == null
          ? null
          : DashPressable(
              key: const ValueKey('clear'),
              onTap: widget.onClear,
              semanticLabel: clear,
              tooltip: clear,
              excludeChildSemantics: true,
              pressScale: false,
              // A 44 px target around the 24 px face.
              builder: (context, s) => SizedBox.square(
                dimension: DashMetrics.target,
                child: Center(
                  child: Container(
                    width: Space.xl,
                    height: Space.xl,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: s.highlighted ? c.muted : null,
                      borderRadius: BorderRadius.circular(Radii.xs - 2),
                    ),
                    child: DashIcon(
                      'x',
                      size: IconSize.xs,
                      color: s.highlighted ? c.textPrimary : c.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
      child: Semantics(
        label: widget.label,
        textField: true,
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          onChanged: widget.onChanged,
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          // A number input: what `type=number` lets through.
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
          // Digits read left to right, aligned to the line's start.
          textDirection: TextDirection.ltr,
          textAlign: context.isRtl ? TextAlign.right : TextAlign.left,
          style: style,
          cursorColor: c.textPrimary,
          cursorWidth: 1.5,
          decoration: InputDecoration(
            isDense: true,
            isCollapsed: true,
            border: InputBorder.none,
            hintText: widget.placeholder,
            hintStyle: style.copyWith(
              color: c.textMuted,
              fontWeight: FontWeight.w400,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: Space.sm),
          ),
        ),
      ),
    );
  }
}

/// The unsaved-edits dot.
class PricingDirtyDot extends StatelessWidget {
  const PricingDirtyDot({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: PricingMetrics.dot,
    height: PricingMetrics.dot,
    decoration: BoxDecoration(
      color: context.madarColors.accent,
      shape: BoxShape.circle,
    ),
  );
}

/// The expand button of an item (row head on desktop, card head on phone).
class PricingItemHead extends StatelessWidget {
  const PricingItemHead({
    required this.item,
    required this.name,
    required this.open,
    required this.dirty,
    required this.onToggle,
    this.onIntent,
    super.key,
  });

  final MenuItemWithCosts item;
  final String name;
  final bool open;
  final bool dirty;
  final VoidCallback onToggle;

  /// About to be pressed: warm the item's studio read.
  final VoidCallback? onIntent;

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.madarColors;
    final hint = open
        ? t('menu.pricing.collapseHint')
        : t('menu.pricing.expandHint');
    return DashPressable(
      onTap: onToggle,
      onIntent: onIntent,
      expanded: open,
      semanticLabel: '$name, $hint',
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Container(
        color: s.highlighted ? c.muted : null,
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm + DashMetrics.hair,
        ),
        child: Row(
          spacing: Space.sm + DashMetrics.hair,
          children: [
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: DashMotion.of(context, DashMotion.base),
              child: DashIcon('chevron-down', color: c.textSecondary),
            ),
            MenuImageTile(
              url: menuImageUrl(item.image, item.imageUrl),
              icon: 'cup-soda',
              size: PricingMetrics.tile,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  MadarClippedText(
                    name,
                    maxLines: 1,
                    style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                  ),
                  Text(
                    hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            if (dirty) const PricingDirtyDot(),
          ],
        ),
      ),
    );
  }
}

/// A size's pill (+ "inactive").
class PricingSizePill extends StatelessWidget {
  const PricingSizePill({required this.label, required this.active, super.key});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.sm,
              vertical: DashMetrics.hair,
            ),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(Radii.pill),
            ),
            child: MadarClippedText(
              label,
              maxLines: 1,
              style: DashType.smallMedium.copyWith(color: c.textPrimary),
            ),
          ),
        ),
        if (!active)
          Text(
            context.t('menu.pricing.inactive'),
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}

// ── the desktop matrix ────────────────────────────────────────────────────

/// The column widths at a given table width: the web's minimums, any spare
/// width shared in proportion (a `w-full` table).
typedef MatrixWidths = ({double first, double catalog, double cell});

MatrixWidths matrixWidths(double available) {
  const min =
      PricingMetrics.first +
      PricingMetrics.catalog +
      PricingMetrics.cell * 5;
  final k = available > min ? available / min : 1.0;
  return (
    first: PricingMetrics.first * k,
    catalog: PricingMetrics.catalog * k,
    cell: PricingMetrics.cell * k,
  );
}

double matrixTotal(MatrixWidths w) => w.first + w.catalog + w.cell * 5;

/// The bordered card that scrolls sideways with its first column held in
/// place (`Matrix`): every row gets [widths] and [sticky] to build with.
class PricingMatrix extends StatefulWidget {
  const PricingMatrix({required this.rows, super.key});

  /// Builds the rows (the head first).
  final List<Widget> Function(MatrixWidths widths, StickyRow sticky) rows;

  @override
  State<PricingMatrix> createState() => _PricingMatrixState();
}

/// Lays out one matrix row: [first] (held in place while the rest scrolls,
/// painted over it) then [rest], all stretched to the row's height.
typedef StickyRow =
    Widget Function(Widget first, List<Widget> rest, {Color? background});

class _PricingMatrixState extends State<PricingMatrix> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final rtl = context.isRtl;
    Widget sticky(Widget first, List<Widget> rest, {Color? background}) {
      // The first cell is listed LAST in a row laid out in the opposite
      // direction, so it paints over the cells scrolling under it.
      return IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: rtl ? TextDirection.ltr : TextDirection.rtl,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ...rest.reversed,
            AnimatedBuilder(
              animation: _scroll,
              builder: (context, child) => Transform.translate(
                offset: Offset(
                  _scroll.hasClients ? _scroll.offset * (rtl ? -1 : 1) : 0,
                  0,
                ),
                child: child,
              ),
              child: ColoredBox(
                color: c.card,
                child: background == null
                    ? first
                    : ColoredBox(color: background, child: first),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = matrixWidths(constraints.maxWidth - 2);
        return Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: c.hairline),
          ),
          child: Scrollbar(
            controller: _scroll,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: matrixTotal(w),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.rows(w, sticky),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A cell with the row's top border and, for editable columns, a start
/// border.
class MatrixCell extends StatelessWidget {
  const MatrixCell({
    required this.width,
    required this.child,
    this.startBorder = false,
    this.topBorder = true,
    this.color,
    this.padding = const EdgeInsets.symmetric(
      horizontal: Space.sm + DashMetrics.hair,
      vertical: Space.sm,
    ),
    this.alignment = AlignmentDirectional.centerStart,
    super.key,
  });

  final double width;
  final Widget child;
  final bool startBorder;
  final bool topBorder;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final line = BorderSide(color: context.madarColors.hairline);
    return Container(
      width: width,
      padding: padding,
      alignment: alignment,
      decoration: BoxDecoration(
        color: color,
        border: BorderDirectional(
          top: topBorder ? line : BorderSide.none,
          start: startBorder ? line : BorderSide.none,
        ),
      ),
      child: child,
    );
  }
}

/// The legend: unsaved swatch, inherited, hidden here.
class PricingLegend extends StatelessWidget {
  const PricingLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.t;
    final c = context.madarColors;
    final style = DashType.small.copyWith(color: c.textSecondary);
    Widget entry(Widget mark, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        mark,
        Text(text, style: style),
      ],
    );
    return Wrap(
      spacing: Space.lg,
      runSpacing: Space.xs + DashMetrics.hair,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        entry(
          Container(
            width: Space.xl,
            height: IconSize.xs,
            decoration: BoxDecoration(
              color: c.hover,
              borderRadius: BorderRadius.circular(DashMetrics.hair),
              border: Border.all(color: c.hairline),
            ),
          ),
          t('menu.pricing.legendDirty'),
        ),
        entry(
          Transform.flip(
            flipX: context.isRtl,
            child: DashIcon('corner-down-right', size: IconSize.xs),
          ),
          t('menu.pricing.legendInherited'),
        ),
        entry(
          DashIcon('eye-off', size: IconSize.xs, color: c.danger),
          t('menu.pricing.legendHidden'),
        ),
      ],
    );
  }
}
