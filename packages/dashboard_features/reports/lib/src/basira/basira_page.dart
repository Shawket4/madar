/// `/basira` Basira (REP-BAS rows): the AI analytics workspace — the
/// conversation rail, the streamed answers with their result blocks, rename
/// and delete (`features/basira/*`). The web has no in-page guard: a refusal
/// surfaces as a toast or as a question's failure box (REP-BAS-001).
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The route's page (`DashRoute.builder`).
Widget basiraPageBuilder(BuildContext context, GoRouterState state) =>
    const BasiraPage();

class BasiraPage extends ConsumerWidget {
  const BasiraPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('basira.title'),
      subtitle: t('basira.subtitle'),
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
