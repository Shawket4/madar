/// The body a scaffolded admin page shows until its builder ports it: the
/// shell's own "on its way" words, so a page never shows an empty frame or a
/// raw key. Builders replace it with the real page.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AdminPendingBody extends ConsumerWidget {
  const AdminPendingBody({this.icon = 'layers', super.key});

  final String icon;

  @override
  Widget build(BuildContext context, WidgetRef ref) => DashEmptyState(
    icon: icon,
    title: ref.t('shell.pendingTitle'),
    description: ref.t('shell.pendingBody'),
  );
}
