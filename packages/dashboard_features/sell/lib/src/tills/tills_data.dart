/// The tills page's reads and URL state: the web's `features/tills/api.ts`
/// (one provider per generated hook, keyed like its React Query key and
/// refreshed by the realtime prefixes `/tills` and `/reports`, SELL-TIL-057),
/// `validateTillsSearch` (SELL-TIL-008) and `getErrorMessage`
/// (`data/api/errors.ts`, SELL-ALL-017) for every toast and inline error.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        CloseTillPreview,
        DeductionLogRow,
        OpenBillsNotice,
        PaginatedTills,
        ReconciliationInput,
        ShiftSummary,
        Till,
        TillPreFill,
        TillReportResponse,
        TillSpotView;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge_dashboard/rules.dart' as rules;

import '../shared/invalidate.dart';

/// The page's search params (`TillsSearch`), URL-held and shareable.
class TillsSearch {
  const TillsSearch({
    this.report,
    this.status,
    this.teller,
    this.device,
    this.flagged = false,
    this.today = false,
  });

  /// `validateTillsSearch`: blank strings are absent, an unknown status is
  /// ignored, booleans accept `true` and `1`.
  factory TillsSearch.fromQuery(Map<String, String> q) {
    String? str(String key) {
      final v = q[key];
      return v == null || v.isEmpty ? null : v;
    }

    bool flag(String key) => q[key] == 'true' || q[key] == '1';
    final status = str('status');
    return TillsSearch(
      report: str('report'),
      status: statuses.contains(status) ? status : null,
      teller: str('teller'),
      device: str('device'),
      flagged: flag('flagged'),
      today: flag('today'),
    );
  }

  static const List<String> statuses = ['open', 'closed', 'force_closed'];

  /// The till whose report is open.
  final String? report;
  final String? status;
  final String? teller;
  final String? device;
  final bool flagged;
  final bool today;
}

/// The query after a filter change: the old params with [patch] laid over
/// them (a null value removes its key), as the web's
/// `navigate({search: (p) => ({...p, ...patch})})`.
Map<String, String> patchQuery(
  Map<String, String> query,
  Map<String, String?> patch,
) {
  final out = {...query};
  for (final e in patch.entries) {
    final v = e.value;
    if (v == null || v.isEmpty) {
      out.remove(e.key);
    } else {
      out[e.key] = v;
    }
  }
  return out;
}

/// `useListTills` params after `cleanParams` (empty and false dropped).
typedef TillsListKey = ({
  String branchId,
  String? status,
  String? tellerId,
  String? deviceId,
  bool flagged,
  DateTime? from,
});

/// The list's key for [scope] under [s] (`?today` passes [from], the start
/// of the day).
TillsListKey tillsListKey(Scope scope, TillsSearch s, {DateTime? from}) => (
  branchId: scope.scopeBranchId,
  status: s.status,
  tellerId: s.teller,
  deviceId: s.device,
  flagged: s.flagged,
  from: from,
);

/// T3 `GET /tills/branches/{branch_id}` (the all-branches id with All
/// branches selected).
final tillsListProvider = FutureProvider.autoDispose
    .family<PaginatedTills, TillsListKey>((ref, k) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/tills/branches/${k.branchId}'));
      return ref
          .watch(apiProvider)
          .tills
          .listTills(
            branchId: k.branchId,
            status: k.status,
            tellerId: k.tellerId,
            deviceId: k.deviceId,
            flagged: k.flagged ? true : null,
            from: k.from,
          );
    });

/// T1 `GET /tills/branches/{branch_id}/current` — my till and the pre-fill.
final tillPreFillProvider = FutureProvider.autoDispose
    .family<TillPreFill, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/tills/branches/$branchId/current'));
      return ref.watch(apiProvider).tills.getCurrentTill(branchId: branchId);
    });

/// T4 `GET /tills/branches/{branch_id}/open` — newest first.
final openTillsProvider = FutureProvider.autoDispose.family<List<Till>, String>(
  (ref, branchId) {
    ref.webCache();
    ref.watch(realtimeEpochProvider('/tills/branches/$branchId/open'));
    return ref.watch(apiProvider).tills.listOpenTills(branchId: branchId);
  },
);

/// T5 `GET /tills/branches/{branch_id}/open-bills-notice`.
final openBillsNoticeProvider = FutureProvider.autoDispose
    .family<OpenBillsNotice, String>((ref, branchId) {
      ref.webCache();
      ref.watch(
        realtimeEpochProvider('/tills/branches/$branchId/open-bills-notice'),
      );
      return ref
          .watch(apiProvider)
          .tills
          .getOpenBillsNotice(branchId: branchId);
    });

