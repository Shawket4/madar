/// Which org, which branch, which period: the web's scope bar
/// (`components/layout/scope-bar.tsx`, `org-picker.tsx`), its store
/// (`data/stores/app.store.ts`), `data/scope/use-scope.ts` and
/// `use-timezone.ts`.
///
/// - The org: a platform admin picks one (persisted); everyone else's comes
///   with their session.
/// - The branch (or all branches): persisted WITH the org it belongs to, and
///   reset to "all branches" when the org changes, when the session ends, or
///   when the org's branch list comes back without it (a stored branch from
///   another org would otherwise send every scoped request against a branch
///   this org does not have).
/// - The period: a preset (the last one used is remembered; `custom` never
///   is) or a custom range, resolved to day boundaries in the active zone.
library;

import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart' show Branch, Org;
import 'package:dashboard_core/src/authz/authz_providers.dart';
import 'package:dashboard_core/src/format/format.dart';
import 'package:dashboard_core/src/format/tz.dart';
import 'package:dashboard_core/src/gateways/preferences.dart';
import 'package:dashboard_core/src/generated/capabilities.dart';
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/providers.dart';
import 'package:dashboard_core/src/scope/period.dart';
import 'package:dashboard_core/src/session/session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The backend's "every branch in my org" id for the
/// `/reports/branches/{branch_id}/…` endpoints (`ALL_BRANCHES_ID`).
const String allBranchesId = '00000000-0000-0000-0000-000000000000';

/// Preference keys.
abstract final class ScopePrefKeys {
  /// A platform admin's picked org: `{"id": …, "logo": …}`.
  static const String org = 'madar.scope.org';

  /// The branch and the org it belongs to: `{"org": …, "branch": …}`.
  static const String branch = 'madar.scope.branch';

  /// The last preset used (`7d`, …).
  static const String preset = 'madar.scope.preset';

  /// The last resolved zone, so a relaunch formats right before data loads.
  static const String timezone = 'madar.scope.tz';
}

// ── The org ───────────────────────────────────────────────────────────────

/// A platform admin's chosen org.
class SelectedOrg {
  const SelectedOrg(this.id, {this.logoUrl});

  final String id;
  final String? logoUrl;
}

class SelectedOrgNotifier extends Notifier<SelectedOrg?> {
  @override
  SelectedOrg? build() {
    final session = ref.watch(currentSessionProvider);
    if (session == null || !session.isPlatform) return null;
    final stored = ref.read(preferencesProvider).getJson(ScopePrefKeys.org);
    if (stored is Map && stored['id'] is String) {
      return SelectedOrg(
        stored['id']! as String,
        logoUrl: stored['logo'] as String?,
      );
    }
    return null;
  }

  /// Picks the org (platform admins). A different org drops the branch.
  Future<void> select(String? orgId, {String? logoUrl}) async {
    final prefs = ref.read(preferencesProvider);
    final changed = state?.id != orgId;
    if (changed) {
      // The branch belongs to the previous org: drop it before anything asks.
      await prefs.setJson(ScopePrefKeys.branch, {'org': orgId, 'branch': null});
    }
    await ref
        .read(sessionGatewayProvider)
        .applyScope(orgId: orgId, branchId: changed ? null : _currentBranch());
    state = orgId == null ? null : SelectedOrg(orgId, logoUrl: logoUrl);
    await prefs.setJson(
      ScopePrefKeys.org,
      orgId == null ? null : {'id': orgId, 'logo': logoUrl},
    );
  }

  String? _currentBranch() {
    final stored = ref.read(preferencesProvider).getJson(ScopePrefKeys.branch);
    return stored is Map ? stored['branch'] as String? : null;
  }
}

final selectedOrgProvider = NotifierProvider<SelectedOrgNotifier, SelectedOrg?>(
  SelectedOrgNotifier.new,
);

/// The org the dashboard is looking at (`useOrgId`): a platform admin's
/// pick, everyone else's own.
final orgIdProvider = Provider<String?>((ref) {
  final session = ref.watch(currentSessionProvider);
  if (session == null) return null;
  return session.isPlatform
      ? ref.watch(selectedOrgProvider)?.id
      : session.user.orgId;
});

// ── Branches and orgs ─────────────────────────────────────────────────────

/// The org's branches (`GET /branches?org_id=`); null without an org.
final branchesProvider = FutureProvider<List<Branch>?>((ref) async {
  final orgId = ref.watch(orgIdProvider);
  if (orgId == null) return null;
  return ref.watch(coreApiProvider).listBranches(orgId);
}, retry: (_, _) => null);

/// The active ones, as the branch picker lists them.
final activeBranchesProvider = Provider<List<Branch>?>((ref) {
  final all = ref.watch(branchesProvider).value;
  return all?.where((b) => b.isActive).toList();
});

