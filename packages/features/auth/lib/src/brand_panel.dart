import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The shared [MadarBrandPanel], worded from the core (`brand.*`).
class BrandPanel extends ConsumerWidget {
  /// Creates the brand panel.
  const BrandPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    return MadarBrandPanel(
      headline: bridge.tr(key: 'brand.headline'),
      tagline: bridge.tr(key: 'brand.tagline'),
    );
  }
}
