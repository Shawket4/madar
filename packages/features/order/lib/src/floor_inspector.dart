// The floor's inspector — the panel beside the room on an iPad and a desktop,
// under it on a portrait iPad, and the sheet a phone opens.
//
// Nothing selected: the worklist — the tables that owe the room a person
// (food up, plates to clear, a long wait, a booking whose hold has begun).
// A table selected: who is there and for how long, the bill so far, and the
// acts its state allows, most likely first. The same widget in all three
// places, so a teller who learns it once has learnt it everywhere.
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/floor_list.dart';
import 'package:feature_order/src/table_glyph.dart';
import 'package:flutter/material.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// The words the inspector needs, resolved by the screen.
typedef FloorWord = String Function(String key);

/// A table's state as a status pill — the same tones as the plan.
MadarStatus floorStatusOf(TableGlyphState s, FloorWord w) => switch (s) {
  TableGlyphState.free => MadarStatus(
    w('tables.free'),
    glyph: MadarGlyph.hollow,
  ),
  TableGlyphState.seated => MadarStatus(
    w('tables.seated'),
    tone: MadarTone.accent,
    glyph: MadarGlyph.users,
  ),
  TableGlyphState.bill => MadarStatus(
    w('tables.seated'),
    tone: MadarTone.accent,
    glyph: MadarGlyph.receipt,
  ),
  TableGlyphState.ready => MadarStatus(
    w('bill.ready'),
    tone: MadarTone.success,
    glyph: MadarGlyph.checkCircle,
  ),
  TableGlyphState.needsClearing => MadarStatus(
    w('tables.needs_clearing'),
    tone: MadarTone.danger,
    glyph: MadarGlyph.sparkle,
  ),
  TableGlyphState.reserved => MadarStatus(
    w('tables.reserved'),
    tone: MadarTone.warning,
    glyph: MadarGlyph.calendar,
  ),
  TableGlyphState.held => MadarStatus(
    w('tables.held_res'),
    tone: MadarTone.warning,
    glyph: MadarGlyph.lock,
  ),
};

/// The rail tone a row carries — the plan's colour for that state.
MadarTone floorToneOf(FloorUrgency u) => switch (u) {
  FloorUrgency.needsClearing => MadarTone.danger,
  FloorUrgency.foodReady => MadarTone.success,
  FloorUrgency.seated => MadarTone.accent,
  FloorUrgency.reserved => MadarTone.warning,
  FloorUrgency.free => MadarTone.neutral,
};

/// Nothing selected: what needs a person, as rows. Tapping one selects it;
/// the one-tap acts (Cleared, Charge, Seat this party) sit on the row.
class FloorWorklist extends StatelessWidget {
  const FloorWorklist({
    required this.rows,
    required this.now,
    required this.currency,
    required this.locale,
    required this.word,
    required this.canCharge,
    required this.onSelect,
    required this.onAction,
    super.key,
  });

  /// Already filtered by [needsAttention].
  final List<FloorRow> rows;
  final DateTime now;
  final String currency;
  final String locale;
  final FloorWord word;
  final bool canCharge;
  final ValueChanged<FloorTableStateView> onSelect;
  final void Function(FloorAction action, FloorTableStateView table) onAction;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsetsDirectional.all(Space.xl),
          child: EmptyState(
            icon: 'checkmark.circle',
            title: word('floor.all_calm_title'),
            message: word('floor.all_calm_desc'),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsetsDirectional.symmetric(vertical: Space.lg),
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: Space.card,
          ),
          child: MadarSectionHeader(
            text: word('floor.needs_attention'),
            trailing: Text(
              '${rows.length}',
              textDirection: TextDirection.ltr,
              style: MadarType.numMd.copyWith(
                color: context.madarColors.textSecondary,
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) const MadarHairline(light: true),
          _row(r, context.madarColors),
        ],
      ],
    );
  }

  Widget _row(FloorRow r, MadarColors colors) {
    final state = tableGlyphState(r.table, r.ticket, now: now);
    final seated = r.seatedFor(now);
    final (FloorAction? cta, String? ctaLabel) = switch (r.urgency) {
      FloorUrgency.needsClearing => (
        FloorAction.cleared,
        word('floor.cleared'),
      ),
      FloorUrgency.foodReady when canCharge && r.ticket != null => (
        FloorAction.charge,
        word('sell.charge'),
      ),
      FloorUrgency.reserved => (FloorAction.seatBooking, word('floor.seat')),
      _ => (null, null),
    };
    final reason = switch (r.urgency) {
      FloorUrgency.seated => word('floor.waiting_long'),
      _ => floorStatusOf(state, word).label,
    };
    return MadarListRow.bill(
      key: ValueKey('floor.worklist.${r.table.id}'),
      title: r.table.label,
      meta: [
        reason,
        if (seated != null) MadarFormat.elapsed(seated, locale: locale),
        if (r.urgency == FloorUrgency.reserved) ?r.table.bookingGuest,
      ].join(' · '),
      minor: r.model.billTotalMinor,
      currency: currency,
      rail: floorToneOf(r.urgency),
      railColor: r.urgency == FloorUrgency.seated ? colors.info : null,
      ctaLabel: ctaLabel,
      onCta: cta == null ? null : () => onAction(cta, r.table),
      onTap: () => onSelect(r.table),
      chevron: false,
    );
  }
}

