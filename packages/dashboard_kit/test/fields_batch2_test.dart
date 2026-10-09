// Kit batch 2, fields: number (Arabic minus, ungrouped, commit as typed,
// money Enter), checkbox in a Wrap, bilingual (Enter, screen breakpoint),
// select height, phone, date (Clear, year, past warning), time (Enter,
// range), search (trim, Esc) and the LTR hint.
import 'dart:convert';
import 'dart:io';

import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => Scaffold(
  body: Padding(padding: const EdgeInsets.all(16), child: child),
);

/// Whether [a] is painted left of [b] in the first paragraph reading [text].
bool _leftOf(WidgetTester tester, String text, String a, String b) {
  final p = tester
      .renderObjectList<RenderParagraph>(find.byType(RichText))
      .firstWhere((p) => p.text.toPlainText() == text);
  double x(String ch) {
    final i = text.indexOf(ch);
    return p
        .getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1))
        .first
        .left;
  }

  return x(a) < x(b);
}

void main() {
  group('7 number: Arabic minus, ungrouped', () {
    testWidgets('a negative preset and range read "-1" in Arabic', (
      tester,
    ) async {
      await pumpDashApp(
        tester,
        _host(
          DashNumberInput(
            value: -1,
            min: -5,
            max: 5,
            presets: const [-1],
            onChanged: (_) {},
          ),
        ),
        lang: 'ar',
      );
      final chip = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .map((p) => p.text.toPlainText())
          .firstWhere((s) => s.contains('-1') && !s.contains('5'));
      expect(_leftOf(tester, chip, '-', '1'), isTrue, reason: 'chip');
      await tester.enterText(find.byType(EditableText), '9');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      final range = tester
          .renderObjectList<RenderParagraph>(find.byType(RichText))
          .map((p) => p.text.toPlainText())
          .firstWhere((s) => s.contains('-5'));
      expect(_leftOf(tester, range, '-', '5'), isTrue, reason: range);
    });

    testWidgets('grouped by default; ungrouped reads 9100', (tester) async {
      await pumpDashApp(
        tester,
        _host(
          Column(
            children: [
              DashNumberField(value: 9100, max: 65535, onChanged: (_) {}),
              DashNumberField(
                value: 9100,
                max: 65535,
                grouped: false,
                onChanged: (_) {},
              ),
            ],
          ),
        ),
      );
      final texts = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .map((e) => e.controller.text);
      expect(texts, ['9,100', '9100']);
    });
  });

  group('8 / 29 number commits as typed', () {
    testWidgets('the form holds the typed number before the field is left', (
      tester,
    ) async {
      double? v = 5;
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            DashNumberField(
              label: 'Qty',
              value: v,
              onChanged: (n) => set(() => v = n),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '12');
      await tester.pump();
      expect(v, 12);
      await tester.enterText(find.byType(TextField), '1x');
      await tester.pump();
      expect(v!.isNaN, isTrue, reason: 'unreadable is handed on as NaN');
      expect(find.text('1x'), findsOneWidget, reason: 'the draft stays');
    });

    testWidgets('money: a half-typed ".5" survives, Enter submits piastres', (
      tester,
    ) async {
      int? v = 100;
      final submitted = <int?>[];
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            DashMoneyField(
              label: 'Amount',
              value: v,
              onChanged: (n) => set(() => v = n),
              onSubmitted: submitted.add,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '.');
      await tester.pump();
      expect(v, isNull);
      expect(find.text('.'), findsOneWidget, reason: 'not wiped mid-typing');
      await tester.enterText(find.byType(TextField), '.5');
      await tester.pump();
      expect(v, 50);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submitted, [50]);
    });
  });

  group('10 checkbox field', () {
    testWidgets('in a Wrap: sized by its words, side by side', (tester) async {
      await pumpDashApp(
        tester,
        _host(
          Wrap(
            spacing: 8,
            children: [
              DashCheckboxField(value: true, label: 'Cairo', onChanged: (_) {}),
              DashCheckboxField(value: false, label: 'Giza', onChanged: (_) {}),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(
        tester.getTopLeft(find.text('Cairo')).dy,
        tester.getTopLeft(find.text('Giza')).dy,
      );
    });

    testWidgets('unbounded (in a Row) it lays out and toggles', (tester) async {
      var on = false;
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            Row(
              children: [
                DashCheckboxField(
                  value: on,
                  label: 'Notify',
                  onChanged: (v) => set(() => on = v),
                ),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Notify'));
      await tester.pump();
      expect(on, isTrue);
    });
  });

  group('11 bilingual field', () {
    Widget field({VoidCallback? onSubmitted}) => _host(
      Align(
        alignment: AlignmentDirectional.topStart,
        child: SizedBox(
          width: 360,
          child: DashBilingualField(
            label: 'Name',
            en: '',
            ar: '',
            onEnChanged: (_) {},
            onArChanged: (_) {},
            onSubmitted: onSubmitted,
          ),
        ),
      ),
    );

    testWidgets('two columns by the window (640+), not its own width', (
      tester,
    ) async {
      await pumpDashApp(tester, field(), size: DashSize.tablet);
      final en = tester.getTopLeft(find.byType(DashTextField).first);
      final ar = tester.getTopLeft(find.byType(DashTextField).last);
      expect(en.dy, ar.dy);
    });

    testWidgets('stacked on a phone; Enter submits', (tester) async {
      var submits = 0;
      await pumpDashApp(
        tester,
        field(onSubmitted: () => submits++),
        size: DashSize.phone,
      );
      final en = tester.getTopLeft(find.byType(DashTextField).first);
      final ar = tester.getTopLeft(find.byType(DashTextField).last);
      expect(ar.dy, greaterThan(en.dy));
      await tester.enterText(find.byType(TextField).last, 'قهوة');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submits, 1);
    });
  });

  testWidgets('12 a long select list stops at 256 and scrolls', (tester) async {
    String? v;
    await pumpDashApp(
      tester,
      StatefulBuilder(
        builder: (context, set) => _host(
          DashSelectField<int>(
            label: 'Table',
            value: v == null ? null : int.parse(v!),
            onChanged: (i) => set(() => v = '$i'),
            options: [
              for (var i = 1; i <= 30; i++)
                DashOption(value: i, label: 'Table $i'),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Select…'));
    await tester.pumpAndSettle();
    final card = tester.getRect(
      find
          .ancestor(
            of: find.byType(DashOptionList<int>),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(card.height, lessThanOrEqualTo(256));
    await tester.scrollUntilVisible(
      find.text('Table 30'),
      100,
      scrollable: find.descendant(
        of: find.byType(DashOptionList<int>),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('Table 30'));
    await tester.pumpAndSettle();
    expect(v, '30');
  });

  group('13 phone', () {
    test('the shared phone vectors and the display form', () {
      final vectors =
          json.decode(
                File(
                  '../dashboard_core/test/vectors/phone_vectors.json',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      for (final v in (vectors['valid']! as List).cast<List<Object?>>()) {
        expect(dashCanonicalPhone(v[0]! as String), v[1], reason: '${v[0]}');
      }
      for (final v in (vectors['invalid']! as List).cast<String>()) {
        expect(dashCanonicalPhone(v), isNull, reason: v);
      }
      expect(dashFormatPhoneDisplay('٠١٠٠١٢٣٤٥٦٧'), '+20 100 123 4567');
      expect(dashFormatPhoneDisplay('966512345678'), '+966512345678');
      expect(dashPhoneProblem('0100123456'), 'short');
      expect(dashPhoneProblem('0141234'), 'prefix');
      expect(dashPhoneProblem('abc'), 'bad');
      expect(dashPhoneProblem(''), isNull);
    });

    testWidgets('Arabic: typed left to right, judged once left', (
      tester,
    ) async {
      var v = '';
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            DashPhoneField(
              label: 'الهاتف',
              value: v,
              onChanged: (s) => set(() => v = s),
            ),
          ),
        ),
        lang: 'ar',
      );
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.textDirection, TextDirection.ltr);
      expect(editable.keyboardType, TextInputType.phone);
      await tester.enterText(find.byType(EditableText), '0100123456');
      await tester.pump();
      final short = DashKitStrings.forLanguage('ar').phoneShort;
      expect(find.text(short), findsNothing, reason: 'not while typing');
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pump();
      expect(find.text(short), findsOneWidget);
      await tester.enterText(find.byType(EditableText), '01001234567');
      await tester.pump();
      expect(find.text(short), findsNothing);
      expect(find.text('+20 100 123 4567'), findsOneWidget);
    });
  });

  group('14 date field', () {
    for (final size in [DashSize.desktop, DashSize.phone]) {
      testWidgets('${size.name}: Clear empties it; the year select jumps', (
        tester,
      ) async {
        var cleared = 0;
        await pumpDashApp(
          tester,
          size: size,
          _host(
            DashDateField(
              value: DateTime(2026, 10, 9),
              today: DateTime(2026, 10, 9),
              semanticLabel: 'Hire date',
              yearLabel: 'Year',
              onCleared: () => cleared++,
              onChanged: (_) {},
            ),
          ),
        );
        await tester.tap(find.bySemanticsLabel(RegExp('^Hire date')));
        await tester.pumpAndSettle();
        expect(find.text('October 2026'), findsOneWidget);
        await tester.tap(find.bySemanticsLabel(RegExp('^Year')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('2030'));
        await tester.pumpAndSettle();
        expect(find.text('October 2030'), findsOneWidget);
        expect(find.byType(DashCalendar), findsOneWidget, reason: 'still open');
        await tester.tap(find.text('Clear'));
        await tester.pumpAndSettle();
        expect(cleared, 1);
        expect(find.byType(DashCalendar), findsNothing);
      });
    }

    testWidgets('no Clear without onCleared or a day', (tester) async {
      await pumpDashApp(
        tester,
        _host(
          DashDateField(
            value: null,
            semanticLabel: 'Day',
            onCleared: () {},
            onChanged: (_) {},
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel(RegExp('^Day')));
      await tester.pumpAndSettle();
      expect(find.text('Clear'), findsNothing);
    });

    testWidgets('a past day with warnPast: warning edge and glyph', (
      tester,
    ) async {
      await pumpDashApp(
        tester,
        _host(
          DashDateField(
            value: DateTime(2026, 10, 1),
            today: DateTime(2026, 10, 9),
            warnPast: true,
            onChanged: (_) {},
          ),
        ),
      );
      final c = tester.element(find.byType(DashFieldShell)).madarColors;
      final box =
          tester
                  .widget<AnimatedContainer>(
                    find.descendant(
                      of: find.byType(DashFieldShell),
                      matching: find.byType(AnimatedContainer),
                    ),
                  )
                  .decoration!
              as BoxDecoration;
      expect(box.border!.top.color, c.warning.withValues(alpha: 0.6));
      final glyph = tester.widget<DashIcon>(
        find
            .descendant(
              of: find.byType(DashSelectTrigger),
              matching: find.byType(DashIcon),
            )
            .first,
      );
      expect(glyph.color, DashTone.warning.foreground(c));
      expect(find.text('This date is in the past'), findsOneWidget);
    });
  });

  group('15 / 30 time', () {
    testWidgets('Enter with nothing typed submits; after typing it settles', (
      tester,
    ) async {
      var t = '09:00';
      var submits = 0;
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            DashTimeFormField(
              label: 'Opens',
              value: t,
              onChanged: (v) => set(() => t = v),
              onSubmitted: () => submits++,
            ),
          ),
        ),
      );
      await tester.showKeyboard(find.byType(EditableText));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(submits, 1);
      await tester.enterText(find.byType(EditableText), '10');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(t, '10:00');
      expect(submits, 1);
    });

    test('span arithmetic', () {
      expect(DashTime.spanMinutes('22:00', '06:00'), 480);
      expect(DashTime.spanMinutes('09:00', '09:00'), 0);
      expect(DashTime.spanMinutes('', '09:00'), isNull);
      expect(DashTime.endsNextDay('22:00', '06:00'), isTrue);
      expect(DashTime.suggestEnd('09:00', '05:00'), '17:00');
      expect(DashTime.suggestEnd('22:00', '06:00'), isNull);
      expect(DashTime.formatSpan(510), '8 h 30 min');
      expect(DashTime.formatSpan(45, arabic: true), '45 د');
    });

    testWidgets('a range: next day, same time, the 9-to-5 fix', (tester) async {
      var range = ('22:00', '06:00');
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            DashTimeRangeField(
              start: range.$1,
              end: range.$2,
              startLabel: 'Start',
              endLabel: 'End',
              onChanged: (s, e) => set(() => range = (s, e)),
            ),
          ),
        ),
      );
      expect(find.text('8 h'), findsOneWidget);
      expect(find.text('Ends the next day'), findsOneWidget);

      await tester.pumpWidget(
        dashTestApp(
          child: _host(
            DashTimeRangeField(
              start: '09:00',
              end: '09:00',
              startLabel: 'Start',
              endLabel: 'End',
              onChanged: (_, _) {},
            ),
          ),
        ),
      );
      expect(find.text("It can't start and end at the same time."), findsOne);

      range = ('09:00', '05:00');
      await tester.pumpWidget(
        dashTestApp(
          child: StatefulBuilder(
            builder: (context, set) => _host(
              DashTimeRangeField(
                start: range.$1,
                end: range.$2,
                startLabel: 'Start',
                endLabel: 'End',
                onChanged: (s, e) => set(() => range = (s, e)),
              ),
            ),
          ),
        ),
      );
      expect(find.text("That's 20 h, overnight."), findsOneWidget);
      await tester.tap(find.text('End at 05:00 PM instead'));
      await tester.pump();
      expect(range, ('09:00', '17:00'));
    });
  });

  group('16 search box', () {
    testWidgets('reports the trimmed query; Esc clears it', (tester) async {
      final got = <String>[];
      await pumpDashApp(
        tester,
        _host(
          DashSearchInput(value: '', placeholder: 'Search', onChanged: got.add),
        ),
      );
      await tester.enterText(find.byType(TextField), ' latte ');
      await tester.pump();
      expect(got.last, 'latte');
      expect(find.bySemanticsLabel('Clear'), findsOneWidget, reason: '×');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(got.last, '');
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '',
      );
    });
  });

  testWidgets('17 a forced-LTR placeholder reads LTR in Arabic', (
    tester,
  ) async {
    await pumpDashApp(
      tester,
      _host(
        DashTextInput(
          value: '',
          placeholder: '010 1234 5678',
          textDirection: TextDirection.ltr,
          onChanged: (_) {},
        ),
      ),
      lang: 'ar',
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.hintTextDirection, TextDirection.ltr);
  });
}
