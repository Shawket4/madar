import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'buttons.dart';
import 'controls.dart';
import 'foundation/l10n.dart';
import 'foundation/popover.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';
import 'table.dart';

/// The shared "Export Excel" button (the web's `ExportButton`). With
/// [onExportCsv] it becomes a menu offering Excel and CSV.
class DashExportButton extends StatelessWidget {
  const DashExportButton({
    required this.onExport,
    this.onExportCsv,
    this.label,
    this.loading = false,
    this.enabled = true,
    this.compact = false,
    super.key,
  });

  final VoidCallback onExport;
  final VoidCallback? onExportCsv;
  final String? label;
  final bool loading;
  final bool enabled;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.dashStrings;
    final size = compact ? DashButtonSize.compact : DashButtonSize.regular;
    if (onExportCsv == null) {
      return DashButton(
        label: label ?? t.export,
        icon: 'download',
        variant: DashButtonVariant.outline,
        size: size,
        loading: loading,
        onPressed: enabled ? onExport : null,
      );
    }
    return DashMenu(
      items: [
        DashMenuItem(
          label: t.exportExcel,
          icon: 'file-spreadsheet',
          onSelected: onExport,
        ),
        DashMenuItem(
          label: t.exportCsv,
          icon: 'file-text',
          onSelected: onExportCsv,
        ),
      ],
      builder: (context, c) => DashButton(
        label: label ?? t.export,
        icon: 'download',
        trailingIcon: 'chevron-down',
        variant: DashButtonVariant.outline,
        size: size,
        loading: loading,
        onPressed: enabled ? c.toggle : null,
      ),
    );
  }
}

/// The food-cost traffic light (the web's `FoodCostChip`): green under 30%,
/// amber to 40%, red above.
class DashFoodCostChip extends StatelessWidget {
  const DashFoodCostChip({required this.ratio, super.key});

