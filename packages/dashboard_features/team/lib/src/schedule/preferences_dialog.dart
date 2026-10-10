/// Someone's preferred time and the days they can't work
/// (`dawam/preferences-dialog.tsx`, TEAM-SCH-060…062): the manager sees
/// them, may override them (logged, and the person is told), and reads who
/// changed them when. Read-only without `hr.staff.edit`.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show PreferenceChange, Preferences, RosterPerson;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/attendance_errors.dart';
import '../shared/staff_query.dart';
import '../shared/week.dart';
import 'schedule_providers.dart';

const String _none = 'none';

/// The note's limit (`z.string().max(300)`).
const int _noteMax = 300;

/// Opens [person]'s preferences, as the week [key] lists them.
Future<void> showPreferencesDialog(
  BuildContext context, {
  required RosterKey key,
  required RosterPerson person,
  required bool canEdit,
}) => showDashDialog<void>(
  context,
  builder: (_) =>
      PreferencesDialog(rosterKey: key, person: person, canEdit: canEdit),
);

class PreferencesDialog extends ConsumerStatefulWidget {
  const PreferencesDialog({
    required this.rosterKey,
    required this.person,
    required this.canEdit,
    super.key,
  });

  final RosterKey rosterKey;
  final RosterPerson person;

  /// Holds `hr.staff.edit`.
  final bool canEdit;

  @override
  ConsumerState<PreferencesDialog> createState() => _PreferencesDialogState();
}

class _PreferencesDialogState extends ConsumerState<PreferencesDialog> {
  RosterPerson? _seeded;
  String _pref = _none;
  Set<int> _days = {};
  String _note = '';
  bool _dirty = false;
  bool _submitted = false;
  bool _busy = false;

  /// The person as the latest roster has them (a refresh re-seeds an
  /// untouched form).
  RosterPerson _current() {
    final staff = ref
        .watch(scheduleRosterProvider(widget.rosterKey))
        .value
        ?.staff;
    for (final p in staff ?? const <RosterPerson>[]) {
      if (p.employeeId == widget.person.employeeId) return p;
    }
    return widget.person;
  }

  void _seed(RosterPerson p) {
    _seeded = p;
    _pref = p.prefTime == 'morning' || p.prefTime == 'evening'
        ? p.prefTime!
        : _none;
    _days = {...p.cantWorkDays};
    _note = '';
  }

  void _edit(VoidCallback change) => setState(() {
    _dirty = true;
    change();
  });

  String? _noteError(Translator t) =>
      _note.length > _noteMax ? t('dawam.errNoteLong') : null;

  Future<void> _save() async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    if (_noteError(t) != null) {
      setState(() => _submitted = true);
      return;
    }
    final api = ref.read(apiProvider);
    final staff = ref.read(staffRevisionsProvider.notifier);
    setState(() {
      _submitted = true;
      _busy = true;
    });
    final note = _note.trim();
    try {
      await api.staff.putEmployeePreferences(
        id: widget.person.employeeId,
        body: Preferences(
          prefTime: _pref == _none ? null : _pref,
          cantWorkDays: _days.toList()..sort(),
          note: note.isEmpty ? null : note,
          explicitNulls: const {'pref_time', 'note'},
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        DashToast.error(context, attendanceErrorText(e, t, f));
        setState(() => _busy = false);
      }
      return;
    }
    staff.invalidateStaff();
    if (!mounted) return;
    DashToast.success(context, t('dawam.prefsSaved'));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final c = context.madarColors;
    final person = _current();
    if (!identical(person, _seeded) && !_dirty) _seed(person);
    final canEdit = widget.canEdit;
    final logQ = ref.watch(
      schedulePreferenceLogProvider(widget.person.employeeId),
    );
    String day(int d) => t(weekdayKeys[d]);
    String prefLabel(String? p) => p == 'morning'
        ? t('dawam.prefers_morning')
        : p == 'evening'
        ? t('dawam.prefers_evening')
        : t('dawam.noPreference');

    Widget labelled(String label, Widget field) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: Space.xs + DashMetrics.hair,
      children: [
        Text(label, style: DashType.bodyMedium.copyWith(color: c.textPrimary)),
        field,
      ],
    );

