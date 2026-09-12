import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/tables_screen.dart';
import 'package:feature_order/src/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Family TYPE annotations moved to the misc library in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Covers stepper for one fire-details presentation, keyed by an identity
/// token the sheet creates per open (so a fresh sheet always starts at 0).
class CoversNotifier extends Notifier<int> {
  /// Creates the notifier for one family [arg].
  CoversNotifier(this.arg);

  /// Family key (one counter per presented sheet).
  final Object arg;

  @override
  int build() => 0;

  void inc() => state = state + 1;

  void dec() => state = state > 0 ? state - 1 : 0;
}

final NotifierProviderFamily<CoversNotifier, int, Object> _coversProvider =
    NotifierProvider.autoDispose.family<CoversNotifier, int, Object>(
      CoversNotifier.new,
    );

/// Dine-in capture before a waiter fires a NEW ticket: customer, table,
/// covers, kitchen notes — all optional, all passed to the core.
class FireDetailsSheet extends ConsumerStatefulWidget {
  const FireDetailsSheet({super.key});

  @override
  ConsumerState<FireDetailsSheet> createState() => _FireDetailsSheetState();
}

class _FireDetailsSheetState extends ConsumerState<FireDetailsSheet> {
  final _customer = TextEditingController();
  final _table = TextEditingController();
  final _notes = TextEditingController();

  /// The picked floor table (branches WITH a layout replace the free-text
  /// field with the picker; the table stays optional either way — outside
  /// orders are a normal daily case).
  String? _tableId;
  String? _tableLabel;

  /// Identity key for this presentation's covers state.
  final Object _coversKey = Object();

  @override
  void initState() {
    super.initState();
    // A table picked on the floor canvas is already bound to the cart. Without
    // this the sheet opened blank and the table was silently forgotten by the
    // time the order fired — the canvas gesture looked like it had worked and
    // had not.
    final s = ref.read(orderProvider);
    _tableId = s.cartTableId;
    _tableLabel = s.cartTableLabel;
  }

  @override
  void dispose() {
    _customer.dispose();
    _table.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _fire() async {
    String? blank(String v) => v.trim().isEmpty ? null : v.trim();
    final covers = ref.read(_coversProvider(_coversKey));
    final ok = await ref
        .read(orderProvider.notifier)
        .fireOrAddRound(
          customerName: blank(_customer.text),
          tableId: _tableId ?? blank(_table.text),
          notes: blank(_notes.text),
          guestCount: covers > 0 ? covers : null,
        );
    if (ok && mounted) {
      await Navigator.of(context).maybePop();
    }
  }

  Future<void> _pickTable() async {
    final pick = await showTablePickerSheet(context, ref);
    if (pick == null || !mounted) return;
    setState(() {
      _tableId = pick.tableId;
      _tableLabel = pick.label;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final covers = ref.watch(_coversProvider(_coversKey));
    final coversNotifier = ref.read(_coversProvider(_coversKey).notifier);
    final isBusy = ref.watch(orderProvider.select((s) => s.isBusy));
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bridge.tr(key: 'waiter.fire'),
            style: MadarType.h2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: Space.md),
          MadarField(
            controller: _customer,
            placeholder: bridge.tr(key: 'waiter.customer_optional'),
            icon: 'person',
          ),
          const SizedBox(height: Space.md),
          // With a floor layout: the real table picker. Without one: the old
          // free-text field (nothing blocks a branch that never drew a floor).
          if (ref.watch(orderProvider.select((s) => s.hasFloor)))
            MadarButton(
              label: _tableLabel == null
                  ? bridge.tr(key: 'tables.pick')
                  : '${bridge.tr(key: 'order.table')} · $_tableLabel',
              icon: 'square.grid.2x2',
              variant: MadarButtonVariant.outline,
              onTap: () => unawaited(_pickTable()),
            )
          else
            MadarField(
              controller: _table,
              placeholder: bridge.tr(key: 'waiter.table'),
              icon: 'square.grid.2x2',
            ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  bridge.tr(key: 'waiter.covers'),
                  style: MadarType.title.copyWith(color: colors.textSecondary),
                ),
              ),
              _CoverStepBox(icon: 'minus', onTap: coversNotifier.dec),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 28 + Space.md * 2),
                child: Text(
                  '$covers',
                  textAlign: TextAlign.center,
                  style: MadarType.h3.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              _CoverStepBox(icon: 'plus', onTap: coversNotifier.inc),
            ],
          ),
          const SizedBox(height: Space.md),
          MadarField(
            controller: _notes,
            placeholder: bridge.tr(key: 'order.notes_hint'),
            icon: 'text.bubble',
          ),
          const SizedBox(height: Space.md),
          MadarButton(
            label: bridge.tr(key: 'waiter.fire'),
            icon: 'arrow.up.circle',
            loading: isBusy,
            onTap: () => unawaited(_fire()),
          ),
        ],
      ),
    );
  }
}

class _CoverStepBox extends StatelessWidget {
  const _CoverStepBox({required this.icon, required this.onTap});

  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      scale: MotionSpec.pressScaleKey,
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        width: kSquareControl,
        height: kSquareControl,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: colors.surfaceAlt,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: colors.border),
        ),
        child: MadarIcon(icon, tint: colors.textPrimary),
      ),
    );
  }
}

