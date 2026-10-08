/// The recipe builder (the web's `features/recipes/recipe-builder.tsx`,
/// MENU-RCP-001..016, 023): one section per size with ingredient rows, a cost
/// and margin per size, scaling from the base size, and either its own
/// "Save recipe" footer (the add-on recipe dialog) or deferred mode (the item
/// dialog streams the cleaned rows to its host). Shared by the item dialogs,
/// the add-on recipe dialog and onboarding; exported from the package.
///
/// Wide (>= 760): a row is one line (ingredient, quantity + unit, line cost,
/// remove), as on the web. Phone: the ingredient takes its own line and the
/// quantity, cost and remove sit under it.
///
/// Not ported: the "Copy from…" picker (MENU-RCP-002). No caller passes copy
/// sources (the add-on recipe dialog passes none, the item dialog none), so
/// on the web it never shows; see `docs/fdash/divergences/catalog_menu-recipes.md`.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show OrgIngredient;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/ingredient_options.dart';
import '../shared/menu_providers.dart' show ingredientsById;
import '../shared/menu_text.dart';
import 'create_ingredient_dialog.dart';
import 'recipe_model.dart';

/// A row the builder starts from (`RecipeRowInit`).
@immutable
class RecipeRowInit {
  const RecipeRowInit({
    required this.sizeLabel,
    required this.ingredientName,
    required this.ingredientUnit,
    required this.quantityUsed,
    this.orgIngredientId,
  });

  /// The size the row belongs to (`one_size` for a simple item).
  final String sizeLabel;
  final String? orgIngredientId;
  final String ingredientName;
  final String ingredientUnit;
  final double quantityUsed;

  @override
  String toString() =>
      'RecipeRowInit($sizeLabel, $orgIngredientId, $ingredientName, '
      '$quantityUsed $ingredientUnit)';
}

/// A row that counts: a name and a finite quantity above zero (`CleanRow`).
@immutable
class CleanRow {
  const CleanRow({
    required this.sizeLabel,
    required this.ingredientName,
    required this.ingredientUnit,
    required this.quantityUsed,
    this.orgIngredientId,
  });

  final String sizeLabel;
  final String? orgIngredientId;
  final String ingredientName;
  final String ingredientUnit;
  final double quantityUsed;

  @override
  bool operator ==(Object other) =>
      other is CleanRow &&
      other.sizeLabel == sizeLabel &&
      other.orgIngredientId == orgIngredientId &&
      other.ingredientName == ingredientName &&
      other.ingredientUnit == ingredientUnit &&
      other.quantityUsed == quantityUsed;

  @override
  int get hashCode => Object.hash(
    sizeLabel,
    orgIngredientId,
    ingredientName,
    ingredientUnit,
    quantityUsed,
  );

  @override
  String toString() =>
      'CleanRow($sizeLabel, $orgIngredientId, $ingredientName, '
      '$quantityUsed $ingredientUnit)';
}

/// A row dropped since the baseline (the standalone save's `removed`).
typedef RemovedRow = ({String sizeLabel, String ingredientName});

class RecipeBuilder extends ConsumerStatefulWidget {
  const RecipeBuilder({
    required this.orgId,
    required this.sizes,
    required this.initialRows,
    required this.catalog,
    this.priceForSize,
    this.onSave,
    this.deferred = false,
    this.onRowsChange,
    this.allowCreateIngredient = true,
    super.key,
  });

  final String orgId;

  /// Ordered size labels; the first is the base size (scaling starts there).
  final List<String> sizes;

  /// Re-seeds the rows whenever their content changes (MENU-RCP-001).
  final List<RecipeRowInit> initialRows;
  final List<OrgIngredient> catalog;

  /// The current price (piastres) of a size, for the margin preview.
  final int? Function(String size)? priceForSize;

  /// Standalone mode: the "Save recipe" footer commits through this. A
  /// failure is the host's to report (it toasts and rethrows); the rows stay
  /// unsaved.
  final Future<void> Function(List<CleanRow> rows, List<RemovedRow> removed)?
  onSave;

