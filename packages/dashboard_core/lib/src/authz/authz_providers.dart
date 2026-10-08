/// Loading what the person may do and what the org has switched on, the way
/// the web does: `use-authz.ts`, `use-org-modules.ts`, the onboarding gate
/// (`features/onboarding/gate.ts`) and the Dawam set-up checklist
/// (`features/dawam/setup.ts`).
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart'
    show ApiException, AttendanceSettings, Branch, Employee, MyAuthz, WorkShift;
import 'package:dashboard_core/src/api_provider.dart';
import 'package:dashboard_core/src/authz/authz.dart';
import 'package:dashboard_core/src/data/query_cache.dart';
import 'package:dashboard_core/src/data/models.dart';
import 'package:dashboard_core/src/gateways/preferences.dart';
import 'package:dashboard_core/src/generated/capabilities.dart';
import 'package:dashboard_core/src/providers.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:dashboard_core/src/session/session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the last answer for a person is remembered (`madar.authz.<id>`).
String authzPrefKey(String userId) => 'madar.authz.$userId';

/// The person's capabilities (`useAuthz`).
///
/// - A platform admin holds everything; nothing is fetched.
/// - While the answer loads, the last answer for this person (kept in
///   preferences) stands in, so a relaunch does not flash an empty sidebar.
/// - A backend without `/authz/me` (404): the role's registry defaults.
/// - Any other failure: holds nothing, with [Authz.error] set ([refresh]
///   asks again).
class AuthzNotifier extends Notifier<Authz> {
  int _generation = 0;

  @override
  Authz build() {
    final session = ref.watch(currentSessionProvider);
    final gen = ++_generation;
    if (session == null) return Authz.none;
    if (session.isPlatform) return Authz.platformAdmin();
    final prefs = ref.read(preferencesProvider);
    final remembered = prefs.getJson(authzPrefKey(session.user.id));
    unawaited(Future<void>.microtask(() => _load(session, gen)));
    if (remembered is Map) {
      try {
        return Authz.from(MyAuthz.fromJson(remembered.cast<String, Object?>()));
      } on Object {
        // An unreadable remembered answer is just not there.
      }
    }
    return Authz.none;
  }

  Future<void> _load(SessionInfo session, int gen) async {
    try {
      final me = await ref.read(coreApiProvider).getMyAuthz();
      if (gen != _generation || !ref.mounted) return;
      state = Authz.from(me);
      unawaited(
        ref
            .read(preferencesProvider)
            .setJson(authzPrefKey(session.user.id), me.toJson()),
      );
    } on ApiException catch (e) {
      if (gen != _generation || !ref.mounted) return;
      state = e.status == 404
          ? Authz.from(defaultsFor(session.user.role, session.user.id))
          : Authz.from(null, error: e);
    } on Object catch (e) {
      if (gen != _generation || !ref.mounted) return;
      state = Authz.from(null, error: e);
    }
  }

  /// Asks the server again (after a role change, or to retry a failure).
  Future<void> refresh() async {
    final session = ref.read(currentSessionProvider);
    if (session == null || session.isPlatform) return;
    await _load(session, _generation);
  }
}

final authzProvider = NotifierProvider<AuthzNotifier, Authz>(AuthzNotifier.new);

// ── Modules ───────────────────────────────────────────────────────────────

/// The org's switched-on modules as the server says (PS-2).
class OrgModulesState {
  const OrgModulesState({
    this.modules = const [],
    this.known = false,
    this.error,
  });

  /// Switched-on modules; empty until the server has answered.
  final List<String> modules;

  /// False until the server answers: nothing module-tagged is shown or
  /// routed to on a guess.
  final bool known;

  /// The server could not be asked (never "all modules" on an error).
  final Object? error;

  bool has(String module) => modules.contains(module);
}

/// `GET /orgs/{id}/modules` for the current org.
final orgModulesQueryProvider = FutureProvider<List<String>?>((ref) async {
  final orgId = ref.watch(orgIdProvider);
  if (orgId == null) return null;
  return ref.watch(coreApiProvider).getOrgModules(orgId);
}, retry: (_, _) => null);

/// `useOrgModulesState`: no org pinned (a platform admin) = every module.
final orgModulesProvider = Provider<OrgModulesState>((ref) {
  final orgId = ref.watch(orgIdProvider);
  if (orgId == null) {
    return const OrgModulesState(modules: OrgModule.all, known: true);
  }
  final q = ref.watch(orgModulesQueryProvider);
  final mods = q.value;
  if (mods != null) return OrgModulesState(modules: mods, known: true);
  return OrgModulesState(error: q.error);
});