/// The current org, when this person may read it (`org.settings.read`).
final currentOrgProvider = FutureProvider<Org?>((ref) async {
  final orgId = ref.watch(orgIdProvider);
  final canRead = ref.watch(
    authzProvider.select((a) => a.can(Cap.orgSettingsRead)),
  );
  if (orgId == null || !canRead) return null;
  return ref.watch(coreApiProvider).getOrg(orgId);
}, retry: (_, _) => null);

/// Every org, by name, for a platform admin's org picker (inactive included).
final orgsProvider = FutureProvider<List<Org>>((ref) async {
  final session = ref.watch(currentSessionProvider);
  if (session == null || !session.isPlatform) return const [];
  final orgs = await ref.watch(coreApiProvider).listOrgs();
  return [...orgs]..sort((a, b) => a.name.compareTo(b.name));
}, retry: (_, _) => null);

// ── Branch + period ───────────────────────────────────────────────────────

/// The scope's own state; read [currentScopeProvider] for the resolved view.
class ScopeState {
  const ScopeState({this.branchId, this.preset = defaultPreset, this.custom});

  /// The selected branch; null = all branches.
  final String? branchId;

  /// The chosen preset. `custom` only counts while [custom] holds dates.
  final ScopePreset preset;
  final PeriodRange? custom;

  /// The preset in effect: a `custom` without dates falls back to the
  /// default, and says so.
  ScopePreset get effectivePreset =>
      preset == ScopePreset.custom && custom == null ? defaultPreset : preset;

  ScopeState copyWith({
    String? Function()? branchId,
    ScopePreset? preset,
    PeriodRange? Function()? custom,
  }) => ScopeState(
    branchId: branchId != null ? branchId() : this.branchId,
    preset: preset ?? this.preset,
    custom: custom != null ? custom() : this.custom,
  );
}

class ScopeNotifier extends Notifier<ScopeState> {
  PreferencesGateway get _prefs => ref.read(preferencesProvider);

  @override
  ScopeState build() {
    final orgId = ref.watch(orgIdProvider);
    final stored = _prefs.getJson(ScopePrefKeys.branch);
    String? branchId;
    if (stored is Map && stored['org'] == orgId) {
      branchId = stored['branch'] as String?;
    } else if (orgId != null) {
      // Another org's branch (or none recorded): reset to all branches. With
      // no org yet (restoring, signed out, a platform admin who has not
      // picked) nothing is decided and nothing is overwritten.
      unawaited(
        _prefs.setJson(ScopePrefKeys.branch, {'org': orgId, 'branch': null}),
      );
    }
    // The branch list may already be in: a branch not in it goes now.
    final known = ref.read(activeBranchesProvider);
    if (branchId != null &&
        known != null &&
        !known.any((b) => b.id == branchId)) {
      branchId = null;
      unawaited(
        _prefs.setJson(ScopePrefKeys.branch, {'org': orgId, 'branch': null}),
      );
    }
    ref.listen(activeBranchesProvider, (_, next) => _heal(next));
    final preset = ScopePreset.fromWire(_prefs.getString(ScopePrefKeys.preset));
    _syncHeaders(orgId, branchId);
    return ScopeState(
      branchId: branchId,
      // The hand-picked range is not kept, so a stored `custom` restores as
      // the default (`AppLayout`'s restore).
      preset: preset == null || preset == ScopePreset.custom
          ? defaultPreset
          : preset,
    );
  }

  /// Self-heal: a branch that is not an active branch of this org goes.
  void _heal(List<Branch>? active) {
    final id = state.branchId;
    if (id == null || active == null) return;
    if (!active.any((b) => b.id == id)) unawaited(setBranch(null));
  }

  void _syncHeaders(String? orgId, String? branchId) {
    final session = ref.read(currentSessionProvider);
    if (session == null) return;
    final role = session.user.role;
    // A branch manager / teller works their own branch (`updateApiContext`).
    final effective = role == 'branch_manager' || role == 'teller'
        ? (session.user.branchId ?? branchId)
        : branchId;
    unawaited(
      ref
          .read(sessionGatewayProvider)
          .applyScope(orgId: orgId, branchId: effective),
    );
  }

  /// Picks a branch; null = all branches.
  Future<void> setBranch(String? branchId) async {
    final orgId = ref.read(orgIdProvider);
    _syncHeaders(orgId, branchId);
    state = state.copyWith(branchId: () => branchId);
    await _prefs.setJson(ScopePrefKeys.branch, {
      'org': orgId,
      'branch': branchId,
    });
  }

  /// Picks a named preset (and forgets any custom range).
  Future<void> setPreset(ScopePreset preset) async {
    state = state.copyWith(preset: preset, custom: () => null);
    await _prefs.setString(ScopePrefKeys.preset, preset.wire);
  }

  /// A custom range: UTC ISO instants, as the date picker sends them.
  Future<void> setCustomRange(String from, String to) async {
    state = state.copyWith(
      preset: ScopePreset.custom,
      custom: () => PeriodRange(from, to),
    );
    await _prefs.setString(ScopePrefKeys.preset, ScopePreset.custom.wire);
  }

