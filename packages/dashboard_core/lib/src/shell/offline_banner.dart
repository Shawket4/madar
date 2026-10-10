/// The frame's offline notice: shown while any data on screen came from the
/// answers saved for offline use, with when the oldest of them was saved.
library;

import 'package:dashboard_core/src/data/offline.dart';
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/scope/scope.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DashOfflineBanner extends ConsumerWidget {
  const DashOfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final at = ref.watch(offlineProvider.select((s) => s.savedAt));
    if (at == null) return const SizedBox.shrink();
    final t = ref.watch(tProvider);
    final time = ref.watch(formatProvider).fmtStamp(at);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        Space.lg,
        Space.sm,
        Space.lg,
        0,
      ),
      child: Semantics(
        liveRegion: true,
        child: NoticeBanner(
          text: t('shell.offlineBanner', args: {'time': time}),
          icon: 'wifi.slash',
        ),
      ),
    );
  }
}
