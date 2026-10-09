/// Delivery settings and zones: the reads, the invalidations and what the
/// web computes in the browser (`features/delivery/settings-page.tsx`,
/// `zones-page.tsx`, `zone-dialog.tsx`, `util.ts`).
///
/// - one autoDispose read per endpoint, keyed by exactly the params the
///   request sends, each watching `realtimeEpochProvider(<its path>)` so a
///   save here (and `resync`) refetches it;
/// - [invalidateBranchSettings] / [invalidateZones]: the web's predicate
///   invalidations (every key starting `/delivery/settings` or
///   `/delivery/zones`);
/// - [DeliveryForm]: the settings form's values and its wire body;
/// - the zone rules: ring numbering, the new-zone defaults, km ↔ m.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show BranchDeliverySettings, BranchSettingsInput, DeliveryZone, Discount;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The query-key paths (the web's Orval keys start with the path).
abstract final class DeliveryPaths {
  static const String settings = '/delivery/settings';
  static const String zones = '/delivery/zones';
  static const String discounts = '/discounts';
}

/// `GET /delivery/settings?branch_id=` (useGetBranchSettings).
final deliverySettingsProvider = FutureProvider.autoDispose
    .family<BranchDeliverySettings, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(DeliveryPaths.settings));
      return ref
          .watch(apiProvider)
          .delivery
          .getBranchSettings(branchId: branchId);
    });

/// `GET /discounts?org_id=` (useListDiscounts): the channel discount
/// choices; asked only with an org in scope.
final deliveryDiscountsProvider = FutureProvider.autoDispose
    .family<List<Discount>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(DeliveryPaths.discounts));
      return ref.watch(apiProvider).discounts.listDiscounts(orgId: orgId);
    });

/// `GET /delivery/zones?branch_id=` (useListZones).
final deliveryZonesProvider = FutureProvider.autoDispose
    .family<List<DeliveryZone>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider(DeliveryPaths.zones));
      return ref.watch(apiProvider).delivery.listZones(branchId: branchId);
    });

/// `invalidateBranchSettings`: every `/delivery/settings*` read. Take the
/// bus before the write's await, so the refetch happens even when the page
/// has gone meanwhile.
void invalidateBranchSettings(RealtimeBus bus) =>
    bus.invalidate(const [DeliveryPaths.settings]);

/// `invalidateZones`: every `/delivery/zones*` read.
void invalidateZones(RealtimeBus bus) =>
    bus.invalidate(const [DeliveryPaths.zones]);

/// `getTranslatedName`: the Arabic name in an Arabic UI when there is one,
/// else the name.
String translatedName(
  String name,
  Map<String, Object?> translations,
  String lang,
) {
  final ar = translations['ar'];
  return lang.startsWith('ar') && ar is String ? ar : name;
}

/// A discount as the channel select lists it: `<name> · 15%` for a
/// percentage, `<name> · EGP 25.00` for a fixed amount (the legacy `value`).
String discountLabel(Discount d, String lang, DashFormat fmt) {
  final value = d.dtype == 'percentage'
      ? '${d.value}%'
      : fmt.fmtMoney(d.value);
  return '${translatedName(d.name, d.nameTranslations, lang)} · $value';
}

// ── the settings form ─────────────────────────────────────────────────────

/// The four ways an order can reach a customer.
enum DeliveryChannel { inMall, outside, umbrella, pickup }

/// One channel's part of the form. Times are the wire's `HH:MM:SS` (or what
/// was typed when the time field could not read it), null when empty; the
/// fee is EGP as typed (null = empty, which counts as 0; NaN = unreadable).
class ChannelForm {
  ChannelForm({
    required this.enabled,
    this.open,
    this.close,
    this.fee,
    this.discountId,
  });

  bool enabled;
  String? open;
  String? close;
  double? fee;
  String? discountId;
}

/// The settings form's values (the web's zod form) and its PUT body.
class DeliveryForm {
  DeliveryForm.from(BranchDeliverySettings s)
    : channels = {
        DeliveryChannel.inMall: ChannelForm(
          enabled: s.inMallEnabled,
          open: s.inMallOpenTime,
          close: s.inMallCloseTime,
          fee: piastresToEgp(s.inMallFee),
          discountId: s.inMallDiscountId,
        ),
        DeliveryChannel.outside: ChannelForm(
          enabled: s.outsideEnabled,
          open: s.outsideOpenTime,
          close: s.outsideCloseTime,
          discountId: s.outsideDiscountId,
        ),
        DeliveryChannel.umbrella: ChannelForm(
          enabled: s.umbrellaEnabled,
          open: s.umbrellaOpenTime,
          close: s.umbrellaCloseTime,
          fee: piastresToEgp(s.umbrellaFee),
          discountId: s.umbrellaDiscountId,
        ),
        DeliveryChannel.pickup: ChannelForm(
          enabled: s.pickupEnabled,
          open: s.pickupOpenTime,
          close: s.pickupCloseTime,
          fee: piastresToEgp(s.pickupFee),
          discountId: s.pickupDiscountId,
        ),
      },
      maxDistance = s.maxRoadDistanceMeters?.toDouble(),
      otpRequired = s.otpRequired,
      requireLocation = s.inMallRequireLocation,
      prepMinutes = s.prepTimeMinutes.toDouble(),
      autoRejectMinutes = s.autoRejectMinutes;

