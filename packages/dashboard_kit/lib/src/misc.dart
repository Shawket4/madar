import 'dart:math' as math;

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

import 'buttons.dart';
import 'controls.dart';
import 'foundation/l10n.dart';
import 'foundation/popover.dart';
import 'foundation/press.dart';
import 'fields.dart';
import 'foundation/tokens.dart';
import 'select.dart';
import 'table.dart';

/// Which file an export makes (the web's `ExportFormat`): the Excel
/// workbook, a PDF, or a CSV. A PDF or a CSV is one sheet of it.
enum DashExportFormat { xlsx, pdf, csv }

/// What the Export panel hands an export (the web's `ExportPick`): the sheet
/// a PDF or a CSV is made of, by its index in the workbook's sheets (in the
/// order declared to the panel). Null: the whole workbook (Excel), or the
/// only sheet there is.
@immutable
class DashExportPick {
  const DashExportPick({this.sheet});

  final int? sheet;

  @override
  bool operator ==(Object other) =>
      other is DashExportPick && other.sheet == sheet;

  @override
  int get hashCode => sheet.hashCode;

  @override
  String toString() => 'DashExportPick(sheet: $sheet)';
}

/// One sheet of a file, named for the panel (the web's `ExportSheet`). A
/// sheet of tables (the recipe book's) has no CSV: `csv: false`.
@immutable
class DashExportSheet {
  const DashExportSheet(this.label, {this.csv = true});

  final String label;
  final bool csv;
}

/// One file the Export panel offers (the web's `ExportFile`).
@immutable
class DashExportFile {
  const DashExportFile({
    required this.key,
    required this.label,
    required this.onExport,
    this.sheets = const [],
  });

  final String key;
  final String label;

  /// Makes the file: the exporter's `exportFile(config, pick)`, which reads
  /// the format chosen in the panel and makes a PDF or CSV of `pick.sheet`.
  final ValueChanged<DashExportPick> onExport;

  /// The workbook's sheets, in the workbook's order. A PDF or a CSV is one
  /// sheet: with two or more to choose from, the panel asks which.
  final List<DashExportSheet> sheets;
}

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

/// A format's icon and name.
(String icon, String label) dashExportFormatName(
  DashKitStrings t,
  DashExportFormat f,
) => switch (f) {
  DashExportFormat.xlsx => ('file-spreadsheet', t.exportFormatExcel),
  DashExportFormat.pdf => ('file-text', t.exportFormatPdf),
  DashExportFormat.csv => ('sheet', t.exportFormatCsv),
};

/// Excel, PDF or CSV: the export's format, as a row of even pills (the
/// web's `ExportFormatPicker`). Shared by the Export panel and the orders
/// export.
class DashExportFormatPicker extends StatelessWidget {
  const DashExportFormatPicker({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final DashExportFormat value;
  final ValueChanged<DashExportFormat> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.dashStrings;
    return _FillPills<DashExportFormat>(
      semanticLabel: t.exportFormatLabel,
      value: value,
      onChanged: onChanged,
      options: [
        for (final f in DashExportFormat.values)
          if (dashExportFormatName(t, f) case (final icon, final label))
            DashOption(value: f, label: label, icon: icon),
      ],
    );
  }
}

/// Pills sharing the full width when each fits its even share, else a row
/// that scrolls (the web's `fill`, whose track scrolls sideways): a long
/// sheet name, or five sheets, never overflows the panel.
class _FillPills<T> extends StatelessWidget {
  const _FillPills({
    required this.options,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
  });

