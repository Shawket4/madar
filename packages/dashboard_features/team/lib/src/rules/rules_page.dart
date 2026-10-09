/// `/staff/rules` (`staff/attendance-rules-page.tsx` `AttendanceRulesPage`,
/// TEAM-RUL rows): what lateness and absence cost, for the business or one
/// branch's overrides of it (RU-2).
///
/// - `hr.rules.edit` changes the rules; `hr.rules.view` alone sees them
///   read-only; neither → the page's own Restricted (TEAM-RUL-001).
/// - The form is seeded from the scope's settings read. A background refresh
///   re-seeds it until the person edits it; a save or "Follow the business"
///   re-seeds it from the answer that follows (TEAM-ALL-009).
/// - A save PUTs every rule (the business) or only the branch's changes plus
///   the rules it hands back, after a confirmation that lists each change
///   (once rules are in force), then invalidates `/staff/attendance…`.
library;

import 'package:collection/collection.dart';
import 'package:dashboard_api/dashboard_api.dart'
    show AttendanceSettings, BranchRules, PutAttendanceSettingsRequest;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/attendance_errors.dart';
import '../shared/page_gate.dart';
import '../shared/refresh_button.dart';
import '../shared/refresh_toast.dart';
import '../shared/staff_query.dart';
import 'rules_cards.dart';
import 'rules_dawam_card.dart';
import 'rules_data.dart';
import 'rules_form.dart';
import 'rules_parts.dart';
import 'rules_preview.dart';
import 'rules_preview_card.dart';

/// The business's own rules in the scope select.
const String _business = '__business__';

/// The cover-pay rule a branch can follow or set (D5).
const String _cover = 'cover_pay_mode';

class AttendanceRulesPage extends ConsumerWidget {
  const AttendanceRulesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => TeamPageGate(
    allowed: (a) => a.canAny(const [Cap.hrRulesEdit, Cap.hrRulesView]),
    titleKey: 'staff.rules',
    whoKey: 'staff.rulesNoAccess',
    child: const _RulesBody(),
  );
}

class _RulesBody extends ConsumerStatefulWidget {
  const _RulesBody();

  @override
  ConsumerState<_RulesBody> createState() => _RulesBodyState();
}

