// The week board on its own, over a roster busier than the app's fixtures:
// two shifts in a day, paid and half-day unpaid leave, a swap waiting, a
// change after publishing, a claimed open shift, a holiday and a coverage
// grid. Each must lay out on a phone and a tablet, Arabic and English,
// without an overflow; taps and drops must reach the screen. With
//   flutter test --dart-define=MADAR_RENDER=true
// it also writes build/shots/board-<lang>-<device>.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:design_system/design_system.dart';
import 'package:feature_dawam_schedule/feature_dawam_schedule.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

const _render = bool.fromEnvironment('MADAR_RENDER');

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

final List<DateTime> _days = [
  for (var i = 0; i < 7; i++) DateTime(2026, 9, 19 + i),
];

/// The board's inputs, and what it sent back.
class _Roster {
  _Roster(MadarColors c, {required this.tight, this.focus = 4}) {
    _fill(c);
  }

  final bool tight;

  /// Today's column (the board opens on it).
  final int focus;

  final taps = <Shift>[];
  final empties = <(String?, DateTime)>[];
  final drops = <(Shift, String?, DateTime)>[];

  static const _people = [
    'Sara Ahmed',
    'Omar Khaled',
    'Youssef Adel',
    'Laila Hassan',
    'Mona Samir',
    'Karim Nabil',
  ];

  final _cards = <String, List<RosterCard>>{};

  // The hours as the screen writes them: the language's AM and PM, and
  // no spaces round the dash on a phone's narrow column.
  String get _dash => tight && !isAr ? '–' : ' – ';
  String get _morning => '8 ${tr('staff.am')}${_dash}4 ${tr('staff.pm')}';
  String get _evening => '3 ${tr('staff.pm')}${_dash}11 ${tr('staff.pm')}';

  void _fill(MadarColors c) {
    final morning = c.series[0];
    final evening = c.series[1];
    void put(
      String? emp,
      int day,
      String title,
      String window,
      Color color, {
      String? leave,
      bool half = false,
      bool changed = false,
      bool swap = false,
      bool claimed = false,
    }) {
      final d = _days[day];
      (_cards['$emp|$d'] ??= []).add(
        RosterCard(
          shift: Shift('$emp|$d|$title', emp, title, d),
          title: title,
          window: window,
          color: color,
          leave: leave,
          half: half,
          changed: changed,
          swap: swap,
          claimed: claimed,
        ),
      );
    }

    for (var d = 0; d < 7; d++) {
      if (d != 3) put('e1', d, 'Morning', _morning, morning);
      if (d != 5) {
        put('e3', d, 'Evening', _evening, evening, swap: d == 2);
      }
      if (d.isEven) put('e4', d, 'Morning', _morning, morning);
      if (d == 1 || d == 6) {
        put('e6', d, 'Evening', _evening, evening, changed: true);
      }
    }
    put('e1', 3, 'Morning', _morning, morning, leave: 'paid');
    put('e2', 4, 'Morning', _morning, morning);
    put('e2', 4, 'Evening', _evening, evening);
    put('e5', 1, 'Evening', _evening, evening, leave: 'unpaid', half: true);
    put(null, 4, 'Evening', _evening, c.warning, claimed: true);
    put(null, 6, 'Morning', _morning, c.warning);
  }

  List<RosterCard> cardsAt(String? emp, DateTime d) =>
      _cards['$emp|$d'] ?? const [];

  List<RosterRow> rows(MadarColors c) => [
    RosterRow(emp: null, name: tr('staff.open_shifts'), color: c.warning),
    for (final (i, n) in _people.indexed)
      RosterRow(
        emp: 'e${i + 1}',
        name: n,
        color: c.series[i % c.series.length],
        minutes: 40 * 60 - i * 90,
      ),
  ];

  List<RosterDay> get days => [
    for (final (i, d) in _days.indexed)
      RosterDay(
        d,
        today: i == 4,
        holiday: i == 6 ? 'Armed Forces Day' : null,
        staffed: 3 + i % 2,
        need: 4,
      ),
  ];

  Widget board() => Builder(
    builder: (context) {
      final c = context.madarColors;
      return RosterBoard(
        rows: rows(c),
        days: days,
        cardsAt: cardsAt,
        focus: focus,
        onTapCard: taps.add,
        onTapEmpty: (e, d) => empties.add((e, d)),
        onDrop: (s, e, d) => drops.add((s, e, d)),
      );
    },
  );
}

