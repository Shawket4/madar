/// Record waste — pushed from the Till (phase 6, `inventory.waste.record`).
///
/// Pick a menu item (its recipe comes off stock) or an ingredient, the
/// quantity, a reason and an optional note. The core prices it from the
/// feed, decides the `max_value` limit, and queues it; a waste over the
/// person's limit goes through the manager-PIN sheet. Works offline.
library;

import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_history/feature_history.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// How many search matches the picker lists at once.
const int _maxMatches = 8;

/// A quantity without trailing zeros (18, 0.25).
String _qtyText(double q) {
  final fixed = q.toStringAsFixed(3);
  return fixed.contains('.')
      ? fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : fixed;
}

/// The waste form, as its own page.
class WasteScreen extends ConsumerStatefulWidget {
  /// Creates the waste screen.
  const WasteScreen({super.key});

  @override
  ConsumerState<WasteScreen> createState() => _WasteScreenState();
}

class _WasteScreenState extends ConsumerState<WasteScreen> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _qty = TextEditingController();
  final TextEditingController _note = TextEditingController();

  String _kind = 'menu_item';
  String? _subjectId;
  String? _subjectName;
  List<String> _sizes = const [];
  String? _size;
  List<String> _units = const ['pcs'];
  String _unit = 'pcs';
  String? _reason;
  bool _busy = false;
  UiText? _error;
  String? _done;

  @override
  void dispose() {
    _search.dispose();
    _qty.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _quantity => double.tryParse(_qty.text.trim());

  WasteInput? _input() {
    final id = _subjectId;
    final qty = _quantity;
    if (id == null || qty == null || qty <= 0) return null;
    final note = _note.text.trim();
    return WasteInput(
      subjectKind: _kind,
      subjectId: id,
      sizeLabel: _size,
      quantity: qty,
      unit: _unit,
      reason: _reason ?? '',
      note: note.isEmpty ? null : note,
    );
  }

  void _setKind(String kind) => setState(() {
    _kind = kind;
    _subjectId = null;
    _subjectName = null;
    _sizes = const [];
    _size = null;
    _units = const ['pcs'];
    _unit = 'pcs';
    _search.clear();
    _error = null;
  });

  void _pickItem(WasteItemView item) => setState(() {
    _subjectId = item.id;
    _subjectName = item.name;
    _sizes = item.sizes;
    _size = item.sizes.isEmpty ? null : item.sizes.first;
    _units = const ['pcs'];
    _unit = 'pcs';
    _error = null;
    _done = null;
  });

  void _pickIngredient(WasteIngredientView ing) => setState(() {
    _subjectId = ing.id;
    _subjectName = ing.name;
    _sizes = const [];
    _size = null;
    _units = ing.units;
    _unit = ing.unit;
    _error = null;
    _done = null;
  });

  Future<void> _record() async {
    final input = _input();
    if (_busy || input == null || _reason == null) return;
    final bridge = ref.read(bridgeProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final preview = bridge.previewWaste(input: input);
      ApprovalView? approval;
      switch (preview.decision.outcome) {
        case 'allow':
          break;
        case 'needs_approval':
          if (!mounted) return;
          approval = await askManager(
            context,
            ref,
            reason: preview.decision.reason,
            capKey: Cap.inventoryWasteRecord,
            approve: (b, pin) => b.approveWaste(approverPin: pin, input: input),
          );
          if (approval == null) {
            if (mounted) setState(() => _busy = false);
            return;
          }
        default:
          if (mounted) {
            setState(() {
              _busy = false;
              _error = UiText.raw(preview.decision.reason);
            });
          }
          return;
      }
      final recorded = await bridge.recordWaste(
        input: input,
        approval: approval,
      );
      MadarHaptics.success();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _done = '${bridge.tr(key: 'waste.recorded')} · ${recorded.subjectName}';
        _subjectId = null;
        _subjectName = null;
        _sizes = const [];
        _size = null;
        _reason = null;
        _qty.clear();
        _note.clear();
        _search.clear();
      });
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

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    String t(String key) => bridge.tr(key: key);
    final currency = bridge.currentSession()?.currencyCode ?? '';

    final query = _search.text;
    final List<({String id, String name, VoidCallback onTap})> matches;
    try {
      matches = _kind == 'menu_item'
          ? [
              for (final i in bridge.wasteItems(query: query).take(_maxMatches))
                (id: i.id, name: i.name, onTap: () => _pickItem(i)),
            ]
          : [
              for (final i
                  in bridge.wasteIngredients(query: query).take(_maxMatches))
                (id: i.id, name: i.name, onTap: () => _pickIngredient(i)),
            ];
    } on MadarError catch (e) {
      return MadarPageScaffold(
        title: t('waste.title'),
        width: MadarContentWidth.form,
        body: NoticeBanner(
          text: UiText.error(e).of(bridge),
          tone: ChipTone.danger,
          icon: 'exclamationmark.circle',
        ),
      );
    }

    final input = _input();
    WastePreviewView? preview;
    if (input != null) {
      try {
        preview = bridge.previewWaste(input: input);
      } on MadarError {
        preview = null;
      }
    }

    return MadarPageScaffold(
      title: t('waste.title'),
      subtitle: t('waste.subtitle'),
      width: MadarContentWidth.form,
      body: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.only(bottom: Space.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.xl,
          children: [
            if (_done != null)
              NoticeBanner(
                text: _done!,
                tone: ChipTone.success,
                icon: 'checkmark.circle',
              ),
            MadarCard.column(
              children: [
                MadarSegmented<String>(
                  items: [
                    MadarSegmentItem(
                      'menu_item',
                      t('waste.kind_item'),
                      glyph: MadarGlyph.receipt,
                    ),
                    MadarSegmentItem(
                      'ingredient',
                      t('waste.kind_ingredient'),
                      glyph: MadarGlyph.bag,
                    ),
                  ],
                  value: _kind,
                  onChanged: _setKind,
                ),
                MadarField(
                  controller: _search,
                  placeholder: t('waste.search'),
                  glyph: MadarGlyph.search,
                  onChanged: (_) => setState(() {}),
                ),
                if (matches.isEmpty)
                  Text(
                    t('waste.empty'),
                    style: MadarType.bodySm.copyWith(color: colors.textMuted),
                  )
                else
                  MadarCard.column(
                    flush: true,
                    children: [
                      for (final (i, m) in matches.indexed) ...[
                        if (i > 0) const MadarHairline.row(),
                        MadarListRow.pick(
                          title: m.name,
                          selected: m.id == _subjectId,
                          onTap: m.onTap,
                        ),
                      ],
                    ],
                  ),
                if (_subjectName != null && _sizes.isNotEmpty) ...[
                  MadarSectionHeader(text: t('waste.size')),
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      for (final s in _sizes)
                        MadarChip(
                          label: s,
                          selected: s == _size,
                          onTap: () => setState(() => _size = s),
                        ),
                    ],
                  ),
                ],
              ],
            ),
            MadarCard.column(
              children: [
                MadarField(
                  controller: _qty,
                  placeholder: t('waste.quantity'),
                  glyph: MadarGlyph.plus,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                if (_units.length > 1)
                  Wrap(
                    spacing: Space.sm,
                    runSpacing: Space.sm,
                    children: [
                      for (final u in _units)
                        MadarChip(
                          label: u,
                          selected: u == _unit,
                          onTap: () => setState(() => _unit = u),
                        ),
                    ],
                  ),
                MadarSectionHeader(text: t('waste.reason')),
                Wrap(
                  spacing: Space.sm,
                  runSpacing: Space.sm,
                  children: [
                    for (final r in bridge.wasteReasons())
                      MadarChip(
                        label: r.label,
                        selected: r.key == _reason,
                        onTap: () => setState(() => _reason = r.key),
                      ),
                  ],
                ),
                MadarField(
                  controller: _note,
                  placeholder: t('waste.note'),
                  glyph: MadarGlyph.note,
                ),
              ],
            ),
            if (preview != null)
              MadarCard.column(
                children: [
                  MadarSectionHeader(
                    text: t('waste.takes'),
                    trailing: preview.valueMinor == null
                        ? null
                        : MoneyText(
                            preview.valueMinor!,
                            currency: currency,
                            style: MadarType.num,
                          ),
                  ),
                  for (final l in preview.lines)
                    MadarSummaryLine(
                      label: l.name,
                      value: MadarFormat.ltr(
                        '${_qtyText(l.quantity)} ${l.unit}',
                      ),
                    ),
                  if (preview.valuePartial)
                    Text(
                      t('waste.value_partial'),
                      style: MadarType.bodySm.copyWith(color: colors.textMuted),
                    ),
                ],
              ),
            if (_error != null)
              NoticeBanner(
                text: _error!.of(bridge),
                tone: ChipTone.danger,
                icon: 'exclamationmark.circle',
              ),
            MadarButton(
              label: t('waste.record'),
              glyph: MadarGlyph.trash,
              variant: MadarButtonVariant.danger,
              loading: _busy,
              enabled: input != null && _reason != null,
              onTap: () => unawaited(_record()),
            ),
          ],
        ),
      ),
    );
  }
}
