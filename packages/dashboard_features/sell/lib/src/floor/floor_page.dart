/// `/floor` (the web's `features/floor/floor-page.tsx`, SELL-FLR rows): the
/// floor-plan editor — canvas, inspector, table history, transfer queue.
///
/// A floor plan is PHYSICAL space: the canvas and every table are never
/// mirrored in Arabic (`Positioned`, never `PositionedDirectional`); the
/// table glyph shares its constants with the POS (`table_glyph.dart`,
/// `kTable*`).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/branch_required.dart';

class FloorPage extends ConsumerWidget {
  const FloorPage({super.key});

  /// The route's builder (routes.dart points here).
  static Widget route(BuildContext context, GoRouterState state) =>
      const FloorPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final branchId = ref.watch(sellBranchIdProvider);
    return DashPageScaffold(
      title: t('floor.title'),
      body: branchId == null
          ? const BranchRequiredState(
              messageKey: 'floor.pickBranch',
              icon: 'armchair',
            )
          : DashEmptyState(
              icon: 'layers',
              title: t('shell.pendingTitle'),
              description: t('shell.pendingBody'),
            ),
    );
  }
}
