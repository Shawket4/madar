/// A branch's booking rules (SET-BKG-004 … 020; the web's
/// `features/bookings/settings-dialog.tsx`): the online switch, the phone
/// code, the weekly hours, slot and duration, party limits, lead time and
/// horizon, the hold, the no-show grace, the reminder, the covers cap and
/// the blackout dates.
///
/// A local port of sell's `BookingSettingsDialog` (see the seam note in
/// `booking_settings_data.dart`); behaviour differences from the web are in
/// `docs/fdash/divergences/setup-booking_settings.md`.
library;

import 'package:dashboard_api/dashboard_api.dart' show BookingSettings;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'booking_settings_data.dart';

/// Opens [branchId]'s rules. Each open is a fresh draft keyed by the branch,
/// so another branch's draft can never be saved here (SET-BKG-017).
Future<void> showBookingRulesDialog(
  BuildContext context, {
  required String branchId,
}) => showDashDialog<void>(
  context,
  width: DashMetrics.dialogWide,
  builder: (context) => BookingRulesDialog(
    key: ValueKey('bkg-dialog-$branchId'),
    branchId: branchId,
  ),
);

/// The hours boxes (`w-20`) and the blackout picker.
const double _timeBox = Space.xxl * 2 + Space.lg;
const double _datePicker = Space.xxl * 5 + Space.xl;

class BookingRulesDialog extends ConsumerStatefulWidget {
  const BookingRulesDialog({required this.branchId, super.key});

  final String branchId;

  @override
  ConsumerState<BookingRulesDialog> createState() => _BookingRulesDialogState();
}

class _BookingRulesDialogState extends ConsumerState<BookingRulesDialog> {
  /// The editable copy (the settings' JSON). It follows every fresh read
  /// (a stale cache refetched on open, a `booking.*` event) until the
  /// person edits (divergence SET-BKG-020).
  Map<String, Object?>? _s;
  BookingSettings? _from;
  bool _dirty = false;
  DateTime? _blackout;
  bool _busy = false;

  List<Map<String, Object?>> get _hours => [
    for (final h in _s!['hours']! as List) Map<String, Object?>.from(h as Map),
  ];

  List<String> get _blackouts => (_s!['blackout_dates']! as List).cast();

  void _set(String key, Object? value) => setState(() {
    _dirty = true;
    _s![key] = value;
  });

  void _setHours(int dow, Map<String, Object?>? entry) {
    final rest = [
      for (final h in _hours)
        if (h['dow'] != dow) h,
    ];
    _set(
      'hours',
      entry == null
          ? rest
          : ([...rest, entry]
              ..sort((a, b) => (a['dow']! as int).compareTo(b['dow']! as int))),
    );
  }

