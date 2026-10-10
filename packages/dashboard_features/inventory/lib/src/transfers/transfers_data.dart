/// The Transfers unit's reads and the rules the web computes in the browser
/// (`transfers-page.tsx`, `transfer-drawer.tsx`, `lib.ts` at af50aa63): the
/// list keyed by scope, direction and status, the org's transfer locations,
/// the differences report, the replenishment rows, the export walk, the steps
/// open to the viewer (madar-inventory's table, through the core), `milli` and
/// the status words and tones.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart' show DashTone;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

import '../shared/inventory_labels.dart';

/// The list's key: the location it reads (or the all-branches id), the
/// direction and the status it sends (null = omitted).
typedef TransfersKey = ({String branchId, String? direction, String? status});

/// The differences report's key: the org and the scope's period.
typedef DifferencesKey = ({String orgId, String from, String to});

/// The replenishment read's key: the warehouse and the branch to fill.
typedef ReplenishKey = ({String warehouseId, String branchId});

/// The status tabs (INV-TRF-005): `all`, the five statuses, `differences`.
const List<String> transferTabs = [
  'all',
  'requested',
  'draft',
  'dispatched',
  'received',
  'cancelled',
  'differences',
];

/// The direction segments (INV-TRF-006; null = "Both ways").
const List<String?> transferDirections = [null, 'incoming', 'outgoing'];

/// The five statuses a transfer can be in.
const List<String> transferStatuses = [
  'requested',
  'draft',
  'dispatched',
  'received',
  'cancelled',
];

/// The status a tab sends (`all` and `differences` send none).
String? tabStatus(String tab) => transferStatuses.contains(tab) ? tab : null;

extension TransfersKeys on Scope {
  /// INV-TRF-002: the scoped location, or the all-branches id.
  TransfersKey transfersKey({String? direction, String? status}) =>
      (branchId: scopeBranchId, direction: direction, status: status);

  /// INV-TRF-011: the org and the scope's period; null without an org.
  DifferencesKey? get differencesKey =>
      orgId == null ? null : (orgId: orgId!, from: from, to: to);
}

/// `GET /inventory/branches/{branch_id}/transfers` (listTransfers): the
/// server's 100 newest.
final transfersProvider = FutureProvider.autoDispose
    .family<List<StockTransfer>, TransfersKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/inventory/branches/${k.branchId}/transfers'),
      );
      return ref
          .watch(apiProvider)
          .inventory
          .listTransfers(
            branchId: k.branchId,
            direction: k.direction,
            status: k.status,
          );
    });

/// `GET /inventory/orgs/{org_id}/transfer-locations` (transferLocations):
/// every live location of the org, for the other side of a transfer.
final transferLocationsProvider = FutureProvider.autoDispose
    .family<List<TransferLocation>, String>((ref, orgId) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/inventory/orgs/$orgId/transfer-locations'),
      );
      return ref.watch(apiProvider).inventory.transferLocations(orgId: orgId);
    });

/// `GET /inventory/orgs/{org_id}/transfer-differences` (transferDifferences).
final transferDifferencesProvider = FutureProvider.autoDispose
    .family<List<TransferDifferenceRow>, DifferencesKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider(
          '/inventory/orgs/${k.orgId}/transfer-differences',
        ),
      );
      return ref
          .watch(apiProvider)
          .inventory
          .transferDifferences(
            orgId: k.orgId,
            from: DateTime.parse(k.from),
            to: DateTime.parse(k.to),
          );
    });

/// `GET /inventory/warehouses/{warehouse_id}/replenishment` (replenishment).
final replenishmentProvider = FutureProvider.autoDispose
    .family<List<ReplenishmentRow>, ReplenishKey>((ref, k) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider(
          '/inventory/warehouses/${k.warehouseId}/replenishment',
        ),
      );
      return ref
          .watch(apiProvider)
          .inventory
          .replenishment(warehouseId: k.warehouseId, branchId: k.branchId);
    });

/// INV-TRF-007: the whole list for [k] (same scope, direction and status),
/// walked 500 at a time and declared as an export (`X-Madar-Export: 1`).
Future<List<StockTransfer>> fetchAllTransfers(
  ApiTransport transport,
  TransfersKey k,
) {
  final api = apiWithHeaders(transport, exportRequestHeaders);
  return fetchAllPages(
    (offset, limit) async => ExportPage(
      await api.inventory.listTransfers(
        branchId: k.branchId,
        direction: k.direction,
        status: k.status,
        limit: limit,
        offset: offset,
      ),
    ),
  );
}

// ── Steps ──────────────────────────────────────────────────────────────────

/// The steps a transfer may take; each name is the step table's action word.
enum TransferAction { edit, accept, decline, dispatch, receive, cancel }

/// The steps open to someone working at [mine] who holds the step's
/// capability AT the acting side (`can(cap, at)`), where the server checks.
/// The table is madar-inventory's (`transfer::step`) through the core.
Set<TransferAction> transferActions(
  StockTransfer t,
  Set<String> mine,
  bool Function(String cap, String at) can,
) => {
  for (final a in TransferAction.values)
    if (rules.transferStep(status: t.status.value, action: a.name)
        case final step?)
      if (step.side == 'source' ? t.sourceBranchId : t.destinationBranchId
          case final at when mine.contains(at) && can(step.cap, at))
        a,
};

/// A quantity in whole thousandths, as the server compares them
/// (`madar_inventory::milli` through the core).
int milli(num q) => rules.milli(q: q.toDouble());

/// `TRANSFER_TONES` (an unknown status is neutral).
DashTone transferTone(String status) => switch (status) {
  'requested' => DashTone.info,
  'dispatched' => DashTone.accent,
  'received' => DashTone.success,
  'cancelled' => DashTone.danger,
  _ => DashTone.neutral,
};

/// `transferStatusLabel`: the status's words, an unknown one raw.
String transferStatusLabel(Translator t, String status) =>
    transferStatuses.contains(status)
    ? t('inventory.transfers.status.$status')
    : status;

/// The Items cell (INV-TRF-008): one line `<name> · <qty> <unit>`, several
/// the names joined.
String lineSummary(DashFormat f, StockTransfer tr) => tr.lines.length == 1
    ? '${tr.lines.first.ingredientName} · '
          '${qtyWithUnit(f, tr.lines.first.qtySent, tr.lines.first.unit)}'
    : tr.lines.map((l) => l.ingredientName).join(', ');

/// The Date cell: received, else sent, else created.
DateTime transferWhen(StockTransfer tr) =>
    (tr.received ?? tr.dispatched ?? tr.created).at;

/// INV-TRF-015: Σ (received − sent) × unit cost over the costed lines.
double transitValue(StockTransfer tr) {
  var sum = 0.0;
  for (final l in tr.lines) {
    final cost = l.unitCost, got = l.qtyReceived;
    if (cost != null && got != null) sum += (got - l.qtySent) * cost;
  }
  return sum;
}
