/// The loyalty admin's vocabulary, rules and reads (SET-LOY rows): the web's
/// `features/loyalty/shared/{access,util,server-errors}.ts`,
/// `admin/program/form-schema.ts`, `admin/rewards/{catalogue,earning}-schema.ts`,
/// `admin/members/{ledger,adjust-schema}.ts`, `customers/{access,util}.ts`,
/// plus one Riverpod read per web query hook.
///
/// Every read calls `webCache()` first and watches the realtime epoch of its
/// own path, so [LoyaltyPaths.people] (the web's `isPersonQuery`) refetches
/// exactly the person reads the web refetches.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The query-key paths (the web's Orval keys start with the path).
abstract final class LoyaltyPaths {
  static const String settings = '/loyalty/settings';
  static const String rewardItems = '/loyalty/reward-items';
  static const String earningItems = '/loyalty/earning-items';
  static const String members = '/loyalty/members';
  static const String analytics = '/loyalty/analytics';
  static const String menuItems = '/menu-items';
  static const String customers = '/customers';

  /// Every query that shows a person (`isPersonQuery`): a customer and their
  /// card share an id, so a write to either side stales both.
  static const List<String> people = ['/customers', '/loyalty/'];
}

// ── Who may do what (`loyalty/shared/access.ts`, `customers/access.ts`) ──

typedef LoyaltyAccess = ({
  bool canReadProgram,
  bool canEditProgram,
  bool canListMembers,
  bool canViewMember,
  bool canAdjust,
  bool canForget,
  bool canInspectWallet,
  bool canViewCustomers,
});

LoyaltyAccess loyaltyAccessOf(Authz a) => (
  canReadProgram: a.can(Cap.loyaltyRead),
  canEditProgram: a.can(Cap.loyaltyUse),
  canListMembers: a.can(Cap.loyaltyMembersList),
  canViewMember: a.canAny(const [Cap.loyaltyMembersList, Cap.loyaltyRead]),
  canAdjust: a.can(Cap.loyaltyPointsAdjust),
  canForget: a.can(Cap.loyaltyMembersDelete),
  canInspectWallet: a.platform,
  canViewCustomers: a.can(Cap.customersView),
);

final loyaltyAccessProvider = Provider<LoyaltyAccess>(
  (ref) => loyaltyAccessOf(ref.watch(authzProvider)),
);

/// Which endpoint the Members tab reads (`peopleSource(access, true)`):
/// `/customers?member=true` for someone who may see customers, the loyalty
/// members endpoint otherwise; null without `loyalty.members.list`.
enum MembersSource { customers, members }

MembersSource? membersSourceOf(LoyaltyAccess a) => !a.canListMembers
    ? null
    : (a.canViewCustomers ? MembersSource.customers : MembersSource.members);

// ── Units (`loyalty/shared/util.ts`) ──────────────────────────────────────

/// `modeOf`: the programme collects stamps ("visits") or points.
String loyaltyModeOf(LoyaltySettings? s) =>
    s?.mode == 'visits' ? 'visits' : 'points';

/// `currencyLabel(mode, count)`: "points" / "orders", plural-aware (Arabic has
/// six forms); no count reads as many.
String loyaltyUnit(Translator t, String mode, [num? count]) => t(
  mode == 'visits' ? 'loyalty.unitOrders' : 'loyalty.unitPoints',
  count: count ?? 2,
);

/// `costLabel`: "5 orders".
String loyaltyCost(Translator t, String mode, int amount) =>
    '$amount ${loyaltyUnit(t, mode, amount)}';

/// The settings row answered for [branchId] is the organisation's, not the
/// branch's own (`!isOwnOverride`).
bool settingsInherited(LoyaltySettings? s, String? branchId) =>
    branchId != null && s?.branchId != branchId;

// ── The programme form (`program/form-schema.ts`) ─────────────────────────

/// The form's values, keyed by the wire names; switches are bools, every
/// typed field a string ("none" is an empty field). Equality is by value, so
/// "changed" is a comparison with what was seeded (react-hook-form's
/// `isDirty`).
@immutable
class ProgramValues {
  ProgramValues(Map<String, Object> values) : _v = Map.unmodifiable(values);

