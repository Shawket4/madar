import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What a till the Free plan switched off shows instead of the sell screen
/// (a downgraded organisation keeps one till per branch selling; the owner
/// picks it under Settings › Plan in the web dashboard, or upgrades).
///
/// Its sales are already synced; nothing here sells, opens a till or takes
/// money. "Check again" is a person's manual pull: the owner may have just
/// chosen this till, and the next sync clears the flag.
class InactiveTillScreen extends ConsumerWidget {
  const InactiveTillScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    return MadarPageScaffold(
      safeTop: false,
      body: EmptyState(
        icon: 'lock',
        title: bridge.tr(key: 'plan.inactive_title'),
        message: bridge.tr(key: 'plan.inactive_body'),
        actionLabel: bridge.tr(key: 'plan.inactive_check'),
        onAction: () => unawaited(ref.read(pullFromServerProvider)()),
      ),
    );
  }
}
