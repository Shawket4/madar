/// Payment methods: the reads, the invalidation and the browser-side rules
/// (web `features/payment-methods/util.ts`, `features/devices/api.ts`):
///
/// - one autoDispose read per endpoint, keyed by exactly the params the
///   request sends, each watching `realtimeEpochProvider(<its path>)` so the
///   `payment_methods.availability_changed` event and a save refetch it;
/// - [invalidatePaymentMethods]: the web's `invalidatePaymentMethods` /
///   `usePutAvailability` onSuccess (every `/payment-methods*` read);
/// - the icon and colour choices, the system method names, [labelOf];
/// - [allowListFor], [availabilityTellers]: what the Availability tab reads
///   off the payloads.
///
/// A failure shows `ApiException.message` (`errorMessage`): the transport
/// has already worded it.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        AllowList,
        Device,
        OrgPaymentMethod,
        PaymentMethodAvailability,
        UserPublic,
        UserRole;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The query-key paths (the web's Orval keys start with the path).
abstract final class PmPaths {
  static const String list = '/payment-methods';
  static const String availability = '/payment-methods/availability';
  static const String users = '/users';
  static const String devices = '/devices';
}

/// `GET /payment-methods` (useListPaymentMethods): paramless — the org rides
/// in `X-Org-Id`, and `webCache` keys the read by the org in scope.
final paymentMethodsProvider =
    FutureProvider.autoDispose<List<OrgPaymentMethod>>((ref) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(PmPaths.list));
      return ref.watch(apiProvider).paymentMethods.listPaymentMethods();
    });

/// `GET /payment-methods/availability?branch_id=` (useAvailability).
final pmAvailabilityProvider = FutureProvider.autoDispose
    .family<PaymentMethodAvailability, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(PmPaths.availability));
      return ref
          .watch(apiProvider)
          .paymentMethods
          .getAvailability(branchId: branchId);
    });

/// `GET /users?org_id=` (useListUsers({org_id})).
final pmUsersProvider = FutureProvider.autoDispose
    .family<List<UserPublic>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(PmPaths.users));
      return ref.watch(apiProvider).users.listUsers(orgId: orgId);
    });

/// `GET /devices?branch_id=` (useDevices).
final pmDevicesProvider = FutureProvider.autoDispose
    .family<List<Device>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(PmPaths.devices));
      return ref.watch(apiProvider).devices.listDevices(branchId: branchId);
    });

/// Every `/payment-methods*` read (the list and the availability), as the
/// web's predicate invalidation does after any write here. Take the bus
/// before the write's await: the refetch happens even when the dialog or the
/// page has gone meanwhile.
void invalidatePaymentMethods(RealtimeBus bus) =>
    bus.invalidate(const [PmPaths.list]);

/// One selectable icon: its id (stored on the method), its words and glyph.
typedef PmIcon = ({String id, String labelKey, String glyph});

/// `PM_ICONS`, in the web's order.
const List<PmIcon> pmIcons = [
  (id: 'money', labelKey: 'settings.pm.iconLabel.money', glyph: 'banknote'),
  (
    id: 'credit_card',
    labelKey: 'settings.pm.iconLabel.credit_card',
    glyph: 'credit-card',
  ),
  (id: 'wallet', labelKey: 'settings.pm.iconLabel.wallet', glyph: 'wallet'),
  (
    id: 'pie_chart',
    labelKey: 'settings.pm.iconLabel.pie_chart',
    glyph: 'pie-chart',
  ),
  (id: 'delivery', labelKey: 'settings.pm.iconLabel.delivery', glyph: 'truck'),
  (id: 'qr_code', labelKey: 'settings.pm.iconLabel.qr_code', glyph: 'qr-code'),
  (id: 'bank', labelKey: 'settings.pm.iconLabel.bank', glyph: 'landmark'),
  (id: 'gift_card', labelKey: 'settings.pm.iconLabel.gift_card', glyph: 'gift'),
  (
    id: 'smartphone',
    labelKey: 'settings.pm.iconLabel.smartphone',
    glyph: 'smartphone',
  ),
  (id: 'receipt', labelKey: 'settings.pm.iconLabel.receipt', glyph: 'receipt'),
  (id: 'store', labelKey: 'settings.pm.iconLabel.store', glyph: 'store'),
  (id: 'star', labelKey: 'settings.pm.iconLabel.star', glyph: 'star'),
  (id: 'link', labelKey: 'settings.pm.iconLabel.link', glyph: 'link'),
];

