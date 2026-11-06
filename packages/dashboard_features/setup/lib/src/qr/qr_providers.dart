/// The reads behind every code on Settings › Links & QR codes
/// (`features/qr/live.ts`, `codes-section.tsx`, `table-codes.tsx`).
///
/// Every code is LIVE: a read keyed by what the code is ([QrCodeRef]) AND by
/// the current output ([QrRenderParams]), so flipping a switch re-renders
/// every code already on screen (the page holds the old image meanwhile,
/// [LiveQrHold]). Nothing is fetched until someone asks for a code, or rests
/// on the button that asks (intent warming): each request mints or looks up a
/// short link on the server. A code never refreshes on its own (the web's
/// `staleTime: Infinity`): it changes only when its inputs do, and those are
/// its key. Asking again for the same code ([QrKindCard]'s second Generate)
/// fetches it again. Nothing is retried.
library;

import 'dart:convert';

import 'package:dashboard_api/dashboard_api.dart' show BranchTable, QrResponse;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'qr_output.dart';

/// A generated code is never stale (the web's `staleTime: Infinity`).
const Duration kQrCodeStaleTime = Duration(days: 365);

/// What scope a code needs: any scope, All branches, or one branch.
enum QrScope { shop, org, branch }

/// Every single code the page makes, in the web's `QrKind` order.
enum QrKind {
  orgLinks(scope: QrScope.shop, feature: 'branding'),
  orgMenuDisplay(scope: QrScope.shop),
  orgOrder(scope: QrScope.org, feature: 'online'),
  orgBooking(scope: QrScope.org, feature: 'bookings'),
  branchOrder(scope: QrScope.branch, feature: 'online'),
  branchBooking(scope: QrScope.branch, feature: 'bookings'),
  branchOrderInMall(scope: QrScope.branch, feature: 'online');

  const QrKind({required this.scope, this.feature});

  final QrScope scope;

  /// The plan feature this code needs (the server refuses it without);
  /// null = every plan.
  final String? feature;

  /// The web's kind id (`org_links`, `branch_order_in_mall`, …).
  String get id => switch (this) {
    orgLinks => 'org_links',
    orgMenuDisplay => 'org_menu_display',
    orgOrder => 'org_order',
    orgBooking => 'org_booking',
    branchOrder => 'branch_order',
    branchBooking => 'branch_booking',
    branchOrderInMall => 'branch_order_in_mall',
  };
}

/// The in-mall card's three fields (`place_name`, `floor`, `unit_number`).
typedef QrPlace = ({String placeName, String floor, String unitNumber});

/// What makes a code a different code: its kind, the org, the id it is made
/// for (the org for shop and org codes, the branch for branch codes) and, for
/// the in-mall kind, the place.
typedef QrCodeRef = ({
  QrKind kind,
  String orgId,
  String scopeId,
  QrPlace? place,
});

/// One code's request: what it is, and how it comes out.
typedef QrLiveKey = ({QrCodeRef code, QrRenderParams params});

/// `GET /orgs/{id}/links-qr` (with `target=menu_display` for the menu without
/// prices), `/orgs/{id}/qr`, `/orgs/{id}/booking-qr`, `/branches/{id}/qr`
/// (with the place for the in-mall kind) or `/branches/{id}/booking-qr`, with
/// the render query.
final qrCodeProvider = FutureProvider.autoDispose.family<QrResponse, QrLiveKey>(
  (ref, k) {
    ref.webCache(staleTime: kQrCodeStaleTime);
    final qr = ref.watch(apiProvider).qr;
    final c = k.code;
    final p = k.params;
    return switch (c.kind) {
      QrKind.orgLinks => qr.orgLinksQr(
        id: c.scopeId,
        card: p.card,
        dpi: p.dpi,
        unbranded: p.unbranded,
        centreLogo: p.centreLogo,
      ),
      QrKind.orgMenuDisplay => qr.orgLinksQr(
        id: c.scopeId,
        card: p.card,
        dpi: p.dpi,
        unbranded: p.unbranded,
        centreLogo: p.centreLogo,
        target: 'menu_display',
      ),
      QrKind.orgOrder => qr.orgQr(
        id: c.scopeId,
        card: p.card,
        dpi: p.dpi,
        unbranded: p.unbranded,
        centreLogo: p.centreLogo,
      ),
      QrKind.orgBooking => qr.orgBookingQr(
        id: c.scopeId,
        card: p.card,
        dpi: p.dpi,
        unbranded: p.unbranded,
        centreLogo: p.centreLogo,
      ),
      QrKind.branchOrder => qr.branchQr(
        id: c.scopeId,
        card: p.card,
        dpi: p.dpi,
        unbranded: p.unbranded,
        centreLogo: p.centreLogo,
      ),
      QrKind.branchBooking => qr.branchBookingQr(
        id: c.scopeId,
        card: p.card,
        dpi: p.dpi,
        unbranded: p.unbranded,
        centreLogo: p.centreLogo,
      ),
      QrKind.branchOrderInMall => qr.branchQr(
        id: c.scopeId,
        card: p.card,
        dpi: p.dpi,
        unbranded: p.unbranded,
        centreLogo: p.centreLogo,
        placeName: c.place?.placeName,
        floor: c.place?.floor,
        unitNumber: c.place?.unitNumber,
      ),
    };
  },
  retry: (_, _) => null,
);

