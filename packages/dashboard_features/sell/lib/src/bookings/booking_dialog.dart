/// Create or edit a booking (the web's `features/bookings/booking-dialog.tsx`,
/// SELL-BKG-036 … 059, 078): a date, a party and a time from the day's
/// availability (the server's pick shown per slot) or typed by hand; tables
/// assigned automatically unless the host chooses them; a booking that fits
/// nowhere can be forced in and then "needs a table".
library;

import 'package:dashboard_api/dashboard_api.dart'
    show BookingView, CreateBookingRequest, FloorTable, UpdateBookingRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/invalidate.dart';
import '../shared/phone.dart';
import '../floor/floor_providers.dart'
    show floorSectionsProvider, floorTablesProvider;
import 'booking_errors.dart';
import 'bookings_parts.dart';
import 'bookings_providers.dart';
import 'bookings_util.dart';

/// Opens the dialog: [booking] present = edit it; absent = a new one on
/// [date] (the page's day).
Future<void> showBookingDialog(
  BuildContext context, {
  required String branchId,
  required String date,
  BookingView? booking,
}) => showDashDialog<void>(
  context,
  width: DashMetrics.dialogWide,
  builder: (context) =>
      BookingDialog(branchId: branchId, date: date, booking: booking),
);

/// The availability read [BookingDialog] makes as it opens on [b] (absent:
/// a new booking on [date]).
BookingAvailabilityKey bookingDialogOpenKey(
  String branchId,
  String date,
  BookingView? b,
  String tz,
) => (
  branchId: branchId,
  date: b == null ? date : serviceDateOf(b.startsAt, tz),
  partySize: b?.partySize ?? 2,
  sectionId: b?.sectionId,
  excludeBookingId: b?.id,
);

/// Intent: warms the reads the dialog makes as it opens, with their keys.
void warmBookingDialog(
  WidgetRef ref, {
  required String branchId,
  required String date,
  BookingView? booking,
}) {
  ref
    ..warm(bookingSettingsProvider(branchId))
    ..warm(floorTablesProvider(branchId))
    ..warm(floorSectionsProvider(branchId));
  if (booking != null) {
    ref.warm(bookingDayProvider((branchId: branchId, date: date)));
  }
  final k = bookingDialogOpenKey(
    branchId,
    date,
    booking,
    ref.read(formatProvider).timezone,
  );
  if (k.partySize > 0) ref.warm(bookingAvailabilityProvider(k));
}

class BookingDialog extends ConsumerStatefulWidget {
  const BookingDialog({
    required this.branchId,
    required this.date,
    this.booking,
    super.key,
  });

  final String branchId;
  final String date;
  final BookingView? booking;

