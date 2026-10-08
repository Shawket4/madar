/// The customers unit's vocabulary, rules and reads: the web's
/// `features/customers/{access,util}.ts`, `features/loyalty/shared/{access,
/// util,server-errors}.ts`, `features/loyalty/admin/members/{ledger,
/// adjust-schema}.ts` and `data/api/errors.ts` (`getErrorMessage`), plus one
/// Riverpod provider per web query hook.
///
/// Every read here watches the realtime epoch of its own path, so
/// [invalidatePeople] (the web's `isPersonQuery` predicate: every
/// `/customers…` and `/loyalty/…` key) refetches exactly what the web's React
/// Query refetches.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/invalidate.dart';

// ── Limits (`customers/util.ts`, `adjust-schema.ts`) ──────────────────────

const int customerNameMax = 120;
const int customerNotesMax = 2000;

/// A list window grows by this much per "Load more" (`PAGE_SIZE`).
const int customersPageSize = 50;

/// The server clamps `limit` to 500 (`LIMIT_MAX`).
const int customersLimitMax = 500;

/// The merge picker's server search asks for this many.
const int mergePickLimit = 20;

/// A customer's bookings, a page at a time (`bookings-section.tsx` `PAGE`).
const int customerBookingsPage = 10;

/// The ledger the member read carries at most (`ledgerTruncated`).
const int ledgerShownMax = 200;

const int adjustLimit = 1000000;
const int adjustReasonMin = 3;
const int adjustReasonMax = 500;

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

// ── Who may see and do what (`customers/access.ts`, loyalty `access.ts`) ──

/// The two capability families that meet on a person and never widen each
/// other: `customers.*` opens the customer, `loyalty.*` opens the card.
@immutable
class PeopleAccess {
  const PeopleAccess({
    required this.ready,
    required this.canViewCustomers,
    required this.canCreate,
    required this.canEdit,
    required this.canMerge,
    required this.canErase,
    required this.canViewAddresses,
    required this.canReadProgram,
    required this.canListMembers,
    required this.canViewMember,
    required this.canAdjust,
    required this.canForget,
    required this.canInspectWallet,
    required this.canOpenBookings,
  });

  factory PeopleAccess.of(Authz a) => PeopleAccess(
    ready: a.ready,
    canViewCustomers: a.can(Cap.customersView),
    canCreate: a.can(Cap.customersCreate),
    canEdit: a.can(Cap.customersEdit),
    canMerge: a.can(Cap.customersMerge),
    canErase: a.can(Cap.customersErase),
    canViewAddresses: a.can(Cap.customersAddressesView),
    canReadProgram: a.can(Cap.loyaltyRead),
    canListMembers: a.can(Cap.loyaltyMembersList),
    canViewMember: a.canAny(const [Cap.loyaltyMembersList, Cap.loyaltyRead]),
    canAdjust: a.can(Cap.loyaltyPointsAdjust),
    canForget: a.can(Cap.loyaltyMembersDelete),
    canInspectWallet: a.platform,
    canOpenBookings: a.can(Cap.bookingsRead),
  );

  /// Permissions are known (`authz.ready`).
  final bool ready;
  final bool canViewCustomers;
  final bool canCreate;
  final bool canEdit;

  /// Split from edit: a merge moves balances and retires a card.
  final bool canMerge;
  final bool canErase;

  /// Where they live is its own PII capability.
  final bool canViewAddresses;
  final bool canReadProgram;
  final bool canListMembers;
  final bool canViewMember;
  final bool canAdjust;
  final bool canForget;

  /// Google Wallet diagnostics: platform admins only.
  final bool canInspectWallet;

  /// A booking row opens its booking (`bookings.read`).
  final bool canOpenBookings;