/// One table, in full: the header, the bill so far, the acts its state
/// allows, and the door to its history. [onClose] shows a close tile (the
/// docked panel); a sheet passes null and closes itself.
class FloorTableDetail extends StatefulWidget {
  const FloorTableDetail({
    required this.table,
    required this.ticket,
    required this.now,
    required this.currency,
    required this.locale,
    required this.word,
    required this.canCharge,
    required this.onAction,
    this.sectionName,
    this.pendingCovers,
    this.hasArrivals = false,
    this.timeOf,
    this.onClose,
    this.scrollable = true,
    super.key,
  });

  final FloorTableStateView table;
  final TicketView? ticket;
  final DateTime now;
  final String currency;
  final String locale;
  final FloorWord word;
  final bool canCharge;
  final String? sectionName;

  /// Covers the host counted on this device before a bill carried any.
  final int? pendingCovers;

  /// Today has bookings to seat — offers "Seat a booking here" on a free table.
  final bool hasArrivals;

  /// Branch-zone clock for an RFC3339 instant.
  final String Function(String rfc3339)? timeOf;
  final VoidCallback? onClose;
  final bool scrollable;

  /// `covers` is the party size on [FloorAction.seat]; `takeOrder` goes
  /// straight to the order after seating.
  final void Function(FloorAction action, {int? covers, bool? takeOrder})
  onAction;

  @override
  State<FloorTableDetail> createState() => _FloorTableDetailState();
}

class _FloorTableDetailState extends State<FloorTableDetail> {
  late int _covers = _defaultCovers;

  int get _defaultCovers => widget.table.seats.clamp(1, 20);

  @override
  void didUpdateWidget(FloorTableDetail old) {
    super.didUpdateWidget(old);
    if (old.table.id != widget.table.id) _covers = _defaultCovers;
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final colors = context.madarColors;
    final t = w.table;
    final model = FloorTableModel(table: t, ticket: w.ticket, now: w.now);
    final state = tableGlyphState(t, w.ticket, now: w.now);
    final seated = model.seatedFor(w.now);
    final covers = model.covers ?? w.pendingCovers;
    final guest = (w.ticket?.customerName ?? t.heldOrderName ?? t.bookingGuest)
        ?.trim();
    final bookedAt = t.bookingStartsAt == null
        ? null
        : w.timeOf?.call(t.bookingStartsAt!);

    final facts = <String>[
      if (covers != null && model.occupied)
        '$covers ${w.word('tables.guests')}',
      if (!model.occupied) '${t.seats} ${w.word('tables.seats')}',
      ?model.server,
      if (guest != null && guest.isNotEmpty) guest,
      if (state == TableGlyphState.reserved && bookedAt != null)
        MadarFormat.ltr(bookedAt),
      if (w.ticket?.ticketRef case final r?) MadarFormat.ltr(r),
    ];

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.xs,
            children: [
              Row(
                spacing: Space.sm,
                children: [
                  Flexible(
                    child: Text(
                      t.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MadarType.h2.copyWith(color: colors.textPrimary),
                    ),
                  ),
                  if (w.sectionName != null)
                    Flexible(
                      child: Text(
                        w.sectionName!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MadarType.bodySm.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                ],
              ),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  MadarStatusPill(floorStatusOf(state, w.word)),
                  if (seated != null)
                    _Clock(
                      text: MadarFormat.elapsed(seated, locale: w.locale),
                      tone: waitTone(seated),
                    ),
                  if (w.ticket?.queuedOffline ?? false)
                    MadarStatusPill(
                      MadarStatus(
                        w.word('bill.queued'),
                        tone: MadarTone.warning,
                        glyph: MadarGlyph.wifiOff,
                      ),
                    ),
                ],
              ),
              if (facts.isNotEmpty)
                Text(
                  facts.join(' · '),
                  style: MadarType.bodySm.copyWith(color: colors.textSecondary),
                ),
            ],
          ),
        ),
        if (w.onClose != null)
          MadarGlyphTile(
            key: const ValueKey('floor.inspector.close'),
            glyph: MadarGlyph.close,
            semanticLabel: w.word('common.close'),
            onTap: w.onClose!,
          ),
      ],
    );

    final children = <Widget>[
      header,
      if (w.ticket != null) ...[
        const SizedBox(height: Space.lg),
        _BillPreview(
          ticket: w.ticket!,
          currency: w.currency,
          word: w.word,
          timeOf: w.timeOf,
          onOpen: () => w.onAction(FloorAction.openBill),
        ),
      ],
      const SizedBox(height: Space.lg),
      ..._actions(context, model, state),
      const SizedBox(height: Space.lg),
      MadarCard(
        flush: true,
        child: MadarListRow.nav(
          key: const ValueKey('floor.inspector.history'),
          title: w.word('tables.history'),
          meta: w.word('tables.history_hint'),
          glyph: MadarGlyph.clock,
          onTap: () => w.onAction(FloorAction.history),
        ),
      ),
    ];
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    if (!w.scrollable) {
      return Padding(
        padding: const EdgeInsetsDirectional.all(Space.card),
        child: column,
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(Space.card),
      child: column,
    );
  }
}

