import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';

/// The shared [MadarBrandPanel], worded from the core (`brand.*`).
class BrandPanel extends StatelessWidget {
  const BrandPanel({required this.tr, this.arabic = false, super.key});

  /// Core-backed localizer (`bridge.tr`).
  final String Function(String key) tr;

  /// Render the Arabic lockup variant (the natives pick by core locale).
  final bool arabic;

  @override
  Widget build(BuildContext context) => MadarBrandPanel(
    headline: tr('brand.headline'),
    tagline: tr('brand.tagline'),
    arabic: arabic,
  );
}