  /// A custom range of whole calendar days (inclusive) in the active zone.
  Future<void> setCustomDays(DateTime first, DateTime last) {
    // Read through the container: the zone depends on this scope, so a
    // tracked read from here would be a cycle.
    final zone = ref.container.read(activeTimezoneProvider);
    final r = customDaysRange(zone, first, last);
    return setCustomRange(r.from, r.to);
  }
}

final scopeProvider = NotifierProvider<ScopeNotifier, ScopeState>(
  ScopeNotifier.new,
);

/// Whether this person picks a branch (`canPickBranch`): someone who works
/// every branch; everyone else is scoped by the server.
final canPickBranchProvider = Provider<bool>((ref) {
  final a = ref.watch(authzProvider);
  return a.platform || a.owner;
});

// ── The zone ──────────────────────────────────────────────────────────────

/// branch -> org -> (for someone who cannot read the org) the first zone
/// among their branches -> [appTimezone] (`resolveTimezone`).
String resolveTimezone({
  String? branchTz,
  String? orgTz,
  List<String?> branchZones = const [],
}) {
  if (branchTz != null && branchTz.isNotEmpty) return branchTz;
  if (orgTz != null && orgTz.isNotEmpty) return orgTz;
  for (final z in branchZones) {
    if (z != null && z.isNotEmpty) return z;
  }
  return appTimezone;
}

/// The zone every date is shown in (`useSyncTimezone`): never the device's.
/// Until the branch/org answers, the zone resolved last time.
final activeTimezoneProvider = Provider<String>((ref) {
  final prefs = ref.watch(preferencesProvider);
  final stored = prefs.getString(ScopePrefKeys.timezone);
  final branchId = ref.watch(scopeProvider.select((s) => s.branchId));
  final branches = ref.watch(branchesProvider).value;
  final canReadOrg = ref.watch(
    authzProvider.select((a) => a.can(Cap.orgSettingsRead)),
  );
  final org = branchId == null && canReadOrg
      ? ref.watch(currentOrgProvider).value
      : null;
  if (branches == null && org == null) {
    return stored != null && isKnownTimezone(stored) ? stored : appTimezone;
  }
  String? branchTz;
  if (branchId != null && branches != null) {
    for (final b in branches) {
      if (b.id == branchId) branchTz = b.timezone;
    }
  }
  final resolved = resolveTimezone(
    branchTz: branchTz,
    orgTz: org?.timezone,
    branchZones: canReadOrg
        ? const []
        : [for (final b in branches ?? const <Branch>[]) b.timezone],
  );
  if (resolved != stored) {
    unawaited(prefs.setString(ScopePrefKeys.timezone, resolved));
  }
  return resolved;
});

// ── The resolved view ────────────────────────────────────────────────────

/// Branch + period, resolved (the web's `Scope`).
class Scope {
  const Scope({
    required this.orgId,
    required this.branchId,
    required this.preset,
    required this.range,
    required this.timezone,
  });

  final String? orgId;

  /// The selected branch; null = all branches.
  final String? branchId;
  final ScopePreset preset;
  final PeriodRange range;
  final String timezone;

  /// The branch id for branch-scoped report endpoints: the branch, or the
  /// all-branches sentinel. Never null.
  String get scopeBranchId => branchId ?? allBranchesId;

  bool get isAllBranches => branchId == null;

  String get from => range.from;
  String get to => range.to;

  /// `hourly` for today/yesterday, else `daily`.
  String get granularity => trendGranularity(preset);

  @override
  bool operator ==(Object other) =>
      other is Scope &&
      other.orgId == orgId &&
      other.branchId == branchId &&
      other.preset == preset &&
      other.range == range &&
      other.timezone == timezone;

  @override
  int get hashCode => Object.hash(orgId, branchId, preset, range, timezone);
}

/// The period in effect, day-bounded in the active zone.
final periodRangeProvider = Provider<PeriodRange>((ref) {
  final s = ref.watch(scopeProvider);
  final tz = ref.watch(activeTimezoneProvider);
  final custom = s.custom;
  if (s.preset == ScopePreset.custom && custom != null) return custom;
  return rangeForPreset(s.effectivePreset, tz, ref.watch(clockProvider)());
});

final currentScopeProvider = Provider<Scope>((ref) {
  final s = ref.watch(scopeProvider);
  return Scope(
    orgId: ref.watch(orgIdProvider),
    branchId: s.branchId,
    preset: s.effectivePreset,
    range: ref.watch(periodRangeProvider),
    timezone: ref.watch(activeTimezoneProvider),
  );
});

/// The formatter for the active language and zone.
final formatProvider = Provider<DashFormat>(
  (ref) => DashFormat(
    lang: ref.watch(localeProvider),
    timezone: ref.watch(activeTimezoneProvider),
    clock: ref.watch(clockProvider),
  ),
);
