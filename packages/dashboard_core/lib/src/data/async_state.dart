/// The web's loading / error / empty rule for one read (TanStack Query), so a
/// page never flashes "nothing here" while a read is still trying.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

extension DashAsyncState<T> on AsyncValue<T> {
  /// The skeleton: nothing to show yet and still loading, Riverpod's
  /// automatic retries included (the web stays pending while it retries).
  bool get awaitingFirst => isLoading && !hasValue && (!hasError || retrying);

  /// The error with Retry: failed with nothing to show once the automatic
  /// retries are spent. It stays up while a manual Retry runs ([isLoading]
  /// is then true: spin the Retry button).
  bool get failedFirst => hasError && !hasValue && !retrying;

  /// The empty state is shown only for a real answer: [hasValue] and empty.
}
