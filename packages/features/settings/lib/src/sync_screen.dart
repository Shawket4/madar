/// The Sync screen — what the outbox pill opens. A header over the full
/// [SyncSection] (every waiting row, every stuck row, the stranded count),
/// capped and centred on a tablet. Pushed as its own route; the header's
/// back pops it.
library;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_settings/src/sync_section.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The outbox inspector. All state flows from `syncProvider` through the
/// section; this screen only frames it.
class SyncScreen extends ConsumerWidget {
  /// Creates the sync screen.
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.watch(bridgeProvider);
    final layout = context.madarLayout;
    // Pushed as its own route — re-derive direction from the locale
    // provider so the screen is RTL-correct wherever it's presented.
    final rtl = ref.watch(localeProvider.select((s) => s.rtl));
    return Directionality(
      textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
      child: MadarPageScaffold(
        body: Column(
          children: [
            Padding(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: layout.gutter,
              ),
              child: MadarHeader(
                title: bridge.tr(key: 'sync.title'),
                onBack: () => Navigator.of(context).maybePop(),
                safeTop: true,
              ),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: SingleChildScrollView(
                  padding: EdgeInsetsDirectional.all(layout.gutter),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: Responsive.billMaxWidth,
                      ),
                      child: const SyncSection(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
