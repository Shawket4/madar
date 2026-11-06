// Settings › Links & QR codes, the screenshot walk: the page's top, its
// codes section and a code's preview, at phone (412) and desktop (1440)
// widths, in English and Arabic, with Unbranded off, Unbranded on with the
// shop's logo in the middle, and Unbranded on with the logo off; plus the
// table sheet, the no-logo note and Free. Written only when FDASH_SHOTS is
// set (`<FDASH_SHOTS>/setup/links-qr/…`).
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_setup/src/shared/qr_preview_dialog.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../qr/qr_support.dart';

const _shot = 'links-qr';

/// The walk's phone: a 412-wide Android handset.
const Size _phone = Size(412, 915);

enum _State {
  off(QrOutput()),
  logo(QrOutput(unbranded: true)),
  plain(QrOutput(unbranded: true, centreLogo: false));

  const _State(this.output);
  final QrOutput output;
}

Future<DashHarness> _pump(
  WidgetTester tester, {
  required DashSize size,
  required String lang,
  QrOutput? output,
  String query = '',
  bool logo = true,
}) async {
  final m = setupMockServer();
  if (logo) {
    m.db['orgs'].update(SeedIds.sabahOrg, {
      'logo_url': 'https://cdn.madar-pos.cloud/sabah/logo.png',
    });
  }
  final h = await pumpQr(
    tester,
    backend: m,
    size: size,
    locale: lang,
    output: output,
    query: query,
  );
  if (size == DashSize.phone) {
    tester.view.physicalSize = _phone * DashSize.pixelRatio;
    await h.settle();
  }
  return h;
}

/// Scrolls [key] to the top of the page and shoots it.
Future<void> _shootAt(DashHarness h, Key key, String name) async {
  await Scrollable.ensureVisible(h.tester.element(find.byKey(key)));
  await h.settle(rounds: 4);
  await h.shot('$_shot/$name');
}

void main() {
  for (final size in [DashSize.desktop, DashSize.phone]) {
    for (final lang in ['en', 'ar']) {
      final at = '${size.name} $lang';

      testWidgets('top of the page, $at', (tester) async {
        final h = await _pump(tester, size: size, lang: lang);
        await h.shot('$_shot/top');
      });

      for (final state in _State.values) {
        testWidgets('codes, ${state.name}, $at', (tester) async {
          final h = await _pump(
            tester,
            size: size,
            lang: lang,
            output: state.output,
          );
          await h.tap(generateOf(QrKind.orgLinks));
          await h.tap(generateOf(QrKind.orgMenuDisplay));
          await h.tap(generateOf(QrKind.orgOrder));
          await _shootAt(
            h,
            const ValueKey('links-qr-codes'),
            'codes-${state.name}-1',
          );
          await _shootAt(
            h,
            const ValueKey('qr-kind-orgLinks'),
            'codes-${state.name}-2',
          );
          if (size == DashSize.phone) {
            await _shootAt(
              h,
              const ValueKey('qr-kind-orgMenuDisplay'),
              'codes-${state.name}-3',
            );
          }
          await h.tap(
            find.descendant(
              of: resultOf(QrKind.orgLinks),
              matching: find.bySemanticsLabel(h.t('qr.enlarge')),
            ),
          );
          expect(find.byType(QrPreviewDialog), findsOneWidget);
          await h.shot('$_shot/preview-${state.name}');
        });
      }
    }
  }

  for (final (size, lang) in [
    (DashSize.desktop, 'en'),
    (DashSize.phone, 'ar'),
  ]) {
    final at = '${size.name} $lang';

    testWidgets('table sheet, unbranded with the logo, $at', (tester) async {
      final h = await _pump(
        tester,
        size: size,
        lang: lang,
        output: _State.logo.output,
        query: atBranch(SeedIds.heliopolis),
      );
      await h.tap(find.byKey(const ValueKey('qr-tables-make')));
      await _shootAt(h, const ValueKey('qr-tables'), 'tables-logo');
    });

    testWidgets('no logo for codes: the note, $at', (tester) async {
      final h = await _pump(
        tester,
        size: size,
        lang: lang,
        output: _State.logo.output,
        logo: false,
      );
      await _shootAt(h, const ValueKey('qr-output-panel'), 'no-logo');
    });

    testWidgets('Free, $at', (tester) async {
      final m = setupMockServer();
      final h = await pumpQr(
        tester,
        backend: m,
        size: size,
        locale: lang,
        overrides: [freePlan],
      );
      if (size == DashSize.phone) {
        tester.view.physicalSize = _phone * DashSize.pixelRatio;
        await h.settle();
      }
      await h.shot('$_shot/free-top');
      await _shootAt(h, const ValueKey('links-qr-codes'), 'free-codes');
    });
  }
}
