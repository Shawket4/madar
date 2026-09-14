/// Cash in / out as its own page — pushed from the Till, on the spec's form
/// width (docs/design/SPEC.md §3): the record form and the till's ledger
/// ([CashInOutPanel]), leading-aligned under the header, the amount focused.
library;

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_till/src/cash_in_out_panel.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The open till's cash in / out, pushed over the shell. The header's back
/// pops it; the shell hand-off after a recorded movement happens inside
/// `CashMovementsNotifier`.
class CashMovementsScreen extends ConsumerWidget {
  /// Creates the cash in/out screen.
  const CashMovementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MadarPageScaffold(
      title: ref.bridge.tr(key: 'cash.title'),
      width: MadarContentWidth.form,
      body: const SingleChildScrollView(
        padding: EdgeInsetsDirectional.only(bottom: Space.xl),
        child: CashInOutPanel(autofocusAmount: true),
      ),
    );
  }
}
