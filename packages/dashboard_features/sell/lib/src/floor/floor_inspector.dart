/// The inspector: what is selected and what can be changed about it — the
/// web's `properties-panel.tsx` and `table-history.tsx` (SELL-FLR-057 –
/// 072, -084).
///
/// Blueprint only: label, seats, shape, rotation. Live status belongs to the
/// POS, so there is no status setter here; the one READING beside the table
/// is who sits there now and what it has done in the last 30 days.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/customer_link.dart';
import '../shared/invalidate.dart';
import 'floor_providers.dart';
import 'floor_util.dart';
import '../shared/error_text.dart';

class FloorInspector extends ConsumerWidget {
  const FloorInspector({
    required this.tables,
    required this.sections,
    required this.editable,
    required this.geoOf,
    required this.onRotate,
    required this.customers,
    required this.adoptToken,
    this.sittingNow,
    super.key,
  });

  /// The selected tables visible in the current area.
  final List<FloorTable> tables;
  final List<FloorSection> sections;
  final bool editable;
  final GeoItem Function(FloorTable) geoOf;

  /// Rotate every selected table by a step (one undo step, autosaved).
  final ValueChanged<double> onRotate;
  final CustomerLinkControl customers;

  /// Hands a PATCH's new `updated_at` to the layout autosave's guard.
  final void Function(String id, DateTime updatedAt) adoptToken;

  /// The open bill at the one selected table that names its customer.
  final OpenTicketView? sittingNow;

