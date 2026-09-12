/// Cash in / out as its own screen — the phone's route from Till, and the
/// full ledger from the iPad's Till row. The panel itself ([CashInOutPanel])
/// is shared with the Till tab; this screen only frames it with a header
/// and focuses the amount, so Till → Pay out → Record is three taps with
/// nothing to hunt for.
library;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_shift/src/cash_in_out_panel.dart';
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The open shift's cash in/out ledger, pushed over the shell. The header's
/// back pops it via `Navigator.maybePop`; the shell hand-off after a recorded
/// movement happens inside `CashMovementsNotifier`.
class CashMovementsScreen extends ConsumerWidget {
  /// Creates the cash in/out screen.
  const CashMovementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.madarColors;
    final bridge = ref.watch(bridgeProvider);
    final layout = context.madarLayout;
    // Scaffold: every screen root owns its own Scaffold in this app.
    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: layout.gutter),
            child: MadarHeader(
              title: bridge.tr(key: 'cash.title'),
              onBack: () => Navigator.maybePop(context),
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
                      maxWidth: Responsive.listMaxWidth,
                    ),
                    child: const CashInOutPanel(
                      autofocusAmount: true,
                      showTitle: false,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
