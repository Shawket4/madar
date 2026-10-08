/// `/tills` (the web's `features/tills/tills-page.tsx`, SELL-TIL rows): open
/// now, all tills, the report sheet, open / close / cash movement dialogs.
/// The legacy `/shifts?…` is redirected here by the shell (SELL-ALL-007).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class TillsPage extends ConsumerWidget {
  const TillsPage({this.query = const {}, super.key});

  /// The route's builder (routes.dart points here; the search params —
  /// `report`, `status`, `teller`, `device`, `flagged`, `today` — are this
  /// unit's to read, SELL-TIL-008).
  static Widget route(BuildContext context, GoRouterState state) =>
      TillsPage(query: state.uri.queryParameters);

  final Map<String, String> query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('nav.tills'),
      subtitle: t('tills.subtitle'),
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