  @override
  bool operator ==(Object other) =>
      other is PeopleAccess &&
      other.ready == ready &&
      other.canViewCustomers == canViewCustomers &&
      other.canCreate == canCreate &&
      other.canEdit == canEdit &&
      other.canMerge == canMerge &&
      other.canErase == canErase &&
      other.canViewAddresses == canViewAddresses &&
      other.canReadProgram == canReadProgram &&
      other.canListMembers == canListMembers &&
      other.canViewMember == canViewMember &&
      other.canAdjust == canAdjust &&
      other.canForget == canForget &&
      other.canInspectWallet == canInspectWallet &&
      other.canOpenBookings == canOpenBookings;

  @override
  int get hashCode => Object.hash(
    ready,
    canViewCustomers,
    canCreate,
    canEdit,
    canMerge,
    canErase,
    canViewAddresses,
    canReadProgram,
    canListMembers,
    canViewMember,
    canAdjust,
    canForget,
    canInspectWallet,
    canOpenBookings,
  );
}

final peopleAccessProvider = Provider<PeopleAccess>(
  (ref) => PeopleAccess.of(ref.watch(authzProvider)),
);

// ── Rows, balances, units ─────────────────────────────────────────────────

/// `modeOf`: the program collects stamps ("visits") or points.
String loyaltyModeOf(LoyaltySettings? s) =>
    s?.mode == 'visits' ? 'visits' : 'points';

/// `currencyLabel(mode, count)`: "points" / "orders" in the reader's
/// language, plural-aware (Arabic has six forms); no count reads as many.
String loyaltyUnit(Translator t, String mode, [num? count]) => t(
  mode == 'visits' ? 'loyalty.unitOrders' : 'loyalty.unitPoints',
  count: count ?? 2,
);

/// "120 points" (`${balance} ${currencyLabel(mode, balance)}`).
String loyaltyAmount(Translator t, String mode, int amount, {DashFormat? fmt}) =>
    '${fmt == null ? amount : fmt.fmtNumber(amount)} '
    '${loyaltyUnit(t, mode, amount)}';

/// One row of the people list (`PersonRow` from a customer).
@immutable
class PersonRow {
  const PersonRow({required this.customer, required this.mode});

  final Customer customer;

  /// The program in force, or null when the viewer may not read it.
  final String? mode;

  String get id => customer.id;
  String get name => customer.name;
  String? get phone => customer.phone;
  bool get isMember => customer.isMember ?? false;

  /// In the program's currency; null for a non-member or an unknown mode.
  int? get balance => !isMember || mode == null
      ? null
      : ((mode == 'visits'
                ? customer.visitsBalance
                : customer.pointsBalance) ??
            0);
}

// ── Birthdays, addresses ──────────────────────────────────────────────────

const List<String> _monthsLongEn = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];
const List<String> _monthsLongAr = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', //
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

String _arabicIndic(String s) => String.fromCharCodes(
  s.codeUnits.map((c) => c >= 0x30 && c <= 0x39 ? 0x0660 + c - 0x30 : c),
);

/// `formatBirthday`: "14 March" / "١٤ مارس" (`Intl` `{day: numeric, month:
/// long}` in the UI language — Arabic's own digits there, as the web's
/// browser formats it); a birthday has no year. Null when not given or not a
/// real day (29 February survives: the web formats it in 2024).
String? formatBirthday(int? month, int? day, String lang) {
  if (month == null || day == null || month < 1 || month > 12 || day < 1) {
    return null;
  }
  final d = DateTime.utc(2024, month, day);
  final ar = lang.startsWith('ar');
  final name = (ar ? _monthsLongAr : _monthsLongEn)[d.month - 1];
  return ar ? '${_arabicIndic('${d.day}')} $name' : '${d.day} $name';
}

/// `formatAddress`: place, "Unit n", "Floor n", street, landmark — trimmed,
/// blanks dropped, joined " · ".
String formatAddressLine(CustomerAddress a, Translator t) => [
  a.placeName,
  if (a.unitNumber case final u? when u.trim().isNotEmpty)
    t('customers.addresses.unit', args: {'n': u}),
  if (a.floor case final f? when f.trim().isNotEmpty)
    t('customers.addresses.floor', args: {'n': f}),
  a.addressLine,
  a.landmark,
].map((p) => p?.trim() ?? '').where((p) => p.isNotEmpty).join(' · ');

