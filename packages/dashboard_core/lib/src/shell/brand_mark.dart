/// Madar's wordmark as the web's `MadarWordmark` draws it: the Latin
/// wordmark in English; in Arabic the mark and the Arabic name (the design
/// system ships the Arabic wordmark only inside its stacked lockup).
library;

import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The wordmark at [height]; [reversed] draws it light, for the ink chrome,
/// in paper only (the teal "d" is lost on the ink).
class ShellWordmark extends ConsumerWidget {
  const ShellWordmark({
    required this.height,
    this.reversed,
    this.animated = false,
    super.key,
  });

  final double height;

  /// Lead with the POS rail's living symbol ([AnimatedBrandMark]).
  final bool animated;

  /// Light-on-dark regardless of the theme (the sidebar, the brand panel).
  final bool? reversed;

  /// The Latin wordmark's width over its height.
  static const double latinAspect = 1600 / 486;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final light = reversed ?? Theme.of(context).brightness == Brightness.dark;
    final name = t('app.name', defaultValue: 'Madar');
    final ink = light ? c.onChrome : c.textPrimary;
    final latin = Theme(
      data: light ? MadarTheme.dark() : MadarTheme.light(),
      child: MadarWordmark(width: height * latinAspect, mono: true),
    );
    final Widget mark = t.isRtl || animated
        ? Row(
            mainAxisSize: MainAxisSize.min,
            spacing: height / 4,
            children: [
              if (animated)
                AnimatedBrandMark(symbolSize: height, wordmark: false, ink: ink)
              else
                MadarSymbol(size: height, reversed: light),
              if (t.isRtl)
                Text(
                  name,
                  style: MadarType.h2.copyWith(
                    fontSize: height * 0.82,
                    height: 1,
                    color: ink,
                  ),
                )
              else
                latin,
            ],
          )
        : latin;
    return Semantics(
      label: name,
      image: true,
      child: ExcludeSemantics(child: mark),
    );
  }
}