  Future<void> _save() async {
    final s = _s;
    if (s == null) return;
    final t = ref.read(tProvider);
    final api = ref.read(apiProvider).bookings;
    // Captured before the await: the web's query client refetches even if
    // the dialog closes mid-save.
    final bus = ref.read(realtimeBusProvider);
    setState(() => _busy = true);
    try {
      await api.putBookingSettings(
        body: bookingSettingsBody({
          ...s,
          'blackout_dates': [..._blackouts],
        }),
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        DashToast.error(context, errorMessage(e, t));
      }
      return;
    }
    bus.invalidate(BookingSettingsPaths.invalidated);
    if (!mounted) return;
    DashToast.success(context, t('common.savedChanges'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final q = ref.watch(bookingRulesProvider(widget.branchId));
    final fresh = q.value;
    if (!_dirty && fresh != null && !identical(fresh, _from)) {
      _from = fresh;
      _s = Map<String, Object?>.of(fresh.toJson());
    }
    final s = _s;
    final arabic = ref.watch(formatProvider).isArabic;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final muted = DashType.small.copyWith(color: c.textSecondary);
    final label = DashType.bodyMedium.copyWith(color: c.textPrimary);
    final digits = [FilteringTextInputFormatter.digitsOnly];

    Widget number(String key, String text, {String? hint}) =>
        DashFormField<String>(
          label: text,
          description: hint,
          builder: (context, _) => DashTextInput(
            key: ValueKey('bkg-$key'),
            value: '${s![key] ?? ''}',
            semanticLabel: text,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            onChanged: (v) => _set(
              key,
              v.isEmpty
                  ? (bookingOptionalFields.contains(key) ? null : 0)
                  : int.parse(v),
            ),
          ),
        );

    Widget toggle(String key, String text, String hint) => Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: c.muted,
        borderRadius: BorderRadius.circular(Radii.xs),
      ),
      child: Row(
        spacing: Space.lg,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(text, style: label),
                Text(hint, style: muted),
              ],
            ),
          ),
          DashSwitch(
            key: ValueKey('bkg-$key'),
            value: s![key] == true,
            semanticLabel: text,
            onChanged: (v) => _set(key, v),
          ),
        ],
      ),
    );

    Widget body;
    if (s == null && q.failedFirst) {
      // Divergence SET-BKG-004/019: the web stays on "Loading…" for ever.
      body = DashErrorState(
        key: const ValueKey('bkg-failed'),
        framed: false,
        message: errorMessage(q.error, t),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(bookingRulesProvider(widget.branchId)),
      );
    } else if (s == null) {
      body = Text(
        t('common.loading'),
        key: const ValueKey('bkg-loading'),
        style: DashType.body.copyWith(color: c.textSecondary),
      );
    } else {
      final hours = {for (final h in _hours) h['dow']! as int: h};
      final fields = [
        DashFormField<int>(
          label: t('bookings.slot'),
          builder: (context, _) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashSegmentedControl<int>(
              key: const ValueKey('bkg-slot_minutes'),
              value: s['slot_minutes']! as int,
              semanticLabel: t('bookings.slot'),
              onChanged: (v) => _set('slot_minutes', v),
              options: [
                for (final m in const [15, 30, 60])
                  DashOption(value: m, label: '$m'),
              ],
            ),
          ),
        ),
        number('default_duration_minutes', t('bookings.defaultDuration')),
        number('min_party', t('bookings.minParty')),
        number(
          'max_party',
          t('bookings.maxParty'),
          hint: t('bookings.maxPartyHint'),
        ),
        number(
          'lead_time_minutes',
          t('bookings.leadTime'),
          hint: t('bookings.leadTimeHint'),
        ),
        number('horizon_days', t('bookings.horizon')),
        number(
          'hold_minutes',
          t('bookings.hold'),
          hint: t('bookings.holdHint'),
        ),
        number(
          'auto_no_show_minutes',
          t('bookings.autoNoShow'),
          hint: t('bookings.autoNoShowHint'),
        ),
        number(
          'reminder_lead_minutes',
          t('bookings.reminder'),
          hint: t('bookings.reminderHint'),
        ),
        number(
          'max_covers_per_slot',
          t('bookings.coversCap'),
          hint: t('bookings.coversCapHint'),
        ),
      ];
      final columns = wide ? 2 : 1;
      final blackout = _blackout == null ? null : dashYmd(_blackout!);
      body = Column(
        key: const ValueKey('bkg-form'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          toggle('enabled', t('bookings.enabled'), t('bookings.enabledHint')),
          toggle(
            'require_otp',
            t('bookings.requireOtp'),
            t('bookings.requireOtpHint'),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              Text(t('bookings.hours'), style: label),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.xs),
                  border: Border.all(color: c.hairline),
                ),
                child: Column(
                  children: [
                    for (final dow in bookingDows)
                      _HoursRow(
                        key: ValueKey('bkg-hours-$dow'),
                        dayName: bookingDayName(dow, arabic: arabic),
                        entry: hours[dow],
                        closedLabel: t('bookings.closed'),
                        last: dow == bookingDows.last,
                        onToggle: (on) => _setHours(
                          dow,
                          on
                              ? {'dow': dow, 'open': '12:00', 'close': '23:00'}
                              : null,
                        ),
                        onChanged: (e) => _setHours(dow, e),
                      ),
                  ],
                ),
              ),
              Text(t('bookings.hoursHint'), style: muted),
            ],
          ),
          // `grid gap-4 sm:grid-cols-2`.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.lg,
            children: [
              for (var i = 0; i < fields.length; i += columns)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: Space.lg,
                  children: [
                    for (var j = i; j < i + columns; j++)
                      Expanded(
                        child: j < fields.length
                            ? fields[j]
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              Text(t('bookings.blackouts'), style: label),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final d in _blackouts)
                    _BlackoutChip(
                      key: ValueKey('bkg-blackout-$d'),
                      date: d,
                      removeLabel: t('common.remove'),
                      onRemove: () => _set('blackout_dates', [
                        for (final x in _blackouts)
                          if (x != d) x,
                      ]),
                    ),
                  SizedBox(
                    width: _datePicker,
                    child: DashDateField(
                      key: const ValueKey('bkg-blackout-date'),
                      value: _blackout,
                      today: ref.read(clockProvider)(),
                      disablePast: true,
                      placeholder: t('bookings.addBlackout'),
                      semanticLabel: t('bookings.addBlackout'),
                      onChanged: (d) => setState(() => _blackout = d),
                    ),
                  ),
                  DashButton(
                    key: const ValueKey('bkg-blackout-add'),
                    label: t('common.add'),
                    variant: DashButtonVariant.outline,
                    size: DashButtonSize.compact,
                    onPressed: blackout == null || _blackouts.contains(blackout)
                        ? null
                        : () => setState(() {
                            _dirty = true;
                            _s!['blackout_dates'] = [..._blackouts, blackout]
                              ..sort();
                            _blackout = null;
                          }),
                  ),
                ],
              ),
              Text(t('bookings.blackoutsHint'), style: muted),
            ],
          ),
        ],
      );
    }

    return DashSurface(
      title: t('bookings.settingsTitle'),
      description: t('bookings.settingsHint'),
      actions: [
        DashButton(
          key: const ValueKey('bkg-cancel'),
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          key: const ValueKey('bkg-save'),
          label: t('common.save'),
          loading: _busy,
          onPressed: s == null || _busy ? null : _save,
        ),
      ],
      body: body,
    );
  }
}

