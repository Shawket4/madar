import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => Scaffold(
  body: Padding(padding: const EdgeInsets.all(16), child: child),
);

void main() {
  group('search', () {
    testWidgets(
      'debounced search reports the trimmed query once typing pauses',
      (tester) async {
        final got = <String>[];
        await pumpDashApp(
          tester,
          _host(
            DashSearchInput(
              value: '',
              placeholder: 'Search orders',
              debounce: DashSearchInput.listDelay,
              onChanged: got.add,
            ),
          ),
        );
        await tester.enterText(find.byType(TextField), 'lat');
        await tester.pump(const Duration(milliseconds: 100));
        await tester.enterText(find.byType(TextField), 'latte ');
        await tester.pump(const Duration(milliseconds: 299));
        expect(got, isEmpty);
        await tester.pump(const Duration(milliseconds: 2));
        expect(got, ['latte']);
      },
    );

    testWidgets('clearing reports the empty query at once', (tester) async {
      final got = <String>[];
      await pumpDashApp(
        tester,
        _host(
          DashSearchInput(
            value: 'mocha',
            placeholder: 'Search',
            debounce: DashSearchInput.listDelay,
            onChanged: got.add,
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Clear'));
      await tester.pump();
      expect(got, ['']);
    });

    testWidgets('the filter bar search is debounced and Clear resets', (
      tester,
    ) async {
      var q = '';
      var cleared = 0;
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            DashFilterBar(
              searchValue: q,
              onSearchChanged: (v) => set(() => q = v),
              onClear: () => set(() {
                q = '';
                cleared++;
              }),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'karim');
      await tester.pump(const Duration(milliseconds: 350));
      expect(q, 'karim');
      await tester.tap(find.text('Clear').last);
      await tester.pump();
      expect(cleared, 1);
      expect(q, '');
      expect(find.text('karim'), findsNothing);
    });
  });

  group('validation', () {
    testWidgets(
      'Form.validate shows the sentence under the field, and a change re-checks',
      (tester) async {
        final form = GlobalKey<FormState>();
        var name = '';
        await pumpDashApp(
          tester,
          StatefulBuilder(
            builder: (context, set) => _host(
              Form(
                key: form,
                child: DashTextField(
                  label: 'Item name',
                  value: name,
                  onChanged: (v) => set(() => name = v),
                  validator: (v) =>
                      v.trim().isEmpty ? 'Give the item a name.' : null,
                ),
              ),
            ),
          ),
        );
        expect(find.text('Give the item a name.'), findsNothing);
        expect(form.currentState!.validate(), isFalse);
        await tester.pump();
        expect(find.text('Give the item a name.'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Flat White');
        await tester.pump();
        await tester.pump();
        expect(find.text('Give the item a name.'), findsNothing);
        expect(form.currentState!.validate(), isTrue);
      },
    );

    testWidgets("a server's errorText shows under the field", (tester) async {
      await pumpDashApp(
        tester,
        _host(
          DashTextField(
            label: 'Barcode',
            value: '1',
            onChanged: (_) {},
            errorText: 'Another item already uses this barcode.',
          ),
        ),
      );
      expect(
        find.text('Another item already uses this barcode.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a number out of range is refused out loud and handed on as typed',
      (tester) async {
        double? v = 5;
        await pumpDashApp(
          tester,
          StatefulBuilder(
            builder: (context, set) => _host(
              DashNumberField(
                label: 'Par',
                value: v,
                max: 12,
                onChanged: (n) => set(() => v = n),
              ),
            ),
          ),
        );
        await tester.enterText(find.byType(TextField), '30');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(find.text('Between 0 and 12'), findsOneWidget);
        expect(v, 30);
        await tester.enterText(find.byType(TextField), 'abc');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();
        expect(find.text('"abc" isn\'t a number'), findsOneWidget);
        expect(v!.isNaN, isTrue);
      },
    );

    testWidgets('the stepper steps and never passes the range', (tester) async {
      double? v = 11;
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            DashNumberField(
              label: 'Par',
              value: v,
              max: 12,
              stepper: true,
              onChanged: (n) => set(() => v = n),
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('More'));
      await tester.pump();
      expect(v, 12);
      await tester.tap(find.bySemanticsLabel('Less'));
      await tester.pump();
      expect(v, 11);
    });

    testWidgets('money is typed in pounds and handed on in piastres', (
      tester,
    ) async {
      int? v;
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            DashMoneyField(
              label: 'Price',
              value: v,
              onChanged: (n) => set(() => v = n),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '19.99');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(v, 1999);
      expect(find.text('EGP'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '١٢٫٥');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(v, 1250);
    });

    testWidgets('a percent is typed as 12.5 and held as 0.125', (tester) async {
      double? v;
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            DashPercentField(
              label: 'Discount',
              value: v,
              onChanged: (n) => set(() => v = n),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '12.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(v, closeTo(0.125, 1e-9));
    });

    testWidgets('a date range ending before it starts says so', (tester) async {
      await pumpDashApp(
        tester,
        _host(
          DashDateRangeField(
            from: DateTime(2026, 10, 9),
            to: DateTime(2026, 10, 1),
            onChanged: (a, b) {},
            quick: const [],
          ),
        ),
      );
      expect(find.text('The end is before the start.'), findsOneWidget);
    });
  });

  group('time', () {
    test('reads times the way people type them', () {
      expect(DashTime.parse('930'), '09:30');
      expect(DashTime.parse('9:30 pm'), '21:30');
      expect(DashTime.parse('9p'), '21:00');
      expect(DashTime.parse('12am'), '00:00');
      expect(DashTime.parse('12 pm'), '12:00');
      expect(DashTime.parse('٩:٣٠ م'), '21:30');
      expect(DashTime.parse('24:00'), '00:00');
      expect(DashTime.parse('21:5'), isNull);
      expect(DashTime.parse('25'), isNull);
      expect(DashTime.parse('soon'), isNull);
    });

    testWidgets(
      'an unreadable time stays on show, invalid, and reaches the form as typed',
      (tester) async {
        String? v = '09:00';
        await pumpDashApp(
          tester,
          StatefulBuilder(
            builder: (context, set) => _host(
              DashTimeField(value: v, onChanged: (s) => set(() => v = s)),
            ),
          ),
        );
        expect(find.text('09:00 AM'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '2130');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(v, '21:30');
        expect(find.text('09:30 PM'), findsWidgets);
        await tester.enterText(find.byType(TextField), 'later');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(v, 'later');
        expect(find.textContaining("Couldn't read \"later\""), findsOneWidget);
      },
    );
  });

  group('choices', () {
    testWidgets('a select opens its list and picks', (tester) async {
      String? v;
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            DashSelectField<String>(
              label: 'Category',
              value: v,
              onChanged: (s) => set(() => v = s),
              options: const [
                DashOption(value: 'hot', label: 'Hot drinks'),
                DashOption(value: 'cold', label: 'Cold drinks'),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Select…'), findsOneWidget);
      await tester.tap(find.text('Select…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cold drinks'));
      await tester.pumpAndSettle();
      expect(v, 'cold');
      expect(find.text('Hot drinks'), findsNothing);
    });

    testWidgets(
      'a searchable select (combobox) filters on label and keywords',
      (tester) async {
        String? v;
        await pumpDashApp(
          tester,
          StatefulBuilder(
            builder: (context, set) => _host(
              DashTimezoneSelect(
                zones: const ['Africa/Cairo', 'America/New_York', 'Asia/Dubai'],
                value: v,
                onChanged: (s) => set(() => v = s),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Select timezone…'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, 'new york');
        await tester.pumpAndSettle();
        expect(find.text('Asia/Dubai'), findsNothing);
        await tester.tap(find.text('America/New_York'));
        await tester.pumpAndSettle();
        expect(v, 'America/New_York');
      },
    );

    testWidgets('a phone select opens a sheet', (tester) async {
      String? v;
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            DashSelect<String>(
              semanticLabel: 'Status',
              value: v,
              onChanged: (s) => set(() => v = s),
              options: const [
                DashOption(value: 'paid', label: 'Paid'),
                DashOption(value: 'open', label: 'Open'),
              ],
            ),
          ),
        ),
        size: DashSize.phone,
      );
      await tester.tap(find.text('Select…'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(v, 'open');
    });

    testWidgets('a multi-select toggles several and reads them back', (
      tester,
    ) async {
      var v = <String>{};
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            DashMultiSelectField<String>(
              label: 'Stations',
              values: v,
              onChanged: (s) => set(() => v = s),
              options: const [
                DashOption(value: 'bar', label: 'Bar'),
                DashOption(value: 'kitchen', label: 'Kitchen'),
                DashOption(value: 'pastry', label: 'Pastry'),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Select…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pastry'));
      await tester.pumpAndSettle();
      expect(v, {'bar', 'pastry'});
    });

    testWidgets('filter chips toggle; a filter select offers "All" as null', (
      tester,
    ) async {
      var chips = <int>{1};
      int? status = 1;
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            Column(
              children: [
                DashFilterChips<int>(
                  values: chips,
                  onChanged: (s) => set(() => chips = s),
                  options: const [
                    DashOption(value: 1, label: 'Dine-in'),
                    DashOption(value: 2, label: 'Delivery'),
                  ],
                ),
                DashFilterSelect<int>(
                  label: 'Status',
                  allLabel: 'All statuses',
                  value: status,
                  onChanged: (s) => set(() => status = s),
                  options: const [DashOption(value: 1, label: 'Paid')],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.text('Delivery'));
      await tester.pump();
      expect(chips, {1, 2});
      await tester.tap(find.text('Dine-in'));
      await tester.pump();
      expect(chips, {2});
      await tester.tap(find.text('Paid'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All statuses'));
      await tester.pumpAndSettle();
      expect(status, isNull);
    });

    testWidgets('switch, checkbox, radio and segments report their choice', (
      tester,
    ) async {
      var on = false;
      var checked = false;
      var size = 'm';
      var view = 'd';
      await pumpDashApp(
        tester,
        StatefulBuilder(
          builder: (context, set) => _host(
            Column(
              children: [
                DashSwitchField(
                  label: 'Active',
                  value: on,
                  onChanged: (v) => set(() => on = v),
                ),
                DashCheckboxField(
                  label: 'Charge VAT',
                  value: checked,
                  onChanged: (v) => set(() => checked = v),
                ),
                DashRadioGroup<String>(
                  value: size,
                  onChanged: (v) => set(() => size = v),
                  options: const [
                    DashOption(value: 's', label: 'Small'),
                    DashOption(value: 'm', label: 'Medium'),
                  ],
                ),
                DashSegmentedControl<String>(
                  value: view,
                  onChanged: (v) => set(() => view = v),
                  options: const [
                    DashOption(value: 'd', label: 'Daily'),
                    DashOption(value: 'w', label: 'Weekly'),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Active').last);
      await tester.tap(find.text('Charge VAT'));
      await tester.tap(find.text('Small'));
      await tester.tap(find.text('Weekly'));
      await tester.pump();
      expect((on, checked, size, view), (true, true, 's', 'w'));
    });

    testWidgets(
      'a date field picks a day from its calendar; Today picks today',
      (tester) async {
        DateTime? v;
        await pumpDashApp(
          tester,
          StatefulBuilder(
            builder: (context, set) => _host(
              DashDateField(
                value: v,
                today: DateTime(2026, 10, 8),
                onChanged: (d) => set(() => v = d),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Pick a date'));
        await tester.pumpAndSettle();
        expect(find.text('October 2026'), findsOneWidget);
        await tester.tap(find.text('14'));
        await tester.pumpAndSettle();
        expect(v, DateTime(2026, 10, 14));
        expect(find.text('14 Oct 2026'), findsOneWidget);
        await tester.tap(find.text('14 Oct 2026'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Today'));
        await tester.pumpAndSettle();
        expect(v, DateTime(2026, 10, 8));
      },
    );

    testWidgets(
      'the period picker applies a hand-picked range, never the future',
      (tester) async {
        DateTime? from;
        DateTime? to;
        String? preset;
        await pumpDashApp(
          tester,
          _host(
            DashDateRangePicker(
              preset: 'last7',
              today: DateTime(2026, 10, 8),
              presets: const [
                DashPeriodPreset(value: 'today', label: 'Today'),
                DashPeriodPreset(value: 'last7', label: 'Last 7 days'),
              ],
              onSelectPreset: (p) => preset = p,
              onApplyCustom: (a, b) {
                from = a;
                to = b;
              },
            ),
          ),
        );
        await tester.tap(find.text('Last 7 days'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('5'));
        await tester.pump();
        await tester.tap(find.text('2'));
        await tester.pump();
        await tester.tap(find.text('20'), warnIfMissed: false);
        await tester.pump();
        expect(find.text('Range selected'), findsOneWidget);
        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect((from, to), (DateTime(2026, 10, 2), DateTime(2026, 10, 5)));
        await tester.tap(find.text('Last 7 days'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Today').first);
        await tester.pumpAndSettle();
        expect(preset, 'today');
      },
    );

    test(
      'quick ranges: pay period from its start day, weeks from Saturday',
      () {
        final t = DateTime(2026, 3, 10);
        final p = dashQuickRange(
          DashQuickRange.thisPeriod,
          today: t,
          periodStartDay: 26,
        );
        expect((p.from, p.to), (DateTime(2026, 2, 26), DateTime(2026, 3, 25)));
        final w = dashQuickRange(
          DashQuickRange.thisWeek,
          today: DateTime(2026, 10, 8),
        );
        expect(w.from.weekday, DateTime.saturday);
        expect(w.from, DateTime(2026, 10, 3));
        expect(w.to, DateTime(2026, 10, 9));
      },
    );
  });

  group('words and figures', () {
    test('fromLookup reads the web keys with their arguments', () {
      final s = DashKitStrings.fromLookup(
        (key, [args]) => '$key${args == null ? '' : args.values.join(',')}',
      );
      expect(s.noResults, 'common.noResults');
      expect(s.page(2, 5), 'common.page2,5');
      expect(s.selectedCount(3), 'grid.selectedCount3');
    });

    test('the web words in both languages', () {
      expect(DashKitStrings.forLanguage('en').page(1, 3), 'Page 1 of 3');
      expect(DashKitStrings.forLanguage('ar').page(1, 3), 'صفحة 1 من 3');
      expect(DashKitStrings.forLanguage('ar').retry, 'إعادة المحاولة');
    });

    test('money in the web shape', () {
      const en = DashKitFormats();
      const ar = DashKitFormats(languageCode: 'ar');
      expect(en.money(123450), 'EGP 1,234.50');
      expect(en.money(-5000), '−EGP 50.00');
      expect(en.money(2000, signed: true), '+EGP 20.00');
      expect(en.money(null), '—');
      expect(ar.money(123450), '\u20661,234.50\u2069 ج.م');
      expect(en.moneyCompact(452865000), 'EGP 4.5M');
      expect(en.percent(0.123), '12.3%');
      expect(ar.percent(0.123), '12.3%');
      expect(en.date(DateTime(2026, 10, 7)), '07 Oct 2026');
      expect(en.time('21:30'), '09:30 PM');
      expect(ar.time('09:05'), '09:05 ص');
    });
  });
}