/// Asks for the modules again (the module gate's retry).
void retryOrgModules(WidgetRef ref) => ref.invalidate(orgModulesQueryProvider);

// ── Onboarding (the POS first-run wizard) ─────────────────────────────────

/// "Skip for now" in the wizard: for this session only.
class OnboardingSkipNotifier extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(currentSessionProvider.select((s) => s?.user.id));
    return false;
  }

  void skip() => state = true;
}

final onboardingSkippedProvider =
    NotifierProvider<OnboardingSkipNotifier, bool>(OnboardingSkipNotifier.new);

/// `GET /orgs/{id}/onboarding` `completed`, asked only of an owner whose org
/// sells with Madar POS and who has not skipped; null otherwise / until known.
final onboardingCompletedProvider = FutureProvider<bool?>((ref) async {
  final orgId = ref.watch(orgIdProvider);
  final role = ref.watch(currentSessionProvider.select((s) => s?.user.role));
  final skipped = ref.watch(onboardingSkippedProvider);
  final mods = ref.watch(orgModulesProvider);
  final hasPos = mods.known && mods.has(OrgModule.pos);
  if (orgId == null || role != 'org_admin' || skipped || !hasPos) return null;
  return ref.watch(coreApiProvider).getOnboardingCompleted(orgId);
}, retry: (_, _) => null);

/// `sendsToOnboarding`: only an owner whose org has POS switched on, whose
/// checklist the server says is unfinished, and who has not skipped it this
/// session. Nothing is decided before the modules are known.
bool sendsToOnboarding({
  required String? role,
  required bool skipped,
  required List<String> modules,
  required bool modulesKnown,
  required bool? completed,
}) =>
    role == 'org_admin' &&
    !skipped &&
    modulesKnown &&
    modules.contains(OrgModule.pos) &&
    completed == false;

final sendsToOnboardingProvider = Provider<bool>((ref) {
  final mods = ref.watch(orgModulesProvider);
  return sendsToOnboarding(
    role: ref.watch(currentSessionProvider.select((s) => s?.user.role)),
    skipped: ref.watch(onboardingSkippedProvider),
    modules: mods.modules,
    modulesKnown: mods.known,
    completed: ref.watch(onboardingCompletedProvider).value,
  );
});

// ── Dawam set-up checklist (SA-4) ─────────────────────────────────────────

/// The four set-up steps, in order.
enum SetupStep { branches, employees, shifts, rules }

/// The reads behind the checklist; a null field = not answered yet.
class SetupData {
  const SetupData({
    this.branches,
    this.activeEmployeeStatuses,
    this.shiftsActive,
    this.rulesKnown = false,
    this.rulesSavedAt,
    this.error,
  });

  final List<Branch>? branches;
  final List<String>? activeEmployeeStatuses;
  final List<bool>? shiftsActive;

  /// Whether the attendance settings answered (their `rules_saved_at` may be
  /// null).
  final bool rulesKnown;
  final DateTime? rulesSavedAt;

  /// The first read that failed, if any.
  final Object? error;
}

/// `SetupProgress`.
class SetupProgress {
  const SetupProgress({
    required this.ready,
    required this.done,
    required this.count,
    required this.complete,
  });

  /// Not asked / not answered: nothing is called done or not done.
  static const SetupProgress unknown = SetupProgress(
    ready: false,
    done: {
      SetupStep.branches: false,
      SetupStep.employees: false,
      SetupStep.shifts: false,
      SetupStep.rules: false,
    },
    count: 0,
    complete: false,
  );

  /// Every answer is in.
  final bool ready;
  final Map<SetupStep, bool> done;
  final int count;
  final bool complete;
}

/// `setupProgress(d)`: each step from real data, never a ticked box.
SetupProgress setupProgress(SetupData d) {
  final branches = d.branches;
  final done = {
    SetupStep.branches:
        branches != null && branches.isNotEmpty && branches.every(branchPinned),
    SetupStep.employees:
        d.activeEmployeeStatuses?.any((s) => s == 'active') ?? false,
    SetupStep.shifts: d.shiftsActive?.any((a) => a) ?? false,
    SetupStep.rules: d.rulesSavedAt != null,
  };
  final count = done.values.where((v) => v).length;
  return SetupProgress(
    ready:
        branches != null &&
        d.activeEmployeeStatuses != null &&
        d.shiftsActive != null &&
        d.rulesKnown,
    done: done,
    count: count,
    complete: count == SetupStep.values.length,
  );
}