extension on _FloorTableDetailState {
  /// The acts, by state: one primary, then the rest in likely order, then
  /// the destructive one last and quiet. Two-up where there is room.
  List<Widget> _actions(
    BuildContext context,
    FloorTableModel model,
    TableGlyphState state,
  ) {
    final w = widget;
    final word = w.word;
    MadarButton button(
      FloorAction a,
      String label, {
      MadarGlyph? glyph,
      MadarButtonVariant variant = MadarButtonVariant.secondary,
      Key? key,
      Widget? trailing,
    }) => MadarButton(
      key: key ?? ValueKey('floor.action.${a.name}'),
      label: label,
      glyph: glyph,
      variant: variant,
      trailing: trailing,
      onTap: () => w.onAction(a),
    );
    // Two-up where both labels fit; stacked in a phone's sheet.
    Widget pair(Widget a, Widget b) => LayoutBuilder(
      builder: (context, box) => box.maxWidth < 356
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: Space.sm,
              children: [a, b],
            )
          : Row(
              spacing: Space.sm,
              children: [
                Expanded(child: a),
                Expanded(child: b),
              ],
            ),
    );
    final acts = model.actions(canCharge: w.canCharge);
    final out = <Widget>[];

    switch (state) {
      case TableGlyphState.free || TableGlyphState.held:
        out
          ..add(MadarSectionHeader(text: word('floor.party_size')))
          ..add(const SizedBox(height: Space.sm))
          ..add(
            Row(
              children: [
                MadarStepper(
                  value: _covers,
                  min: 1,
                  max: 99,
                  onChanged: (n) => setState(() => _covers = n),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    '${w.table.seats} ${word('tables.seats')}',
                    style: MadarType.bodySm.copyWith(
                      color: context.madarColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          )
          ..add(const SizedBox(height: Space.lg))
          ..add(
            MadarButton(
              key: const ValueKey('floor.seat_and_order'),
              label: word('floor.seat_and_order'),
              glyph: MadarGlyph.receipt,
              onTap: () => w.onAction(
                FloorAction.seat,
                covers: _covers,
                takeOrder: true,
              ),
            ),
          )
          ..add(const SizedBox(height: Space.sm))
          ..add(
            MadarButton(
              key: const ValueKey('floor.action.seat'),
              label: word('floor.seat'),
              glyph: MadarGlyph.users,
              variant: MadarButtonVariant.secondary,
              onTap: () => w.onAction(FloorAction.seat, covers: _covers),
            ),
          );
        if (w.hasArrivals) {
          out
            ..add(const SizedBox(height: Space.sm))
            ..add(
              button(
                FloorAction.seatBooking,
                word('floor.seat_booking_here'),
                glyph: MadarGlyph.calendar,
                variant: MadarButtonVariant.ghost,
              ),
            );
        }
      case TableGlyphState.needsClearing:
        out.add(
          button(
            FloorAction.cleared,
            word('floor.cleared'),
            glyph: MadarGlyph.check,
            variant: MadarButtonVariant.primary,
          ),
        );
      case TableGlyphState.reserved:
        out
          ..add(
            button(
              FloorAction.seatBooking,
              word('tables.seat_booking'),
              glyph: MadarGlyph.users,
              variant: MadarButtonVariant.primary,
            ),
          )
          ..add(const SizedBox(height: Space.sm))
          ..add(
            pair(
              button(FloorAction.noShow, word('tables.no_show')),
              button(
                FloorAction.walkIn,
                word('floor.walk_in_here'),
                variant: MadarButtonVariant.ghost,
              ),
            ),
          );
      case TableGlyphState.seated:
        out
          ..add(
            button(
              FloorAction.takeOrder,
              word('floor.take_order'),
              glyph: MadarGlyph.receipt,
              variant: MadarButtonVariant.primary,
            ),
          )
          ..add(const SizedBox(height: Space.sm))
          ..add(
            button(
              FloorAction.move,
              word('floor.move'),
              glyph: MadarGlyph.move,
            ),
          )
          ..add(const SizedBox(height: Space.sm))
          ..add(
            pair(
              button(
                FloorAction.openBill,
                word('floor.open_bill'),
                variant: MadarButtonVariant.ghost,
              ),
              button(
                FloorAction.unseat,
                word('floor.unseat'),
                variant: MadarButtonVariant.ghost,
              ),
            ),
          );
      case TableGlyphState.bill || TableGlyphState.ready:
        if (acts.contains(FloorAction.charge)) {
          out
            ..add(
              button(
                FloorAction.charge,
                word('sell.charge'),
                glyph: MadarGlyph.check,
                variant: MadarButtonVariant.primary,
                trailing: model.billTotalMinor == null
                    ? null
                    : MoneyText(
                        model.billTotalMinor!,
                        currency: w.currency,
                        color: context.madarColors.textOnAccent,
                      ),
              ),
            )
            ..add(const SizedBox(height: Space.sm));
        }
        out
          ..add(
            pair(
              button(
                FloorAction.addRound,
                word('tables.add_round'),
                glyph: MadarGlyph.plus,
                variant: w.canCharge
                    ? MadarButtonVariant.secondary
                    : MadarButtonVariant.primary,
              ),
              button(
                FloorAction.move,
                word('floor.move'),
                glyph: MadarGlyph.move,
              ),
            ),
          )
          ..add(const SizedBox(height: Space.sm))
          ..add(
            pair(
              button(
                FloorAction.openBill,
                word('floor.open_bill'),
                glyph: MadarGlyph.receipt,
                variant: MadarButtonVariant.ghost,
              ),
              button(
                FloorAction.voidBill,
                word('bill.void_bill'),
                glyph: MadarGlyph.trash,
                variant: MadarButtonVariant.ghost,
              ),
            ),
          );
    }
    return out;
  }
}

/// The bill so far: each round collapsed to one line, then the total.
class _BillPreview extends StatelessWidget {
  const _BillPreview({
    required this.ticket,
    required this.currency,
    required this.word,
    required this.onOpen,
    this.timeOf,
  });

  final TicketView ticket;
  final String currency;
  final FloorWord word;
  final VoidCallback onOpen;
  final String Function(String rfc3339)? timeOf;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final rounds = groupBillByRound(ticket.lines);
    final total = ticket.bill?.totalMinor ?? ticket.subtotalMinor;
    return MadarCard(
      flush: true,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(Radii.card),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            Space.card,
            Space.md,
            Space.card,
            Space.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (rounds.isEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: Space.sm),
                  child: Text(
                    word('tables.bill_pending'),
                    style: MadarType.bodySm.copyWith(color: colors.textMuted),
                  ),
                ),
              for (final r in rounds)
                MadarSummaryLine(
                  label: [
                    '${word('tables.round')} ${r.number}',
                    if (r.firedAt.isNotEmpty && timeOf != null)
                      MadarFormat.ltr(timeOf!(r.firedAt)),
                  ].join(' · '),
                  minor: r.lines
                      .where((l) => !l.voided)
                      .fold<int>(0, (n, l) => n + l.lineTotalMinor),
                  currency: currency,
                  muted: true,
                ),
              const MadarHairline(light: true),
              MadarSummaryLine(
                label: word(
                  ticket.bill == null ? 'order.subtotal' : 'order.total',
                ),
                minor: total,
                currency: currency,
                emphasis: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The table's clock, amber then red as the wait grows.
class _Clock extends StatelessWidget {
  const _Clock({required this.text, required this.tone});

  final String text;
  final MadarTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final ink = tone == MadarTone.neutral
        ? colors.textSecondary
        : tone.color(colors);
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs,
      children: [
        MadarGlyphIcon(MadarGlyph.clock, size: IconSize.xs, color: ink),
        Text(text, style: MadarType.numMd.copyWith(color: ink)),
      ],
    );
  }
}