  /// Deferred (embedded) mode: no footer; [onRowsChange] gets the cleaned
  /// rows on every edit.
  final bool deferred;
  final ValueChanged<List<CleanRow>>? onRowsChange;

  /// Offers "New ingredient" (the add-on recipe dialog does, the item dialog
  /// does not).
  final bool allowCreateIngredient;

  @override
  ConsumerState<RecipeBuilder> createState() => _RecipeBuilderState();
}

/// The quantity box with its unit word (the web's `w-20` input + `min-w-12`
/// unit).
const double _qtyWidth = 152;

/// The line cost slot (the web's `5rem`, a little wider for Arabic money).
const double _costWidth = 96;

/// A scale factor box.
const double _factorWidth = 112;

class _RecipeBuilderState extends ConsumerState<RecipeBuilder> {
  var _seq = 0;
  List<RecipeDraftRow> _rows = const [];
  List<RecipeDraftRow> _baseline = const [];
  late String _seedKey;
  bool _saving = false;
  bool _scaling = false;
  final Map<String, String> _factors = {};
  String? _emitted;

  static String _keyOf(List<RecipeRowInit> rows) => recipeSeedKey([
    for (final r in rows)
      (
        sizeLabel: r.sizeLabel,
        ingredientName: r.ingredientName,
        quantityUsed: r.quantityUsed,
      ),
  ]);

  int _nextId() => _seq++;

  @override
  void initState() {
    super.initState();
    _seedKey = _keyOf(widget.initialRows);
    _seed();
  }

  @override
  void didUpdateWidget(RecipeBuilder old) {
    super.didUpdateWidget(old);
    final key = _keyOf(widget.initialRows);
    if (key != _seedKey) {
      _seedKey = key;
      _seed();
    } else if (widget.deferred != old.deferred) {
      _emit();
    }
  }

  /// `form.reset({rows: initialRows})`: the draft and its baseline.
  void _seed() {
    _rows = [
      for (final r in widget.initialRows)
        RecipeDraftRow(
          id: _nextId(),
          sizeLabel: r.sizeLabel,
          orgIngredientId: r.orgIngredientId,
          ingredientName: r.ingredientName,
          ingredientUnit: r.ingredientUnit,
          quantity: jsNumberText(r.quantityUsed),
        ),
    ];
    _baseline = _rows;
    _emit();
  }