  /// Cost over price (0.32 = 32%).
  final double ratio;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final tone = ratio < 0.3
        ? DashTone.success
        : ratio <= 0.4
        ? DashTone.warning
        : DashTone.danger;
    final icon = ratio < 0.3
        ? 'check-circle-2'
        : ratio <= 0.4
        ? 'alert-triangle'
        : 'alert-circle';
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.xs + DashMetrics.hair,
        vertical: DashMetrics.hair,
      ),
      decoration: BoxDecoration(
        color: tone.wash(c),
        borderRadius: BorderRadius.circular(Radii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          DashIcon(icon, size: 12, color: tone.foreground(c)),
          Text(
            dashFigure(context.dashFormats.percent(ratio)),
            style: DashType.smallStrong.copyWith(
              color: tone.foreground(c),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The warning glyph on a row whose cost is incomplete; it opens the
/// recipes for that item (the page passes [onOpen]).
class DashCostMissingLink extends StatelessWidget {
  const DashCostMissingLink({required this.onOpen, super.key});
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final t = context.dashStrings;
    return DashPressable(
      onTap: onOpen,
      tooltip: t.costMissingFix,
      semanticLabel: t.costMissingFix,
      excludeChildSemantics: true,
      builder: (context, s) => SizedBox.square(
        dimension: Space.xl,
        child: Center(
          child: DashIcon(
            'alert-triangle',
            size: IconSize.xs,
            color: DashTone.warning.foreground(c),
          ),
        ),
      ),
    );
  }
}

/// One size's cost line for [DashItemCostCell].
@immutable
class DashSkuCost {
  const DashSkuCost({
    required this.sizeLabel,
    required this.cost,
    this.foodCostRatio,
    this.costMissing = false,
  });
  final String sizeLabel;

  /// Minor units, or null when unknown.
  final int? cost;
  final double? foodCostRatio;
  final bool costMissing;
}

/// Cost / margin for a menu item, one line per size (the web's
/// `ItemCostCell`).
class DashItemCostCell extends StatelessWidget {
  const DashItemCostCell({required this.skus, this.onFixMissing, super.key});
  final List<DashSkuCost> skus;
  final VoidCallback? onFixMissing;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final f = context.dashFormats;
    if (skus.isEmpty) {
      return Text('—', style: DashType.small.copyWith(color: c.textSecondary));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      spacing: DashMetrics.hair,
      children: [
        for (final s in skus)
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.xs + DashMetrics.hair,
            children: [
              if (skus.length > 1)
                Text(
                  s.sizeLabel,
                  style: DashType.small.copyWith(color: c.textSecondary),
                ),
              Text(
                f.money(s.cost),
                style: DashType.small.copyWith(
                  color: c.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (s.foodCostRatio != null)
                DashFoodCostChip(ratio: s.foodCostRatio!),
              if (s.costMissing && onFixMissing != null)
                DashCostMissingLink(onOpen: onFixMissing!),
            ],
          ),
      ],
    );
  }
}

/// Cost / margin for an add-on (the web's `AddonCostCell`).
class DashAddonCostCell extends StatelessWidget {
  const DashAddonCostCell({
    required this.cost,
    required this.price,
    this.costMissing = false,
    this.onFixMissing,
    super.key,
  });

  /// Minor units; null when the add-on has no cost row.
  final int? cost;
  final int price;
  final bool costMissing;
  final VoidCallback? onFixMissing;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final f = context.dashFormats;
    if (cost == null && !costMissing) {
      return Text('—', style: DashType.small.copyWith(color: c.textSecondary));
    }
    final ratio = cost != null && price > 0 ? cost! / price : null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        Text(
          f.money(cost),
          style: DashType.small.copyWith(
            color: c.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (ratio != null) DashFoodCostChip(ratio: ratio),
        if (costMissing && onFixMissing != null)
          DashCostMissingLink(onOpen: onFixMissing!),
      ],
    );
  }
}

/// Where a [DashPeopleList]'s search sits.
enum DashPeopleSearchLayout {
  /// Inside the table's own toolbar.
  table,

  /// A row of its own over the table, with filters and actions.
  above,
}

/// The shell of a list of people — customers, loyalty members (the web's
/// `PeopleList`): a server-side search box, optional filters and actions,
/// the table, and a line under it. It owns no data: search and paging are
/// the caller's.
class DashPeopleList<T> extends StatelessWidget {
  const DashPeopleList({
    required this.table,
    required this.searchValue,
    required this.onSearchChanged,
    required this.searchPlaceholder,
    this.layout = DashPeopleSearchLayout.table,
    this.filters = const [],
    this.actions = const [],
    this.footer,
    super.key,
  });

  /// The table, built WITHOUT its own toolbar.
  final DashDataTable<T> Function(Widget? toolbar) table;
  final String searchValue;

  /// Debounced, trimmed.
  final ValueChanged<String> onSearchChanged;
  final String searchPlaceholder;
  final DashPeopleSearchLayout layout;
  final List<Widget> filters;
  final List<Widget> actions;

  /// "Showing 100 of 412" ([DashListCount]).
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final phone = DashBreakpoints.isPhone(context);
    final box = DashSearchInput(
      value: searchValue,
      onChanged: onSearchChanged,
      placeholder: searchPlaceholder,
      debounce: DashSearchInput.listDelay,
      width: phone ? null : DashMetrics.searchWidth,
    );
    if (layout == DashPeopleSearchLayout.table && footer == null) {
      return table(box);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.lg,
      children: [
        if (layout == DashPeopleSearchLayout.above)
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.md,
            runSpacing: Space.md,
            children: [
              Wrap(
                spacing: Space.lg,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [box, ...filters],
              ),
              if (actions.isNotEmpty)
                Wrap(spacing: Space.sm, children: actions),
            ],
          ),
        table(layout == DashPeopleSearchLayout.table ? box : null),
        ?footer,
      ],
    );
  }
}

/// The quiet line under a list showing fewer rows than exist.
class DashListCount extends StatelessWidget {
  const DashListCount(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: DashType.small.copyWith(color: context.madarColors.textSecondary),
  );
}