/// The void sheet's confirm payload — wraps the (nullable) free-form reason
/// so a dismissed sheet (null result) is distinguishable from "no reason".
@immutable
class VoidTicketResult {
  const VoidTicketResult(this.reason);

  final String? reason;
}

/// The picked void-reason key for one void-sheet presentation, keyed by an
/// identity token the sheet creates per open.
class VoidReasonNotifier extends Notifier<String?> {
  /// Creates the notifier for one family [arg].
  VoidReasonNotifier(this.arg);

  /// Family key (one selection per presented sheet).
  final Object arg;

  @override
  String? build() => null;

  /// Not a setter — Notifier state writes are method-guarded.
  // ignore: use_setters_to_change_properties
  void pick(String key) => state = key;
}

final NotifierProviderFamily<VoidReasonNotifier, String?, Object>
_voidReasonProvider = NotifierProvider.autoDispose
    .family<VoidReasonNotifier, String?, Object>(VoidReasonNotifier.new);

/// Compact confirmation for voiding an OPEN ticket from the waiter cart: a
/// reason picker + free-text note (the shared `void.*` keys) and a
/// Cancel / danger-Void pair. Pops a [VoidTicketResult] on confirm.
class WaiterVoidSheet extends ConsumerStatefulWidget {
  const WaiterVoidSheet({required this.ticket, this.lineLabel, super.key});

  final TicketView ticket;

  /// Set when ONE line is being voided rather than the whole bill — the
  /// line's own words ("2× Calamari"), so the sheet says which plate is
  /// coming off. The two acts are near enough identical to share a sheet and
  /// far enough apart that the header must not be ambiguous about which is
  /// about to happen.
  final String? lineLabel;

  @override
  ConsumerState<WaiterVoidSheet> createState() => _WaiterVoidSheetState();
}

class _WaiterVoidSheetState extends ConsumerState<WaiterVoidSheet> {
  static const _reasonKeys = [
    'void.reason_mistake',
    'void.reason_customer',
    'void.reason_quality',
    'void.reason_other',
  ];

  final _note = TextEditingController();

  /// Identity key for this presentation's picked-reason state.
  final Object _reasonStateKey = Object();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _confirm() {
    // A single free-form reason: the picked label + the note (either may be
    // absent — voidTicket accepts a null reason).
    final reasonKey = ref.read(_voidReasonProvider(_reasonStateKey));
    final picked = reasonKey == null
        ? null
        : ref.read(bridgeProvider).tr(key: reasonKey);
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final reason = [?picked, ?note].join(' — ');
    Navigator.of(
      context,
    ).maybePop(VoidTicketResult(reason.isEmpty ? null : reason));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final bridge = ref.bridge;
    final reasonKey = ref.watch(_voidReasonProvider(_reasonStateKey));
    final reasonNotifier = ref.read(
      _voidReasonProvider(_reasonStateKey).notifier,
    );
    final ticketRef = widget.ticket.ticketRef;
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(Space.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  bridge.tr(key: 'void.title'),
                  style: MadarType.h2.copyWith(color: colors.textPrimary),
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                behavior: HitTestBehavior.opaque,
                child: MadarIcon('xmark', tint: colors.textMuted),
              ),
            ],
          ),
          if ([?ticketRef?.ifNotEmpty, ?widget.lineLabel].join(' · ')
              case final sub when sub.isNotEmpty) ...[
            const SizedBox(height: Space.xs),
            Text(
              sub,
              style: MadarType.bodySm.copyWith(
                color: widget.lineLabel == null
                    ? colors.textSecondary
                    : colors.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: Space.md),
          Text(
            bridge.tr(key: 'void.reason'),
            style: MadarType.label.copyWith(
              fontWeight: FontWeight.w700,
              color: colors.textMuted,
            ),
          ),
          const SizedBox(height: Space.sm),
          for (final key in _reasonKeys) ...[
            _VoidReasonRow(
              label: bridge.tr(key: key),
              active: reasonKey == key,
              onTap: () => reasonNotifier.pick(key),
            ),
            const SizedBox(height: Space.sm),
          ],
          MadarField(
            controller: _note,
            placeholder: bridge.tr(key: 'void.note'),
            icon: 'note.text',
          ),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Expanded(
                child: MadarButton(
                  label: bridge.tr(key: 'void.cancel'),
                  variant: MadarButtonVariant.outline,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: MadarButton(
                  label: bridge.tr(key: 'void.confirm'),
                  variant: MadarButtonVariant.danger,
                  icon: 'trash',
                  onTap: _confirm,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single selectable void-reason row — a radio glyph + label,
/// danger-tinted when picked.
class _VoidReasonRow extends StatelessWidget {
  const _VoidReasonRow({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    return TactileScale(
      scale: 0.99,
      onTap: () {
        MadarHaptics.selection();
        onTap();
      },
      child: Container(
        padding: const EdgeInsetsDirectional.all(Space.md),
        decoration: BoxDecoration(
          color: active ? colors.dangerBg : colors.surface,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(
            color: active
                ? colors.danger.withValues(alpha: Opacities.disabled)
                : colors.border,
          ),
        ),
        child: Row(
          children: [
            MadarIcon(
              active ? 'largecircle.fill.circle' : 'circle',
              tint: active ? colors.danger : colors.textMuted,
              size: IconSize.lg,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                label,
                style: MadarType.body.copyWith(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

extension on String {
  String? get ifNotEmpty => isEmpty ? null : this;
}