Future<_Roster> _pump(
  WidgetTester tester,
  String lang,
  Size size, {
  int focus = 4,
}) async {
  currentLang = lang;
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  late _Roster roster;
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: MadarTheme.light(),
        home: Directionality(
          textDirection: lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
          child: Builder(
            builder: (context) {
              roster = _Roster(
                context.madarColors,
                tight: MadarLayout.of(context).isPhone,
                focus: focus,
              );
              return Scaffold(
                backgroundColor: context.madarColors.bg,
                body: Padding(
                  padding: const EdgeInsets.all(16),
                  child: roster.board(),
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return roster;
}

Future<void> _write(WidgetTester tester, String name) async {
  final boundary =
      tester.renderObject(find.byKey(const ValueKey('shot')))
          as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/shots')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  words = (key) => coreWord(key, arabic: currentLang == 'ar');
  use24h = false;

  setUpAll(_loadFonts);

  const devices = {'phone': Size(390, 844), 'tablet': Size(1180, 820)};
  for (final lang in ['ar', 'en']) {
    for (final MapEntry(key: device, value: size) in devices.entries) {
      testWidgets('the board lays out · $lang · $device', (tester) async {
        await _pump(tester, lang, size);
        expect(tester.takeException(), isNull);
        expect(find.byType(ShiftCard), findsWidgets);
        if (_render) await _write(tester, 'board-$lang-$device');
      });
    }
  }

  for (final lang in ['ar', 'en']) {
    test('a card says it is edited and ends the next day · $lang', () {
      currentLang = lang;
      final s = Shift('e1|2026-09-24|w', 'e1', 'w', DateTime(2026, 9, 24));
      final card = RosterCard(
        shift: s,
        title: 'Evening',
        window: '18:00 – 02:00 +1',
        color: const Color(0xFF000000),
        edited: true,
        nextDay: true,
      );
      expect(card.label, contains(tr('staff.edited')));
      expect(card.label, contains(tr('staff.ends_next_day')));
      expect(
        RosterCard(
          shift: s,
          title: 'Evening',
          window: '',
          color: const Color(0xFF000000),
        ).label,
        isNot(contains(tr('staff.edited'))),
      );
    });
  }

  testWidgets('a tablet sees the whole week without scrolling', (t) async {
    await _pump(t, 'en', const Size(1180, 820));
    for (final d in _days) {
      expect(find.text('${d.day}'), findsOneWidget);
    }
  });

  testWidgets('a phone opens on today and sees about three days', (t) async {
    await _pump(t, 'ar', const Size(390, 844));
    // Today is the fifth day (the 23rd); Saturday has scrolled away.
    expect(find.text('23'), findsOneWidget);
    expect(find.text('19'), findsNothing);
  });

  // Found with the fixtures written on a Friday: on a phone, a today late
  // in the week (the last column) was never scrolled to; the board stayed
  // on Saturday and today's cards were off screen.
  testWidgets('a phone opens on today even when it is the last day', (t) async {
    await _pump(t, 'en', const Size(390, 844), focus: 6);
    await t.pump();
    expect(find.text('25'), findsOneWidget, reason: "today's column shows");
    expect(find.text('19'), findsNothing);
  });

  testWidgets('tapping a card or an empty day reaches the screen', (t) async {
    final r = await _pump(t, 'en', const Size(1180, 820));
    await t.tap(find.byType(ShiftCard).first);
    expect(r.taps, hasLength(1));
    await t.tap(find.text(tr('staff.off')).first);
    expect(r.empties, hasLength(1));
    expect(r.empties.single.$1, isNotNull, reason: 'a person, not open');
  });

  // Minor #20: only an empty cell had a "+"; a second block on a worked day
  // (a split day, SC-11) needed a detour. A filled day has one too.
  for (final lang in ['en', 'ar']) {
    testWidgets('a filled day has a + that adds to it · $lang', (t) async {
      final r = await _pump(t, lang, const Size(1180, 820));
      // Omar (e2) works two shifts on Wednesday the 23rd.
      final add = find.byKey(const ValueKey('add|e2|2026-09-23'));
      expect(add, findsOneWidget);
      await t.tap(add);
      expect(r.empties, [('e2', DateTime(2026, 9, 23))]);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('a long-press drag moves a shift to another day', (t) async {
    final r = await _pump(t, 'en', const Size(1180, 820));
    // Omar (e2) works only Wednesday; drag one of his cards to Friday.
    final card = find.byWidgetPredicate(
      (w) => w is ShiftCard && w.card.shift.emp == 'e2',
    );
    final from = t.getCenter(card.first);
    final to = Offset(t.getCenter(find.text('25')).dx, from.dy);
    final g = await t.startGesture(from);
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await g.moveTo(to);
    await t.pump();
    await g.up();
    await t.pump();
    expect(r.drops, hasLength(1));
    final (s, emp, day) = r.drops.single;
    expect(s.emp, 'e2');
    expect(emp, 'e2');
    expect(day, DateTime(2026, 9, 25));
  });

  testWidgets('a drop that changes both day and person is refused', (t) async {
    final r = await _pump(t, 'en', const Size(1180, 820));
    final card = find.byWidgetPredicate(
      (w) => w is ShiftCard && w.card.shift.emp == 'e2',
    );
    final from = t.getCenter(card.first);
    final sara = t.getCenter(find.text('Sara Ahmed'));
    final to = Offset(t.getCenter(find.text('25')).dx, sara.dy);
    final g = await t.startGesture(from);
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await g.moveTo(to);
    await t.pump();
    await g.up();
    await t.pump();
    expect(r.drops, isEmpty);
  });
}