class _RulesBodyState extends ConsumerState<_RulesBody> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _loadedAt;

  /// The scope: null is the business.
  String? _branchId;

  /// What the form shows now.
  RulesValues _values = RulesValues.empty;

  /// What the form was last reset to (the web's `defaultValues`): dirty is
  /// any difference from it.
  RulesValues _base = RulesValues.empty;

  /// The scope's rules as the server holds them (never the suggestion):
  /// what a save's changes are measured against.
  RulesValues _loaded = RulesValues.empty;

  /// Rules this branch hands back to the business on the next save.
  List<String> _inherit = const [];

  /// Cover pay a branch picked for itself though it followed the business:
  /// saved as its own even at the value it runs on now (D5).
  bool _coverOwnNew = false;

  /// The fields checked so far (`mode: onChange`, every field on a save).
  Set<RulesField> _checked = const {};
  PayExample _exampleIn = PayExample.initial;
  bool _busy = false;

  AttendanceSettings? _seededFrom;
  (String?, bool)? _seedKey;

  /// A save or a follow-the-business landed: the next answer re-seeds the
  /// form even though it was edited.
  bool _reseed = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _onResume);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  bool get _dirty => _values != _base || _inherit.isNotEmpty;

  bool get _canEdit => ref.read(authzProvider).can(Cap.hrRulesEdit);

  /// Refetch on focus (`dawamQuery`): the branch list always, the settings
  /// only for someone who can't edit (a refetch never resets an editor's
  /// typing). Sooner than 30 s does nothing.
  void _onResume() {
    final at = _loadedAt;
    if (at == null || !mounted) return;
    final now = ref.read(clockProvider)();
    if (now.difference(at) < kQueryStaleTime) return;
    _loadedAt = now;
    ref.invalidate(rulesBranchesProvider);
    if (!_canEdit) ref.invalidate(rulesSettingsFor(_branchId));
  }

  void _seed(AttendanceSettings s, bool canEdit) {
    // A business that never saved starts from the suggested ladder (RU-1).
    _base = RulesValues.from(s, suggest: _branchId == null && canEdit);
    _values = _base;
    _loaded = RulesValues.from(s);
    _inherit = const [];
    _coverOwnNew = false;
    _checked = const {};
    _seededFrom = s;
    _seedKey = (_branchId, canEdit);
    _reseed = false;
  }

  /// A field changed: it is checked from now on (`shouldValidate`).
  void _set(RulesValues v, [RulesField? check]) => setState(() {
    _values = v;
    if (check != null) _checked = {..._checked, check};
  });

  void _discard(AttendanceSettings s) =>
      setState(() => _seed(s, _seedKey?.$2 ?? _canEdit));

  String _words(TierProblem p, Translator t) =>
      t(p.key, args: p.n == null ? null : {'n': jsNum(p.n)});

  void _chooseCover(String c, List<String> overridden) {
    if (c == coverBusiness) {
      setState(() {
        _coverOwnNew = false;
        if (overridden.contains(_cover) && !_inherit.contains(_cover)) {
          _inherit = [..._inherit, _cover];
        }
        // Back to what it runs on now, so nothing is sent as a change.
        _values = _values.copyWith(
          dawam: _values.dawam.copyWith(
            coverPayMode: _loaded.dawam.coverPayMode,
          ),
        );
      });
      return;
    }
    setState(() {
      _inherit = [..._inherit]..remove(_cover);
      _coverOwnNew = !overridden.contains(_cover);
      _values = _values.copyWith(
        dawam: _values.dawam.copyWith(coverPayMode: c),
      );
      _checked = {..._checked, RulesField.dawam};
    });
  }

  /// Rules already in force change people's pay: say exactly what changes
  /// first. The very first business save asks nothing.
  Future<bool> _confirmChanges(
    RulesValues v,
    AttendanceSettings s,
    String branchName,
    bool canGender,
  ) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final branchId = _branchId;
    if (s.rulesSavedAt == null && branchId == null) return true;
    final changes = changedRules(v, _loaded, canGender: canGender)
        .where((c) => branchId == null || !businessOnlyRules.contains(c.name))
        .toList();
    if (changes.isEmpty && _inherit.isEmpty) return true;
    return showRulesConfirm(
      context,
      title: branchId != null
          ? t('staff.rulesConfirmBranchTitle', args: {'name': branchName})
          : t('staff.rulesConfirmTitle'),
      hint: t('staff.rulesConfirmHint'),
      lines: [
        for (final c in changes)
          (label: ruleLabel(c.name, t), change: describeChange(c, t, f)),
        for (final n in _inherit)
          (
            label: t('staff.rulesConfirmInherit', args: {'rule': ruleLabel(n, t)}),
            change: null,
          ),
      ],
      confirmLabel: t('staff.rulesConfirmSave'),
    );
  }

  Future<void> _save(
    AttendanceSettings s,
    String branchName,
    bool canGender,
  ) async {
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final v = _values;
    final problems = rulesProblems(v);
    if (problems.isNotEmpty) {
      setState(() => _checked = RulesField.values.toSet());
      final first = RulesField.values.map((x) => problems[x]).nonNulls.first;
      DashToast.error(context, _words(first, t));
      return;
    }
    final branchId = _branchId;
    final body = branchId != null
        ? branchBody(
            branchId,
            v,
            _loaded,
            _inherit,
            _coverOwnNew ? const [_cover] : const [],
          )
        : fullBody(v, canGender: canGender);
    if (body == null) {
      DashToast.info(context, t('staff.rulesNothingChanged'));
      return;
    }
    if (!await _confirmChanges(v, s, branchName, canGender)) return;
    if (!mounted) return;
    final api = ref.read(apiProvider);
    final revisions = ref.read(staffRevisionsProvider.notifier);
    setState(() => _busy = true);
    try {
      await api.staff.putAttendanceSettings(
        body: PutAttendanceSettingsRequest.fromJson(body),
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        DashToast.error(
          context,
          attendanceErrorText(e, t, f, fieldLabel: (x) => ruleLabel(x, t)),
        );
      }
      return;
    }
    _reseed = true;
    revisions.invalidateAttendance();
    if (!mounted) return;
    setState(() => _busy = false);
    DashToast.success(context, t('staff.rulesSaved'));
  }

  Future<void> _followBusiness(String branchName) async {
    final branchId = _branchId;
    if (branchId == null) return;
    final t = ref.read(tProvider);
    final f = ref.read(formatProvider);
    final ok = await showDashConfirm(
      context,
      title: t('staff.rulesFollowBusinessTitle', args: {'name': branchName}),
      description: t('staff.rulesFollowBusinessHint'),
      confirmLabel: t('staff.rulesFollowBusiness'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    final api = ref.read(apiProvider);
    final revisions = ref.read(staffRevisionsProvider.notifier);
    try {
      await api.staff.deleteBranchRules(branchId: branchId);
    } on Object catch (e) {
      if (mounted) DashToast.error(context, attendanceErrorText(e, t, f));
      return;
    }
    _reseed = true;
    revisions.invalidateAttendance();
    if (mounted) DashToast.success(context, t('staff.rulesSaved'));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final f = ref.watch(formatProvider);
    final authz = ref.watch(authzProvider);
    final canEdit = authz.can(Cap.hrRulesEdit);
    final canView = authz.ready && (canEdit || authz.can(Cap.hrRulesView));
    final readOnly = !canEdit;
    final canGender = canEdit && authz.can(Cap.hrRosterSettings);
    final branchId = _branchId;
    final settingsP = rulesSettingsFor(branchId);

    // The reads stay off until the person may see the rules.
    final branchesQ = canView
        ? ref.watch(rulesBranchesProvider)
        : const AsyncLoading<List<BranchRules>>();
    final q = canView
        ? ref.watch(settingsP)
        : const AsyncLoading<AttendanceSettings>();
    if (canView) {
      listenStaffRefreshFailure(ref, context, rulesBranchesProvider);
      listenStaffRefreshFailure(ref, context, settingsP);
      ref.listen(settingsP, (_, next) {
        if (next.hasValue && !next.isLoading) {
          _loadedAt = ref.read(clockProvider)();
        }
      });
    }
    final s = q.value;
    if (s != null) _loadedAt ??= ref.read(clockProvider)();
    final key = (branchId, canEdit);
    if (s != null && (!identical(s, _seededFrom) || _seedKey != key)) {
      // Another scope, or a fresh answer the person hasn't edited over.
      if (_seedKey != key || !_dirty || _reseed) {
        _seed(s, canEdit);
      } else {
        _seededFrom = s;
      }
    }

    final branches = branchesQ.value ?? const <BranchRules>[];
    final branchName =
        branches.firstWhereOrNull((b) => b.branchId == branchId)?.branchName ??
        '';
    final refresh = DawamRefreshButton(
      key: const ValueKey('rules-refresh'),
      busy: anyFetching([branchesQ, q]),
    );
    final scopeSelect = Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        width: DashMetrics.dialog / 2,
        child: DashSelect<String>(
          key: RulesKeys.scope,
          value: branchId ?? _business,
          semanticLabel: t('staff.rulesFor'),
          options: [
            DashOption(value: _business, label: t('staff.rulesBusiness')),
            for (final b in branches)
              DashOption(
                value: b.branchId,
                label: b.overridden.isNotEmpty
                    ? t('staff.rulesBranchOwn', args: {'name': b.branchName})
                    : b.branchName,
              ),
          ],
          // Picking a scope reads its rules: warm that read.
          onOptionIntent: (v) =>
              ref.warm(rulesSettingsFor(v == _business ? null : v)),
          onChanged: (v) => setState(() => _branchId = v == _business ? null : v),
        ),
      ),
    );

    final title = t('staff.rules');
    // The web's `isLoading || error`: a failed refresh with the form on
    // screen shows the skeleton too (TEAM-ALL-010).
    if (s == null || q.hasError) {
      return DashPageScaffold(
        title: title,
        width: DashPageWidth.reading,
        actions: [refresh],
        filters: scopeSelect,
        body: q.failedFirst
            ? DashErrorState(
                title: t('staff.rulesLoadError'),
                message: attendanceErrorText(q.error, t, f),
                retryLabel: t('common.retry'),
                retrying: q.isLoading,
                onRetry: () => ref.invalidate(settingsP),
              )
            : const Column(
                key: ValueKey('rules-skeleton'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: Space.lg,
                children: [
                  DashSkeleton(height: Space.xxl * 8, radius: Radii.control),
                  DashSkeleton(height: Space.xxl * 6, radius: Radii.control),
                ],
              ),
      );
    }

    final v = _values;
    final problems = rulesProblems(v);
    String? shown(RulesField x) {
      final p = _checked.contains(x) ? problems[x] : null;
      return p == null ? null : _words(p, t);
    }

    final shownErrors = {
      for (final x in RulesField.values)
        if (shown(x) != null) x: shown(x)!,
    };
    final tierError = shownErrors[RulesField.tiers];
    // The worked examples divide by the working days being edited.
    final wd = v.workingDays;
    final example = _exampleIn.copyWith(
      workingDays: wd != null && wd.isFinite ? wd : 0,
    );
    final overridden = branchId != null
        ? (s.overridden ?? const <String>[])
        : const <String>[];
    final coverFollows =
        !_coverOwnNew &&
        (!overridden.contains(_cover) || _inherit.contains(_cover));
    final c = context.madarColors;

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: Space.xl,
      children: [
        if (readOnly)
          RulesNote(
            child: Row(
              spacing: Space.sm,
              children: [
                DashIcon('eye', size: IconSize.xs, color: c.textPrimary),
                Expanded(
                  child: Text(
                    t('staff.rulesReadOnly'),
                    style: DashType.body.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            ),
          ),
        if (branchId == null && s.rulesSavedAt == null)
          RulesNote(
            tone: DashTone.warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t('dawam.rulesFirstTitle'),
                  style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                ),
                if (canEdit && storedTiers(s).isEmpty)
                  Text(
                    t('staff.rulesSuggested'),
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
          ),
        if (branchId != null)
          RulesBranchCard(
            overridden: overridden,
            inherit: _inherit,
            readOnly: readOnly,
            t: t,
            onToggle: (name) => setState(() {
              _inherit = _inherit.contains(name)
                  ? ([..._inherit]..remove(name))
                  : [..._inherit, name];
            }),
            onFollow: () => _followBusiness(branchName),
          ),
        RulesLadderCard(
          tiers: v.tiers,
          example: example,
          error: tierError,
          readOnly: readOnly,
          t: t,
          f: f,
          onChanged: (tiers) =>
              _set(v.copyWith(tiers: tiers), RulesField.tiers),
        ),
        RulesPreviewCard(
          tiers: v.tiers,
          example: example,
          onExample: (e) => setState(() => _exampleIn = e),
          t: t,
          f: f,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Space.lg,
          children: [
            RulesPayBasisCard(
              values: v,
              example: example,
              errors: shownErrors,
              readOnly: readOnly,
              t: t,
              f: f,
              onWorkingDays: (n) => _set(
                v.copyWith(workingDays: () => n),
                RulesField.workingDays,
              ),
              onAbsenceDays: (n) => _set(
                v.copyWith(absenceDays: () => n),
                RulesField.absenceDays,
              ),
              onAutoBuffer: (n) => _set(
                v.copyWith(autoBuffer: () => n),
                RulesField.autoBuffer,
              ),
            ),
            RulesPoliciesCard(
              excusedPaid: v.excusedPaid,
              readOnly: readOnly,
              t: t,
              onExcusedPaid: (b) => _set(v.copyWith(excusedPaid: b)),
            ),
            DawamRulesCard(
              value: v.dawam,
              t: t,
              f: f,
              canGender: canGender,
              readOnly: readOnly,
              branch: branchId != null,
              coverFollows: coverFollows,
              onCoverChoice: (choice) => _chooseCover(choice, overridden),
              onChanged: (d) =>
                  _set(v.copyWith(dawam: d), RulesField.dawam),
            ),
            if (shownErrors[RulesField.dawam] != null)
              RulesErrorText(shownErrors[RulesField.dawam]!),
          ],
        ),
      ],
    );

    final page = DashPageScaffold(
      title: title,
      subtitle: t('staff.rulesSubtitle'),
      width: DashPageWidth.reading,
      actions: [refresh],
      filters: scopeSelect,
      body: body,
    );
    if (readOnly) return page;

    final status = tierError != null || shownErrors.isNotEmpty
        ? Text(
            t('staff.rulesFixFirst'),
            style: DashType.body.copyWith(color: c.errorText),
          )
        : _dirty
        ? Text(
            t('staff.rulesUnsaved'),
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          )
        : branchId == null && s.rulesSavedAt == null
        ? Text(
            t('staff.rulesNotSavedYet'),
            style: DashType.bodyMedium.copyWith(color: c.textPrimary),
          )
        : Text(
            t('staff.rulesAllSaved'),
            style: DashType.body.copyWith(color: c.textSecondary),
          );
    final bar = _SaveBar(
      status: status,
      actions: [
        if (_dirty)
          DashButton(
            key: RulesKeys.discard,
            label: t('staff.rulesDiscard'),
            variant: DashButtonVariant.ghost,
            onPressed: () => _discard(q.value!),
          ),
        DashButton(
          key: RulesKeys.save,
          label: t('common.save'),
          icon: 'save',
          loading: _busy,
          onPressed: tierError != null || _busy
              ? null
              : () => _save(s, branchName, canGender),
        ),
      ],
    );
    // The save bar sticks to the bottom of the viewport, under the page's
    // reading column.
    return LayoutBuilder(
      builder: (context, box) {
        final gutter = DashBreakpoints.gutter(box.maxWidth);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: page),
            Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
              child: Align(
                alignment: AlignmentDirectional.bottomStart,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: DashPageWidth.reading.max,
                  ),
                  child: bar,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The sticky save bar: what the form's state is, and its buttons.
class _SaveBar extends StatelessWidget {
  const _SaveBar({required this.status, required this.actions});

  final Widget status;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return Container(
      key: RulesKeys.saveBar,
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.control),
        ),
        border: Border(
          top: BorderSide(color: c.hairline),
          left: BorderSide(color: c.hairline),
          right: BorderSide(color: c.hairline),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: Space.md,
        runSpacing: Space.md,
        children: [
          Semantics(liveRegion: true, child: status),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: Space.sm,
            children: actions,
          ),
        ],
      ),
    );
  }
}