/// One weekday: ticked = open and close boxes (24-hour, LTR); unticked =
/// "Closed".
class _HoursRow extends StatelessWidget {
  const _HoursRow({
    required this.dayName,
    required this.entry,
    required this.closedLabel,
    required this.last,
    required this.onToggle,
    required this.onChanged,
    super.key,
  });

  final String dayName;
  final Map<String, Object?>? entry;
  final String closedLabel;
  final bool last;
  final ValueChanged<bool> onToggle;
  final ValueChanged<Map<String, Object?>> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    final e = entry;
    Widget box(String key, String placeholder) => SizedBox(
      width: _timeBox,
      child: DashTextInput(
        key: ValueKey('bkg-hours-$key'),
        value: e![key]! as String,
        placeholder: placeholder,
        semanticLabel: '$dayName $placeholder',
        textDirection: TextDirection.ltr,
        mono: true,
        onChanged: (v) => onChanged({...e, key: v}),
      ),
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs,
      ),
      decoration: BoxDecoration(
        border: last ? null : Border(bottom: BorderSide(color: c.hairline)),
      ),
      child: Row(
        spacing: Space.md,
        children: [
          DashCheckbox(
            value: e != null,
            semanticLabel: dayName,
            onChanged: onToggle,
          ),
          // `w-24`, giving way on a phone.
          Flexible(
            child: SizedBox(
              width: Space.xxl * 3,
              child: MadarClippedText(
                dayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DashType.body.copyWith(color: c.textPrimary),
              ),
            ),
          ),
          if (e != null)
            Directionality(
              textDirection: TextDirection.ltr,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: Space.sm,
                children: [
                  box('open', '12:00'),
                  Text('–', style: TextStyle(color: c.textSecondary)),
                  box('close', '23:00'),
                ],
              ),
            )
          else
            Text(
              closedLabel,
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// A blackout date as typed (`YYYY-MM-DD`, LTR digits) with its ×.
class _BlackoutChip extends StatelessWidget {
  const _BlackoutChip({
    required this.date,
    required this.removeLabel,
    required this.onRemove,
    super.key,
  });

  final String date;
  final String removeLabel;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      padding: const EdgeInsetsDirectional.only(start: Space.sm),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: c.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            date,
            textDirection: TextDirection.ltr,
            style: DashType.mono.copyWith(
              fontSize: DashType.small.fontSize,
              color: c.textPrimary,
            ),
          ),
          DashIconButton(
            icon: 'x',
            semanticLabel: removeLabel,
            iconSize: IconSize.xs - 2,
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