  @override
  ConsumerState<BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends ConsumerState<BookingDialog> {
  final _form = GlobalKey<FormState>();
  late final String _tz = ref.read(formatProvider).timezone;
  BookingView? _b;
  late String _day;
  late String _party;
  DateTime? _startsAt;
  late String _customTime;
  late String _duration;
  String? _sectionId;
  late bool _manualTables;
  late List<String> _tableIds;
  late bool _force;
  bool _sendConfirmation = true;
  late String _name;
  late String _phone;
  late String _notes;
  bool _busy = false;
  String? _error;

  /// The values as seeded: while the form still equals them, a fresh read
  /// of the booking re-seeds it.
  late Object _seeded;

  Object get _values => (
    _day,
    _party,
    _startsAt,
    _customTime,
    _duration,
    _sectionId,
    _manualTables,
    _tableIds.join(','),
    _force,
    _name,
    _phone,
    _notes,
  );

  bool get _editing => _b != null;

  @override
  void initState() {
    super.initState();
    _seed(widget.booking);
  }

  void _seed(BookingView? b) {
    final k = bookingDialogOpenKey(widget.branchId, widget.date, b, _tz);
    final guest = guestValuesOf(b);
    _b = b;
    _day = k.date;
    _party = '${k.partySize}';
    _startsAt = b?.startsAt;
    _customTime = b == null ? '' : localHHMM(b.startsAt, _tz);
    _duration = b == null
        ? ''
        : '${b.endsAt.difference(b.startsAt).inMinutes}';
    _sectionId = k.sectionId;
    _manualTables = b != null && (b.needsTable || b.tableIds.isNotEmpty);
    _tableIds = [...?b?.tableIds];
    _force = b != null;
    _name = guest.name;
    _phone = guest.phone;
    _notes = guest.notes;
    _seeded = _values;
  }

  /// `Number(value)`: blank or not a number reads 0.
  int get _partyN => int.tryParse(_party) ?? 0;

  String? _nameError(String v, Translator t) =>
      v.trim().isEmpty ? t('bookings.errName') : null;

  String? _phoneError(String v, Translator t) {
    if (v.trim().isEmpty) return t('bookings.errPhoneRequired');
    return isValidPhone(v) ? null : t('bookings.errPhone');
  }

  void _useCustomTime(Translator t) {
    if (!customTimePattern.hasMatch(_customTime)) {
      setState(() => _error = t('bookings.errTime'));
      return;
    }
    setState(() {
      _error = null;
      _startsAt = localInstant(_day, _customTime, _tz);
    });
  }

  Future<void> _submit() async {
    final t = ref.read(tProvider);
    // The guest fields first, on their own lines (RHF's handleSubmit).
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _error = null);
    final startsAt = _startsAt;
    if (startsAt == null) return setState(() => _error = t('bookings.errSlot'));
    if (_partyN <= 0) return setState(() => _error = t('bookings.errParty'));
    setState(() => _busy = true);
    final api = ref.read(apiProvider).bookings;
    // Captured now: the refresh runs even if the dialog closes mid-save.
    final bus = ref.read(realtimeBusProvider);
    final duration = _duration.isEmpty ? null : int.tryParse(_duration);
    final tableIds = _manualTables ? _tableIds : null;
    try {
      final b = _b;
      if (b != null) {
        await api.updateBooking(
          id: b.id,
          body: UpdateBookingRequest(
            partySize: _partyN,
            startsAt: startsAt,
            durationMinutes: duration,
            guestName: _name.trim(),
            guestPhone: guestPhoneToWire(_phone),
            // As typed: "" when blank (unlike create).
            notes: _notes,
            sectionId: _sectionId,
            tableIds: tableIds,
            force: _force,
            explicitNulls: {
              if (duration == null) 'duration_minutes',
              if (_sectionId == null) 'section_id',
              if (tableIds == null) 'table_ids',
            },
          ),
        );
      } else {
        await api.createBooking(
          body: CreateBookingRequest(
            branchId: widget.branchId,
            partySize: _partyN,
            startsAt: startsAt,
            durationMinutes: duration,
            guestName: _name.trim(),
            guestPhone: guestPhoneToWire(_phone),
            notes: _notes.isEmpty ? null : _notes,
            sectionId: _sectionId,
            tableIds: tableIds,
            force: _force,
            sendConfirmation: _sendConfirmation,
            explicitNulls: {
              if (duration == null) 'duration_minutes',
              if (_notes.isEmpty) 'notes',
              if (_sectionId == null) 'section_id',
              if (tableIds == null) 'table_ids',
            },
          ),
        );
      }
      bus.invalidate(SellInvalidate.bookings);
      if (!mounted) return;
      DashToast.success(
        context,
        _editing ? t('bookings.updated') : t('bookings.created'),
      );
      Navigator.of(context).pop();
    } on Object catch (e) {
      // The server's words on the dialog's own line, not a toast.
      if (mounted) setState(() => _error = bookingErrorText(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final settings = ref.watch(bookingSettingsProvider(widget.branchId)).value;
    final editing = widget.booking;
    if (editing != null) {
      // The page's day refetched (a timer, an event): an untouched form
      // follows the booking's newer values.
      ref.listen(
        bookingDayProvider((branchId: widget.branchId, date: widget.date)),
        (_, next) {
          final fresh = next.value?.where((x) => x.id == editing.id);
          if (fresh == null || fresh.isEmpty) return;
          if (_busy || _values != _seeded) return;
          setState(() => _seed(fresh.first));
        },
      );
    }
    final tables = activeTablesByLabel(
      ref.watch(floorTablesProvider(widget.branchId)).value,
    );
    final sections =
        ref.watch(floorSectionsProvider(widget.branchId)).value ?? const [];
    final availQ = watchIf(
      ref,
      _day.isNotEmpty && _partyN > 0,
      () => bookingAvailabilityProvider((
        branchId: widget.branchId,
        date: _day,
        partySize: _partyN < 1 ? 1 : _partyN,
        sectionId: _sectionId,
        excludeBookingId: _b?.id,
      )),
    );
    final slots = availQ.value?.slots ?? const [];
    final selected = slots
        .where((s) => s.startsAt.isAtSameMomentAs(_startsAt ?? DateTime(0)))
        .firstOrNull;
    final offGrid = _startsAt != null && selected == null;
    final seatsChosen = tables
        .where((x) => _tableIds.contains(x.id))
        .fold(0, (n, x) => n + x.seats);
    final muted = DashType.small.copyWith(color: c.textSecondary);
    final today = serviceToday(ref.read(clockProvider)(), _tz);
    final digits = [FilteringTextInputFormatter.digitsOnly];

    Widget pair(Widget a, Widget b) => wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: Space.lg,
            children: [
              Expanded(child: a),
              Expanded(child: b),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.lg,
            children: [a, b],
          );

    String autoHint() {
      if (_manualTables) {
        return t(
          'bookings.chooseTablesOn',
          args: {'seats': seatsChosen, 'party': _partyN},
        );
      }
      if (selected != null && selected.available) {
        return t(
          'bookings.autoPick',
          args: {
            'tables': selected.tableIds
                .map(
                  (id) =>
                      tables.where((x) => x.id == id).firstOrNull?.label ?? '?',
                )
                .join(' + '),
          },
        );
      }
      return t('bookings.autoHint');
    }

    final timeSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.sm,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                t('bookings.time'),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
            ),
            if (availQ.isLoading)
              SizedBox.square(
                key: const ValueKey('booking-slots-busy'),
                dimension: IconSize.xs,
                child: CircularProgressIndicator(
                  strokeWidth: DashMetrics.hair,
                  color: c.textSecondary,
                ),
              ),
          ],
        ),
        if (slots.isEmpty && !availQ.awaitingFirst)
          Text(t('bookings.noSlots'), style: muted)
        else
          BookingGrid(
            columns: wide ? 6 : 4,
            spacing: Space.xs + DashMetrics.hair,
            children: [
              for (final s in slots)
                _SlotButton(
                  key: ValueKey('slot-${s.startsAt.toIso8601String()}'),
                  label: fmt.fmtTime(s.startsAt),
                  selected: s.startsAt.isAtSameMomentAs(
                    _startsAt ?? DateTime(0),
                  ),
                  full: !s.available,
                  fullHint: t('bookings.slotFull'),
                  onTap: () => setState(() => _startsAt = s.startsAt),
                ),
            ],
          ),
        Wrap(
          spacing: Space.sm,
          runSpacing: Space.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: Space.xxl * 3 + Space.lg,
              child: DashTextInput(
                key: const ValueKey('booking-custom-time'),
                value: _customTime,
                placeholder: '19:30',
                semanticLabel: t('bookings.customTime'),
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.datetime,
                mono: true,
                onChanged: (v) => setState(() => _customTime = v),
              ),
            ),
            DashButton(
              key: const ValueKey('booking-use-time'),
              label: t('bookings.useTime'),
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              onPressed: () => _useCustomTime(t),
            ),
            if (_startsAt != null)
              Text(
                t('bookings.chosen', args: {'time': fmt.fmtTime(_startsAt)}) +
                    (offGrid ? ' · ${t('bookings.offGrid')}' : ''),
                style: muted,
              ),
          ],
        ),
        if (selected != null && !selected.available && !_manualTables)
          Row(
            spacing: Space.xs + DashMetrics.hair,
            children: [
              DashIcon(
                'alert-triangle',
                size: IconSize.xs,
                color: DashTone.warning.foreground(c),
              ),
              Expanded(
                child: Text(
                  t('bookings.slotFullHint'),
                  style: DashType.small.copyWith(
                    color: DashTone.warning.foreground(c),
                  ),
                ),
              ),
            ],
          ),
      ],
    );

    Widget switchRow(
      String label,
      String? hint,
      bool value,
      ValueChanged<bool> on,
    ) => Row(
      spacing: Space.md,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              if (hint != null) Text(hint, style: muted),
            ],
          ),
        ),
        DashSwitch(value: value, onChanged: on, semanticLabel: label),
      ],
    );

    final tablesBox = Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.xs),
        border: Border.all(color: c.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          switchRow(
            t('bookings.chooseTables'),
            autoHint(),
            _manualTables,
            (v) => setState(() => _manualTables = v),
          ),
          if (_manualTables)
            BookingGrid(
              columns: wide ? 5 : 3,
              spacing: Space.xs + DashMetrics.hair,
              children: [
                for (final x in tables)
                  _TableTick(
                    key: ValueKey('booking-table-${x.id}'),
                    table: x,
                    on: _tableIds.contains(x.id),
                    onChanged: (v) => setState(
                      () => _tableIds = v
                          ? [..._tableIds, x.id]
                          : [
                              for (final id in _tableIds)
                                if (id != x.id) id,
                            ],
                    ),
                  ),
              ],
            ),
          switchRow(
            t('bookings.force'),
            t('bookings.forceHint'),
            _force,
            (v) => setState(() => _force = v),
          ),
          if (!_editing)
            switchRow(
              t('bookings.sendConfirmation'),
              null,
              _sendConfirmation,
              (v) => setState(() => _sendConfirmation = v),
            ),
        ],
      ),
    );

    return DashSurface(
      title: _editing ? t('bookings.editTitle') : t('bookings.newTitle'),
      description: _editing ? t('bookings.editHint') : t('bookings.newHint'),
      actions: [
        DashButton(
          key: const ValueKey('booking-cancel'),
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          key: const ValueKey('booking-submit'),
          label: _editing ? t('common.save') : t('bookings.confirmBooking'),
          loading: _busy,
          onPressed: _submit,
        ),
      ],
      body: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            pair(
              DashDateFormField(
                key: const ValueKey('booking-date'),
                label: t('bookings.date'),
                value: dashParseYmd(_day),
                today: dashParseYmd(today),
                disablePast: !_editing,
                onChanged: (d) => setState(() {
                  _day = dashYmd(d);
                  _startsAt = null;
                }),
              ),
              DashTextField(
                key: const ValueKey('booking-party'),
                label: t('bookings.party'),
                value: _party,
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                onChanged: (v) => setState(() => _party = v),
              ),
            ),
            timeSection,
            pair(
              DashTextField(
                key: const ValueKey('booking-name'),
                label: t('bookings.guestName'),
                value: _name,
                validator: (v) => _nameError(v, t),
                onChanged: (v) => setState(() => _name = v),
              ),
              DashTextField(
                key: const ValueKey('booking-phone'),
                label: t('bookings.phone'),
                value: _phone,
                placeholder: '01x xxxx xxxx',
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                validator: (v) => _phoneError(v, t),
                onChanged: (v) => setState(() => _phone = v),
              ),
            ),
            pair(
              DashFormField<String>(
                label: t('bookings.section'),
                builder: (context, _) => DashSelect<String>(
                  key: const ValueKey('booking-section'),
                  value: _sectionId ?? '',
                  searchable: true,
                  semanticLabel: t('bookings.section'),
                  placeholder: t('bookings.anySection'),
                  options: [
                    DashOption(value: '', label: t('bookings.anySection')),
                    for (final s in sections)
                      DashOption(value: s.id, label: s.name),
                  ],
                  onChanged: (v) =>
                      setState(() => _sectionId = v.isEmpty ? null : v),
                ),
              ),
              DashTextField(
                key: const ValueKey('booking-duration'),
                label: t('bookings.duration'),
                value: _duration,
                placeholder: '${settings?.defaultDurationMinutes ?? 90}',
                keyboardType: TextInputType.number,
                inputFormatters: digits,
                onChanged: (v) => setState(() => _duration = v),
              ),
            ),
            DashTextAreaField(
              key: const ValueKey('booking-notes'),
              label: t('bookings.notes'),
              value: _notes,
              placeholder: t('bookings.notesPlaceholder'),
              minLines: 2,
              maxLines: 4,
              onChanged: (v) => setState(() => _notes = v),
            ),
            tablesBox,
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const ValueKey('booking-error'),
                  style: DashType.body.copyWith(color: c.errorText),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One slot: chosen (filled), open (plain) or full (dashed, muted, still
/// choosable, "Full for this party" on hover).
class _SlotButton extends StatelessWidget {
  const _SlotButton({
    required this.label,
    required this.selected,
    required this.full,
    required this.fullHint,
    required this.onTap,
    super.key,
  });

  final String label;
  final bool selected;
  final bool full;
  final String fullHint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final fg = selected
        ? c.textOnAccent
        : full
        ? c.textMuted.withValues(alpha: 0.6)
        : c.textPrimary;
    Widget face(DashPressState s) => CustomPaint(
      foregroundPainter: full && !selected
          ? _DashedBorder(color: c.hairline, radius: Radii.xs - 2)
          : null,
      child: Container(
        height: DashMetrics.target,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? c.accent
              : s.highlighted && !full
              ? c.hover
              : null,
          borderRadius: BorderRadius.circular(Radii.xs - 2),
          border: full && !selected
              ? null
              : Border.all(color: selected ? c.accent : c.hairline),
        ),
        child: Text(
          label,
          maxLines: 1,
          style: DashType.mono.copyWith(color: fg),
        ),
      ),
    );
    final button = DashPressable(
      onTap: onTap,
      selected: selected,
      checked: selected,
      semanticLabel: full ? '$label, $fullHint' : label,
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => face(s),
    );
    return full ? Tooltip(message: fullHint, child: button) : button;
  }
}

/// A table to tick when choosing tables: "label … seats".
class _TableTick extends StatelessWidget {
  const _TableTick({
    required this.table,
    required this.on,
    required this.onChanged,
    super.key,
  });

  final FloorTable table;
  final bool on;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: () => onChanged(!on),
      checked: on,
      isButton: false,
      semanticLabel: '${table.label} · ${table.seats}',
      excludeChildSemantics: true,
      pressScale: false,
      builder: (context, s) => Container(
        height: DashMetrics.target,
        padding: const EdgeInsetsDirectional.only(end: Space.sm),
        decoration: BoxDecoration(
          color: on ? c.accent.withValues(alpha: 0.05) : null,
          borderRadius: BorderRadius.circular(Radii.xs - 2),
          border: Border.all(color: on ? c.accent : c.hairline),
        ),
        child: Row(
          children: [
            IgnorePointer(
              child: DashCheckbox(
                value: on,
                onChanged: (_) {},
                semanticLabel: table.label,
              ),
            ),
            Expanded(
              child: MadarClippedText(
                table.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
            ),
            Text(
              '${table.seats}',
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// A dashed rounded outline (a full slot).
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});

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
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += Space.sm) {
        canvas.drawPath(m.extractPath(d, d + Space.xs), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}
