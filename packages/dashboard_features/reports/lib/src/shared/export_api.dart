/// The client the analytics exports re-read through: every request carries
/// `X-Madar-Export: 1` (the web's `EXPORT_REQUEST`, `lib/export-all.ts`), so
/// the backend counts it against the per-person export budget and answers
/// 429 `EXPORT_RATE_LIMITED` past it (REP-ALL-027). Used by Operations
/// (Items, Tellers, Waiters, Branches) and Financial (Channel).
///
/// The generated client has no per-call headers, so this is dashboard_core's
/// [apiWithHeaders] over the active transport.
library;

import 'package:dashboard_api/dashboard_api.dart' show DashboardApi;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `ref.read(exportApiProvider).reports.branchTellerStats(...)` for an
/// export's re-read.
final exportApiProvider = Provider<DashboardApi>(
  (ref) => apiWithHeaders(ref.watch(transportProvider), exportRequestHeaders),
);
