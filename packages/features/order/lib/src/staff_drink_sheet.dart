// A cart line on the branch's staff pool (owner design 2026-09-19).
//
// The shop used to ring a staff drink as a zero-priced twin of the real item
// ("Latte staff" beside "Latte"), so the stock never came off and the menu grew
// a shadow copy of itself. The pool replaces that: the REAL line is put on an
// allowance that belongs to the branch and starts again every business day.
//
// Everything here is sequencing. The core decides whether the action belongs on
// this line at all, whether this person may act or must ask a manager, how many
// are left today and whether this one goes over — and it hands back the words
// already chosen, in the till's language. Nothing on this page counts a drink,
// compares a date or picks a string.
//
// Saving the sheet MARKS the line (owner rule 2026-09-21): the line becomes a
// staff drink in the core's cart — badge, struck-through price, comp through
// the bill engine — and the pool entry is written when the order is CHARGED,
// with the order, so an abandoned cart burns nothing. Tapping the badge comes
// back here to edit the note or take the mark off.
//
// Only a COUNTER sale carries one. A table's bill never does (the server
// refuses a pooled line on a ticket), so the tile is not drawn on a cart that
// fires, and a marked cart that becomes a table's loses its marks — the core
// says why and the cart toasts it.
//
// Two rules the sheet exists to hold:
//   * a NOTE IS REQUIRED. Save is dead until there is one, because the note is
//     the only record of who drank it, in the teller's own words — and the
//     column at the far end refuses a blank one anyway.
//   * an OVERSPEND STILL SAVES. Going past the allowance is warned about, in
//     full sentences, and then allowed: the drink was already made and the sale
//     already rung, so refusing it now would only lose the record.
import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_history/feature_history.dart' show askManager;
import 'package:feature_order/src/order_providers.dart';
import 'package:flutter/material.dart'
    show InkWell, Material, MaterialType, Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The core's verdict on putting a cart line on the pool, re-asked whenever the
/// order tables move. Synchronous in the core (local rows, no network), so the
/// tile can decide to draw itself inside one build.
// ignore: specify_nonobvious_property_types  (Riverpod 3 infers the family)
final staffDrinkPreviewProvider = Provider.autoDispose
    .family<StaffDrinkPreviewView?, (String, String?, int, String?)>((
      ref,
      key,
    ) {
      final bridge = ref.read(bridgeProvider);
      try {
        return bridge.previewStaffDrink(
          input: StaffDrinkInput(
            menuItemId: key.$1,
            sizeLabel: key.$2,
            quantity: key.$3,
            note: '',
            // A line that is ALREADY marked does not count itself.
            lineKey: key.$4,
          ),
        );
      } on Object {
        // No session, no branch, no settings yet: no action. A pool this device
        // has never heard of is a pool that is off.
        return null;
      }
    });

/// The staff-drink tile on a cart line. Draws NOTHING when the core says the
/// action is not offered — hidden, not greyed: there is nothing to explain
/// about a pool the branch never switched on, or an item that was never on its
/// list, and a dead control on every line of every cart is worse than no
/// control at all.
/// Whether [StaffDrinkTile] shows for [line]: the cart charges a counter
/// sale, the line is not marked yet, and the core offers the pool on it. The
/// cart line asks too, to lay its row out before it draws it.
bool staffDrinkTileShows(
  WidgetRef ref,
  CartLineView line, {
  String? tableId,
  bool counterSale = true,
}) {
  // Not on a table's bill and not twice: a marked line's way back in is its
  // badge.
  if (!counterSale || tableId != null || line.staffDrink != null) {
    return false;
  }
  final preview = ref.watch(
    staffDrinkPreviewProvider((line.itemId, line.sizeLabel, line.qty, null)),
  );
  return preview != null && preview.offered;
}

class StaffDrinkTile extends ConsumerWidget {
  const StaffDrinkTile({
    required this.line,
    this.tableId,
    this.counterSale = true,
    this.dense = false,
    this.label,
    super.key,
  });

  final CartLineView line;
  final String? tableId;

  /// The cart line's dense tile, beside its dense stepper.
  final bool dense;

  /// The cart CHARGES a counter sale. False on a cart that fires a round (a
  /// table's cart, a targeted bill, a waiter's): a ticket never carries a
  /// staff drink, so the action is not there to be tapped.
  final bool counterSale;

