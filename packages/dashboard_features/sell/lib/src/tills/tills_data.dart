/// The tills page's reads and URL state: the web's `features/tills/api.ts`
/// (one provider per generated hook, keyed like its React Query key and
/// refreshed by the realtime prefixes `/tills` and `/reports`, SELL-TIL-057),
/// `validateTillsSearch` (SELL-TIL-008) and `getErrorMessage`
/// (`data/api/errors.ts`, SELL-ALL-017) for every toast and inline error.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show
        ApiException,
        CloseTillPreview,
        DeductionLogRow,
        OpenBillsNotice,
        PaginatedTills,
        ShiftSummary,
        Till,
        TillPreFill,
        TillReportResponse,
        TillSpotView;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
/// close, cash movement, force close or delete).
void invalidateTills(WidgetRef ref) =>
    sellInvalidateFromWidget(ref, SellInvalidate.tills);

/// React Query's `isLoading`: the first load, nothing to show yet.
extension TillsAsync<T> on AsyncValue<T> {
  bool get firstLoad => isLoading && !hasValue && !hasError;
}

/// The kinds the backend's `AppError` writes before its sentence.
final RegExp _serverKindPrefix = RegExp(
  r'^(?:Unauthorized|Forbidden|Not found|Bad request|Conflict|'
  r'Service unavailable|Database error): ',
);

/// `getErrorMessage` (`data/api/errors.ts`): a coded refusal the tables know
/// reads in the person's language; an uncoded 429 or 403 has its own words
/// (never the server's English); otherwise the server's sentence without its
/// "Kind: " prefix; then by status.
String tillsErrorMessage(Object? error, Translator t) {
  if (error is ApiException) {
    final code = error.code;
    final details = error.details;
    final vars = details is Map && details['vars'] is Map
        ? (details['vars']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    if (code != null && t.exists('errors.codes.$code')) {
      return t('errors.codes.$code', args: vars);
    }
    final status = error.status;
    if (status == 429 && code == null) return t('errors.tooManyRequests');
    if (status == 403 && code == null) return t('errors.unauthorized');
    final message = error.message.replaceFirst(_serverKindPrefix, '');
    if (message.isNotEmpty && message != 'HTTP $status') return message;
    if (status <= 0) return t('errors.networkError');
    return switch (status) {
      401 => t('errors.sessionExpired'),
      403 => t('errors.unauthorized'),
      404 => t('errors.notFound'),
      409 => t('errors.conflict'),
      422 => t('errors.validation'),
      >= 500 => t('errors.server'),
      _ => message,
    };
  }
  return t('errors.unknown');
}

/// A payment method's name: `payments.<method>` when the tables have it,
/// else the method as stored (`t(\`payments.${m}\`, m)`).
String paymentMethodLabel(Translator t, String method) =>
    t.exists('payments.$method') ? t('payments.$method') : method;
