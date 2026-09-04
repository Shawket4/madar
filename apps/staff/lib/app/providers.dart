import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

import '../i18n/strings.dart';
import '../platform/location.dart';

/// The booted core — overridden with the live instance in the ready
/// ProviderScope (see `boot.dart` / `main.dart`).
final coreProvider = Provider<MadarCore>(
  (ref) => throw StateError('coreProvider must be overridden at boot'),
);

/// The loaded UI strings — overridden at boot.
final stringsProvider = Provider<Strings>(
  (ref) => throw StateError('stringsProvider must be overridden at boot'),
);

final locationProvider = Provider<LocationService>(
  (ref) => const LocationService(),
);

/// Active UI locale ('en'/'ar'). Writes through to the core, which is the
/// source of truth for both text lookup and layout direction.
///
/// The FIRST launch follows the device: an Egyptian phone gets Arabic without
/// anyone hunting for a toggle. After that the stored choice wins, because a
/// deliberate switch should survive a reinstall of the system language.
class LocaleNotifier extends Notifier<String> {
  @override
  String build() {
    final stored = ref.read(coreProvider).bridge.locale();
    if (stored.isNotEmpty) return stored;
    final device = PlatformDispatcher.instance.locale.languageCode;
    final resolved = device == 'ar' ? 'ar' : 'en';
    ref.read(coreProvider).bridge.setLocale(locale: resolved);
    return resolved;
  }

  void set(String locale) {
    ref.read(coreProvider).bridge.setLocale(locale: locale);
    state = locale;
  }

  void toggle() => set(state == 'ar' ? 'en' : 'ar');
}

final localeProvider = NotifierProvider<LocaleNotifier, String>(
  LocaleNotifier.new,
);

bool isRtlLocale(String locale) => locale == 'ar';

/// A translator bound to the active locale, with `{placeholder}` substitution:
/// `ref.watch(tProvider)('home.greeting', {'name': 'Sara'})`.
typedef Translate = String Function(String key, [Map<String, String>? args]);

final tProvider = Provider<Translate>((ref) {
  final strings = ref.watch(stringsProvider);
  final locale = ref.watch(localeProvider);
  return (key, [args]) {
    var out = strings.t(locale, key);
    if (args != null) {
      for (final entry in args.entries) {
        out = out.replaceAll('{${entry.key}}', entry.value);
      }
    }
    return out;
  };
});

/// The signed-in session (null = signed out).
class SessionNotifier extends Notifier<SessionSnapshot?> {
  @override
  SessionSnapshot? build() => ref.read(coreProvider).bridge.currentSession();

  Future<void> signIn(String email, String password) async {
    final snap = await ref
        .read(coreProvider)
        .bridge
        .staffSignIn(email: email, password: password);
    state = snap;
    // None of the data providers depend on this one, so without an explicit
    // sweep they survive the sign-in holding whatever the PREVIOUS session left
    // behind — most visibly the "invalid or expired token" error that sent the
    // employee to the login screen in the first place, still on screen after a
    // successful sign-in.
    _dropCachedData();
  }

  Future<void> signOut() async {
    await ref.read(coreProvider).bridge.logout(wipeOutbox: false);
    state = null;
    // Signing out must not leave one employee's attendance or payslips readable
    // to whoever signs in next.
    _dropCachedData();
  }

  void _dropCachedData() {
    ref.invalidate(todayProvider);
    ref.invalidate(attendanceProvider);
    ref.invalidate(requestsProvider);
    ref.invalidate(leaveBalancesProvider);
    ref.invalidate(payslipsProvider);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionSnapshot?>(
  SessionNotifier.new,
);

/// Today's status. The single source for the home screen, refetched after every
/// check-in/out so the button state comes from the SERVER rather than from what
/// the app thinks it just did.
class TodayNotifier extends AsyncNotifier<TodayView> {
  @override
  Future<TodayView> build() => ref.read(coreProvider).bridge.staffToday();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(coreProvider).bridge.staffToday(),
    );
  }
}

final todayProvider = AsyncNotifierProvider<TodayNotifier, TodayView>(
  TodayNotifier.new,
);

/// The employee's attendance over a window, keyed by `from|to` so switching
/// months doesn't clobber the previous month's cache.
final attendanceProvider =
    FutureProvider.family<List<AttendanceRecordView>, ({String from, String to})>(
  (ref, range) => ref
      .read(coreProvider)
      .bridge
      .staffAttendance(from: range.from, to: range.to),
);

/// Every request the employee has filed, of any kind.
final requestsProvider = FutureProvider<List<StaffRequestView>>(
  (ref) => ref.read(coreProvider).bridge.staffRequests(),
);

