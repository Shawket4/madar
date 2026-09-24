// E2E roster (the owner, iPad Air 11" portrait, 24 Sep): the top bar's
// subtitle names every branch the person works at; for the owner that is all
// nine of Rue's, and the bar overflowed by 524 px on every tab. A long
// subtitle gives way (ellipsis) in Arabic and English; the title stays.

import 'dart:io';

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

void main() {
  setUpAll(_loadFonts);

  for (final ar in [false, true]) {
    testWidgets('a long subtitle gives way on a tablet · ${ar ? 'ar' : 'en'}', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(820, 1180);
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final branches = List.generate(
        9,
        (i) => ar ? 'فرع رقم ${i + 1}' : 'Branch number ${i + 1}',
      );
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: MadarTheme.light(),
          locale: Locale(ar ? 'ar' : 'en'),
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: Scaffold(
            body: MadarShellScaffold(
              tabs: const [
                MadarTab(label: 'Team', glyph: MadarGlyph.users),
                MadarTab(label: 'Schedule', glyph: MadarGlyph.calendar),
              ],
              selectedIndex: 0,
              onSelect: (_) {},
              person: const MadarPerson(name: 'Tasbeeh', initial: 'T'),
              onPersonTap: () {},
              topBar: MadarTopBar(
                title: ar ? 'دوام · الإدارة' : 'Dawam · Manage',
                subtitle: branches.join(' · '),
                actions: const [
                  SizedBox.square(dimension: 44),
                  SizedBox.square(dimension: 44),
                ],
              ),
              body: const SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(
        find.text(ar ? 'دوام · الإدارة' : 'Dawam · Manage'),
        findsOneWidget,
      );
    });
  }
}