  /// A short word to show beside the glyph: the cart line's second row of
  /// labelled tools, when its buttons do not fit one row.
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!staffDrinkTileShows(
      ref,
      line,
      tableId: tableId,
      counterSale: counterSale,
    )) {
      return const SizedBox.shrink();
    }
    final bridge = ref.read(bridgeProvider);
    void open() => unawaited(
      showStaffDrinkSheet(context, ref, line: line, tableId: tableId),
    );
    if (this.label case final word?) {
      return MadarButton(
        key: ValueKey('staff-drink-${line.key}'),
        label: word,
        glyph: MadarGlyph.users,
        variant: MadarButtonVariant.secondary,
        size: MadarButtonSize.dense,
        onTap: open,
      );
    }
    final label = bridge.tr(key: 'staff_pool.action');
    return Tooltip(
      message: label,
      child: MadarGlyphTile(
        key: ValueKey('staff-drink-${line.key}'),
        glyph: MadarGlyph.users,
        dense: dense,
        semanticLabel: label,
        onTap: () => unawaited(
          showStaffDrinkSheet(context, ref, line: line, tableId: tableId),
        ),
      ),
    );
  }
}

/// The "Staff drink" badge on a MARKED line. Tapping it reopens the sheet to
/// edit the note or take the mark off.
class StaffDrinkBadge extends ConsumerWidget {
  const StaffDrinkBadge({required this.line, this.tableId, super.key});

  final CartLineView line;
  final String? tableId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (line.staffDrink == null) return const SizedBox.shrink();
    final label = ref.read(bridgeProvider).tr(key: 'staff_pool.badge');
    return Semantics(
      button: true,
      label: label,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: ValueKey('staff-badge-${line.key}'),
          borderRadius: BorderRadius.circular(Radii.xs),
          onTap: () => unawaited(
            showStaffDrinkSheet(context, ref, line: line, tableId: tableId),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: Metrics.tagHeight),
            child: MadarTag(
              label: label,
              tone: MadarTone.accent,
              glyph: MadarGlyph.users,
            ),
          ),
        ),
      ),
    );
  }
}

/// A marked line's price: the NORMAL price struck through, then what the pool
/// leaves to pay — "Free", or "Extras 25.00". Both figures are the core's.
class StaffDrinkPrice extends ConsumerWidget {
  const StaffDrinkPrice({
    required this.line,
    required this.currency,
    super.key,
  });

  final CartLineView line;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mark = line.staffDrink;
    if (mark == null) return const SizedBox.shrink();
    final colors = context.madarColors;
    final bridge = ref.read(bridgeProvider);
    final free = mark.chargedMinor <= 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        MoneyText(
          line.lineTotalMinor,
          key: ValueKey('staff-normal-${line.key}'),
          currency: currency,
          style: MadarType.money.copyWith(
            decoration: TextDecoration.lineThrough,
          ),
          color: colors.textMuted,
        ),
        Text(
          bridge.tr(
            key: free ? 'staff_pool.line_free' : 'staff_pool.line_extras',
          ),
          key: ValueKey('staff-charged-label-${line.key}'),
          style: MadarType.label.copyWith(
            color: free ? colors.success : colors.textSecondary,
          ),
        ),
        if (!free)
          MoneyText(
            mark.chargedMinor,
            key: ValueKey('staff-charged-${line.key}'),
            currency: currency,
            color: colors.textPrimary,
          ),
      ],
    );
  }
}

/// The sheet: the pool as it stands, the required note, and Save.
Future<void> showStaffDrinkSheet(
  BuildContext context,
  WidgetRef ref, {
  required CartLineView line,
  String? tableId,
}) async {
  await showMadarSheet<void>(
    context,
    size: SheetSize.hug,
    maxWidth: Responsive.sheetCompactMaxWidth,
    builder: (_) => StaffDrinkSheet(line: line, tableId: tableId),
  );
}

/// The sheet's body. Public so the render tests can mount it on its own.
class StaffDrinkSheet extends ConsumerStatefulWidget {
  const StaffDrinkSheet({required this.line, this.tableId, super.key});

  final CartLineView line;
  final String? tableId;

  @override
  ConsumerState<StaffDrinkSheet> createState() => _StaffDrinkSheetState();
}