final leaveBalancesProvider = FutureProvider<List<LeaveBalanceView>>(
  (ref) => ref.read(coreProvider).bridge.staffLeaveBalances(),
);

final payslipsProvider = FutureProvider<List<PayslipView>>(
  (ref) => ref.read(coreProvider).bridge.staffPayslips(),
);

// ── Manager mode ──────────────────────────────────────────────

/// Whether this user sees the manager tabs.
///
/// A UI HINT ONLY. Every manager endpoint re-checks the same permission on the
/// server, so a user who forces their way past this sees empty screens and
/// 403s, not someone else's payroll. Keyed on `attendance:read` because that is
/// the cheapest permission any of the four manager tabs needs — payroll itself
/// is checked again when the payroll tab loads.
final managerCapableProvider = Provider<bool>((ref) {
  // Depends on the SESSION: permissions arrive with it, so a provider that
  // only read the bridge would answer once — while signed out, i.e. "no" —
  // and cache that answer through the sign-in that made it wrong.
  final session = ref.watch(sessionProvider);
  if (session == null) return false;
  return ref
      .read(coreProvider)
      .bridge
      .hasPermission(resource: 'attendance', action: 'read');
});

/// Whether the manager side is currently SHOWING. Someone who manages a branch
/// still clocks in themselves, so the two faces are a toggle rather than a
/// fork — and it starts on the manager side for those who have it, which is
/// the screen they open the app for.
class ManagerModeNotifier extends Notifier<bool> {
  @override
  bool build() => ref.watch(managerCapableProvider);

  void set(bool value) {
    if (!ref.read(managerCapableProvider)) return;
    state = value;
  }

  void toggle() => set(!state);
}

final managerModeProvider = NotifierProvider<ManagerModeNotifier, bool>(
  ManagerModeNotifier.new,
);

/// The employee's own roster over a window — the Shifts tab.
final scheduleProvider =
    FutureProvider.family<List<ScheduledDayView>, ({String from, String to})>(
      (ref, range) => ref
          .read(coreProvider)
          .bridge
          .staffSchedule(from: range.from, to: range.to),
    );

/// Live team state, keyed by branch (null = every branch).
final teamPresenceProvider = FutureProvider.family<TeamPresenceView, String?>(
  (ref, branchId) =>
      ref.read(coreProvider).bridge.managerTeamPresence(branchId: branchId),
);

/// The approvals queue.
final pendingRequestsProvider = FutureProvider<List<StaffRequestView>>(
  (ref) => ref
      .read(coreProvider)
      .bridge
      .managerRequests(status: 'pending', kind: null),
);

/// Badge count for the approvals tab. Reads the queue rather than fetching its
/// own count, so the number and the list can never disagree.
final pendingApprovalsCountProvider = Provider<int>(
  (ref) => ref.watch(pendingRequestsProvider).maybeWhen(
    data: (rows) => rows.length,
    orElse: () => 0,
  ),
);

/// The roster, filtered by the search box.
final rosterProvider = FutureProvider.family<List<EmployeeView>, String>(
  (ref, query) => ref
      .read(coreProvider)
      .bridge
      .managerEmployees(search: query.trim().isEmpty ? null : query.trim()),
);

final payrollPeriodsProvider = FutureProvider<List<PayrollPeriodView>>(
  (ref) => ref.read(coreProvider).bridge.managerPayrollPeriods(),
);

/// What generating a period would pay — the run table.
final payrollPreviewProvider =
    FutureProvider.family<List<PayrollLineView>, String>(
      (ref, periodId) =>
          ref.read(coreProvider).bridge.managerPayrollPreview(periodId: periodId),
    );

// ── Payroll adjustments ───────────────────────────────────────

/// Bonuses (`deductions: false`) or deductions (`true`) over the current month.
///
/// Keyed on the flag AND the window so the two lists never share a cache entry.
final adjustmentsProvider =
    FutureProvider.family<
      List<AdjustmentView>,
      ({bool deductions, String from, String to})
    >(
      (ref, q) => ref
          .read(coreProvider)
          .bridge
          .managerAdjustments(
            deductions: q.deductions,
            userId: null,
            from: q.from,
            to: q.to,
            // 0 = "listing everyone", so a percent-of-base row resolves to 0
            // rather than to some other employee's percentage.
            baseSalaryMinor: 0,
          ),
    );

/// Every salary advance in the org, for the approve/reject queue.
final advancesProvider = FutureProvider<List<SalaryAdvanceView>>(
  (ref) => ref.read(coreProvider).bridge.managerAdvances(),
);
