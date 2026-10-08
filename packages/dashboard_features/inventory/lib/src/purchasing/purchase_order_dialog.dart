/// The New purchase order dialog (INV-PUR-028…042, -063, -067, -069…071;
/// web `purchase-order-dialog.tsx`), opened from Purchasing (empty, or a
/// Reorder group's "Create draft PO") and from Today's low-stock "Create PO"
/// (INV-TOD-013/028). Owned by the purchasing unit; Today calls
/// [showPurchaseOrderDialog] and nothing else.
///
/// Each line's TOTAL (EGP, as on the supplier's invoice) is what is typed
/// and sent; the unit cost is worked out from it and only shown. Until a
/// total is typed it follows the catalog's estimate for the quantity.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show CreatePurchaseOrderRequest, OrgIngredient, POLineInput, Supplier;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/inventory_data.dart';
import '../shared/inventory_lib.dart';
import 'purchasing_data.dart';
import 'purchasing_widgets.dart';

/// One prefilled line: the ingredient, the quantity in [purchaseUnit] (the
/// stock unit when null) — the total is estimated from the catalog cost.
class PurchaseOrderPrefillLine {
  const PurchaseOrderPrefillLine({
    required this.orgIngredientId,
    required this.quantity,
    this.purchaseUnit,
  });

  final String orgIngredientId;
  final double quantity;
  final String? purchaseUnit;
}

/// What the dialog opens with (Today's low-stock row, a Reorder group).
class PurchaseOrderPrefill {
  const PurchaseOrderPrefill({this.supplierId, this.lines = const []});

  /// May name an inactive supplier: the picker then shows its placeholder
  /// while the id is still sent (INV-ALL-023).
  final String? supplierId;
  final List<PurchaseOrderPrefillLine> lines;
}

/// Opens the dialog for [branchId]; true once an order was created (the
/// dialog has invalidated inventory and toasted by then).
Future<bool?> showPurchaseOrderDialog(
  BuildContext context, {
  required String branchId,
  PurchaseOrderPrefill? prefill,
}) => showDashDialog<bool>(
  context,
  width: DashMetrics.dialogWide,
  builder: (_) => PurchaseOrderDialog(branchId: branchId, prefill: prefill),
);

/// One line as typed (`LineState`).
class _Line {
  _Line(this.key);

  final int key;
  String? ingredientId;
  String purchaseUnit = '';
  String qty = '';
  String total = '';
  bool totalTouched = false;
}

class PurchaseOrderDialog extends ConsumerStatefulWidget {
  const PurchaseOrderDialog({required this.branchId, this.prefill, super.key});

  final String branchId;
  final PurchaseOrderPrefill? prefill;

  @override
  ConsumerState<PurchaseOrderDialog> createState() =>
      _PurchaseOrderDialogState();
}

class _PurchaseOrderDialogState extends ConsumerState<PurchaseOrderDialog> {
  var _nextKey = 0;
  String? _supplierId;
  DateTime? _expected;
  String _reference = '';
  late List<_Line> _lines;
  bool _busy = false;

  /// The catalog as last built (read in callbacks; [build] watches it).
  List<OrgIngredient> _catalog = const [];

  String? get _orgId => ref.read(orgIdProvider);