  final Map<String, Object> _v;

  bool flag(String key) => _v[key] == true;
  String text(String key) => _v[key] as String? ?? '';
  String get mode => text('mode') == 'visits' ? 'visits' : 'points';

  ProgramValues set(String key, Object value) =>
      ProgramValues({..._v, key: value});

  @override
  bool operator ==(Object other) =>
      other is ProgramValues && mapEquals(other._v, _v);

  @override
  int get hashCode => Object.hashAllUnordered(
    _v.entries.map((e) => Object.hash(e.key, e.value)),
  );
}

String _egp(int piastres) =>
    piastres % 100 == 0 ? '${piastres ~/ 100}' : (piastres / 100).toString();

String _positive(int? n) => n != null && n > 0 ? '$n' : '';

/// `fromWire`: the saved settings as the form holds them.
ProgramValues programFromWire(LoyaltySettings s) => ProgramValues({
  'enabled': s.enabled,
  'program_name': s.programName,
  'program_name_ar': s.programNameAr ?? '',
  'mode': loyaltyModeOf(s),
  'earn_egp_per_point': _egp(s.earnPiastresPerPoint),
  'earn_on_discounted': s.earnOnDiscounted,
  'earn_include_tax': s.earnIncludeTax,
  // Null only from a server that predates the field: per-order.
  'stamp_per_line_item': s.stampPerLineItem ?? false,
  'default_reward_cost': '${s.defaultRewardCost}',
  'reward_any_item': s.rewardAnyItem ?? false,
  'balance_cap_enabled': s.balanceCapEnabled ?? false,
  'balance_cap': s.balanceCap == null ? '' : '${s.balanceCap}',
  'max_rewards_per_order': _positive(s.maxRewardsPerOrder),
  'require_otp': s.requireOtp,
  'birthday_enabled': s.birthdayEnabled ?? false,
  'birthday_reward_amount': s.birthdayRewardAmount == 0
      ? ''
      : '${s.birthdayRewardAmount ?? ''}',
  'birthday_message': s.birthdayMessage ?? '',
  'birthday_message_ar': s.birthdayMessageAr ?? '',
  'winback_enabled': s.winbackEnabled ?? false,
  'winback_message': s.winbackMessage ?? '',
  'winback_reward_amount': s.winbackRewardAmount == 0
      ? ''
      : '${s.winbackRewardAmount ?? ''}',
  'terms': s.terms ?? '',
});

final RegExp _wholeDigits = RegExp(r'^\d+$');
const int _int32Max = 2147483647;

/// `optionalPositiveInt`: empty, or a whole number above zero.
bool optionalPositiveInt(String v) {
  final s = v.trim();
  if (s.isEmpty) return true;
  final n = int.tryParse(s);
  return _wholeDigits.hasMatch(s) && n != null && n > 0 && n <= _int32Max;
}

/// `intOrNull`: the parsed whole number above zero, or null.
int? intOrNull(String v) {
  final s = v.trim();
  final n = num.tryParse(s);
  if (s.isEmpty || n == null || n != n.truncateToDouble() || n <= 0) {
    return null;
  }
  return n.toInt();
}

/// The optional whole-number fields, validated whether or not they show
/// (SET-LOY-083: a hidden invalid value still blocks Save).
const List<String> programOptionalInts = [
  'balance_cap',
  'max_rewards_per_order',
  'birthday_reward_amount',
  'winback_reward_amount',
];

/// `programSchema`: each invalid field and its message KEY.
Map<String, String> validateProgram(ProgramValues v) {
  final e = <String, String>{};
  if (v.text('program_name').trim().isEmpty) {
    e['program_name'] = 'loyalty.errors.nameRequired';
  }
  final rateText = v.text('earn_egp_per_point').trim();
  // `z.coerce.number()`: an empty field is 0.
  final rate = rateText.isEmpty ? 0 : double.tryParse(rateText);
  if (rate == null || rate < 0.01 || rate > 1000000) {
    e['earn_egp_per_point'] = 'loyalty.errors.earnRate';
  }
  final costText = v.text('default_reward_cost').trim();
  final cost = costText.isEmpty ? 0 : num.tryParse(costText);
  if (cost == null || cost != cost.truncateToDouble() || cost <= 0) {
    e['default_reward_cost'] = 'loyalty.errors.positiveInt';
  }
  for (final k in programOptionalInts) {
    if (!optionalPositiveInt(v.text(k))) {
      e[k] = 'loyalty.errors.optionalPositiveInt';
    }
  }
  return e;
}