  final List<DashOption<T>> options;
  final T value;
  final ValueChanged<T> onChanged;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // As the segment's Text resolves its style, with a hair to spare.
    final style = DefaultTextStyle.of(context).style.merge(DashType.bodyMedium);
    var widest = 0.0;
    for (final o in options) {
      final words = TextPainter(
        text: TextSpan(text: o.label, style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final icon = o.icon == null
          ? 0.0
          : IconSize.sm + Space.xs + DashMetrics.hair;
      widest = math.max(
        widest,
        words.width + icon + Space.md * 2 + DashMetrics.hair * 2,
      );
      words.dispose();
    }
    return LayoutBuilder(
      builder: (context, box) => DashSegmentedControl<T>(
        expand: widest * options.length <= box.maxWidth - DashMetrics.ring * 2,
        semanticLabel: semanticLabel,
        value: value,
        onChanged: onChanged,
        options: options,
      ),
    );
  }
}

/// One sheet a format can be: its index in the workbook, and its name.
typedef DashSheetChoice = ({int index, String label});

/// The sheets [format] can be, by their index in the workbook (the web's
/// `sheetChoices`): none for Excel (the whole workbook); a CSV never a sheet
/// of tables.
List<DashSheetChoice> dashSheetChoices(
  List<DashExportSheet> sheets,
  DashExportFormat format,
) => format == DashExportFormat.xlsx
    ? const []
    : [
        for (final (index, s) in sheets.indexed)
          if (format != DashExportFormat.csv || s.csv)
            (index: index, label: s.label),
      ];

/// The sheet question of a PDF or CSV (the web's `useSheetPick`), for the
/// sheet [chosen] last: the [choices], the one [at], whether the panel
/// [asks], and the [pick] to pass the export (the one sheet when only one
/// fits the format).
@immutable
class DashSheetPick {
  factory DashSheetPick(
    List<DashExportSheet> sheets,
    DashExportFormat format,
    int chosen,
  ) {
    final choices = dashSheetChoices(sheets, format);
    final at =
        choices.where((c) => c.index == chosen).firstOrNull ??
        choices.firstOrNull;
    return DashSheetPick._(
      choices,
      at,
      sheets.length > 1 && at != null
          ? DashExportPick(sheet: at.index)
          : const DashExportPick(),
    );
  }

  const DashSheetPick._(this.choices, this.at, this.pick);

  final List<DashSheetChoice> choices;
  final DashSheetChoice? at;
  final DashExportPick pick;

  bool get asks => choices.length > 1;
}

/// The Sheet pills of a PDF or CSV (the web's `SheetPicker`).
class DashSheetPicker extends StatelessWidget {
  const DashSheetPicker({
    required this.choices,
    required this.at,
    required this.onChanged,
    super.key,
  });

  final List<DashSheetChoice> choices;

  /// The chosen sheet's index in the workbook.
  final int at;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => _FillPills<int>(
    semanticLabel: context.dashStrings.exportFormatSheet,
    value: at,
    onChanged: onChanged,
    options: [
      for (final c in choices) DashOption(value: c.index, label: c.label),
    ],
  );
}

/// A labelled part of an export panel: the small muted label over its
/// control.
class DashExportField extends StatelessWidget {
  const DashExportField({required this.label, required this.child, super.key});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    spacing: Space.xs + DashMetrics.hair,
    children: [
      Text(
        label,
        style: DashType.smallMedium.copyWith(
          color: context.madarColors.textSecondary,
        ),
      ),
      child,
    ],
  );
}

/// The shared Export button of every list and report (the web's
/// `ExportButton`). It opens a small panel (as Apex's trip report): the
/// format at the top (Excel, PDF or CSV, remembered on this device for every
/// export); the file, when the page offers several ([more]); the sheet, when
/// a PDF or CSV is asked of a workbook with several (each is one sheet);
/// then Download.
///
/// The format is the [DashExportFormatScope]'s, set here and read by the
/// export itself, so [onExport] never asks which: it gets only the sheet.
class DashExportButton extends StatefulWidget {
  const DashExportButton({
    required this.onExport,
    this.sheets = const [],
    this.fileLabel,
    this.more = const [],
    this.label,
    this.loading = false,
    this.enabled = true,
    this.compact = false,
    super.key,
  });

  /// The page's own file. See [DashExportFile.onExport].
  final ValueChanged<DashExportPick> onExport;

  /// The page's workbook's sheets. See [DashExportFile.sheets].
  final List<DashExportSheet> sheets;

  /// The page's file's name, when the panel offers several ([more]).
  final String? fileLabel;

  /// Other files, offered after the page's own.
  final List<DashExportFile> more;

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
  String _fileKey = 'page';
  int _sheet = 0;

