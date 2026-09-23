// The top bar on the narrowest phone we support (358 pt, an iPhone SE-class
// width with a large text setting's side margins): the person, the branch,
// two 44-pt actions and the outbox pill must fit — the staff app's manager
// bar overflowed by 27 px here. Nothing may overflow; the names give way
// (ellipsis) and the actions never shrink below their tap target.

import 'dart:io';
import 'dart:typed_data';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      loader.addFont(
        File(
          'assets/fonts/$family-$cut.ttf',
        ).readAsBytes().then(ByteData.sublistView),
      );
    }
    await loader.load();
  }
}

Widget _action(String label) => SizedBox.square(
  key: ValueKey(label),
  dimension: 44,
  child: Tooltip(message: label, child: const Icon(Icons.circle)),
);

Widget _bar({required bool ar, required bool pill, String? name}) =>
    MadarShellScaffold(
      tabs: [
        MadarTab(label: ar ? 'الفريق' : 'Team', glyph: MadarGlyph.users),
        MadarTab(
          label: ar ? 'الموافقات' : 'Approvals',
          glyph: MadarGlyph.inbox,
        ),
      ],
      selectedIndex: 0,
      onSelect: (_) {},
      person: MadarPerson(
        name: name ?? (ar ? 'تسبيح إبراهيم محمود' : 'Tasbeeh Ibrahim Mahmoud'),
        initial: ar ? 'ت' : 'T',
      ),
      onPersonTap: () {},
      topBar: MadarTopBar(
        title: ar ? 'دوام · الإدارة' : 'Dawam · Manage',
        subtitle: ar ? 'أركان · المعادي' : 'Arkan · Maadi',
        pill: pill
            ? MadarOutboxPill(
                state: OutboxState.queued,
                label: ar ? 'في الانتظار' : 'Queued',
                count: 12,
                onTap: () {},
              )
            : null,
        actions: [_action('manage'), _action('inbox')],
      ),
      body: const SizedBox.expand(),
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  required bool ar,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(358, 780);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: MadarTheme.light(),
      locale: Locale(ar ? 'ar' : 'en'),
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: Scaffold(body: child),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUpAll(_loadFonts);

  for (final ar in [false, true]) {
    for (final pill in [false, true]) {
      final tag = '${ar ? 'ar' : 'en'}${pill ? ' · queued pill' : ''}';
      testWidgets('the top bar fits a 358-pt phone · $tag', (tester) async {
        await _pump(
          tester,
          _bar(ar: ar, pill: pill),
          ar: ar,
        );
        expect(tester.takeException(), isNull, reason: 'no overflow');
        // Both actions keep their full 44-pt target, inside the screen.
        for (final a in ['manage', 'inbox']) {
          final r = tester.getRect(find.byKey(ValueKey(a)));
          expect(r.width, 44);
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(358));
        }
      });
    }
  }

  testWidgets('compact: the name is read out and the pill keeps its count', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, _bar(ar: false, pill: true), ar: false);
    expect(find.bySemanticsLabel('Tasbeeh Ibrahim Mahmoud'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Queued'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Queued')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('the POS look is kept: no actions, the name and word show', (
    tester,
  ) async {
    await _pump(
      tester,
      MadarShellScaffold(
        tabs: [MadarTab(label: 'Sell', glyph: MadarGlyph.bag)],
        selectedIndex: 0,
        onSelect: (_) {},
        person: MadarPerson(name: 'Sara', initial: 'S'),
        topBar: MadarTopBar(
          title: 'Zamalek',
          pill: MadarOutboxPill(
            state: OutboxState.queued,
            label: 'Queued',
            count: 3,
          ),
        ),
        body: const SizedBox.expand(),
      ),
      ar: false,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Sara'), findsOneWidget);
    expect(find.text('Queued'), findsOneWidget);
  });
}