/// `GET /branches/{id}/tables` (`useListTables`, enabled with a branch).
final qrTablesProvider = FutureProvider.autoDispose
    .family<List<BranchTable>, String>((ref, branchId) {
      ref.webCache();
      ref.watch(realtimeEpochProvider('/branches/$branchId/tables'));
      return ref.watch(apiProvider).qr.listTables(id: branchId);
    });

/// One table's code on the sheet: the table's id and label, and its code.
typedef QrTableCode = ({String id, String label, QrResponse qr});

/// The table sheet's request: the branch, its rows (`id` and `label`, as
/// JSON so the key compares by value) and the render query.
typedef QrTableSheetKey = ({
  String branchId,
  String rows,
  QrRenderParams params,
});

/// The sheet key for [rows] at [branchId] under [params].
QrTableSheetKey qrTableSheetKey(
  String branchId,
  List<BranchTable> rows,
  QrRenderParams params,
) => (
  branchId: branchId,
  rows: jsonEncode([
    for (final r in rows) [r.id, r.label],
  ]),
  params: params,
);

/// Every table's code, `GET /branches/{id}/tables/{tid}/qr` with the render
/// query and `caption=<label>`, one request at a time (the web's sequential
/// loop: a shared short-link provider rate-limits a burst).
final qrTableSheetProvider = FutureProvider.autoDispose
    .family<List<QrTableCode>, QrTableSheetKey>((ref, k) async {
      ref.webCache(staleTime: kQrCodeStaleTime);
      final api = ref.watch(apiProvider).qr;
      final p = k.params;
      final out = <QrTableCode>[];
      for (final r in (jsonDecode(k.rows) as List).cast<List<Object?>>()) {
        final id = r[0]! as String;
        final label = r[1]! as String;
        final qr = await api.tableQr(
          id: k.branchId,
          tid: id,
          card: p.card,
          dpi: p.dpi,
          unbranded: p.unbranded,
          centreLogo: p.centreLogo,
          caption: label,
        );
        out.add((id: id, label: label, qr: qr));
      }
      return out;
    }, retry: (_, _) => null);

/// What a live code shows: the current answer, or while a new render is on
/// its way the last one (the web's `keepPreviousData`).
class LiveQrView<T> {
  const LiveQrView({
    this.data,
    this.busy = false,
    this.error,
    this.placeholder = false,
  });

  final T? data;

  /// A render is on its way (the image on screen is the one before).
  final bool busy;

  /// The current render failed (with no answer to show for it).
  final Object? error;

  /// [data] is the previous render's, held until the new one lands.
  final bool placeholder;
}

/// Holds a live code's last answer across a change of key (a switch was
/// flipped), so the old image stays up, with a busy veil, until the new one
/// lands. One per place that shows a code.
class LiveQrHold<T> {
  T? _last;

  /// The view of [q], the current key's read; null = nothing asked for (the
  /// held answer is forgotten).
  LiveQrView<T> view(AsyncValue<T>? q) {
    if (q == null) {
      _last = null;
      return const LiveQrView();
    }
    final now = q.value;
    if (now != null) {
      _last = now;
    } else if (q.hasError) {
      _last = null;
    }
    final data = now ?? _last;
    return LiveQrView(
      data: data,
      busy: q.isLoading,
      error: q.hasError ? q.error : null,
      placeholder: now == null && data != null,
    );
  }
}

/// The code came back plain although the switches asked for the logo in the
/// middle (`missingLogo`): the shop has no printable logo for codes.
bool qrMissingLogo(QrOutput o, LiveQrView<QrResponse> live) =>
    o.unbranded &&
    o.centreLogo &&
    !live.placeholder &&
    live.data?.centreLogo == false;