/// An address channel's name, or the raw code for one the tables lack.
String addressChannel(Translator t, String channel) =>
    t('customers.addresses.channel.$channel', defaultValue: channel);

// ── The ledger (`ledger.ts`) ──────────────────────────────────────────────

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
Set<String> reversedIds(Iterable<LedgerEntry> entries) => {
  for (final e in entries)
    if (e.reversesId case final id? when id.isNotEmpty) id,
};

/// "+12" / "−5" with a true minus / "0".
String signedAmount(int n) => n > 0 ? '+$n' : (n < 0 ? '−${n.abs()}' : '0');

/// "by Mona" for a person, "automatic" for the system.
String ledgerActor(LedgerEntry e, Translator t) {
  final name = e.createdByName;
  if (name != null && name.isNotEmpty) {
    return t('loyalty.ledger.by', args: {'name': name});
  }
  if (e.createdBy != null) return t('loyalty.ledger.by', args: {'name': '—'});
  return t('loyalty.ledger.bySystem');
}

// ── Errors (`getErrorMessage`, SELL-ALL-017) ──────────────────────────────

final RegExp _serverKind = RegExp(
  r'^(?:Unauthorized|Forbidden|Not found|Bad request|Conflict|Service unavailable|Database error): ',
);

/// The server's own sentence (`error`, else `message`), when it sent one.
String? serverText(Object? e) {
  if (e is! ApiException) return null;
  final d = e.details;
  if (d is Map) {
    final err = d['error'];
    if (err is String) return err;
    final msg = d['message'];
    if (msg is String) return msg;
  }
  return e.message.isEmpty ? null : e.message;
}

/// The words for a failed request, exactly as the web's `getErrorMessage`:
/// a known `code` reads its translation; an uncoded 429 / 403 reads
/// "too many requests" / "no permission" (never the server's English);
/// otherwise the server's sentence without its "Kind: " prefix; then by
/// status.
String peopleErrorMessage(Object? e, Translator t) {
  if (e is ApiException) {
    final code = e.code;
    if (code != null && t.exists('errors.codes.$code')) {
      final vars = e.details is Map ? (e.details! as Map)['vars'] : null;
      return t(
        'errors.codes.$code',
        args: vars is Map ? vars.cast<String, Object?>() : null,
      );
    }
    if (code == null && e.status == 429) return t('errors.tooManyRequests');
    if (code == null && e.status == 403) return t('errors.unauthorized');
    final text = serverText(e);
    if (text != null && text.isNotEmpty && e.status != 0) {
      return text.replaceFirst(_serverKind, '');
    }
    return switch (e.status) {
      0 => t('errors.networkError'),
      401 => t('errors.sessionExpired'),
      403 => t('errors.unauthorized'),
      404 => t('errors.notFound'),
      409 => t('errors.conflict'),
      422 => t('errors.validation'),
      >= 500 => t('errors.server'),
      _ => e.message,
    };
  }
  if (e is ExportTooLargeError) return e.message(t);
  return t('errors.unknown');
}

/// A 409 with the backend's [code] (`refusedWith`).
bool refusedWith(Object? e, String code) =>
    e is ApiException && e.status == 409 && e.code == code;

/// "Another customer already has this phone" (`isPhoneTaken`).
bool isPhoneTaken(Object? e) => refusedWith(e, 'CUSTOMER_PHONE_EXISTS');

/// Only the duplicate holds a card, so it must stay (`isMemberMustSurvive`).
bool isMemberMustSurvive(Object? e) =>
    refusedWith(e, 'CUSTOMER_MERGE_MEMBER_SURVIVES');