  OrgIngredient? _ingredient(String? id) {
    if (id == null) return null;
    for (final c in _catalog) {
      if (c.id == id) return c;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    _supplierId = p?.supplierId;
    final org = _orgId;
    _catalog = org == null
        ? const <OrgIngredient>[]
        : ref.read(inventoryCatalogProvider(org)).value ?? const [];
    if (p != null && p.lines.isNotEmpty) {
      final catalog = _catalog;
      _lines = [
        for (final l in p.lines)
          _withEstimate(
            _Line(++_nextKey)
              ..ingredientId = l.orgIngredientId
              ..purchaseUnit =
                  l.purchaseUnit ??
                  catalog
                      .where((c) => c.id == l.orgIngredientId)
                      .firstOrNull
                      ?.unit ??
                  ''
              ..qty = jsNumberString(l.quantity),
            catalog,
          ),
      ];
    } else {
      _lines = [_Line(++_nextKey)];
    }
  }

  /// Refills an untouched total from the catalog's cost for the quantity.
  _Line _withEstimate(_Line l, [List<OrgIngredient>? catalog]) {
    if (l.totalTouched) return l;
    final all = catalog ?? _catalog;
    final ing = l.ingredientId == null
        ? null
        : all.where((c) => c.id == l.ingredientId).firstOrNull;
    final est = ing == null
        ? null
        : estimateLineTotal(
            ing.costPerUnit,
            parseInputNumber(l.qty),
            l.purchaseUnit,
            ing.unit,
          );
    l.total = est == null ? '' : piastresToEgpFixed(est);
    return l;
  }

  void _setLine(_Line l, void Function(_Line l) patch) => setState(() {
    patch(l);
    _withEstimate(l);
  });

  /// The line's total in piastres; NaN unless a non-negative number.
  double _linePiastres(_Line l) {
    final egp = parseInputNumber(l.total);
    return egp.isFinite && egp >= 0
        ? egpToPiastres(egp).toDouble()
        : double.nan;
  }

  bool _valid(_Line l) =>
      l.ingredientId != null &&
      parseInputNumber(l.qty) > 0 &&
      _linePiastres(l).isFinite;

  Future<void> _submit() async {
    final valid = _lines.where(_valid).toList();
    if (valid.isEmpty) return;
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    setState(() => _busy = true);
    try {
      final d = _expected;
      final expectedAt = d == null
          ? null
          : DateTime.parse(
              f.cairoDateISO(d.year, d.month - 1, d.day, endOfDay: true),
            );
      final reference = _reference.trim().isEmpty ? null : _reference.trim();
      await ref
          .read(apiProvider)
          .purchasing
          .createPurchaseOrder(
            branchId: widget.branchId,
            body: CreatePurchaseOrderRequest(
              supplierId: _supplierId,
              expectedAt: expectedAt,
              reference: reference,
              explicitNulls: {
                if (_supplierId == null) 'supplier_id',
                if (expectedAt == null) 'expected_at',
                if (reference == null) 'reference',
              },
              lines: [
                for (final l in valid)
                  POLineInput(
                    orgIngredientId: l.ingredientId!,
                    // A real stock unit in the ingredient's measure; the
                    // server derives the pack factor from it.
                    purchaseUnit: l.purchaseUnit.isNotEmpty
                        ? l.purchaseUnit
                        : (_ingredient(l.ingredientId)?.unit ?? 'pcs'),
                    quantityOrdered: parseInputNumber(l.qty),
                    lineCost: _linePiastres(l).toInt(),
                    explicitNulls: const {'units_per_purchase_unit'},
                  ),
              ],
            ),
          );
      invalidateInventory(ref);
      if (!mounted) return;
      DashToast.success(context, t('inventory.purchasing.newOrder'));
      Navigator.of(context).pop(true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      DashToast.error(context, errorMessage(e, t));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final org = ref.watch(orgIdProvider);
    final suppliers = org == null
        ? const <Supplier>[]
        : ref.watch(inventorySuppliersProvider(org)).value ?? const [];
    final catalog = _catalog = org == null
        ? const <OrgIngredient>[]
        : ref.watch(inventoryCatalogProvider(org)).value ?? const [];
    final total = _lines.fold<double>(0, (sum, l) {
      final p = _linePiastres(l);
      return p.isFinite ? sum + p : sum;
    });
    final canSubmit = _lines.any(_valid);
    final now = f.cairoNow();

    final supplierField = DashFormField<String?>(
      label: t('inventory.purchasing.supplier'),
      builder: (context, _) => DashSelect<String>(
        key: const ValueKey('po-supplier'),
        options: [
          for (final s in activeSuppliers(suppliers))
            DashOption(value: s.id, label: s.name),
        ],
        value: _supplierId,
        onChanged: (v) => setState(() => _supplierId = v),
        placeholder: t('inventory.purchasing.pickSupplier'),
        semanticLabel: t('inventory.purchasing.supplier'),
        searchable: true,
        searchPlaceholder: t('common.search'),
        emptyText: t('common.noResults'),
      ),
    );
    final expectedField = DashFormField<DateTime?>(
      label: t('inventory.purchasing.expectedAt'),
      builder: (context, _) => DashDateField(
        key: const ValueKey('po-expected'),
        value: _expected,
        onChanged: (d) => setState(() => _expected = d),
        placeholder: t('inventory.purchasing.expectedAt'),
        semanticLabel: t('inventory.purchasing.expectedAt'),
        today: DateTime(now.year, now.month, now.day),
        warnPast: true,
      ),
    );

    return DashSurface(
      title: t('inventory.purchasing.newOrder'),
      description: t('inventory.purchasing.orders'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.md,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.md,
            children: [
              Expanded(child: supplierField),
              Expanded(child: expectedField),
            ],
          ),
          DashFormField<String>(
            label: t('inventory.purchasing.reference'),
            optionalText: '(${t('common.optional')})',
            builder: (context, _) => DashTextInput(
              key: const ValueKey('po-reference'),
              value: _reference,
              semanticLabel: t('inventory.purchasing.reference'),
              onChanged: (v) => setState(() => _reference = v),
            ),
          ),
          Divider(height: 1, thickness: 1, color: c.hairline),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: [
              Text(
                t('inventory.purchasing.lines'),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              for (var i = 0; i < _lines.length; i++)
                _LineBox(
                  key: ValueKey('po-line-${_lines[i].key}'),
                  index: i,
                  line: _lines[i],
                  catalog: catalog,
                  ingredient: _ingredient(_lines[i].ingredientId),
                  linePiastres: _linePiastres(_lines[i]),
                  onPick: (id) => _setLine(_lines[i], (l) {
                    l
                      ..ingredientId = id
                      ..purchaseUnit = _ingredient(id)?.unit ?? '';
                  }),
                  onUnit: (u) => _setLine(_lines[i], (l) => l.purchaseUnit = u),
                  onQty: (v) => _setLine(_lines[i], (l) => l.qty = v),
                  onTotal: (v) => _setLine(_lines[i], (l) {
                    l
                      ..total = v
                      ..totalTouched = true;
                  }),
                  onRemove: () {
                    final key = _lines[i].key;
                    setState(() => _lines.removeWhere((x) => x.key == key));
                  },
                ),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: DashButton(
                  key: const ValueKey('po-add-line'),
                  label: t('inventory.purchasing.addLine'),
                  icon: 'plus',
                  variant: DashButtonVariant.outline,
                  size: DashButtonSize.compact,
                  onPressed: () =>
                      setState(() => _lines.add(_Line(++_nextKey))),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.only(top: Space.md),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.hairline)),
            ),
            child: DashSummaryLine(
              key: const ValueKey('po-total'),
              label: t('inventory.purchasing.grandTotal'),
              value: f.fmtMoney(total),
              emphasis: true,
            ),
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DashButton(
          key: const ValueKey('po-submit'),
          label: t('inventory.purchasing.order'),
          loading: _busy,
          onPressed: canSubmit ? _submit : null,
        ),
      ],
    );
  }
}

/// One line's box: the ingredient picker and ✕, the three small fields,
/// the locked unit cost.
class _LineBox extends ConsumerWidget {
  const _LineBox({
    required this.index,
    required this.line,
    required this.catalog,
    required this.ingredient,
    required this.linePiastres,
    required this.onPick,
    required this.onUnit,
    required this.onQty,
    required this.onTotal,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _Line line;
  final List<OrgIngredient> catalog;
  final OrgIngredient? ingredient;
  final double linePiastres;
  final ValueChanged<String> onPick;
  final ValueChanged<String> onUnit;
  final ValueChanged<String> onQty;
  final ValueChanged<String> onTotal;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final ing = ingredient;
    final units = ing == null ? const <String>[] : unitsForFamily(ing.unit);
    final unitCost = unitCostFromTotal(
      linePiastres,
      parseInputNumber(line.qty),
    );
    final unitWord = line.purchaseUnit.isNotEmpty
        ? t('units.${line.purchaseUnit}', defaultValue: line.purchaseUnit)
        : t('inventory.purchasing.unitCostUnit');

    Widget small(String label, Widget control) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        MadarClippedText(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: DashType.smallMedium.copyWith(color: c.textPrimary),
        ),
        control,
      ],
    );

    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          Row(
            spacing: Space.sm,
            children: [
              Expanded(
                child: DashSelect<String>(
                  key: ValueKey('po-line-ingredient-$index'),
                  options: [
                    for (final i in catalog)
                      DashOption(value: i.id, label: i.name),
                  ],
                  value: line.ingredientId,
                  onChanged: onPick,
                  placeholder: t('inventory.purchasing.pickIngredient'),
                  semanticLabel: t('inventory.purchasing.pickIngredient'),
                  searchable: true,
                  searchPlaceholder: t('common.search'),
                  emptyText: t('common.noResults'),
                ),
              ),
              DashIconButton(
                key: ValueKey('po-line-remove-$index'),
                icon: 'x',
                semanticLabel: t('common.remove'),
                onPressed: onRemove,
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.sm,
            children: [
              Expanded(
                child: small(
                  t('inventory.purchasing.purchaseUnit'),
                  DashSelect<String>(
                    key: ValueKey('po-line-unit-$index'),
                    options: [
                      for (final u in units)
                        DashOption(
                          value: u,
                          label: t('units.$u', defaultValue: u),
                        ),
                    ],
                    value: line.purchaseUnit.isEmpty ? null : line.purchaseUnit,
                    onChanged: onUnit,
                    placeholder: '—',
                    semanticLabel: t('inventory.purchasing.purchaseUnit'),
                    enabled: ing != null,
                  ),
                ),
              ),
              Expanded(
                child: small(
                  t('inventory.purchasing.qtyOrdered'),
                  PoNumberInput(
                    key: ValueKey('po-line-qty-$index'),
                    value: line.qty,
                    onChanged: onQty,
                    semanticLabel: t('inventory.purchasing.qtyOrdered'),
                  ),
                ),
              ),
              Expanded(
                child: small(
                  t('inventory.purchasing.lineTotal'),
                  PoNumberInput(
                    key: ValueKey('po-line-total-$index'),
                    value: line.total,
                    onChanged: onTotal,
                    semanticLabel: t('inventory.purchasing.lineTotal'),
                  ),
                ),
              ),
            ],
          ),
          // Locked: nothing types here. It is the line total ÷ the
          // quantity, recomputed as either changes.
          Tooltip(
            message: t('inventory.purchasing.unitCostLockedHint'),
            child: Semantics(
              readOnly: true,
              label: t(
                'inventory.purchasing.unitCostLocked',
                args: {'unit': unitWord},
              ),
              child: DashedFrame(
                child: Row(
                  spacing: Space.md,
                  children: [
                    Expanded(
                      child: Row(
                        spacing: Space.xs + DashMetrics.hair,
                        children: [
                          DashIcon(
                            'lock',
                            size: IconSize.xs,
                            color: c.textSecondary,
                          ),
                          Flexible(
                            child: MadarClippedText(
                              t(
                                'inventory.purchasing.unitCostLocked',
                                args: {'unit': unitWord},
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DashType.small.copyWith(
                                color: c.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Directionality(
                      textDirection: TextDirection.ltr,
                      child: DashAnimatedFigure(
                        unitCost != null ? formatUnitCost(f, unitCost) : '—',
                        key: ValueKey('po-line-unit-cost-$index'),
                        style: DashType.monoMedium.copyWith(
                          fontSize: 14,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