/// Every nullable key a settings body carries as an explicit null (the web
/// sends `{...saved, …}` with its nulls).
const Set<String> _settingsNullables = {
  'allow_negative_balance',
  'balance_cap',
  'balance_cap_enabled',
  'birthday_enabled',
  'birthday_message',
  'birthday_message_ar',
  'birthday_reward_amount',
  'branch_id',
  'effective_balance_cap',
  'geofenced_branches',
  'max_rewards_per_order',
  'program_name_ar',
  'reward_any_item',
  'stamp_per_line_item',
  'terms',
  'terms_ar',
  'winback_enabled',
  'winback_message',
  'winback_reward_amount',
};

String? _orNull(String s) => s.isEmpty ? null : s;

/// `toWire`: the saved settings with the form on top. A gift or a message
/// goes with its feature (off = null); the cap figure only with the cap on;
/// names trimmed; empty texts null; EGP → piastres, rounded.
LoyaltySettings programToWire(
  ProgramValues v, {
  required String orgId,
  required String? branchId,
  required LoyaltySettings saved,
}) {
  final birthday = v.flag('birthday_enabled');
  final winback = v.flag('winback_enabled');
  final rate = double.tryParse(v.text('earn_egp_per_point').trim()) ?? 0;
  return LoyaltySettings(
    allowNegativeBalance: saved.allowNegativeBalance,
    balanceCap: v.flag('balance_cap_enabled')
        ? intOrNull(v.text('balance_cap'))
        : null,
    balanceCapEnabled: v.flag('balance_cap_enabled'),
    birthdayEnabled: birthday,
    birthdayMessage: birthday ? _orNull(v.text('birthday_message')) : null,
    birthdayMessageAr: birthday ? _orNull(v.text('birthday_message_ar')) : null,
    birthdayRewardAmount: birthday
        ? intOrNull(v.text('birthday_reward_amount'))
        : null,
    branchId: branchId,
    defaultRewardCost: num.parse(v.text('default_reward_cost').trim()).toInt(),
    earnIncludeTax: v.flag('earn_include_tax'),
    earnOnDiscounted: v.flag('earn_on_discounted'),
    earnPiastresPerPoint: (rate * 100).round(),
    effectiveBalanceCap: saved.effectiveBalanceCap,
    enabled: v.flag('enabled'),
    geofencedBranches: saved.geofencedBranches,
    maxRewardsPerOrder: intOrNull(v.text('max_rewards_per_order')),
    mode: v.mode,
    orgId: orgId,
    programName: v.text('program_name').trim(),
    programNameAr: _orNull(v.text('program_name_ar').trim()),
    requireOtp: v.flag('require_otp'),
    rewardAnyItem: v.flag('reward_any_item'),
    // Always concrete: an omission tells the server "leave it".
    stampPerLineItem: v.flag('stamp_per_line_item'),
    terms: _orNull(v.text('terms')),
    termsAr: saved.termsAr,
    winbackEnabled: winback,
    winbackMessage: winback ? _orNull(v.text('winback_message')) : null,
    winbackRewardAmount: winback
        ? intOrNull(v.text('winback_reward_amount'))
        : null,
    explicitNulls: _settingsNullables,
  );
}

/// `previewOf`: what the birthday preview renders — the saved settings with
/// the live edits on top; null while birthdays are off.
LoyaltySettings? birthdayPreviewOf(ProgramValues v, LoyaltySettings saved) {
  if (!v.flag('birthday_enabled')) return null;
  final name = v.text('program_name');
  return LoyaltySettings.fromJson({
    ...saved.toJson(),
    'program_name': name.isEmpty ? saved.programName : name,
    'mode': v.mode,
    'birthday_reward_amount': intOrNull(v.text('birthday_reward_amount')),
    'birthday_message': _orNull(v.text('birthday_message')),
    'birthday_message_ar': _orNull(v.text('birthday_message_ar')),
  });
}

