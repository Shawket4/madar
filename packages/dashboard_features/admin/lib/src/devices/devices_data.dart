/// The Devices page's state and reads (web `features/devices/api.ts`,
/// `devices-page.tsx` `validateDevicesSearch`):
///
/// - [DevicesSearch]: the view, window and legacy switch held in the URL
///   (ADM-DEV-002, -023, -024, -028);
/// - one provider per read, keyed like the web's React Query keys, each
///   watching `realtimeEpochProvider(<its path>)` so a prefix invalidation
///   (a change here, the server's `resync`) refetches it;
/// - [DevicesInvalidate]: what each change invalidates, as the web's
///   `invalidate(...prefixes)` does;
/// - [devicesErrorText]: a failure in words (the web's `getErrorMessage`).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show ActivationCode, ApiException, ClientSeen, Device;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The query-key paths (the web's Orval keys start with the path).
abstract final class DevicesPaths {
  static const String devices = '/devices';
  static const String codes = '/devices/activation-codes';
  static const String clients = '/devices/client-versions';
  static const String tills = '/tills';
}

/// `DEVICE_CODE_RE`: what a device code may be, after trim + uppercase.
final RegExp deviceCodePattern = RegExp(r'^[A-Z0-9]{1,6}$');

/// The Client versions windows (`DAY_OPTIONS`); 14 is the default.
const List<int> clientWindowDays = [7, 14, 30, 90];
const int defaultClientWindow = 14;

/// The two views of the page.
enum DevicesView { devices, clients }

/// The page's own URL params, validated as `validateDevicesSearch` does:
/// `view` is `clients` or nothing, `days` one of [clientWindowDays] or
/// nothing, `all` only the string `true`.
class DevicesSearch {
  const DevicesSearch({this.view, this.days, this.all});

  factory DevicesSearch.parse(Map<String, String> q) {
    final days = int.tryParse(q['days'] ?? '');
    return DevicesSearch(
      view: q['view'] == 'clients' ? DevicesView.clients : null,
      days: days != null && clientWindowDays.contains(days) ? days : null,
      all: q['all'] == 'true' ? true : null,
    );
  }

  final DevicesView? view;
  final int? days;
  final bool? all;

  DevicesView get effectiveView => view ?? DevicesView.devices;
  int get effectiveDays => days ?? defaultClientWindow;
  bool get legacyOnly => all != true;

  @override
  bool operator ==(Object other) =>
      other is DevicesSearch &&
      other.view == view &&
      other.days == days &&
      other.all == all;

  @override
  int get hashCode => Object.hash(view, days, all);

  @override
  String toString() => 'DevicesSearch(view: $view, days: $days, all: $all)';
}

/// "4072 1958": an 8-character code in two groups, any other unchanged
/// (`groupCode`).
String groupActivationCode(String code) =>
    code.length == 8 ? '${code.substring(0, 4)} ${code.substring(4)}' : code;

/// `GET /devices?branch_id=` (useDevices) — only with a branch picked.
final devicesListProvider = FutureProvider.autoDispose
    .family<List<Device>, String>((ref, branchId) {
      ref.watch(realtimeEpochProvider(DevicesPaths.devices));
      return ref.watch(apiProvider).devices.listDevices(branchId: branchId);
    });

/// `GET /devices/activation-codes?branch_id=` (useActivationCodes) — only
/// for someone with `branches.edit`.
final activationCodesProvider = FutureProvider.autoDispose
    .family<List<ActivationCode>, String>((ref, branchId) {
      ref.watch(realtimeEpochProvider(DevicesPaths.codes));
      return ref.watch(apiProvider).devices.listCodes(branchId: branchId);
    });

/// The Client versions read's key: the branch (null = org-wide), the
/// legacy-only switch and the window.
typedef ClientVersionsKey = ({String? branchId, bool legacyOnly, int days});

/// `GET /devices/client-versions` (useClientVersions): always sends
/// `legacy_only` and `days`; `branch_id` only with a branch picked.
final clientVersionsProvider = FutureProvider.autoDispose
    .family<List<ClientSeen>, ClientVersionsKey>((ref, k) {
      ref.watch(realtimeEpochProvider(DevicesPaths.clients));
      return ref
          .watch(apiProvider)
          .devices
          .listClientVersions(
            branchId: k.branchId,
            legacyOnly: k.legacyOnly,
            days: k.days,
          );
    });

/// What a change makes stale (`api.ts`): the bus wakes every read whose path
/// starts with one of the prefixes.
class DevicesInvalidate {
  const DevicesInvalidate(this._bus);

  final RealtimeBus _bus;

  /// `usePatchDevice`: `/devices*` (codes and client versions included) and
  /// `/tills*`.
  void deviceSaved() => _bus.invalidate(const [
    DevicesPaths.devices,
    DevicesPaths.tills,
  ]);

  /// `useIssueActivationCode` / `useRevokeActivationCode`.
  void codesChanged() => _bus.invalidate(const [DevicesPaths.codes]);
}

extension DevicesInvalidateRef on WidgetRef {
  DevicesInvalidate get devicesInvalidate =>
      DevicesInvalidate(read(realtimeBusProvider));
}

final RegExp _serverKind = RegExp(
  r'^(Unauthorized|Forbidden|Not found|Bad request|Conflict|Service unavailable|Database error): ',
);

/// A failure in words, as the web's `getErrorMessage` picks them: a coded
/// refusal the tables word (`errors.codes.<CODE>`, with its vars); an
/// uncoded 403 is a missing right (`errors.unauthorized`); else the
/// server's sentence without its kind prefix. In real mode the core has
/// already done this (the message arrives worded), so it changes nothing
/// there; in mock mode it gives the same words.
String devicesErrorText(Object? error, Translator t) {
  if (error is ApiException) {
    final code = error.code;
    if (code != null && t.exists('errors.codes.$code')) {
      final details = error.details;
      final vars = details is Map && details['vars'] is Map
          ? Map<String, Object?>.from(details['vars']! as Map)
          : null;
      return t('errors.codes.$code', args: vars);
    }
    if (error.status == 403 && code == null) return t('errors.unauthorized');
    final said = error.message.replaceFirst(_serverKind, '').trim();
    if (said.isNotEmpty) return said;
  }
  return errorMessage(error, t);
}

/// React Query's `isLoading`: the first load, nothing to show yet.
extension DevicesAsync<T> on AsyncValue<T> {
  bool get firstLoad => isLoading && !hasValue && !hasError;

  /// The failure to show: it stays up while a Retry is on its way, as the
  /// web's table keeps its error state through a refetch.
  Object? get shownError => hasError ? error : null;
}
