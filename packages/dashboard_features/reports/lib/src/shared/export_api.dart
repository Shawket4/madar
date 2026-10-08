/// The client the analytics exports re-read through: every request carries
/// `X-Madar-Export: 1` (the web's `EXPORT_REQUEST`, `lib/export-all.ts`), so
/// the backend counts it against the per-person export budget and answers
/// 429 `EXPORT_RATE_LIMITED` past it (REP-ALL-027). Used by Operations
/// (Items, Tellers, Waiters, Branches) and Financial (Channel).
///
/// The generated client has no per-call headers, so this wraps the active
/// transport with dashboard_core's [exportRequestHeaders] instead.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// An [ApiTransport] that adds [extra] headers to every request (the
/// request's own headers win on a clash).
class HeaderTransport implements ApiTransport {
  const HeaderTransport(this.inner, this.extra);

  final ApiTransport inner;
  final Map<String, String> extra;

  ApiRequest _with(ApiRequest r) => ApiRequest(
    method: r.method,
    path: r.path,
    query: r.query,
    body: r.body,
    files: r.files,
    headers: {...extra, ...r.headers},
  );

  @override
  Future<ApiResponse> send(ApiRequest request) => inner.send(_with(request));

  @override
  Stream<String> stream(ApiRequest request) => inner.stream(_with(request));
}

/// `ref.read(exportApiProvider).reports.branchTellerStats(...)` for an
/// export's re-read.
final exportApiProvider = Provider<DashboardApi>(
  (ref) => DashboardApi(
    HeaderTransport(ref.watch(transportProvider), exportRequestHeaders),
  ),
);
