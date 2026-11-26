import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

import 'buttons.dart';
import 'controls.dart';
import 'foundation/l10n.dart';
import 'foundation/popover.dart';
import 'foundation/press.dart';
import 'foundation/tokens.dart';
import 'table.dart';

/// Which file an export makes (the web's `ExportFormat`): the Excel
/// workbook or a PDF of the same sheets.
enum DashExportFormat { xlsx, pdf }

/// The format every [DashExportButton] under it shows and sets: one choice
/// for the whole dashboard (dashboard_core fills it from its remembered
/// `exportFormatProvider`; the exporter reads the same). Without one, a
/// button keeps its own.
class DashExportFormatScope extends InheritedWidget {
  const DashExportFormatScope({
    required this.format,
    required this.onChanged,
    required super.child,
    super.key,
  });

  final DashExportFormat format;
  final ValueChanged<DashExportFormat> onChanged;

  static DashExportFormatScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashExportFormatScope>();

  @override
  bool updateShouldNotify(DashExportFormatScope oldWidget) =>
      format != oldWidget.format || onChanged != oldWidget.onChanged;
}

/// One more file a [DashExportButton] offers, under the page's own export
/// and CSV (the web's `ExportOption`).
@immutable
class DashExportOption {
  const DashExportOption({
    required this.label,
    required this.onSelected,
    this.icon = 'file-spreadsheet',
  });

  final String label;
  final VoidCallback onSelected;

  /// A `MadarIcon` name drawn before the label.
  final String icon;
}

/// The shared Export button of every list and report (the web's
/// `ExportButton`): Excel or PDF of the same sheets, the PDF in the
/// dashboard's typeface, embedded.
///
/// - One file: the menu is the choice, "Export as Excel / PDF" (as Apex's
///   export menu), and picking one exports at once.
/// - Several files ([onExportCsv], or [more]): the format sits at the top,
///   checked and keeping the menu open, then a rule and the files: the
///   page's own ([excelLabel]), the CSV, and [more] in their own section
///   under [moreHeading].
///
/// The format is the [DashExportFormatScope]'s, set here and read by the
/// export itself, so [onExport] never asks which.
class DashExportButton extends StatefulWidget {
  const DashExportButton({
    required this.onExport,
    this.onExportCsv,
    this.excelLabel,
    this.more = const [],
    this.moreHeading,
    this.label,
    this.loading = false,
    this.enabled = true,
    this.compact = false,
    super.key,
  });

  /// The export, made in the chosen format.
  final VoidCallback onExport;

  /// A CSV as well: its own item, whatever the format.
  final VoidCallback? onExportCsv;

  /// The menu's name for [onExport] when it offers several files (default
  /// "Export").
  final String? excelLabel;

  /// Other files, in their own section of the menu.
  final List<DashExportOption> more;

  /// That section's heading.
  final String? moreHeading;

  /// The button's words (default "Export").
  final String? label;
  final bool loading;
  final bool enabled;
  final bool compact;

  @override
  State<DashExportButton> createState() => _DashExportButtonState();
}

class _DashExportButtonState extends State<DashExportButton> {
  /// The choice when no [DashExportFormatScope] holds one.
  DashExportFormat _own = DashExportFormat.xlsx;

  void _set(DashExportFormatScope? scope, DashExportFormat format) {
    if (scope != null) {
      scope.onChanged(format);
    } else {
      setState(() => _own = format);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.dashStrings;
    final w = widget;
    final scope = DashExportFormatScope.maybeOf(context);
    final format = scope?.format ?? _own;
    final formats = [
      (DashExportFormat.xlsx, t.exportFormatExcel, 'file-spreadsheet'),
      (DashExportFormat.pdf, t.exportFormatPdf, 'file-text'),
    ];
    final List<DashMenuItem> items;
    if (w.onExportCsv == null && w.more.isEmpty) {
      items = [
        DashMenuItem.heading(t.exportFormatAs),
        for (final (value, text, icon) in formats)
          DashMenuItem(
            label: text,
            icon: icon,
            onSelected: () {
              _set(scope, value);
              w.onExport();
            },
          ),
      ];
    } else {
      items = [
        DashMenuItem.heading(t.exportFormatLabel),
        // Choosing a format keeps the menu open: the file is picked next.
        for (final (value, text, _) in formats)
          DashMenuItem(
            label: text,
            checked: format == value,
            radio: true,
            keepOpen: true,
            onSelected: () => _set(scope, value),
          ),
        const DashMenuItem.divider(),
        DashMenuItem(
          label: w.excelLabel ?? t.exportFile,
          icon: format == DashExportFormat.pdf
              ? 'file-text'
              : 'file-spreadsheet',
          onSelected: w.onExport,
        ),
        if (w.onExportCsv != null)
          DashMenuItem(
            label: t.exportCsv,
            icon: 'file-text',
            onSelected: w.onExportCsv,
          ),
        if (w.more.isNotEmpty) ...[
          const DashMenuItem.divider(),
          if (w.moreHeading case final heading?) DashMenuItem.heading(heading),
          for (final o in w.more)
            DashMenuItem(
              label: o.label,
              icon: o.icon,
              onSelected: o.onSelected,
            ),
        ],
      ];
    }
    return DashMenu(
      items: items,
      builder: (context, c) => DashButton(
        label: w.label ?? t.exportMenu,
        icon: 'download',
        trailingIcon: 'chevron-down',
        variant: DashButtonVariant.outline,
        size: w.compact ? DashButtonSize.compact : DashButtonSize.regular,
        loading: w.loading,
        onPressed: w.enabled ? c.toggle : null,
      ),
    );
  }
}

/// The food-cost traffic light (the web's `FoodCostChip`): madar-money's
/// food-cost band through the core (green under 30%, amber to 40%, red
/// above); nothing without a price above zero.
class DashFoodCostChip extends StatelessWidget {
  const DashFoodCostChip({required this.cost, required this.price, super.key});

  /// Minor units.
  final int cost;
  final int price;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final (tone, icon) = switch (rules.foodCostBand(cost: cost, price: price)) {
      'good' => (DashTone.success, 'check-circle-2'),
      'fair' => (DashTone.warning, 'alert-triangle'),
      'poor' => (DashTone.danger, 'alert-circle'),
      _ => (null, ''),
    };
    if (tone == null) return const SizedBox.shrink();
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
            dashFigure(context.dashFormats.percent(cost / price)),
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
    this.price,
    this.costMissing = false,
  });
  final String sizeLabel;

  /// Minor units, or null when unknown.
  final int? cost;

  /// Minor units; a complete cost is graded against it.
  final int? price;
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
              if (s.cost != null && s.price != null && !s.costMissing)
                DashFoodCostChip(cost: s.cost!, price: s.price!),
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
        // A partial cost is not graded.
        if (cost != null && !costMissing)
          DashFoodCostChip(cost: cost!, price: price),
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
