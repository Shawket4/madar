/// The WhatsApp pane's one read: `GET /whatsapp/status` (whatsappStatus).
///
/// A notifier, so each mutation's answer replaces the cached status as the
/// web's `setQueryData(getWhatsappStatusQueryKey(), data)` does, without a
/// second read. No realtime: the page polls ([kWhatsappPoll]).
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The web's `refetchInterval: 2500`.
const Duration kWhatsappPoll = Duration(milliseconds: 2500);

class WhatsappStatusNotifier extends AsyncNotifier<WhatsappStatus> {
  @override
  Future<WhatsappStatus> build() {
    ref.webCache();
    return ref.watch(apiProvider).whatsapp.whatsappStatus();
  }

  /// The status a mutation answered with (the web's `cacheStatus`).
  void write(WhatsappStatus status) => state = AsyncData(status);
}

final whatsappStatusProvider =
    AsyncNotifierProvider.autoDispose<WhatsappStatusNotifier, WhatsappStatus>(
      WhatsappStatusNotifier.new,
    );

/// The route's intent warming: the status, for a platform admin only (the
/// pane refuses everyone else without reading).
final whatsappWarmProvider = FutureProvider.autoDispose<void>((ref) async {
  // ignore: avoid_print
  print('WARM platform=${ref.read(currentSessionProvider)?.isPlatform}');
  if (ref.read(currentSessionProvider)?.isPlatform != true) return;
  await ref.watch(whatsappStatusProvider.future);
});