/// The loyalty endpoints' refusals the screen can point at
/// (`loyaltyServerError`): the adjust "note required" one gets its field.
({bool noteRequired, String message}) loyaltyServerError(
  Object? e,
  Translator t,
) {
  final text = (e is ApiException ? serverText(e) : null) ?? '';
  final mentionsNote = RegExp(r'\(note\)|adjusted', caseSensitive: false);
  final saysWhy = RegExp('say why|note', caseSensitive: false);
  if (mentionsNote.hasMatch(text) && saysWhy.hasMatch(text)) {
    return (
      noteRequired: true,
      message: t('loyalty.errors.serverNoteRequired'),
    );
  }
  return (noteRequired: false, message: peopleErrorMessage(e, t));
}

// ── Reads ─────────────────────────────────────────────────────────────────

/// Marks every person read stale (`invalidateQueries({predicate:
/// isPersonQuery})`).
void invalidatePeople(WidgetRef ref) =>
    sellInvalidateFromWidget(ref, SellInvalidate.people);

/// The arguments of [customersListProvider] (`useListCustomers`).
typedef CustomersQuery = ({String q, bool? member, String? source, int limit});

/// `GET /customers?q&member&source&limit&offset=0`.
final customersListProvider = FutureProvider.autoDispose
    .family<List<Customer>, CustomersQuery>((ref, k) {
      ref.watch(realtimeEpochProvider('/customers'));
      return ref
          .watch(apiProvider)
          .customers
          .listCustomers(
            q: k.q.isEmpty ? null : k.q,
            member: k.member,
            source: k.source,
            limit: k.limit,
            offset: 0,
          );
    });

/// `GET /loyalty/settings[?branch_id]` (`useGetLoyaltySettings`): the
/// program in force (null branch = the organisation's).
final loyaltySettingsProvider = FutureProvider.autoDispose
    .family<LoyaltySettings, String?>((ref, branchId) {
      ref.watch(realtimeEpochProvider('/loyalty/settings'));
      return ref
          .watch(apiProvider)
          .loyalty
          .getLoyaltySettings(branchId: branchId);
    });

/// `GET /customers/{id}` (`useGetCustomer`): a merged id resolves.
final customerDetailProvider = FutureProvider.autoDispose
    .family<CustomerDetail, String>((ref, id) {
      ref.watch(realtimeEpochProvider('/customers/$id'));
      return ref.watch(apiProvider).customers.getCustomer(id: id);
    });

/// The arguments of [loyaltyMemberProvider].
typedef MemberQuery = ({String id, String? branchId});

/// `GET /loyalty/members/{id}[?branch_id]` (`useGetLoyaltyMember`, no
/// retry).
final loyaltyMemberProvider = FutureProvider.autoDispose
    .family<MemberDetail, MemberQuery>((ref, k) {
      ref.watch(realtimeEpochProvider('/loyalty/members/${k.id}'));
      return ref
          .watch(apiProvider)
          .loyalty
          .getLoyaltyMember(id: k.id, branchId: k.branchId);
    });

/// `GET /customers/{id}/addresses` (`useListCustomerAddresses`).
final customerAddressesProvider = FutureProvider.autoDispose
    .family<List<CustomerAddress>, String>((ref, id) {
      ref.watch(realtimeEpochProvider('/customers/$id/addresses'));
      return ref.watch(apiProvider).customers.listCustomerAddresses(id: id);
    });

/// The arguments of [customerBookingsProvider].
typedef CustomerBookingsQuery = ({String id, int limit});

/// `GET /customers/{id}/bookings?limit&offset=0`
/// (`useListCustomerBookings`).
final customerBookingsProvider = FutureProvider.autoDispose
    .family<List<BookingView>, CustomerBookingsQuery>((ref, k) {
      ref.watch(realtimeEpochProvider('/customers/${k.id}/bookings'));
      return ref
          .watch(apiProvider)
          .customers
          .listCustomerBookings(id: k.id, limit: k.limit, offset: 0);
    });

/// The API with [headers] on every request (the export's
/// `X-Madar-Export: 1`, `EXPORT_REQUEST`).
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
