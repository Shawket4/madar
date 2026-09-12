import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// Family TYPE annotations moved to the misc library in Riverpod 3.
import 'package:flutter_riverpod/misc.dart';
import 'package:rust_bridge/rust_bridge.dart';

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
