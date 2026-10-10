/// A branch's booking settings (the web's `features/bookings/settings-dialog.tsx`,
/// SELL-BKG-060 … 073, 079): the online switch, the weekly hours, slot and
/// duration, party limits, lead time and horizon, the hold, the no-show
/// grace, the reminder, the covers cap and the blackout dates.
///
/// Public: the setup area's `/settings/bookings` pane opens the same dialog
/// (inventory §3.5).
library;

import 'package:dashboard_api/dashboard_api.dart' show BookingSettings;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../shared/invalidate.dart';
import 'bookings_parts.dart';
import 'bookings_providers.dart';
import '../shared/error_text.dart';

Future<void> showBookingSettingsDialog(
  BuildContext context, {
  required String branchId,
}) => showDashDialog<void>(
  context,
  width: DashMetrics.dialogWide,
  builder: (context) => BookingSettingsDialog(branchId: branchId),
);

/// Sunday = 0 … Saturday = 6, the backend's `dow`.
const List<int> _dows = [0, 1, 2, 3, 4, 5, 6];

/// The optional fields: blank saves null.
const Set<String> _optional = {
  'auto_no_show_minutes',
  'reminder_lead_minutes',
  'max_covers_per_slot',
};

/// The weekday's long name in the UI language (`Intl` `en-GB` / `ar-EG`).
String bookingDayName(int dow, {required bool arabic}) {
  final locale = arabic ? 'ar' : 'en_GB';
  initializeDateFormatting(locale);
  // 2024-01-07 was a Sunday.
  return DateFormat('EEEE', locale).format(DateTime(2024, 1, 7 + dow));
}

class BookingSettingsDialog extends ConsumerStatefulWidget {
  const BookingSettingsDialog({required this.branchId, super.key});

  final String branchId;

  @override
  ConsumerState<BookingSettingsDialog> createState() =>
      _BookingSettingsDialogState();
}

class _BookingSettingsDialogState extends ConsumerState<BookingSettingsDialog> {
  /// The editable copy (the settings' JSON). Like the web it follows every
  /// fresh read (a stale cache refetched on open), until the person edits.
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
    // Captured now: the refresh runs even if the dialog closes mid-save.
    final bus = ref.read(realtimeBusProvider);
    setState(() => _busy = true);
    try {
      final body = BookingSettings.fromJson({
        ...s,
        'blackout_dates': [..._blackouts],
      });
      await ref
          .read(apiProvider)
          .bookings
          .putBookingSettings(
            body: BookingSettings(
              branchId: body.branchId,
              enabled: body.enabled,
              hours: body.hours,
              slotMinutes: body.slotMinutes,
              defaultDurationMinutes: body.defaultDurationMinutes,
              minParty: body.minParty,
              maxParty: body.maxParty,
              leadTimeMinutes: body.leadTimeMinutes,
              horizonDays: body.horizonDays,
              holdMinutes: body.holdMinutes,
              autoNoShowMinutes: body.autoNoShowMinutes,
              reminderLeadMinutes: body.reminderLeadMinutes,
              requireOtp: body.requireOtp,
              maxCoversPerSlot: body.maxCoversPerSlot,
              blackoutDates: body.blackoutDates,
              explicitNulls: {
                for (final k in _optional)
                  if (s[k] == null) k,
              },
            ),
          );
      bus.invalidate(SellInvalidate.bookings);
      if (!mounted) return;
      DashToast.success(context, t('common.savedChanges'));
      Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) DashToast.error(context, sellErrorText(e, t));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final q = ref.watch(bookingSettingsProvider(widget.branchId));
    final fresh = q.value;
    if (!_dirty && fresh != null && !identical(fresh, _from)) {
      _from = fresh;
      _s = Map<String, Object?>.of(fresh.toJson());
    }
    final s = _s;
    final arabic = ref.watch(formatProvider).isArabic;
    final wide = MediaQuery.sizeOf(context).width >= DashBreakpoints.sm;
    final muted = DashType.small.copyWith(color: c.textSecondary);
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final today = ref.read(clockProvider)();

    Widget number(String key, String label, {String? hint}) =>
        DashFormField<String>(
          label: label,
          description: hint,
          builder: (context, _) => DashTextInput(
            key: ValueKey('settings-$key'),
            value: '${s![key] ?? ''}',
            semanticLabel: label,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            onChanged: (v) => _set(
              key,
              v.isEmpty ? (_optional.contains(key) ? null : 0) : int.parse(v),
            ),
          ),
        );

    Widget toggle(String key, String label, String hint) => Container(
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
                Text(
                  label,
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                Text(hint, style: muted),
              ],
            ),
          ),
          DashSwitch(
            key: ValueKey('settings-$key'),
            value: s![key] == true,
            semanticLabel: label,
            onChanged: (v) => _set(key, v),
          ),
        ],
      ),
    );

    Widget body;
    if (s == null && q.failedFirst) {
      // Divergence SELL-BKG-079: the web stays on "Loading…" forever.
      body = DashErrorState(
        framed: false,
        message: sellErrorText(q.error, t),
        retryLabel: t('common.retry'),
        retrying: q.isLoading,
        onRetry: () => ref.invalidate(bookingSettingsProvider(widget.branchId)),
      );
    } else if (s == null) {
      body = Text(t('common.loading'), style: muted);
    } else {
      final hours = {for (final h in _hours) h['dow']! as int: h};
      final fields = [
        DashFormField<int>(
          label: t('bookings.slot'),
          builder: (context, _) => Align(
            alignment: AlignmentDirectional.centerStart,
            child: DashSegmentedControl<int>(
              key: const ValueKey('settings-slot_minutes'),
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
      final blackout = _blackout == null ? null : dashYmd(_blackout!);
      body = Column(
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
              Text(
                t('bookings.hours'),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.xs),
                  border: Border.all(color: c.hairline),
                ),
                child: Column(
                  children: [
                    for (final dow in _dows)
                      _HoursRow(
                        key: ValueKey('settings-hours-$dow'),
                        dayName: bookingDayName(dow, arabic: arabic),
                        entry: hours[dow],
                        closedLabel: t('bookings.closed'),
                        last: dow == _dows.last,
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
          BookingGrid(
            columns: wide ? 2 : 1,
            spacing: Space.lg,
            children: fields,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: Space.sm,
            children: [
              Text(
                t('bookings.blackouts'),
                style: DashType.bodyMedium.copyWith(color: c.textPrimary),
              ),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final d in _blackouts)
                    _BlackoutChip(
                      key: ValueKey('blackout-$d'),
                      date: d,
                      removeLabel: t('common.remove'),
                      onRemove: () => _set('blackout_dates', [
                        for (final x in _blackouts)
                          if (x != d) x,
                      ]),
                    ),
                  SizedBox(
                    width: BookingMetrics.datePicker,
                    child: DashDateField(
                      key: const ValueKey('settings-blackout-date'),
                      value: _blackout,
                      today: today,
                      disablePast: true,
                      placeholder: t('bookings.addBlackout'),
                      semanticLabel: t('bookings.addBlackout'),
                      onChanged: (d) => setState(() => _blackout = d),
                    ),
                  ),
                  DashButton(
                    key: const ValueKey('settings-blackout-add'),
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
          key: const ValueKey('settings-cancel'),
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        DashButton(
          key: const ValueKey('settings-save'),
          label: t('common.save'),
          loading: _busy,
          onPressed: s == null ? null : _save,
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
      width: Space.xxl * 2 + Space.lg,
      child: DashTextInput(
        key: ValueKey('hours-$key'),
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
            onChanged: (v) => onToggle(v),
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