/// The preview's debounce trigger (`key`): the five fields it renders from.
String birthdayPreviewKey(LoyaltySettings s) => [
  s.birthdayMessage,
  s.birthdayMessageAr,
  s.birthdayRewardAmount,
  s.mode,
  s.programName,
].join('\u0000');

// ── The reward catalogue (`rewards/catalogue-schema.ts`) ──────────────────

const int rewardMaxCost = 1000000;

/// One editor row: the cost as typed.
typedef RewardRow = ({String menuItemId, String name, String cost});

/// Why a row cannot be saved as it stands.
enum RewardProblem { cost, duplicate, unavailable, inactive }

/// `inactive` only warns; the rest make the server refuse.
bool rewardBlocking(RewardProblem? p) =>
    p != null && p != RewardProblem.inactive;

/// `isOfferable` / `isPickable`: exists, not deleted, on sale.
bool menuItemOfferable(MenuItem m) => m.isActive && m.deletedAt == null;

int? rewardCostOf(String text) {
  final n = num.tryParse(text.trim());
  if (n == null || n != n.truncateToDouble()) return null;
  final i = n.toInt();
  return i > 0 && i <= rewardMaxCost ? i : null;
}

List<RewardRow> rewardRowsFrom(List<RewardItem> items) => [
  for (final i in items)
    (menuItemId: i.menuItemId, name: i.name, cost: '${i.costAmount}'),
];

/// `rowProblems`: index-aligned; nothing flagged unavailable while [menu]
/// (null) is still loading.
List<RewardProblem?> rewardProblems(
  List<RewardRow> rows,
  List<MenuItem>? menu,
) {
  final byId = menu == null ? null : {for (final m in menu) m.id: m};
  final seen = <String>{};
  return [
    for (final r in rows)
      () {
        final dup = !seen.add(r.menuItemId);
        if (rewardCostOf(r.cost) == null) return RewardProblem.cost;
        if (dup) return RewardProblem.duplicate;
        if (byId != null) {
          final m = byId[r.menuItemId];
          if (m == null || m.deletedAt != null) {
            return RewardProblem.unavailable;
          }
          if (!m.isActive) return RewardProblem.inactive;
        }
        return null;
      }(),
  ];
}

/// `catalogueChanged`: length, order, item or cost differs.
bool rewardsChanged(List<RewardRow> rows, List<RewardItem> saved) {
  if (rows.length != saved.length) return true;
  for (var i = 0; i < rows.length; i++) {
    if (rows[i].menuItemId != saved[i].menuItemId) return true;
    final c = num.tryParse(rows[i].cost.trim());
    if (c == null || c != saved[i].costAmount) return true;
  }
  return false;
}

/// `rowsToWire`: priced in the scope's currency.
List<RewardItemInput> rewardsToWire(List<RewardRow> rows, String mode) => [
  for (final r in rows)
    RewardItemInput(
      menuItemId: r.menuItemId,
      costCurrency: mode,
      costAmount: rewardCostOf(r.cost),
    ),
];

// ── The items that collect a stamp (`rewards/earning-schema.ts`) ──────────

typedef EarningRow = ({String menuItemId, String name});

List<EarningRow> earningRowsFrom(List<EarningItem> items) => [
  for (final i in items) (menuItemId: i.menuItemId, name: i.name),
];

/// Ids alone, in order, deduplicated.
List<String> earningToWire(List<EarningRow> rows) {
  final seen = <String>{};
  return [
    for (final r in rows)
      if (seen.add(r.menuItemId)) r.menuItemId,
  ];
}

/// Changed as SETS: a reorder alone is not a change.
bool earningChanged(List<EarningRow> rows, List<EarningItem> saved) {
  final a = earningToWire(rows).toSet();
  final b = {for (final i in saved) i.menuItemId};
  return a.length != b.length || !a.containsAll(b);
}

// ── Members (`customers/util.ts`) ─────────────────────────────────────────

/// A list window grows by this much per "Load more".
const int membersPageSize = 50;

