import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_checkout/src/manager_approval_sheet.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The cart's discount (phase 6): a preset, an amount typed by hand, or a
/// percentage typed by hand. Only the kinds this person holds (or may ask a
/// manager for) are offered. The core decides each act against the person's
/// caps; over a cap the manager-PIN sheet asks for an approval, which the core
/// keeps with the cart and the sale carries. Pops true when the cart changed.
Future<bool> showCartDiscountSheet(
  BuildContext context,
  WidgetRef ref, {
  required List<DiscountView> presets,
  required String currency,
  String? tableId,
}) async {
  final bridge = ref.read(bridgeProvider);
  final CartDiscountView current;
  try {
    current = await bridge.cartDiscount(tableId: tableId);
  } on Object {
    return false;
  }
  if (!context.mounted) return false;
  final changed = await showMadarSheet<bool>(
    context,
    size: SheetSize.hug,
    maxWidth: Responsive.sheetCompactMaxWidth,
    builder: (_) => _CartDiscountSheet(
      presets: presets.where((d) => d.isActive).toList(),
      current: current,
      currency: currency,
      tableId: tableId,
    ),
  );
  return changed ?? false;
}

/// The label for the cart's discount, or null for none: a preset's name (and
/// percentage), or the typed amount / percentage.
String? cartDiscountLabel(
  MadarBridge bridge,
  CartDiscountView v,
  List<DiscountView> presets,
  String Function(DiscountView) presetLabel,
) {
  switch (v.kind) {
    case 'preset':
      final d = presets.where((p) => p.id == v.presetId).firstOrNull;
      return d == null ? null : presetLabel(d);
    case 'manual_amount':
      return '${bridge.tr(key: 'discount.manual_amount')} '
          '${MadarFormat.ltr(Money.format(v.amountMinor ?? 0))}';
    case 'manual_percent':
      return '${bridge.tr(key: 'discount.manual_percent')} '
          '${_pct(v.percentBps ?? 0)}%';
    default:
      return null;
  }
}

String _pct(int bps) {
  final whole = bps ~/ 100;
  final frac = bps % 100;
  if (frac == 0) return '$whole';
  return frac % 10 == 0 ? '$whole.${frac ~/ 10}' : '$whole.$frac';
}

class _CartDiscountSheet extends ConsumerStatefulWidget {
  const _CartDiscountSheet({
    required this.presets,
    required this.current,
    required this.currency,
    required this.tableId,
  });

  final List<DiscountView> presets;
  final CartDiscountView current;
  final String currency;
  final String? tableId;

  @override
  ConsumerState<_CartDiscountSheet> createState() => _CartDiscountSheetState();
}

class _CartDiscountSheetState extends ConsumerState<_CartDiscountSheet> {
  late String _kind;
  int? _amountMinor;
  final TextEditingController _percent = TextEditingController();
  bool _busy = false;
  UiText? _error;

  MadarBridge get _bridge => ref.read(bridgeProvider);

  bool _offered(String cap) =>
      _bridge.can(cap: cap) || _bridge.canAskManager(cap: cap);

  List<String> get _kinds => [
    if (_offered(Cap.ordersDiscountPreset) && widget.presets.isNotEmpty)
      'preset',
    if (_offered(Cap.ordersDiscountManualAmount)) 'manual_amount',
    if (_offered(Cap.ordersDiscountManualPercent)) 'manual_percent',
  ];

  @override
  void initState() {
    super.initState();
    final kinds = _kinds;
    _kind = kinds.contains(widget.current.kind)
        ? widget.current.kind
        : (kinds.isEmpty ? 'preset' : kinds.first);
    _amountMinor = widget.current.amountMinor;
    final bps = widget.current.percentBps;
    if (widget.current.kind == 'manual_percent' && bps != null) {
      _percent.text = _pct(bps);
    }
  }

  @override
  void dispose() {
    _percent.dispose();
    super.dispose();
  }

  /// The typed percentage in basis points; null when blank or unreadable.
  int? get _percentBps {
    final v = double.tryParse(_percent.text.trim().replaceAll(',', '.'));
    return v == null ? null : (v * 100).round();
  }

