import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart';

import '../i18n/strings.dart';

/// The booted core — overridden with the live instance in the ready
/// ProviderScope (see `boot.dart` / `main.dart`).
final coreProvider = Provider<MadarCore>(
  (ref) => throw StateError('coreProvider must be overridden at boot'),
);

/// The loaded UI strings — overridden at boot.
final stringsProvider = Provider<Strings>(
  (ref) => throw StateError('stringsProvider must be overridden at boot'),
);

/// Active UI locale ('en'/'ar'). Writes through to the core, which is the
/// source of truth for both text lookup and layout direction.
class LocaleNotifier extends Notifier<String> {
  @override
  String build() => ref.read(coreProvider).bridge.locale();

  void set(String locale) {
    ref.read(coreProvider).bridge.setLocale(locale: locale);
    state = locale;
  }

  void toggle() => set(state == 'ar' ? 'en' : 'ar');
}

final localeProvider = NotifierProvider<LocaleNotifier, String>(
  LocaleNotifier.new,
);

/// Whether a locale is right-to-left.
bool isRtlLocale(String locale) => locale == 'ar';

/// Dark mode (v1: in-memory, defaults to light).
class DarkModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

final darkModeProvider = NotifierProvider<DarkModeNotifier, bool>(
  DarkModeNotifier.new,
);

/// A translator bound to the active locale: `ref.watch(tProvider)('nav.orders')`.
final tProvider = Provider<String Function(String)>((ref) {
  final strings = ref.watch(stringsProvider);
  final locale = ref.watch(localeProvider);
  return (key) => strings.t(locale, key);
});

/// The signed-in session (null = signed out).
class SessionNotifier extends Notifier<SessionSnapshot?> {
  @override
  SessionSnapshot? build() => ref.read(coreProvider).bridge.currentSession();

  Future<void> signIn(String email, String password, {String? orgId}) async {
    final snap = await ref
        .read(coreProvider)
        .bridge
        .dashboardSignIn(email: email, password: password, orgId: orgId);
    state = snap;
  }

  Future<void> signOut() async {
    await ref.read(coreProvider).bridge.logout(wipeOutbox: false);
    state = null;
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionSnapshot?>(
  SessionNotifier.new,
);

/// The org's active branches (feeds the scope-bar picker).
final branchesProvider = FutureProvider<List<BranchView>>((ref) async {
  ref.watch(sessionProvider); // re-fetch on sign-in / org change
  return ref.read(coreProvider).bridge.listBranches();
});

/// The active org/branch scope override (branch selection lives here).
class ScopeNotifier extends Notifier<ActiveScopeView?> {
  @override
  ActiveScopeView? build() => ref.read(coreProvider).bridge.activeScope();

  void setBranch(String? branchId) {
    final orgId = ref.read(sessionProvider)?.orgId;
    ref
        .read(coreProvider)
        .bridge
        .setActiveScope(orgId: orgId, branchId: branchId);
    state = ActiveScopeView(orgId: orgId, branchId: branchId);
  }
}

final scopeProvider = NotifierProvider<ScopeNotifier, ActiveScopeView?>(
  ScopeNotifier.new,
);

/// Reporting-window presets for the scope bar.
enum Period { today, yesterday, d7, d30, mtd, custom }

/// The active period: a preset plus an optional custom range.
class PeriodState {
  const PeriodState(this.preset, {this.customFrom, this.customTo});

  final Period preset;
  final DateTime? customFrom;
  final DateTime? customTo;
}

class PeriodNotifier extends Notifier<PeriodState> {
  @override
  PeriodState build() => const PeriodState(Period.d30);

  void setPreset(Period p) => state = PeriodState(p);

  void setCustom(DateTime from, DateTime to) =>
      state = PeriodState(Period.custom, customFrom: from, customTo: to);

  /// `(fromRfc3339, toRfc3339)` for the current window, in UTC.
  (String, String) range() {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final (DateTime from, DateTime to) = switch (state.preset) {
      Period.today => (startOfToday, now),
      Period.yesterday => (
        startOfToday.subtract(const Duration(days: 1)),
        startOfToday,
      ),
      Period.d7 => (now.subtract(const Duration(days: 7)), now),
      Period.d30 => (now.subtract(const Duration(days: 30)), now),
      Period.mtd => (DateTime(now.year, now.month), now),
      Period.custom => (
        state.customFrom ?? now.subtract(const Duration(days: 30)),
        state.customTo ?? now,
      ),
    };
    return (from.toUtc().toIso8601String(), to.toUtc().toIso8601String());
  }

  /// Trend bucket granularity for the current window (matches the web).
  String granularity() => switch (state.preset) {
    Period.today || Period.yesterday => 'hourly',
    _ => 'daily',
  };
}

final periodProvider = NotifierProvider<PeriodNotifier, PeriodState>(
  PeriodNotifier.new,
);