/// The server clamps `/customers` to 500 and `/loyalty/members` to 200.
const int customersLimitMax = 500;
const int membersLimitMax = 200;

/// Where a customer first came from, in filter order (`SOURCES`).
const List<String> customerSources = [
  'pos',
  'online',
  'loyalty',
  'booking',
  'table_qr',
  'aggregator',
  'dashboard',
];

bool isCustomerSource(String? v) => v != null && customerSources.contains(v);

/// One row of the members list, whichever endpoint it came from.
@immutable
class PersonRow {
  const PersonRow({
    required this.id,
    required this.name,
    required this.phone,
    required this.balance,
    required this.mode,
    this.customer,
    this.member,
  });

  /// `rowOfCustomer`: [mode] is the programme in force, null when unreadable.
  factory PersonRow.ofCustomer(Customer c, String? mode) => PersonRow(
    id: c.id,
    name: c.name,
    phone: c.phone,
    balance: c.isMember != true || mode == null
        ? null
        : ((mode == 'visits' ? c.visitsBalance : c.pointsBalance) ?? 0),
    mode: mode,
    customer: c,
  );

  /// `rowOfMember`.
  factory PersonRow.ofMember(MemberView m) => PersonRow(
    id: m.id,
    name: m.name,
    phone: m.phone,
    balance: m.balance,
    mode: m.mode,
    member: m,
  );

  final String id;
  final String name;
  final String? phone;
  final int? balance;
  final String? mode;
  final Customer? customer;
  final MemberView? member;
}

// ── The ledger (`members/ledger.ts`) ──────────────────────────────────────

/// The ledger the member read carries at most.
const int ledgerShownMax = 200;

enum LedgerTone { earn, spend, reversal, gift, manual }

LedgerTone ledgerTone(LedgerEntry e) {
  if (e.kind.startsWith('reverse_')) return LedgerTone.reversal;
  if (e.source == 'manual') return LedgerTone.manual;
  if (e.source == 'birthday' || e.source == 'winback') return LedgerTone.gift;
  if (e.kind == 'redeem') return LedgerTone.spend;
  return LedgerTone.earn;
}

/// The sentence a manager needs for a row's kind and cause.
String ledgerLabel(LedgerEntry e, Translator t) {
  if (e.kind.startsWith('reverse_')) {
    final what = e.kind.substring('reverse_'.length);
    if (e.source == 'refund') {
      return what == 'redeem'
          ? t('loyalty.ledger.refundRedeem')
          : t('loyalty.ledger.refundEarn');
    }
    if (e.source == 'void') {
      return switch (what) {
        'redeem' => t('loyalty.ledger.voidRedeem'),
        'adjust' => t('loyalty.ledger.voidAdjust'),
        _ => t('loyalty.ledger.voidEarn'),
      };
    }
    return t('loyalty.ledger.reversal');
  }
  return switch (e.source) {
    'sale' => t('loyalty.ledger.sale'),
    'redemption' => t('loyalty.ledger.redemption'),
    'birthday' => t('loyalty.ledger.birthday'),
    'winback' => t('loyalty.ledger.winback'),
    'manual' => t('loyalty.ledger.manual'),
    _ => e.kind,
  };
}

/// Ids of rows a later reversal undoes.
Set<String> ledgerReversedIds(Iterable<LedgerEntry> entries) => {
  for (final e in entries)
    if (e.reversesId case final id? when id.isNotEmpty) id,
};

/// "+12" / "−5" with a true minus / "0".
String ledgerSigned(int n) => n > 0 ? '+$n' : (n < 0 ? '−${n.abs()}' : '0');

/// "by Mona"; "by —" when the author's account is gone (SET-LOY-084);
/// "automatic" only for a row with no author at all.
String ledgerActor(LedgerEntry e, Translator t) {
  final name = e.createdByName;
  if (name != null && name.isNotEmpty) {
    return t('loyalty.ledger.by', args: {'name': name});
  }
  if (e.createdBy != null) return t('loyalty.ledger.by', args: {'name': '—'});
  return t('loyalty.ledger.bySystem');
}

// ── Adjust (`members/adjust-schema.ts`) ───────────────────────────────────