  void _setFormat(DashExportFormatScope? scope, DashExportFormat format) {
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
    final label = w.label ?? t.exportMenu;
    return DashPopover(
      align: DashPopoverAlign.end,
      // Wide enough for the three format pills in the dashboard's face.
      width: 340,
      maxHeight: 520,
      anchor: (context, c) => DashButton(
        label: label,
        icon: 'download',
        trailingIcon: 'chevron-down',
        variant: DashButtonVariant.outline,
        size: w.compact ? DashButtonSize.compact : DashButtonSize.regular,
        loading: w.loading,
        onPressed: w.enabled ? c.toggle : null,
      ),
      content: (context, c) {
        final scope = DashExportFormatScope.maybeOf(context);
        final format = scope?.format ?? _own;
        final files = [
          DashExportFile(
            key: 'page',
            label: w.fileLabel ?? t.exportMenu,
            onExport: w.onExport,
            sheets: w.sheets,
          ),
          ...w.more,
        ];
        final file =
            files.where((f) => f.key == _fileKey).firstOrNull ?? files.first;
        final sheet = DashSheetPick(file.sheets, format, _sheet);
        return Semantics(
          container: true,
          explicitChildNodes: true,
          label: label,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              spacing: Space.lg,
              children: [
                DashExportField(
                  label: t.exportFormatLabel,
                  child: DashExportFormatPicker(
                    value: format,
                    onChanged: (f) => _setFormat(scope, f),
                  ),
                ),
                if (files.length > 1)
                  DashExportField(
                    label: t.exportFormatFile,
                    child: _FileList(
                      files: files,
                      chosen: file.key,
                      onChanged: (k) => setState(() => _fileKey = k),
                    ),
                  ),
                if (sheet.asks)
                  DashExportField(
                    label: t.exportFormatSheet,
                    child: DashSheetPicker(
                      choices: sheet.choices,
                      at: sheet.at!.index,
                      onChanged: (i) => setState(() => _sheet = i),
                    ),
                  ),
                DashButton(
                  key: const ValueKey('export-download'),
                  label: t.exportFormatDownload(
                    dashExportFormatName(t, format).$2,
                  ),
                  icon: 'download',
                  expand: true,
                  onPressed: () {
                    c.close();
                    file.onExport(sheet.pick);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The panel's files: bordered rows, the chosen one marked.
class _FileList extends StatelessWidget {
  const _FileList({
    required this.files,
    required this.chosen,
    required this.onChanged,
  });

  final List<DashExportFile> files;
  final String chosen;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Semantics(
      container: true,
      label: context.dashStrings.exportFormatFile,
      child: Container(
        padding: const EdgeInsets.all(DashMetrics.ring),
        decoration: BoxDecoration(
          border: Border.all(color: c.hairline),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          spacing: DashMetrics.hair,
          children: [
            for (final f in files)
              DashPressable(
                onTap: () => onChanged(f.key),
                isButton: false,
                selected: f.key == chosen,
                checked: f.key == chosen,
                semanticLabel: f.label,
                excludeChildSemantics: true,
                pressScale: false,
                builder: (context, s) {
                  final on = f.key == chosen;
                  return Container(
                    height: DashMetrics.control,
                    padding: const EdgeInsets.symmetric(horizontal: Space.sm),
                    foregroundDecoration: dashFocusRing(
                      context,
                      s,
                      BorderRadius.circular(Radii.xs),
                    ),
                    decoration: BoxDecoration(
                      color: on || s.hovered ? c.hover : null,
                      borderRadius: BorderRadius.circular(Radii.xs),
                    ),
                    child: Row(
                      spacing: Space.sm,
                      children: [
                        Expanded(
                          child: Text(
                            f.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: (on ? DashType.bodyMedium : DashType.body)
                                .copyWith(
                                  color: on || s.hovered
                                      ? c.textPrimary
                                      : c.textSecondary,
                                ),
                          ),
                        ),
                        if (on)
                          DashIcon(
                            'check',
                            size: IconSize.sm,
                            color: c.textPrimary,
                          ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
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