/// `iconFor`: the glyph of [id]; an id outside the list draws the banknote.
String pmGlyph(String id) =>
    pmIcons.where((i) => i.id == id).firstOrNull?.glyph ?? 'banknote';

/// `PM_COLORS`: user-chosen identity colours (data, not theme), drawn
/// literally in both themes.
const List<String> pmColors = [
  '#0F172A',
  '#334155',
  '#10B981',
  '#059669',
  '#3B82F6',
  '#2563EB',
  '#8B5CF6',
  '#7C3AED',
  '#F59E0B',
  '#D97706',
  '#EF4444',
  '#DC2626',
  '#EC4899',
  '#DB2777',
];

/// The new method's colour (`PM_COLORS[2]`).
const String pmDefaultColor = '#10B981';

/// `SYSTEM_METHODS`: the built-in names.
const List<String> pmSystemMethods = [
  'cash',
  'card',
  'digital_wallet',
  'mixed',
  'talabat_online',
  'talabat_cash',
];

bool isSystemMethod(OrgPaymentMethod m) => pmSystemMethods.contains(m.name);

/// What an identifier may be (`^[a-z0-9_]+$`).
final RegExp pmIdentifierPattern = RegExp(r'^[a-z0-9_]+$');

/// What typing into the identifier becomes: lowercased, and every character
/// outside `a-z0-9_` an underscore.
String sanitizeIdentifier(String raw) =>
    raw.toLowerCase().replaceAll(RegExp('[^a-z0-9_]'), '_');

/// The method's label translations as a plain map.
Map<String, String> pmTranslations(OrgPaymentMethod m) {
  final tr = m.labelTranslations;
  if (tr is! Map) return const {};
  return {
    for (final e in tr.entries)
      if (e.value is String) '${e.key}': e.value as String,
  };
}

/// `labelOf`: the label in [lang], else English, else Arabic, else the
/// identifier (an empty string counts as missing).
String labelOf(OrgPaymentMethod m, String lang) {
  final tr = pmTranslations(m);
  for (final k in [lang, 'en', 'ar']) {
    final v = tr[k];
    if (v != null && v.isNotEmpty) return v;
  }
  return m.name;
}

/// Whose allow-list an editor holds (`AvailabilityScope`).
enum PmOwner { branches, users, devices }

/// `allowListFor`: the branch's list as the server says; a teller or a
/// device is restricted exactly when it has a row.
AllowList allowListFor(
  PaymentMethodAvailability? a,
  PmOwner owner,
  String id,
) {
  const none = AllowList(restricted: false, paymentMethodIds: []);
  if (a == null) return none;
  if (owner == PmOwner.branches) return a.branch;
  final ids = owner == PmOwner.users
      ? a.users.where((u) => u.userId == id).firstOrNull?.paymentMethodIds
      : a.devices.where((d) => d.deviceId == id).firstOrNull?.paymentMethodIds;
  return ids == null
      ? none
      : AllowList(restricted: true, paymentMethodIds: ids);
}

/// The people the Tellers section lists: active tellers and branch managers
/// of [branchId] or of no branch, in the server's order.
List<UserPublic> availabilityTellers(List<UserPublic> users, String branchId) =>
    [
      for (final u in users)
        if (u.isActive &&
            (u.role == UserRole.teller || u.role == UserRole.branchManager) &&
            (u.branchId == null || u.branchId == branchId))
          u,
    ];

/// React Query's `isLoading`: the first load, nothing to show yet.
extension PmAsync<T> on AsyncValue<T> {
  bool get firstLoad => isLoading && !hasValue && !hasError;
}