  Future<void> _apply({String? presetId}) async {
    if (_busy) return;
    final bridge = _bridge;
    final kind = _kind;
    final amount = kind == 'manual_amount' ? _amountMinor : null;
    final bps = kind == 'manual_percent' ? _percentBps : null;
    if ((kind == 'manual_amount' && (amount ?? 0) <= 0) ||
        (kind == 'manual_percent' && (bps ?? 0) <= 0)) {
      return;
    }
    final decision = bridge.decideDiscount(
      tableId: widget.tableId,
      kind: kind,
      presetId: presetId,
      amountMinor: amount,
      percentBps: bps,
    );
    if (decision.outcome == 'deny') {
      setState(() => _error = UiText.raw(decision.reason));
      return;
    }
    ApprovalView? approval;
    if (decision.outcome == 'needs_approval') {
      approval = await askManagerWith(
        context,
        reason: decision.reason,
        approve: (pin) => bridge.approveDiscount(
          approverPin: pin,
          tableId: widget.tableId,
          kind: kind,
          presetId: presetId,
          amountMinor: amount,
          percentBps: bps,
        ),
      );
      if (approval == null || !mounted) return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await bridge.applyDiscount(
        tableId: widget.tableId,
        kind: kind,
        presetId: presetId,
        amountMinor: amount,
        percentBps: bps,
        approval: approval,
      );
      if (mounted) MadarSheet.close(context, true);
    } on MadarError catch (e) {
      MadarHaptics.warning();
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e is MadarError_Forbidden
              ? UiText.raw(e.action)
              : UiText.error(e);
        });
      }
    }
  }

  Future<void> _clear() async {
    try {
      await _bridge.cartClearDiscount(tableId: widget.tableId);
    } on Object {
      return;
    }
    if (mounted) MadarSheet.close(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    final colors = context.madarColors;
    String t(String key) => bridge.tr(key: key);
    final kinds = _kinds;
    final current = widget.current;
    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Text(
            t('order.discount'),
            style: MadarType.h3.copyWith(color: colors.textPrimary),
          ),
          if (current.approvedByName != null)
            Text(
              t(
                'approval.approved_by',
              ).replaceAll('{name}', current.approvedByName!),
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
          if (kinds.length > 1)
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final k in kinds)
                  MadarChip(
                    label: t('discount.$k'),
                    selected: _kind == k,
                    onTap: () => setState(() {
                      _kind = k;
                      _error = null;
                    }),
                  ),
              ],
            ),
          if (kinds.isEmpty)
            Text(
              t('discount.none_allowed'),
              style: MadarType.body.copyWith(color: colors.textSecondary),
            )
          else if (_kind == 'preset')
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                for (final d in widget.presets)
                  MadarChip(
                    label: _presetLabel(d),
                    selected:
                        current.kind == 'preset' && current.presetId == d.id,
                    enabled: !_busy,
                    onTap: () => _apply(presetId: d.id),
                  ),
              ],
            )
          else if (_kind == 'manual_amount')
            MadarAmountField(
              amountMinor: _amountMinor,
              currencyCode: widget.currency,
              autofocus: true,
              onAmountMinor: (v) => _amountMinor = v,
              onSubmitted: (_) => _apply(),
            )
          else
            MadarField(
              controller: _percent,
              placeholder: t('discount.percent_hint'),
              kind: MadarFieldKind.decimal,
              glyph: MadarGlyph.percent,
              autofocus: true,
              enabled: !_busy,
              onSubmitted: (_) => _apply(),
            ),
          if (_error != null)
            NoticeBanner(
              text: _error!.of(bridge),
              tone: ChipTone.danger,
              icon: 'exclamationmark.circle',
            ),
          if (kinds.isNotEmpty && _kind != 'preset')
            MadarButton(
              label: t('discount.apply'),
              onTap: _apply,
              loading: _busy,
              icon: 'checkmark.circle',
            ),
          if (current.kind.isNotEmpty)
            MadarButton(
              label: t('order.no_discount'),
              variant: MadarButtonVariant.ghost,
              onTap: _clear,
            ),
        ],
      ),
    );
  }

  String _presetLabel(DiscountView d) {
    if (d.dtype != 'percentage') return d.name;
    final pct = (d.value * 1000).round() / 10;
    final text = pct == pct.roundToDouble()
        ? pct.toStringAsFixed(0)
        : pct.toStringAsFixed(1);
    return '${d.name} $text%';
  }
}