    final List<PreferenceChange> log = logQ.value ?? const [];
    Widget logBody;
    if (logQ.failedFirst) {
      logBody = Text(
        attendanceErrorText(logQ.error, t, f),
        style: DashType.body.copyWith(color: c.errorText),
      );
    } else if (!logQ.hasValue) {
      logBody = const DashSkeleton(height: Space.xxl + Space.lg);
    } else if (log.isEmpty) {
      logBody = Text(
        t('dawam.prefsLogEmpty'),
        style: DashType.body.copyWith(color: c.textSecondary),
      );
    } else {
      logBody = Semantics(
        container: true,
        label: t('dawam.prefsLog'),
        explicitChildNodes: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.xs,
          children: [
            for (final e in log)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm + 2,
                  vertical: Space.xs + 2,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.xs),
                  border: Border.all(color: c.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Space.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          e.source == 'manager'
                              ? t(
                                  'dawam.prefsChangedBy',
                                  args: {'name': e.changedByName ?? ''},
                                )
                              : t('dawam.prefsChangedByEmployee'),
                          style: DashType.bodyMedium.copyWith(
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          f.fmtDate(
                            e.createdAt.toUtc().toIso8601String().substring(
                              0,
                              10,
                            ),
                          ),
                          style: DashType.small.copyWith(
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      [
                        prefLabel(e.prefTime),
                        if (e.cantWorkDays.isNotEmpty)
                          e.cantWorkDays
                              .where((d) => d >= 0 && d < 7)
                              .map(day)
                              .join(' '),
                        if (e.note != null && e.note!.isNotEmpty) e.note!,
                      ].join(' · '),
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.md,
      children: [
        labelled(
          t('dawam.prefTime'),
          DashSelect<String>(
            key: const Key('prefs-time'),
            value: _pref,
            semanticLabel: t('dawam.prefTime'),
            enabled: canEdit,
            options: [
              DashOption(value: _none, label: t('dawam.noPreference')),
              DashOption(value: 'morning', label: t('dawam.prefers_morning')),
              DashOption(value: 'evening', label: t('dawam.prefers_evening')),
            ],
            onChanged: (v) => _edit(() => _pref = v),
          ),
        ),
        labelled(
          t('dawam.cantWorkDays'),
          Semantics(
            container: true,
            label: t('dawam.cantWorkDays'),
            explicitChildNodes: true,
            child: Wrap(
              spacing: Space.xs + 2,
              runSpacing: Space.xs,
              children: [
                for (final d in weekOrder)
                  DashChoiceChip(
                    key: ValueKey('prefs-day-$d'),
                    label: day(d),
                    selected: _days.contains(d),
                    enabled: canEdit,
                    onTap: () => _edit(() {
                      _days = _days.contains(d)
                          ? ({..._days}..remove(d))
                          : {..._days, d};
                    }),
                  ),
              ],
            ),
          ),
        ),
        if (canEdit)
          DashTextAreaField(
            key: const Key('prefs-note'),
            label: t('dawam.prefsNote'),
            value: _note,
            minLines: 2,
            maxLines: 4,
            errorText: _submitted ? _noteError(t) : null,
            onChanged: (v) => _edit(() => _note = v),
          ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.xs + 2,
          children: [
            Semantics(
              header: true,
              child: Text(
                t('dawam.prefsLog'),
                style: DashType.smallStrong.copyWith(color: c.textSecondary),
              ),
            ),
            logBody,
          ],
        ),
      ],
    );

    return DashSurface(
      title: t('dawam.prefsTitle', args: {'name': person.name}),
      description: person.prefsSetBy == 'manager'
          ? t('dawam.prefsByManager')
          : t('dawam.prefsByEmployee'),
      body: body,
      actions: [
        DashButton(
          label: t('common.close'),
          variant: DashButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (canEdit)
          DashButton(
            label: t('common.save'),
            loading: _busy,
            onPressed: _busy ? null : _save,
          ),
      ],
    );
  }
}