const int adjustLimit = 1000000;
const int adjustReasonMin = 3;
const int adjustReasonMax = 500;

// ── Errors (`loyalty/shared/server-errors.ts`) ────────────────────────────

enum LoyaltyRefusal { noteRequired, inactiveReward, other }

/// The refusals a person can fix from the screen they are on, in their
/// language; anything else as the server said it.
({LoyaltyRefusal kind, String message}) loyaltyServerError(
  Object? e,
  Translator t,
) {
  final d = e is ApiException ? e.details : null;
  // The backend's own (English) sentence names the refusal; the message
  // beside it may already be in Arabic.
  final text = [
    if (e is ApiException) e.message,
    if (d is Map) d['error'],
    if (d is Map) d['message'],
  ].whereType<String>().join(' ');
  if (RegExp(r'\(note\)|adjusted', caseSensitive: false).hasMatch(text) &&
      RegExp('say why|note', caseSensitive: false).hasMatch(text)) {
    return (
      kind: LoyaltyRefusal.noteRequired,
      message: t('loyalty.errors.serverNoteRequired'),
    );
  }
  if (RegExp('active menu items', caseSensitive: false).hasMatch(text)) {
    return (
      kind: LoyaltyRefusal.inactiveReward,
      message: t('loyalty.errors.serverInactiveReward'),
    );
  }
  return (kind: LoyaltyRefusal.other, message: errorMessage(e, t));
}

// ── Reads ─────────────────────────────────────────────────────────────────

/// `GET /loyalty/settings[?branch_id]` (`useGetLoyaltySettings`): the
/// programme in force (null branch = the organisation's own row).
final loyaltySettingsProvider = FutureProvider.autoDispose
    .family<LoyaltySettings, String?>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(LoyaltyPaths.settings));
      return ref
          .watch(apiProvider)
          .loyalty
          .getLoyaltySettings(branchId: branchId);
    });

/// `GET /loyalty/reward-items[?branch_id]`.
final rewardItemsProvider = FutureProvider.autoDispose
    .family<RewardCatalogue, String?>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(LoyaltyPaths.rewardItems));
      return ref
          .watch(apiProvider)
          .loyalty
          .getLoyaltyRewardItems(branchId: branchId);
    });

/// `GET /loyalty/earning-items[?branch_id]`.
final earningItemsProvider = FutureProvider.autoDispose
    .family<EarningItemList, String?>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(LoyaltyPaths.earningItems));
      return ref
          .watch(apiProvider)
          .loyalty
          .getLoyaltyEarningItems(branchId: branchId);
    });

/// `GET /menu-items?org_id=` (`useListMenuItems({org_id})`).
final loyaltyMenuProvider = FutureProvider.autoDispose
    .family<List<MenuItem>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(LoyaltyPaths.menuItems));
      return ref.watch(apiProvider).menu.listMenuItems(orgId: orgId);
    });

/// The arguments of [memberCustomersProvider].
typedef MemberCustomersQuery = ({String q, String? source, int limit});

/// `GET /customers?q&member=true&source&limit&offset=0` — the Members tab's
/// list for someone who may see customers.
final memberCustomersProvider = FutureProvider.autoDispose
    .family<List<Customer>, MemberCustomersQuery>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(LoyaltyPaths.customers));
      return ref
          .watch(apiProvider)
          .customers
          .listCustomers(
            q: k.q.isEmpty ? null : k.q,
            member: true,
            source: k.source,
            limit: k.limit,
            offset: 0,
          );
    });

/// The arguments of [loyaltyMembersProvider].
typedef MembersQuery = ({String? branchId, String q, int limit});

/// `GET /loyalty/members?branch_id&q&limit` — the Members tab for someone
/// holding only the loyalty side, and the Overview's member total (limit 1).
final loyaltyMembersProvider = FutureProvider.autoDispose
    .family<MembersPage, MembersQuery>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(LoyaltyPaths.members));
      return ref
          .watch(apiProvider)
          .loyalty
          .listLoyaltyMembers(
            branchId: k.branchId,
            q: k.q.isEmpty ? null : k.q,
            limit: k.limit,
          );
    });

/// The arguments of [loyaltyMemberProvider].
typedef MemberKey = ({String id, String? branchId});

