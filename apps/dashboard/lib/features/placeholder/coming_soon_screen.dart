import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';

/// A placeholder for nav destinations not yet ported to Flutter (Phase 2+).
class ComingSoonScreen extends ConsumerWidget {
  const ComingSoonScreen({
    required this.titleKey,
    required this.fallback,
    super.key,
  });

  final String titleKey;
  final String fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final title = t(titleKey);
    return EmptyState(
      icon: 'square.stack.3d.up.fill',
      title: title == titleKey ? fallback : title,
      message: t('comingSoon.body'),
    );
  }
}