  final Map<DeliveryChannel, ChannelForm> channels;

  /// Metres; null = never set (saved as null).
  double? maxDistance;

  /// The distance field was edited: emptied now, it reads as 0 and is
  /// refused (the web's `z.coerce` of `""`), never as "no limit".
  bool maxDistanceEdited = false;
  bool otpRequired;
  bool requireLocation;
  double? prepMinutes;

  /// Not on the form: sent back as read so a save never clears it.
  final int? autoRejectMinutes;

  ChannelForm operator [](DeliveryChannel c) => channels[c]!;

  /// "Fee cannot be negative" (empty is 0).
  static bool feeOk(double? v) => v == null || (!v.isNaN && v >= 0);

  /// "Prep time cannot be negative" (empty is 0).
  static bool prepOk(double? v) => v == null || (!v.isNaN && v >= 0);

  /// "Distance must be greater than 0", once the field was edited.
  bool get distanceOk => maxDistance == null
      ? !maxDistanceEdited
      : !maxDistance!.isNaN && maxDistance! > 0;

  /// The body of `PUT /delivery/settings`: every field, the switched-off
  /// channels' too; fees EGP → piastres; empties as explicit nulls.
  BranchSettingsInput toInput(String branchId) {
    int fee(DeliveryChannel c) => egpToPiastres(this[c].fee ?? 0);
    final distance = maxDistance?.round();
    final nulls = <String>{
      for (final (c, wire) in _wire) ...[
        if (this[c].open == null) '${wire}_open_time',
        if (this[c].close == null) '${wire}_close_time',
        if (this[c].discountId == null) '${wire}_discount_id',
      ],
      if (distance == null) 'max_road_distance_meters',
    };
    final inMall = this[DeliveryChannel.inMall];
    final outside = this[DeliveryChannel.outside];
    final umbrella = this[DeliveryChannel.umbrella];
    final pickup = this[DeliveryChannel.pickup];
    return BranchSettingsInput(
      branchId: branchId,
      inMallEnabled: inMall.enabled,
      outsideEnabled: outside.enabled,
      umbrellaEnabled: umbrella.enabled,
      pickupEnabled: pickup.enabled,
      inMallOpenTime: inMall.open,
      inMallCloseTime: inMall.close,
      outsideOpenTime: outside.open,
      outsideCloseTime: outside.close,
      umbrellaOpenTime: umbrella.open,
      umbrellaCloseTime: umbrella.close,
      pickupOpenTime: pickup.open,
      pickupCloseTime: pickup.close,
      inMallFee: fee(DeliveryChannel.inMall),
      umbrellaFee: fee(DeliveryChannel.umbrella),
      pickupFee: fee(DeliveryChannel.pickup),
      prepTimeMinutes: (prepMinutes ?? 0).round(),
      maxRoadDistanceMeters: distance,
      inMallDiscountId: inMall.discountId,
      outsideDiscountId: outside.discountId,
      umbrellaDiscountId: umbrella.discountId,
      pickupDiscountId: pickup.discountId,
      otpRequired: otpRequired,
      inMallRequireLocation: requireLocation,
      autoRejectMinutes: autoRejectMinutes,
      explicitNulls: nulls,
    );
  }

  static const List<(DeliveryChannel, String)> _wire = [
    (DeliveryChannel.inMall, 'in_mall'),
    (DeliveryChannel.outside, 'outside'),
    (DeliveryChannel.umbrella, 'umbrella'),
    (DeliveryChannel.pickup, 'pickup'),
  ];
}

/// The time field's answer as the form keeps it: `HH:MM` → `HH:MM:00`,
/// cleared → null, unreadable text as typed + `:00` (the web's
/// `TimePicker`; the server refuses it).
String? timeFromField(String v) => v.isEmpty ? null : '$v:00';

// ── zones ─────────────────────────────────────────────────────────────────

/// A zone with its display-only ring number.
typedef NumberedZone = ({DeliveryZone zone, int number});

/// Closest ring first, numbered 1, 2, 3… (never stored).
List<NumberedZone> numberZones(List<DeliveryZone> zones) {
  final sorted = [...zones]
    ..sort((a, b) => a.maxRoadDistanceMeters - b.maxRoadDistanceMeters);
  return [
    for (var i = 0; i < sorted.length; i++) (zone: sorted[i], number: i + 1),
  ];
}

/// "Zone 3".
String zoneLabel(Translator t, int number) =>
    '${t('delivery.zoneWord')} $number';

/// A new zone's distance: the farthest ring's km + 1, or 1 with none.
double defaultZoneKm(List<DeliveryZone> zones) => zones.isEmpty
    ? 1
    : zones
                  .map((z) => z.maxRoadDistanceMeters)
                  .reduce((a, b) => a > b ? a : b) /
              1000 +
          1;

/// The form's km on the wire (metres, rounded).
int kmToMeters(double km) => (km * 1000).round();
