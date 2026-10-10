/// The inputs the Employees unit's dialogs share, local ports of the web's
/// `components/inputs/phone-field.tsx`, `staff/branch-checklist.tsx`,
/// `dawam/salary-calculator.tsx` and `features/users/row-action.tsx` (kit
/// candidates: the kit has no phone field, branch checklist or row action).
library;

import 'package:dashboard_api/dashboard_api.dart' show Branch;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'employees_data.dart';

/// An icon-only row action (`RowAction`): ghost, tooltip and label;
/// destructive tints the glyph only.
class EmployeeRowAction extends StatelessWidget {
  const EmployeeRowAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.destructive = false,
    super.key,
  });

  final String icon;
  final String label;
  final VoidCallback onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) => DashIconButton(
    icon: icon,
    semanticLabel: label,
    onPressed: onPressed,
    color: destructive ? context.madarColors.danger : null,
  );
}

/// A phone number, Egyptian-first (`PhoneField`): always left to right, reads
/// it back as `+20 100 123 4567` once it is a real number, and says what is
/// wrong (too short, not a mobile prefix) after the field is left, not while
/// typing. A form error ([errorText]) wins over the field's own words.
class PhoneField extends ConsumerStatefulWidget {
  const PhoneField({
    required this.value,
    required this.onChanged,
    required this.label,
    this.errorText,
    this.description,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final String label;
  final String? errorText;
  final String? description;

  @override
  ConsumerState<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends ConsumerState<PhoneField> {
  bool _touched = false;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final canonical = canonicalPhone(widget.value);
    final problem = _touched ? phoneProblem(widget.value) : null;
    final own = switch (problem) {
      'short' => t('inputs.phoneShort'),
      'long' => t('inputs.phoneLong'),
      'prefix' => t('inputs.phonePrefix'),
      'bad' => t('inputs.phoneBad'),
      _ => null,
    };
    return DashFormField<String>(
      label: widget.label,
      errorText: widget.errorText ?? own,
      builder: (context, invalid) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.xs,
        children: [
          DashTextInput(
            value: widget.value,
            semanticLabel: widget.label,
            // Isolated: the groups would reorder in an Arabic hint.
            placeholder: ltr('010 1234 5678'),
            keyboardType: TextInputType.phone,
            textDirection: TextDirection.ltr,
            invalid: invalid,
            trailing: canonical == null
                ? null
                : DashIcon('check', color: c.success),
            onFocusChange: (focused) {
              if (!focused && !_touched) setState(() => _touched = true);
            },
            onChanged: (v) {
              if (_touched && canonicalPhone(v) != null) {
                setState(() => _touched = false);
              }
              widget.onChanged(v);
            },
          ),
          if (!invalid && canonical != null)
            Text(
              formatPhoneDisplay(canonical),
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.start,
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
          if (widget.description != null)
            Text(
              widget.description!,
              style: DashType.body.copyWith(color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// Where someone works: a tick per branch, several allowed
/// (`BranchChecklist`).
class BranchChecklist extends StatelessWidget {
  const BranchChecklist({
    required this.branches,
    required this.value,
    required this.onChanged,
    required this.label,
    this.errorText,
    super.key,
  });

  final List<Branch> branches;
  final List<String> value;
  final ValueChanged<List<String>> onChanged;
  final String label;
  final String? errorText;

  @override
  Widget build(BuildContext context) => DashFormField<List<String>>(
    label: label,
    errorText: errorText,
    builder: (context, invalid) => Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: [
        for (final b in branches)
          DashCheckChip(
            label: b.name,
            value: value.contains(b.id),
            onChanged: (on) => onChanged(
              on
                  ? [...value.where((v) => v != b.id), b.id]
                  : value.where((v) => v != b.id).toList(),
            ),
          ),
      ],
    ),
  );
}

/// The quick salary calculator beside a monthly salary (`SalaryCalculator`):
/// type the monthly salary, a day rate or an hourly rate and the other two
/// follow, from the rules' working days a month and day length; with a hire
/// date it names the first pay. Only the monthly figure is saved; the boxes
/// read Arabic digits and separators.
class SalaryCalculator extends ConsumerStatefulWidget {
  const SalaryCalculator({
    required this.label,
    required this.monthly,
    required this.onMonthly,
    this.hireDate,
    this.placeholder,
    this.onlyOpenPeriod = false,
    this.errorText,
    this.description,
    super.key,
  });

  final String label;

  /// The monthly salary as typed, in EGP.
  final String monthly;
  final ValueChanged<String> onMonthly;

  /// Names the first pay when given.
  final String? hireDate;
  final String? placeholder;

  /// Name the first pay only while that period hasn't ended.
  final bool onlyOpenPeriod;
  final String? errorText;
  final String? description;

  @override
  ConsumerState<SalaryCalculator> createState() => _SalaryCalculatorState();
}

class _SalaryCalculatorState extends ConsumerState<SalaryCalculator> {
  /// What was typed into the day or hour box, kept as typed while it is the
  /// source.
  ({bool daily, String text})? _typed;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    // The rules (stale 60 s on the web): the business's, when readable.
    final s = ref.watch(staffAttendanceSettingsProvider).value;
    final days = s != null && s.workingDaysPerMonth != 0
        ? s.workingDaysPerMonth
        : defaultPayBasis.workingDays;
    final PayBasis basis = (
      workingDays: days,
      dayMinutes: s != null && s.limitDayHours != 0
          ? (s.limitDayHours * 60).round()
          : defaultPayBasis.dayMinutes,
    );
    final startDay = s != null && s.periodStartDay != 0 ? s.periodStartDay : 1;

    final m = readPounds(widget.monthly);
    final r = m == null ? null : ratesFrom(basis, monthly: m);
    final typed = _typed;
    final dailyText = typed != null && typed.daily
        ? typed.text
        : r == null
        ? ''
        : egpText(r.daily);
    final hourlyText = typed != null && !typed.daily
        ? typed.text
        : r == null
        ? ''
        : egpText(r.hourly);

    void fromRate(bool daily, String text) {
      setState(() => _typed = (daily: daily, text: text));
      final p = readPounds(text);
      if (p == null) return widget.onMonthly('');
      final rr = daily
          ? ratesFrom(basis, daily: p)
          : ratesFrom(basis, hourly: p);
      widget.onMonthly(egpText(rr.monthly));
    }

    final hire = widget.hireDate;
    final first = m != null && isIsoDate(hire)
        ? firstPay(m, hire!, startDay)
        : null;
    final todayUtc = ref.read(clockProvider)().toUtc().toIso8601String();
    final showFirst =
        first != null &&
        (!widget.onlyOpenPeriod ||
            first.to.compareTo(todayUtc.substring(0, 10)) >= 0);

    Widget box(
      String label,
      String value,
      ValueChanged<String> onChanged, {
      String? placeholder,
      String? error,
    }) => DashFormField<String>(
      label: label,
      errorText: error,
      builder: (context, invalid) => DashTextInput(
        value: value,
        semanticLabel: label,
        placeholder: placeholder,
        invalid: invalid,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textDirection: TextDirection.ltr,
        onChanged: onChanged,
      ),
    );

    final boxes = [
      box(
        widget.label,
        widget.monthly,
        (v) {
          setState(() => _typed = null);
          widget.onMonthly(v);
        },
        placeholder: widget.placeholder,
        error: widget.errorText,
      ),
      box(t('dawam.dailyRateEgp'), dailyText, (v) => fromRate(true, v)),
      box(t('dawam.hourlyRateEgp'), hourlyText, (v) => fromRate(false, v)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.sm,
      children: [
        // `sm:grid-cols-3`: three across from the web's `sm` window up.
        if (MediaQuery.sizeOf(context).width >= DashBreakpoints.sm)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: Space.md,
            children: [for (final b in boxes) Expanded(child: b)],
          )
        else
          ...boxes,
        Text(
          t(
            'dawam.salaryBasis',
            args: {
              'days': jsNumber(basis.workingDays),
              'hours': jsNumber(basis.dayMinutes / 60),
            },
          ),
          style: DashType.small.copyWith(color: c.textSecondary),
        ),
        if (showFirst)
          Text(
            t(
              'dawam.firstPay',
              args: {
                'from': f.fmtDate(first.from),
                'to': f.fmtDate(first.to),
                'amount': f.fmtMoney(first.piastres),
              },
            ),
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          ),
        if (widget.description != null)
          Text(
            widget.description!,
            style: DashType.body.copyWith(color: c.textSecondary),
          ),
      ],
    );
  }
}

/// A day as `yyyy-mm-dd` (the web's `<Input type="date">`): the month opens
/// in its own small dialog (the kit's date field has no Clear and no year
/// jump, and its popover cannot flip above a field low in a dialog: kit
/// candidate), with a year to jump to, Today, and Clear once a day is set.
class EmployeeDateField extends StatelessWidget {
  const EmployeeDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.today,
    this.errorText,
    super.key,
  });

  final String label;

  /// `yyyy-mm-dd`, or empty.
  final String value;

  /// The day picked, or empty once cleared.
  final ValueChanged<String> onChanged;

  /// The business's today (its zone).
  final DateTime? today;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final picked = dashParseYmd(value);
    final t = context.dashStrings;
    return DashFormField<String>(
      label: label,
      errorText: errorText,
      builder: (context, invalid) => DashSelectTrigger(
        label: picked == null ? t.pickDate : context.dashFormats.date(picked),
        placeholder: picked == null,
        leadingIcon: 'calendar',
        invalid: invalid,
        semanticLabel: label,
        onTap: () async {
          // `(day,)`: a day, or `(null,)` for Clear; null = dismissed.
          final r = await showDashDialog<(DateTime?,)>(
            context,
            width: DashMetrics.sidePanel - Space.xxl * 3,
            builder: (_) => _MonthCard(
              title: label,
              selected: picked,
              today: dashDay(today ?? DateTime.now()),
            ),
          );
          if (r == null) return;
          onChanged(r.$1 == null ? '' : dashYmd(r.$1!));
        },
      ),
    );
  }
}

class _MonthCard extends ConsumerStatefulWidget {
  const _MonthCard({
    required this.title,
    required this.selected,
    required this.today,
  });

  final String title;
  final DateTime? selected;
  final DateTime today;

  @override
  ConsumerState<_MonthCard> createState() => _MonthCardState();
}

class _MonthCardState extends ConsumerState<_MonthCard> {
  late DateTime _month = widget.selected ?? widget.today;

  @override
  Widget build(BuildContext context) {
    final t = context.dashStrings;
    final year = ref.watch(tProvider)('teamEmployees.year');
    void pick(DateTime? d) => Navigator.of(context).pop((d,));
    // A hire date can be decades back: jump by year, not month by month.
    final first = _month.year < widget.today.year - 60
        ? _month.year
        : widget.today.year - 60;
    final last = _month.year > widget.today.year + 5
        ? _month.year
        : widget.today.year + 5;
    return DashSurface(
      title: widget.title,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        spacing: Space.sm,
        children: [
          Row(
            spacing: Space.sm,
            children: [
              Expanded(
                child: DashMonthBar(
                  month: _month,
                  onChanged: (m) => setState(() => _month = m),
                ),
              ),
              DashSelect<int>(
                expand: false,
                semanticLabel: year,
                value: _month.year,
                options: [
                  for (var y = last; y >= first; y--)
                    DashOption(value: y, label: '$y'),
                ],
                onChanged: (y) =>
                    setState(() => _month = DateTime(y, _month.month)),
              ),
            ],
          ),
          DashCalendar(
            month: _month,
            today: widget.today,
            selected: widget.selected,
            onPick: pick,
          ),
        ],
      ),
      actions: [
        if (widget.selected != null)
          DashButton(
            label: t.clear,
            variant: DashButtonVariant.ghost,
            onPressed: () => pick(null),
          ),
        DashButton(
          label: t.today,
          variant: DashButtonVariant.ghost,
          onPressed: () => pick(widget.today),
        ),
      ],
    );
  }
}