class _StaffDrinkSheetState extends ConsumerState<StaffDrinkSheet> {
  final TextEditingController _note = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The line is already a staff drink: this is the edit / remove sheet.
  CartStaffDrinkView? get _mark => widget.line.staffDrink;

  StaffDrinkInput get _input => StaffDrinkInput(
    menuItemId: widget.line.itemId,
    sizeLabel: widget.line.sizeLabel,
    quantity: widget.line.qty,
    note: _note.text,
    lineKey: _mark == null ? null : widget.line.key,
  );

  @override
  void initState() {
    super.initState();
    _note.text = _mark?.note ?? '';
    // Every keystroke re-asks the core, because the ONE thing that changes
    // between "cannot save" and "can" is whether there is a note — and the
    // core is the only thing that knows what counts as one (whitespace does
    // not). The read is local and synchronous; there is nothing to await.
    _note.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _record(StaffDrinkPreviewView preview) async {
    if (_busy) return;
    final bridge = ref.read(bridgeProvider);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      ApprovalView? approval;
      switch (preview.access.outcome) {
        case 'allow':
          break;
        case 'needs_approval':
          if (!mounted) return;
          approval = await askManager(
            context,
            ref,
            reason: preview.access.reason,
            capKey: Cap.ordersStaffDrinkRecord,
            approve: (b, pin) => b.approveStaffDrink(approverPin: pin),
          );
          if (approval == null) {
            if (mounted) setState(() => _busy = false);
            return;
          }
        default:
          if (mounted) {
            setState(() {
              _busy = false;
              _error = preview.access.reason;
            });
          }
          return;
      }
      // MARK the line. Nothing is spent yet: the pool entry is written when
      // the order is charged, with the order.
      await bridge.markStaffDrink(
        tableId: widget.tableId,
        lineKey: widget.line.key,
        note: _note.text,
        approval: approval,
      );
      await _landed(
        '${bridge.tr(key: 'staff_pool.recorded')} · ${widget.line.name}',
        tone: preview.decision.overspent ? ChipTone.warning : ChipTone.success,
      );
    } on MadarError catch (e) {
      MadarHaptics.warning();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e) {
          MadarError_Forbidden(:final action) => action,
          MadarError_Validation(:final detail) => detail,
          _ => e.toString(),
        };
      });
    }
  }

  /// The cart changed in the core: re-read it (lines, totals — the bill
  /// engine has already re-priced), refresh every tile's count, close, toast.
  Future<void> _landed(String toast, {required ChipTone tone}) async {
    MadarHaptics.success();
    ref.invalidate(staffDrinkPreviewProvider);
    await ref.read(cartProvider(widget.tableId).notifier).load();
    if (!mounted) return;
    await Navigator.of(context).maybePop();
    ref.read(orderProvider.notifier).showToast(toast, tone: tone);
  }

  Future<void> _run(Future<void> Function(MadarBridge bridge) act) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await act(ref.read(bridgeProvider));
    } on MadarError catch (e) {
      MadarHaptics.warning();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e) {
          MadarError_Forbidden(:final action) => action,
          MadarError_Validation(:final detail) => detail,
          _ => e.toString(),
        };
      });
    }
  }

  Future<void> _saveNote() => _run((bridge) async {
    await bridge.editStaffDrinkNote(
      tableId: widget.tableId,
      lineKey: widget.line.key,
      note: _note.text,
    );
    await _landed(
      bridge.tr(key: 'staff_pool.note_saved'),
      tone: ChipTone.success,
    );
  });

  Future<void> _remove() => _run((bridge) async {
    await bridge.unmarkStaffDrink(
      tableId: widget.tableId,
      lineKey: widget.line.key,
    );
    await _landed(bridge.tr(key: 'staff_pool.removed'), tone: ChipTone.neutral);
  });

  @override
  Widget build(BuildContext context) {
    final bridge = ref.read(bridgeProvider);
    final colors = context.madarColors;
    final editing = _mark != null;
    final preview = ref.watch(
      staffDrinkPreviewProvider((
        widget.line.itemId,
        widget.line.sizeLabel,
        widget.line.qty,
        editing ? widget.line.key : null,
      )),
    );
    // Asked WITH the typed note, so the refusal and the warning are about what
    // the teller has actually written, not about an empty field.
    StaffDrinkPreviewView? typed;
    try {
      typed = bridge.previewStaffDrink(input: _input);
    } on Object {
      typed = preview;
    }
    final v = typed ?? preview;
    final canSave = v != null && v.decision.allowed && !_busy;

    // The words and the note scroll; the action is pinned under them. With the
    // keyboard up on an iPad in landscape a sheet keeps ~350 px, and a Column
    // that could not scroll overflowed and left "Mark as staff drink" under
    // the keys (T2 B1).
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.fromSTEB(
              Space.xl,
              Space.xl,
              Space.xl,
              Space.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.lg,
              children: [
                Text(
                  bridge.tr(
                    key: editing ? 'staff_pool.edit_title' : 'staff_pool.title',
                  ),
                  style: MadarType.h2,
                ),
                Text(
                  bridge.tr(key: 'staff_pool.subtitle'),
                  style: MadarType.bodySm.copyWith(color: colors.textSecondary),
                ),
                Row(
                  spacing: Space.sm,
                  children: [
                    Flexible(
                      child: Text(
                        widget.line.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.title.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                    if (v != null)
                      MadarTag(
                        label: v.poolLabel,
                        tone: v.decision.overspent
                            ? MadarTone.warning
                            : MadarTone.neutral,
                      ),
                  ],
                ),
                if (v != null && v.overWarning.isNotEmpty)
                  MadarCard(
                    child: Row(
                      spacing: Space.sm,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MadarGlyphIcon(
                          MadarGlyph.alertTriangle,
                          size: IconSize.sm,
                          color: colors.warning,
                        ),
                        Expanded(
                          child: Text(
                            v.overWarning,
                            style: MadarType.bodySm.copyWith(
                              color: colors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Text(
                  bridge.tr(key: 'staff_pool.note'),
                  style: MadarType.label.copyWith(color: colors.textSecondary),
                ),
                MadarField(
                  key: const ValueKey('staff-drink-note'),
                  controller: _note,
                  placeholder: bridge.tr(key: 'staff_pool.note_placeholder'),
                  kind: MadarFieldKind.note,
                  icon: 'text.bubble',
                  autofocus: true,
                ),
                Text(
                  bridge.tr(key: 'staff_pool.note_help'),
                  style: MadarType.bodySm.copyWith(color: colors.textMuted),
                ),
                if (_error case final e? when e.isNotEmpty)
                  Text(
                    e,
                    style: MadarType.bodySm.copyWith(color: colors.danger),
                  )
                else if (v != null &&
                    v.reason.isNotEmpty &&
                    _note.text.isNotEmpty)
                  Text(
                    v.reason,
                    style: MadarType.bodySm.copyWith(color: colors.textMuted),
                  ),
                Text(
                  bridge.tr(key: 'staff_pool.in_cart_note'),
                  textAlign: TextAlign.center,
                  style: MadarType.bodySm.copyWith(color: colors.textMuted),
                ),
                if (v != null)
                  Text(
                    bridge.tr(key: 'staff_pool.resets'),
                    textAlign: TextAlign.center,
                    style: MadarType.bodySm.copyWith(color: colors.textMuted),
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.xl,
            0,
            Space.xl,
            Space.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              if (editing) ...[
                MadarButton(
                  key: const ValueKey('staff-drink-save-note'),
                  label: bridge.tr(key: 'staff_pool.save_note'),
                  loading: _busy,
                  // The note stays required: a staff drink with no note is
                  // not one.
                  enabled: !_busy && _note.text.trim().isNotEmpty,
                  onTap: () => unawaited(_saveNote()),
                ),
                MadarButton(
                  key: const ValueKey('staff-drink-remove'),
                  label: bridge.tr(key: 'staff_pool.remove'),
                  variant: MadarButtonVariant.danger,
                  enabled: !_busy,
                  onTap: () => unawaited(_remove()),
                ),
              ] else
                MadarButton(
                  key: const ValueKey('staff-drink-save'),
                  label: bridge.tr(key: 'staff_pool.record'),
                  loading: _busy,
                  // Dead until there is a note. An overspend is NOT a reason to
                  // disable it — that is the whole point of the warning above.
                  enabled: canSave,
                  onTap: () => v == null ? null : unawaited(_record(v)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