  /// Deferred mode: hands the rows that count to the host whenever the rows
  /// change (also after seeding), once the frame is built.
  void _emit() {
    final onRowsChange = widget.onRowsChange;
    if (!widget.deferred || onRowsChange == null) return;
    final sig = [
      for (final r in _rows)
        '${r.sizeLabel}\u0000${r.orgIngredientId}\u0000${r.ingredientName}'
            '\u0000${r.ingredientUnit}\u0000${r.quantity}',
    ].join('\u0001');
    if (sig == _emitted) return;
    _emitted = sig;
    final clean = _clean(_rows);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRowsChange?.call(clean);
    });
  }

  static List<CleanRow> _clean(List<RecipeDraftRow> rows) => [
    for (final c in cleanRecipeRows(rows))
      CleanRow(
        sizeLabel: c.sizeLabel,
        orgIngredientId: c.orgIngredientId,
        ingredientName: c.ingredientName,
        ingredientUnit: c.ingredientUnit,
        quantityUsed: c.quantityUsed,
      ),
  ];

  void _set(List<RecipeDraftRow> rows) {
    setState(() => _rows = rows);
    _emit();
  }

  void _replace(RecipeDraftRow row) => _set([
    for (final r in _rows)
      if (r.id == row.id) row else r,
  ]);

  bool get _dirty => recipeRowsDiffer(_rows, _baseline);

  String get _baseSize => widget.sizes.isEmpty ? oneSize : widget.sizes.first;

  void _addRow(String size) => _set([
    ..._rows,
    RecipeDraftRow(
      id: _nextId(),
      sizeLabel: size,
      ingredientName: '',
      ingredientUnit: 'g',
      quantity: '',
    ),
  ]);

  Future<void> _newIngredient() async {
    final ing = await showCreateIngredientDialog(context, orgId: widget.orgId);
    if (ing == null || !mounted) return;
    _set([
      ..._rows,
      RecipeDraftRow(
        id: _nextId(),
        sizeLabel: _baseSize,
        orgIngredientId: ing.id,
        ingredientName: ing.name,
        ingredientUnit: ing.unit,
        quantity: '',
      ),
    ]);
  }

  void _applyScaling() =>
      _set(scaleRecipeRows(_rows, widget.sizes, _factors, _nextId));

  Future<void> _save() async {
    final onSave = widget.onSave;
    if (onSave == null) return;
    final current = _rows;
    final cleaned = _clean(current);
    final removed = removedRecipeRows([
      for (final r in widget.initialRows)
        (sizeLabel: r.sizeLabel, ingredientName: r.ingredientName),
    ], cleanRecipeRows(current));
    setState(() => _saving = true);
    try {
      await onSave(cleaned, removed);
      if (!mounted) return;
      // `form.reset({rows: current})`: what was saved is the new baseline.
      setState(() {
        _rows = current;
        _baseline = current;
      });
    } on Object {
      // The host has said why (a toast); the rows stay unsaved.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final format = ref.watch(formatProvider);
    final c = context.madarColors;
    final phone = DashBreakpoints.isPhone(context);
    final byId = ingredientsById(widget.catalog);
    final options = ingredientOptions(widget.catalog, t);
    double? unitCostOf(String? id) =>
        id == null ? null : positiveUnitCost(byId[id]);

    final toolbar = _toolbar(t, c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.lg + Space.xs,
      children: [
        ?toolbar,
        if (_scaling && widget.sizes.length > 1) _scalePanel(t, c),
        for (final (i, size) in widget.sizes.indexed)
          _section(
            key: ValueKey('recipe-size-$i'),
            size: size,
            t: t,
            format: format,
            c: c,
            phone: phone,
            options: options,
            unitCostOf: unitCostOf,
          ),
        if (!widget.deferred) _footer(t, c),
      ],
    );
  }

  // ── toolbar ────────────────────────────────────────────────────────────

  Widget? _toolbar(Translator t, MadarColors c) {
    final leading = widget.allowCreateIngredient
        ? Container(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.sm,
              vertical: Space.xs,
            ),
            decoration: BoxDecoration(
              color: c.muted.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            child: DashButton(
              label: t('recipes.newIngredient'),
              icon: 'plus',
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              onPressed: _newIngredient,
            ),
          )
        : null;
    final trailing = widget.sizes.length > 1 ? _scaleToggle(t, c) : null;
    if (leading == null && trailing == null) return null;
    if (leading != null && trailing != null) {
      return Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.md,
        runSpacing: Space.sm,
        children: [leading, trailing],
      );
    }
    return Align(
      alignment: leading != null
          ? AlignmentDirectional.centerStart
          : AlignmentDirectional.centerEnd,
      child: leading ?? trailing,
    );
  }

  Widget _scaleToggle(Translator t, MadarColors c) {
    final label = t(
      'recipes.builder.scaleFromBase',
      args: {'base': sizeLabelText(_baseSize, t('recipes.oneSize'))},
    );
    void toggle() => setState(() => _scaling = !_scaling);
    return Container(
      padding: const EdgeInsetsDirectional.only(start: Space.xs, end: Space.md),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.4),
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DashSwitch(
            value: _scaling,
            semanticLabel: label,
            onChanged: (_) => toggle(),
          ),
          ExcludeSemantics(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: toggle,
              child: Text(
                label,
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scalePanel(Translator t, MadarColors c) {
    final base = sizeLabelText(_baseSize, t('recipes.oneSize'));
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.3),
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.sm,
        children: [
          Text(
            t('recipes.builder.scaleHint', args: {'base': base}),
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: Space.md,
            children: [
              Expanded(
                child: Wrap(
                  spacing: Space.md,
                  runSpacing: Space.sm,
                  children: [
                    for (final size in widget.sizes.skip(1))
                      _factorField(size, t, c),
                  ],
                ),
              ),
              DashButton(
                label: t('recipes.builder.applyScaling'),
                variant: DashButtonVariant.outline,
                size: DashButtonSize.compact,
                onPressed: _applyScaling,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _factorField(String size, Translator t, MadarColors c) {
    final label = sizeLabelText(size, t('recipes.oneSize'));
    return SizedBox(
      width: _factorWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          ExcludeSemantics(
            child: MadarClippedText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ),
          DashTextInput(
            key: ValueKey('recipe-factor-$size'),
            value: _factors[size] ?? '',
            placeholder: '1.5',
            semanticLabel: label,
            textAlign: TextAlign.end,
            textDirection: TextDirection.ltr,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            leading: Text(
              '×',
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
            onChanged: (v) => setState(() => _factors[size] = _decimal(v)),
          ),
        ],
      ),
    );
  }

  // ── a size ─────────────────────────────────────────────────────────────

  Widget _section({
    required Key key,
    required String size,
    required Translator t,
    required DashFormat format,
    required MadarColors c,
    required bool phone,
    required List<DashOption<String>> options,
    required double? Function(String?) unitCostOf,
  }) {
    final rows = [
      for (final r in _rows)
        if (r.sizeLabel == size) r,
    ];
    final estimate = recipeSizeEstimate(rows, unitCostOf);
    final margin = recipeMargin(estimate, widget.priceForSize?.call(size));
    final figure = DashType.bodyStrong.copyWith(
      color: c.textPrimary,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    Widget stat(String label, String value, Color color) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: DashType.small.copyWith(
            color: c.textSecondary,
            letterSpacing: 0.3,
            height: 1.2,
          ),
        ),
        Text(value, style: figure.copyWith(color: color, height: 1.3)),
      ],
    );
    final marginColor = margin == null
        ? c.textPrimary
        : switch (recipeMarginTone(margin)) {
            RecipeMarginTone.good => DashTone.success.foreground(c),
            RecipeMarginTone.fair => c.textPrimary,
            RecipeMarginTone.low => DashTone.warning.foreground(c),
          };

    final header = Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: Space.lg,
        vertical: Space.sm,
      ),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.4),
        border: Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        spacing: Space.md,
        children: [
          Flexible(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm + DashMetrics.hair,
                  vertical: Space.xs,
                ),
                decoration: BoxDecoration(
                  color: c.muted,
                  borderRadius: BorderRadius.circular(Radii.pill),
                ),
                child: MadarClippedText(
                  sizeLabelText(size, t('recipes.oneSize')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: DashType.smallMedium.copyWith(color: c.textPrimary),
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.lg,
            children: [
              stat(
                t('recipes.builder.estimate'),
                estimate == null ? '—' : format.fmtMoney(estimate),
                c.textPrimary,
              ),
              if (margin != null)
                stat(
                  t('recipes.builder.margin'),
                  format.fmtPercent(margin),
                  marginColor,
                ),
            ],
          ),
        ],
      ),
    );

    return DecoratedBox(
      key: key,
      decoration: BoxDecoration(
        color: c.card,
        border: Border.all(color: c.hairline),
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.control),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            Padding(
              padding: const EdgeInsets.all(Space.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: phone ? Space.sm : Space.xs,
                children: [
                  for (final r in rows)
                    _row(
                      r,
                      size: size,
                      t: t,
                      format: format,
                      c: c,
                      phone: phone,
                      options: options,
                      unitCost: unitCostOf(r.orgIngredientId),
                    ),
                  _AddRowButton(
                    label: t('recipes.addIngredient'),
                    onTap: () => _addRow(size),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(
    RecipeDraftRow r, {
    required String size,
    required Translator t,
    required DashFormat format,
    required MadarColors c,
    required bool phone,
    required List<DashOption<String>> options,
    required double? unitCost,
  }) {
    final lineCost = recipeLineCost(unitCost, r.quantity);
    final costText = lineCost == null ? '—' : format.fmtMoney(lineCost);
    final sizeText = sizeLabelText(size, t('recipes.oneSize'));
    final picker = DashSelect<String>(
      options: options,
      value: r.orgIngredientId,
      searchable: true,
      placeholder: r.ingredientName.isNotEmpty
          ? r.ingredientName
          : t('recipes.ingredient'),
      semanticLabel: t('recipes.ingredient'),
      sheetTitle: t('recipes.ingredient'),
      searchPlaceholder: t('common.search'),
      emptyText: t('common.noResults'),
      onChanged: (id) {
        final ing = widget.catalog.where((c) => c.id == id).firstOrNull;
        _replace(
          r.copyWith(
            orgIngredientId: () => id,
            ingredientName: ing?.name,
            ingredientUnit: ing?.unit,
          ),
        );
      },
    );
    final qty = DashTextInput(
      key: ValueKey('recipe-qty-${r.id}'),
      value: r.quantity,
      placeholder: '0.000',
      textAlign: TextAlign.end,
      textDirection: TextDirection.ltr,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      semanticLabel: t(
        'modeling.grid.cellAria',
        args: {
          'ingredient': r.ingredientName.isNotEmpty
              ? r.ingredientName
              : t('recipes.ingredient'),
          'size': sizeText,
        },
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: Space.xxl),
        child: Text(
          unitWord(t, r.ingredientUnit),
          style: DashType.small.copyWith(color: c.textSecondary),
        ),
      ),
      onChanged: (v) => _replace(r.copyWith(quantity: _decimal(v))),
    );
    final cost = SizedBox(
      width: _costWidth,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerEnd,
        child: Text(
          costText,
          style: DashType.body.copyWith(
            color: lineCost == null ? c.textSecondary : c.textPrimary,
            fontWeight: lineCost == null ? null : FontWeight.w500,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
    final remove = DashIconButton(
      icon: 'trash-2',
      color: c.danger,
      semanticLabel: t('recipes.builder.removeIngredient'),
      onPressed: () => _set([
        for (final x in _rows)
          if (x.id != r.id) x,
      ]),
    );
    if (phone) {
      return Column(
        key: ValueKey('recipe-row-${r.id}'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xs,
        children: [
          picker,
          Row(
            spacing: Space.sm,
            children: [
              Expanded(child: qty),
              cost,
              remove,
            ],
          ),
        ],
      );
    }
    return Row(
      key: ValueKey('recipe-row-${r.id}'),
      spacing: Space.md,
      children: [
        Expanded(child: picker),
        SizedBox(width: _qtyWidth, child: qty),
        cost,
        remove,
      ],
    );
  }

  // ── footer ─────────────────────────────────────────────────────────────

  Widget _footer(Translator t, MadarColors c) {
    final dirty = _dirty;
    return Container(
      padding: const EdgeInsetsDirectional.only(top: Space.md),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.hairline)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        spacing: Space.sm,
        children: [
          if (dirty)
            Flexible(
              child: Text(
                t('recipes.builder.unsaved'),
                textAlign: TextAlign.end,
                style: DashType.small.copyWith(
                  color: DashTone.warning.foreground(c),
                ),
              ),
            ),
          DashButton(
            label: t('recipes.builder.saveAll'),
            icon: 'save',
            loading: _saving,
            onPressed: dirty ? () => unawaited(_save()) : null,
          ),
        ],
      ),
    );
  }
}

/// What a quantity or factor box keeps while typing: Latin digits (Arabic
/// digits read as Latin), one decimal point (a comma or `٫` reads as one).
String _decimal(String v) =>
    cleanDecimal(DashTime.latinDigits(v).replaceAll('٫', '.'));

/// The dashed "Add ingredient" target under a size's rows.
class _AddRowButton extends StatelessWidget {
  const _AddRowButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: onTap,
      semanticLabel: label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) {
        final fg = s.highlighted ? c.textPrimary : c.textSecondary;
        return CustomPaint(
          painter: _DashedRRect(
            color: s.highlighted || s.focused ? c.textSecondary : c.input,
            radius: Radii.control,
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: DashMetrics.target),
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: Space.md,
            ),
            child: Row(
              spacing: Space.sm,
              children: [
                DashIcon('plus', size: IconSize.sm, color: fg),
                Flexible(
                  child: Text(label, style: DashType.body.copyWith(color: fg)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DashedRRect extends CustomPainter {
  const _DashedRRect({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.5),
      );
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 4), paint);
        d += 7;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) =>
      old.color != color || old.radius != radius;
}
