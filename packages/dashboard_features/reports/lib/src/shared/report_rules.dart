/// Rules every reports unit shares: when a read shows its error
/// (REP-ALL-018).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The error with Retry: dashboard_core's `failedFirst`, and also a refetch
/// that failed over rows already shown (the web checks `isError`, which
/// drops them, REP-ALL-018). Never during Riverpod's automatic retries; it
/// stays up while a manual Retry runs.
extension ReportAsync<T> on AsyncValue<T> {
  bool get failed => hasError && !retrying;
}
