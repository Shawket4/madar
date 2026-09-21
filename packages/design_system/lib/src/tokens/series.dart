import 'package:design_system/src/tokens/colors.dart';
import 'package:flutter/painting.dart';

/// Categorical hues — one per person, branch or series (a roster's people,
/// a chart's lines). Derived from the colour roles, so they hold in both
/// themes and never stray from the palette. Pick by a stable index:
/// `colors.series[i % colors.series.length]`.
extension MadarSeries on MadarColors {
  List<Color> get series => [
    brand,
    info,
    success,
    warning,
    Color.lerp(brand, info, 0.55)!,
    Color.lerp(warning, danger, 0.5)!,
    Color.lerp(success, brand, 0.5)!,
    accentDeep,
  ];
}