/// Whether the checklist is asked at all: someone who sets the rules, in an
/// org with Dawam, with an org in scope (the sidebar's `useSetupProgress`).
final setupEnabledProvider = Provider<bool>((ref) {
  final can = ref.watch(authzProvider.select((a) => a.can(Cap.hrRulesEdit)));
  final dawam = ref.watch(
    orgModulesProvider.select((m) => m.has(OrgModule.dawam)),
  );
  return can && dawam && ref.watch(orgIdProvider) != null;
});

// The three Dawam reads the checklist shares with Dawam's own pages: one
// request each, as the web's one query key does. A staff write or Refresh
// invalidates them on the realtime bus, by path prefix.

/// `GET /staff/employees?employment_status=active`.
final staffActiveEmployeesProvider = FutureProvider.autoDispose<List<Employee>>(
  (ref) {
    ref.webCache();
    ref.watch(realtimeEpochProvider('/staff/employees'));
    return ref
        .watch(apiProvider)
        .staff
        .listEmployees(employmentStatus: 'active');
  },
);

/// `GET /staff/work-shifts`.
final staffWorkShiftsProvider = FutureProvider.autoDispose<List<WorkShift>>((
  ref,
) {
  ref.webCache();
  ref.watch(realtimeEpochProvider('/staff/work-shifts'));
  return ref.watch(apiProvider).staff.listWorkShifts();
});

/// `GET /staff/attendance/settings` (the business's rules).
final staffAttendanceSettingsProvider =
    FutureProvider.autoDispose<AttendanceSettings>((ref) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/staff/attendance/settings'));
      return ref.watch(apiProvider).staff.getAttendanceSettings();
    });

final _setupEmployeesProvider = FutureProvider<List<String>?>((ref) async {
  if (!ref.watch(setupEnabledProvider)) return null;
  return [
    for (final e in await ref.watch(staffActiveEmployeesProvider.future))
      e.employmentStatus,
  ];
}, retry: (_, _) => null);

final _setupShiftsProvider = FutureProvider<List<bool>?>((ref) async {
  if (!ref.watch(setupEnabledProvider)) return null;
  return [
    for (final s in await ref.watch(staffWorkShiftsProvider.future)) s.isActive,
  ];
}, retry: (_, _) => null);

final _setupRulesProvider = FutureProvider<(DateTime?,)?>((ref) async {
  if (!ref.watch(setupEnabledProvider)) return null;
  return (
    (await ref.watch(staffAttendanceSettingsProvider.future)).rulesSavedAt,
  );
}, retry: (_, _) => null);

/// The live data behind the checklist.
final setupDataProvider = Provider<SetupData>((ref) {
  if (!ref.watch(setupEnabledProvider)) return const SetupData();
  final b = ref.watch(branchesProvider);
  final e = ref.watch(_setupEmployeesProvider);
  final s = ref.watch(_setupShiftsProvider);
  final r = ref.watch(_setupRulesProvider);
  final failed = [b, e, s, r].where((q) => q.hasError && !q.hasValue);
  return SetupData(
    branches: b.value,
    activeEmployeeStatuses: e.value,
    shiftsActive: s.value,
    rulesKnown: r.value != null,
    rulesSavedAt: r.value?.$1,
    error: failed.isEmpty ? null : failed.first.error,
  );
});

final setupProgressProvider = Provider<SetupProgress>((ref) {
  if (!ref.watch(setupEnabledProvider)) return SetupProgress.unknown;
  return setupProgress(ref.watch(setupDataProvider));
});

/// Asks every set-up read again.
void retrySetup(WidgetRef ref) {
  ref
    ..invalidate(branchesProvider)
    ..invalidate(_setupEmployeesProvider)
    ..invalidate(_setupShiftsProvider)
    ..invalidate(_setupRulesProvider);
}

// ── All of it ─────────────────────────────────────────────────────────────

/// Everything the gates read, in one place.
class AuthzState {
  const AuthzState({
    required this.authz,
    required this.modules,
    required this.setup,
    required this.sendsToOnboarding,
  });

  final Authz authz;
  final OrgModulesState modules;
  final SetupProgress setup;

  /// The shell routes to the POS first-run wizard.
  final bool sendsToOnboarding;

  bool get platform => authz.platform;
  bool can(String cap) => authz.can(cap);
  bool canAny(Iterable<String> caps) => authz.canAny(caps);

  /// The set-up checklist is known unfinished (`setup.ready && !setup.complete`).
  bool get setupIncomplete => setup.ready && !setup.complete;
}

final authzStateProvider = Provider<AuthzState>(
  (ref) => AuthzState(
    authz: ref.watch(authzProvider),
    modules: ref.watch(orgModulesProvider),
    setup: ref.watch(setupProgressProvider),
    sendsToOnboarding: ref.watch(sendsToOnboardingProvider),
  ),
);