/// T7 `GET /tills/{till_id}/report`.
final tillReportProvider = FutureProvider.autoDispose
    .family<TillReportResponse, String>((ref, tillId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/tills/$tillId/report'));
      return ref.watch(apiProvider).tills.getTillReport(tillId: tillId);
    });

/// T15 `GET /reports/tills/{till_id}/summary`.
final tillSummaryProvider = FutureProvider.autoDispose
    .family<ShiftSummary, String>((ref, tillId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/tills/$tillId/summary'));
      return ref.watch(apiProvider).reports.tillSummary(tillId: tillId);
    });

/// T16 `GET /reports/tills/{till_id}/deductions`.
final tillDeductionsProvider = FutureProvider.autoDispose
    .family<List<DeductionLogRow>, String>((ref, tillId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/reports/tills/$tillId/deductions'));
      return ref.watch(apiProvider).reports.tillDeductions(tillId: tillId);
    });

/// T17 `GET /tills/{till_id}/spot-views`.
final tillSpotViewsProvider = FutureProvider.autoDispose
    .family<List<TillSpotView>, String>((ref, tillId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/tills/$tillId/spot-views'));
      return ref.watch(apiProvider).tills.listSpotViews(tillId: tillId);
    });

/// T8 `GET /tills/{till_id}/close-preview`.
final closePreviewProvider = FutureProvider.autoDispose
    .family<CloseTillPreview, String>((ref, tillId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/tills/$tillId/close-preview'));
      return ref.watch(apiProvider).tills.closePreview(tillId: tillId);
    });

/// `invalidateTills`: every `/tills…` and `/reports…` read (after an open,
/// close, cash movement, force close or delete). Take it before the save's
/// `await` and call it after: the refresh then runs even when the dialog or
/// page closed mid-save, as the web's query client does.
VoidCallback tillsInvalidator(WidgetRef ref) {
  final bus = ref.read(realtimeBusProvider);
  return () => bus.invalidate(SellInvalidate.tills);
}

/// A payment method's name: `payments.<method>` when the tables have it,
/// else the method as stored (`t(\`payments.${m}\`, m)`).
String paymentMethodLabel(Translator t, String method) =>
    t.exists('payments.$method') ? t('payments.$method') : method;

/// A till's status word (`t(`tillStatus.${s}`, s)`).
String tillStatusLabel(Translator t, String status) =>
    t.exists('tillStatus.$status') ? t('tillStatus.$status') : status;

/// `isFlagged`: opened while another till was open, or its payment check
/// disagreed.
bool isFlaggedTill(Till t) =>
    t.openedWhileAnotherOpen || t.reconciliationStatus == 'disagreed';

/// Why the server would refuse a live close's payment check, or null:
/// madar-till `reconcile::plan_lines` run through the bridge
/// (`rules.reconcileRefusal`), pinned by the shared `reconcile_vectors.json`.
/// The refusal's code is null for a status that is neither `checked` nor
/// `disagreed`.
rules.ReconcileRefusal? reconcileRefusal(
  List<rules.ReconcileTotal> totals,
  List<ReconciliationInput> inputs, {
  required int closingCashDeclared,
  required int closingCashSystem,
  String? cashNote,
}) => rules.reconcileRefusal(
  totals: totals,
  closingCashDeclared: closingCashDeclared,
  closingCashSystem: closingCashSystem,
  cashNote: cashNote,
  inputs: [
    for (final i in inputs)
      rules.ReconcileInput(
        method: i.method,
        status: i.status,
        declaredAmount: i.declaredAmount,
        note: i.note,
      ),
  ],
);

/// The list's discrepancy (SELL-TIL-021): "—" for none, plain zero, else
/// signed money ("+EGP 20.00" / "−EGP 50.00").
String discrepancyText(DashFormat fmt, int? d) => d == null
    ? '—'
    : d == 0
    ? fmt.fmtMoney(0)
    : fmt.fmtMoneySigned(d);

/// Warms what [tillId]'s report panel reads on opening (the web's
/// `onRowPrefetch`, plus the panel's other reads), so it opens on data.
void warmTillReport(WidgetRef ref, String tillId) {
  ref
    ..warm(tillReportProvider(tillId))
    ..warm(tillSummaryProvider(tillId))
    ..warm(tillDeductionsProvider(tillId));
  if (ref.read(authzStateProvider).can(Cap.tillRead)) {
    ref.warm(tillSpotViewsProvider(tillId));
  }
}
