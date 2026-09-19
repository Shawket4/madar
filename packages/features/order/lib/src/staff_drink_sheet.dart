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
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The core's verdict on putting a cart line on the pool, re-asked whenever the
/// order tables move. Synchronous in the core (local rows, no network), so the
/// tile can decide to draw itself inside one build.
// ignore: specify_nonobvious_property_types  (Riverpod 3 infers the family)
final staffDrinkPreviewProvider = Provider.autoDispose
    .family<StaffDrinkPreviewView?, (String, String?, int)>((ref, key) {
      final bridge = ref.read(bridgeProvider);
      try {
        return bridge.previewStaffDrink(
          input: StaffDrinkInput(
            menuItemId: key.$1,
            sizeLabel: key.$2,
            quantity: key.$3,
            note: '',
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
class StaffDrinkTile extends ConsumerWidget {
  const StaffDrinkTile({required this.line, this.tableId, super.key});

  final CartLineView line;
  final String? tableId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(
      staffDrinkPreviewProvider((line.itemId, line.sizeLabel, line.qty)),
    );
    if (preview == null || !preview.offered) return const SizedBox.shrink();
    final bridge = ref.read(bridgeProvider);
    final label = bridge.tr(key: 'staff_pool.action');
    return Tooltip(
      message: label,
      child: MadarGlyphTile(
        key: ValueKey('staff-drink-${line.key}'),
        glyph: MadarGlyph.users,
        semanticLabel: label,
        onTap: () => unawaited(
          showStaffDrinkSheet(context, ref, line: line, tableId: tableId),
        ),
      ),
    );
  }
}

/// The sheet: the pool as it stands, the required note, and Record.
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

  StaffDrinkInput get _input => StaffDrinkInput(
    menuItemId: widget.line.itemId,
    sizeLabel: widget.line.sizeLabel,
    quantity: widget.line.qty,
    note: _note.text,
  );

  @override
  void initState() {
    super.initState();
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
      final done = await bridge.recordStaffDrink(
        input: _input,
        approval: approval,
      );
      MadarHaptics.success();
      if (!mounted) return;
      // The line's tile re-reads the pool at once: the count on the NEXT line
      // of the same cart must not still say what it said before this drink.
      ref.invalidate(staffDrinkPreviewProvider);
      Navigator.of(context).maybePop();
      ref
          .read(orderProvider.notifier)
          .showToast(
            '${done.message} · ${done.itemName}',
            tone: done.overspent ? ChipTone.warning : ChipTone.success,
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

  @override
  Widget build(BuildContext context) {
    final bridge = ref.read(bridgeProvider);
    final colors = context.madarColors;
    final preview = ref.watch(
      staffDrinkPreviewProvider((
        widget.line.itemId,
        widget.line.sizeLabel,
        widget.line.qty,
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

    return Padding(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Text(bridge.tr(key: 'staff_pool.title'), style: MadarType.h2),
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
                  style: MadarType.title.copyWith(color: colors.textPrimary),
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
                      style: MadarType.bodySm.copyWith(color: colors.warning),
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
            Text(e, style: MadarType.bodySm.copyWith(color: colors.danger))
          else if (v != null && v.reason.isNotEmpty && _note.text.isNotEmpty)
            Text(
              v.reason,
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
          MadarButton(
            key: const ValueKey('staff-drink-save'),
            label: bridge.tr(key: 'staff_pool.record'),
            loading: _busy,
            // Dead until there is a note. An overspend is NOT a reason to
            // disable it — that is the whole point of the warning above.
            enabled: canSave,
            onTap: () => v == null ? null : unawaited(_record(v)),
          ),
          if (v != null)
            Text(
              bridge.tr(key: 'staff_pool.resets'),
              textAlign: TextAlign.center,
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
        ],
      ),
    );
  }
}