  /// Blueprint patch — label / seats / shape. Not geometry, never status.
  Future<void> _patch(
    BuildContext context,
    WidgetRef ref,
    FloorTable table,
    UpdateFloorTableRequest body,
  ) async {
    final t = ref.read(tProvider);
    final bus = ref.read(realtimeBusProvider);
    try {
      final row = await ref
          .read(apiProvider)
          .reservations
          .updateFloorTable(id: table.id, body: body);
      adoptToken(row.id, row.updatedAt);
      bus.invalidate(SellInvalidate.floor);
    } on Object catch (e) {
      if (context.mounted) DashToast.error(context, sellErrorText(e, t));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final meta = DashType.meta.copyWith(color: c.textSecondary);
    if (tables.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Text(
          t(editable ? 'floor.selectHint' : 'floor.lockedHint'),
          style: meta,
        ),
      );
    }
    final single = tables.length == 1 ? tables.single : null;
    final seatsTotal = tables.fold<int>(0, (s, tb) => s + tb.seats);
    final g = single == null ? null : geoOf(single);
    final hairline = BorderSide(color: c.hairline);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.md,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                spacing: Space.sm,
                children: [
                  Expanded(
                    child: MadarClippedText(
                      single?.label ??
                          t('floor.selectedCount', count: tables.length),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                    ),
                  ),
                  Text(t('floor.seatsTotal', count: seatsTotal), style: meta),
                ],
              ),
              if (single != null && g != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.sm,
                  children: [
                    Expanded(
                      child: _Labelled(
                        label: t('floor.tableLabel'),
                        child: _CommitInput(
                          key: ValueKey('floor-label-${single.id}'),
                          value: single.label,
                          semanticLabel: t('floor.tableLabel'),
                          onCommit: (v) {
                            if (v.trim().isEmpty) return;
                            _patch(
                              context,
                              ref,
                              single,
                              UpdateFloorTableRequest(label: v.trim()),
                            );
                          },
                        ),
                      ),
                    ),
                    SizedBox(
                      width: _seatsWidth,
                      child: _Labelled(
                        label: t('floor.seats'),
                        child: _CommitInput(
                          key: ValueKey('floor-seats-${single.id}'),
                          value: '${single.seats}',
                          semanticLabel: t('floor.seats'),
                          number: true,
                          onCommit: (v) {
                            // Anything but a whole 0–99 is ignored (the web).
                            final n = int.tryParse(v.trim());
                            if (n == null || n < 0 || n > 99) return;
                            _patch(
                              context,
                              ref,
                              single,
                              UpdateFloorTableRequest(seats: n),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                _Labelled(
                  label: t('floor.shape'),
                  child: DashSegmentedControl<String>(
                    semanticLabel: t('floor.shape'),
                    expand: true,
                    enabled: editable,
                    value: single.shape,
                    options: [
                      DashOption(value: 'rect', label: t('floor.shapeRect')),
                      DashOption(
                        value: 'circle',
                        label: t('floor.shapeCircle'),
                      ),
                    ],
                    onChanged: (s) {
                      if (s == single.shape) return;
                      _patch(
                        context,
                        ref,
                        single,
                        UpdateFloorTableRequest(shape: s),
                      );
                    },
                  ),
                ),
                Text(
                  '${jsRoundInt(g.x)}, ${jsRoundInt(g.y)} · '
                  '${jsRoundInt(g.w)}×${jsRoundInt(g.h)}',
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.start,
                  style: meta.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                // Which area a table belongs to is shown, not chosen.
                Text(
                  sections
                          .where((s) => s.id == single.sectionId)
                          .firstOrNull
                          ?.name ??
                      t('floor.unassigned'),
                  style: meta,
                ),
              ] else
                Text(t('floor.multiHint'), style: meta),
              DecoratedBox(
                decoration: BoxDecoration(border: Border(top: hairline)),
                child: Padding(
                  padding: const EdgeInsets.only(top: Space.md),
                  child: Row(
                    children: [
                      Expanded(child: Text(t('floor.rotation'), style: meta)),
                      DashIconButton(
                        icon: 'rotate-ccw',
                        semanticLabel: t('floor.rotateCcw'),
                        variant: DashButtonVariant.outline,
                        iconSize: IconSize.xs,
                        onPressed: editable
                            ? () => onRotate(-kRotationStep)
                            : null,
                      ),
                      SizedBox(
                        width: Space.xxl + Space.sm,
                        child: Text(
                          g == null
                              ? '—'
                              : '${jsRoundInt(normalizeAngle(g.rot))}°',
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.ltr,
                          style: meta.copyWith(color: c.textPrimary),
                        ),
                      ),
                      DashIconButton(
                        icon: 'rotate-cw',
                        semanticLabel: t('floor.rotateCw'),
                        variant: DashButtonVariant.outline,
                        iconSize: IconSize.xs,
                        onPressed: editable
                            ? () => onRotate(kRotationStep)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (single != null)
          if (sittingNow?.customerName case final name? when name.isNotEmpty)
            DecoratedBox(
              decoration: BoxDecoration(border: Border(top: hairline)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: Row(
                  spacing: Space.md,
                  children: [
                    Text(
                      t('floor.sittingNow'),
                      style: DashType.body.copyWith(color: c.textSecondary),
                    ),
                    Expanded(
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: CustomerLink(
                          name: name,
                          customerId: sittingNow?.customerId,
                          control: customers,
                          style: DashType.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        if (single != null)
          DecoratedBox(
            decoration: BoxDecoration(border: Border(top: hairline)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: Space.lg,
                    end: Space.lg,
                    top: Space.md,
                  ),
                  child: Text(
                    t('floor.history.title'),
                    style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                  ),
                ),
                TableHistoryPanel(tableId: single.id, customers: customers),
              ],
            ),
          ),
      ],
    );
  }
}

/// The Seats field's width (`grid-cols-[1fr_72px]`).
const double _seatsWidth = Space.xxl * 2 + Space.sm;

class _Labelled extends StatelessWidget {
  const _Labelled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: Space.xs,
    children: [
      ExcludeSemantics(
        child: Text(
          label,
          style: DashType.meta.copyWith(
            color: context.madarColors.textSecondary,
          ),
        ),
      ),
      child,
    ],
  );
}

/// A field that keeps its own draft and commits on blur or Enter, when
/// changed (`CommitInput`). A new [value] from the server replaces the draft.
class _CommitInput extends StatefulWidget {
  const _CommitInput({
    required this.value,
    required this.onCommit,
    required this.semanticLabel,
    this.number = false,
    super.key,
  });

  final String value;
  final ValueChanged<String> onCommit;
  final String semanticLabel;
  final bool number;

  @override
  State<_CommitInput> createState() => _CommitInputState();
}

class _CommitInputState extends State<_CommitInput> {
  late String _draft = widget.value;

  /// What was last committed: Enter also blurs the field here, and that
  /// blur must not send the same draft twice.
  String? _sent;

  @override
  void didUpdateWidget(_CommitInput old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _draft = widget.value;
      _sent = null;
    }
  }

  void _commit() {
    if (_draft == widget.value || _draft == _sent) return;
    _sent = _draft;
    widget.onCommit(_draft);
  }

  @override
  Widget build(BuildContext context) => DashTextInput(
    value: _draft,
    semanticLabel: widget.semanticLabel,
    keyboardType: widget.number ? TextInputType.number : null,
    textDirection: widget.number ? TextDirection.ltr : null,
    onChanged: (v) => setState(() => _draft = v),
    onSubmitted: (_) => _commit(),
    onFocusChange: (focused) {
      // Back in the field: a failed save may be sent again.
      if (focused) _sent = null;
      if (!focused) _commit();
    },
  );
}

/// A stay, not a timestamp: `42m` · `1h 05m`; "—" under a minute.
String _stay(DashFormat fmt, int minutes) =>
    minutes < 1 ? '—' : fmt.fmtElapsedMs(minutes * 60000);

/// A table's figures, then what happened — the last 30 days
/// (`TableHistory`, SELL-FLR-067 – 072).
class TableHistoryPanel extends ConsumerWidget {
  const TableHistoryPanel({
    required this.tableId,
    required this.customers,
    super.key,
  });

  final String tableId;
  final CustomerLinkControl customers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final q = ref.watch(floorTableHistoryProvider(tableId));
    final quiet = DashType.meta.copyWith(color: c.textSecondary);
    if (q.awaitingFirst) {
      return const Padding(
        padding: EdgeInsets.all(Space.lg),
        child: Column(
          spacing: Space.sm,
          children: [
            DashSkeleton(height: _figureHeight),
            DashSkeleton(height: _figureHeight),
          ],
        ),
      );
    }
    final data = q.value;
    if (data == null || (q.hasError && !q.retrying)) {
      return Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Text(t('floor.history.failed'), style: quiet),
      );
    }
    if (data.sittings.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Text(t('floor.history.empty'), style: quiet),
      );
    }
    // Turns ride the wire ×100; one decimal is as far as one is read.
    final turns = fmt.fmtNumber(
      data.turnsPerDayX100 / 100,
      const NumberOptions(minimumFractionDigits: 1, maximumFractionDigits: 1),
    );
    Widget figure(String label, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(Space.md),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: Space.xs,
          children: [
            Text(label, style: quiet),
            // A long sum shrinks to fit rather than being cut.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                value,
                maxLines: 1,
                style: DashType.monoStrong.copyWith(
                  fontSize: 18,
                  color: c.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.lg,
        children: [
          Column(
            spacing: Space.sm,
            children: [
              Row(
                spacing: Space.sm,
                children: [
                  figure(
                    t('floor.history.takings'),
                    fmt.fmtMoney(data.totalMinor),
                  ),
                  figure(
                    t('floor.history.avgBill'),
                    fmt.fmtMoney(data.averageBillMinor),
                  ),
                ],
              ),
              Row(
                spacing: Space.sm,
                children: [
                  figure(
                    t('floor.history.avgStay'),
                    _stay(fmt, data.averageMinutes),
                  ),
                  figure(t('floor.history.turns'), turns),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: Space.xs),
                child: Text(
                  t('floor.history.bills'),
                  style: DashType.bodyStrong.copyWith(color: c.textPrimary),
                ),
              ),
              for (final (i, s) in data.sittings.indexed)
                _SittingRow(
                  sitting: s,
                  customers: customers,
                  last: i == data.sittings.length - 1,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A figure tile's height while loading (`h-16`).
const double _figureHeight = Space.xxl * 2;

class _SittingRow extends ConsumerWidget {
  const _SittingRow({
    required this.sitting,
    required this.customers,
    required this.last,
  });

  final TableSitting sitting;
  final CustomerLinkControl customers;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final s = sitting;
    final name = s.customerName?.trim();
    final who = (name == null || name.isEmpty) ? (s.ticketRef ?? '—') : name;
    final covers = s.guestCount ?? 0;
    final line = [
      _stay(fmt, s.minutes),
      if (covers > 0) t('floor.history.covers', count: covers),
    ].join(' · ');
    final total = s.totalAmount;
    // A live bill is still open (a bill marked ready is live too); any other
    // bill without money was voided.
    final live = s.status == 'open' || s.status == 'ready';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.sm),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        spacing: Space.md,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (name != null && name.isNotEmpty)
                  CustomerLink(
                    name: name,
                    customerId: s.customerId,
                    control: customers,
                  )
                else
                  MadarClippedText(
                    who,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashType.body.copyWith(color: c.textPrimary),
                  ),
                Text(
                  line,
                  style: DashType.meta.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          if (total == null)
            DashStatusPill(
              label: t(
                live ? 'floor.history.stillOpen' : 'floor.history.voided',
              ),
              tone: live ? DashTone.accent : DashTone.danger,
              small: true,
            )
          else
            Text(
              fmt.fmtMoney(total),
              style: DashType.mono.copyWith(color: c.textPrimary),
            ),
        ],
      ),
    );
  }
}
