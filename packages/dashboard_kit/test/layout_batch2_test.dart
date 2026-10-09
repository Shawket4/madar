import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(loadDashFonts);

  for (final s in ['3', '32', '128', '1,284']) {
    for (final variant in ['feff', 'cgj', 'lrmAfter', 'lrmInside', 'nnbsp']) {
      testWidgets('probe $s $variant', (tester) async {
        final base = DashType.statFigure(18);
        final style = variant == 'noSpacing'
            ? base.copyWith(letterSpacing: 0)
            : base;
        final text = switch (variant) {
          'feff' => '${dashFigure(s)}\uFEFF',
          'cgj' => '${dashFigure(s)}\u034F',
          'lrmAfter' => '${dashFigure(s)}\u200E',
          'lrmInside' => '\u2066$s\u200E\u2069',
          'nnbsp' => '\u2066$s\u2069\u2060\u200B',
          'lrm' => '\u200E$s\u200E',
          'lriOnly' => '\u2066$s',
          'lre' => '\u202A$s\u202C',
          'fsi' => '\u2068$s\u2069',
          _ => dashFigure(s),
        };
        await pumpDashApp(
          tester,
          Scaffold(
            body: Center(
              child: SizedBox(
                width: 200,
                child: variant == 'wjRow' ? Row(children: [Text(text, maxLines: 1, style: style)]) : FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    text,
                    maxLines: 1,
                    softWrap: variant != 'nowrap',
                    textDirection:
                        variant == 'plain' ? TextDirection.ltr : null,
                    style: style,
                  ),
                ),
              ),
            ),
          ),
          lang: variant == 'en' ? 'en' : 'ar',
        );
        final p = tester.renderObject<RenderParagraph>(find.byType(RichText));
        // ignore: avoid_print
        print('$s $variant exceed=${p.didExceedMaxLines} size=${p.size} '
            'intr=${p.getMaxIntrinsicWidth(double.infinity)}');
      });
    }
  }
}