/// `GET /loyalty/members/{id}[?branch_id]` (asked once: `retry: false`).
final loyaltyMemberProvider = FutureProvider.autoDispose
    .family<MemberDetail, MemberKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('${LoyaltyPaths.members}/${k.id}'));
      return ref
          .watch(apiProvider)
          .loyalty
          .getLoyaltyMember(id: k.id, branchId: k.branchId);
    }, retry: (_, _) => null);

/// `GET /loyalty/members/{id}/google-object`: a live read of Google, never
/// cached (`staleTime: 0, gcTime: 0`) — so no `webCache()`.
final googleObjectProvider = FutureProvider.autoDispose
    .family<GoogleObjectDump, String>(
      (ref, id) =>
          ref.watch(apiProvider).loyalty.getLoyaltyGoogleObject(id: id),
    );

/// The arguments of [loyaltyQrProvider].
typedef LoyaltyQrKey = ({String orgId, String? branchId});

/// `GET /branches/{id}/loyalty-qr` (a branch in scope) or
/// `GET /orgs/{id}/loyalty-qr`: the sign-up code. The web asks on each
/// press; kept here so the button's intent can warm it. A programme save
/// re-reads it (switching the programme off refuses the code), and it is
/// asked once, like the web's plain call.
final loyaltyQrProvider = FutureProvider.autoDispose
    .family<QrResponse, LoyaltyQrKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(LoyaltyPaths.settings));
      final qr = ref.watch(apiProvider).qr;
      final branchId = k.branchId;
      return branchId != null
          ? qr.branchLoyaltyQr(id: branchId)
          : qr.orgLoyaltyQr(id: k.orgId);
    }, retry: (_, _) => null);

/// The API with [headers] on every request (the export's
/// `X-Madar-Export: 1`).
DashboardApi apiWithHeaders(ApiTransport inner, Map<String, String> headers) =>
    DashboardApi(_HeaderTransport(inner, headers));

class _HeaderTransport implements ApiTransport {
  _HeaderTransport(this.inner, this.headers);

  final ApiTransport inner;
  final Map<String, String> headers;

  ApiRequest _with(ApiRequest r) => ApiRequest(
    method: r.method,
    path: r.path,
    query: r.query,
    body: r.body,
    files: r.files,
    headers: {...r.headers, ...headers},
  );

  @override
  Future<ApiResponse> send(ApiRequest request) => inner.send(_with(request));

  @override
  Stream<String> stream(ApiRequest request) => inner.stream(_with(request));
}

// ── Phones (`lib/phone.ts`, the sell area's copy of the one rule) ─────────

final RegExp _nonDigits = RegExp('[^0-9]');
final RegExp _egMobilePrefix = RegExp(r'^201[0125]');
final RegExp _egMobileGroups = RegExp(r'^20(1\d{2})(\d{3})(\d{4})$');

/// A phone for reading: `+20 100 123 4567` for an Egyptian mobile,
/// `+<digits>` for another number, anything else as given. Always LTR.
String formatPhoneDisplay(String? phone) {
  if (phone == null || phone.isEmpty) return '';
  if (phone.runes.length > 32) return phone;
  final ascii = String.fromCharCodes(
    phone.runes.map(
      (r) => r >= 0x0660 && r <= 0x0669
          ? 0x30 + r - 0x0660
          : (r >= 0x06F0 && r <= 0x06F9 ? 0x30 + r - 0x06F0 : r),
    ),
  );
  var d = ascii.replaceAll(_nonDigits, '');
  if (d.startsWith('00')) {
    d = d.substring(2);
  } else if (d.startsWith('20')) {
    // Already country-coded.
  } else if (d.startsWith('0')) {
    d = '20${d.substring(1)}';
  } else if (d.length == 10 && d.startsWith('1')) {
    d = '20$d';
  }
  if (d.length < 10 || d.length > 15) return phone;
  if (_egMobilePrefix.hasMatch(d) && d.length != 12) return phone;
  final m = _egMobileGroups.firstMatch(d);
  return m != null ? '+20 ${m[1]} ${m[2]} ${m[3]}' : '+$d';
}
