// E2E posnotif L-17: on an iPhone the Shifts tab's Month view gives each day
// about 60 pt under the swap card and the toolbar. Every day with a shift
// overflowed its cell ("BOTTOM OVERFLOWED BY 4.4 PIXELS") and showed only
// "+1". The month must lay out without an overflow, in both languages.
import 'dart:io';

import 'package:design_system/design_system.dart';
import 'package:feature_dawam_schedule/feature_dawam_schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

Future<void> _loadFonts() async {
  const cuts = ['Regular', 'Medium', 'SemiBold', 'Bold'];
  for (final family in [MadarType.fontFamily, MadarType.monoFamily]) {
    final loader = FontLoader('packages/${MadarType.fontPackage}/$family');
    for (final cut in cuts) {
      final file = File('../../design_system/assets/fonts/$family-$cut.ttf');
      if (file.existsSync()) {
        loader.addFont(file.readAsBytes().then(ByteData.sublistView));
      }
    }
    await loader.load();
  }
}

void main() {
  words = (key) => coreWord(key, arabic: currentLang == 'ar');
  use24h = false;
  setUpAll(_loadFonts);

  // What the Shifts tab leaves the calendar (its toolbar included) under a
  // swap card: about 50 pt a week row on an iPhone SE, about 60 on an
  // iPhone 17e (the E2E screenshot: "BOTTOM OVERFLOWED BY 4.4 PIXELS").
  const phone = Size(393, 852);
  const heights = {
    'iPhone SE, swap card': 400.0,
    'iPhone 17e, swap card': 428.0,
    'iPhone 17e': 500.0,
  };

  for (final lang in ['ar', 'en']) {
    for (final MapEntry(key: device, value: monthHeight) in heights.entries) {
      testWidgets('the month fits a phone · $lang · $device', (tester) async {
        currentLang = lang;
        tester.view.physicalSize = phone * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final shifts = [
          for (var d = 1; d <= 30; d++)
            if (d % 7 != 3)
              Shift('e1|$d', 'e1', 'Morning', DateTime(2026, 9, d))
                ..start = 8 * 60
                ..end = 16 * 60
                ..published = true,
          // A split day: two shifts on the 25th.
          Shift('e1|25b', 'e1', 'Evening', DateTime(2026, 9, 25))
            ..start = 16 * 60
            ..end = 23 * 60
            ..published = true,
        ];
        await tester.pumpWidget(
          MaterialApp(
            theme: MadarTheme.light(),
            home: Directionality(
              textDirection: lang == 'ar'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: Scaffold(
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    height: monthHeight,
                    child: ShiftCalendar(
                      shifts: shifts,
                      now: () => DateTime(2026, 9, 24, 18),
                      colorOf: (_) => const Color(0xFF0F766E),
                      titleOf: (s) => s.tpl,
                      phoneView: CalendarView.month,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(tester.takeException(), isNull, reason: 'the month overflowed');
      });
    }
  }
}
