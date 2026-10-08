import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page with one button that runs [open] with a context under the app.
Widget _opener(Future<void> Function(BuildContext context) open) => Scaffold(
  body: Builder(
    builder: (context) => Center(
      child: DashButton(label: 'Open', onPressed: () => open(context)),
    ),
  ),
);

void main() {
  group('confirm', () {
    for (final (label, expectResult) in [('Delete', true), ('Cancel', false)]) {
      testWidgets('resolves $expectResult on $label', (tester) async {
        bool? result;
        await pumpDashApp(
          tester,
          _opener((c) async {
            result = await showDashConfirm(
              c,
              title: 'Delete the Zamalek branch?',
              description: "Its 3 tills stop syncing. This can't be undone.",
              confirmLabel: 'Delete',
              destructive: true,
            );
          }),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(find.text('Delete the Zamalek branch?'), findsOneWidget);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(result, expectResult);
        expect(find.text('Delete the Zamalek branch?'), findsNothing);
      });
    }

    testWidgets('a tap outside is a no', (tester) async {
      bool? result;
      await pumpDashApp(
        tester,
        _opener(
          (c) async =>
              result = await showDashConfirm(c, title: 'Void order #1042?'),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('Arabic words for the default buttons', (tester) async {
      await pumpDashApp(
        tester,
        _opener((c) => showDashConfirm(c, title: 'حذف الفرع؟')),
        lang: 'ar',
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('تأكيد'), findsOneWidget);
      expect(find.text('إلغاء'), findsOneWidget);
    });
  });

  group('dialog, panel, sheet', () {
    Widget surface(BuildContext context) => DashSurface(
      title: 'Edit Flat White',
      description: 'Changes reach every till.',
      actions: [
        DashButton(
          label: 'Cancel',
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.pop(context),
        ),
        DashButton(
          label: 'Save',
          onPressed: () => Navigator.pop(context, 'saved'),
        ),
      ],
      body: const Text('form body'),
    );

    testWidgets('a dialog is centred on a wide screen and returns its result', (
      tester,
    ) async {
      Object? got;
      await pumpDashApp(
        tester,
        _opener(
          (c) async => got = await showDashDialog<String>(c, builder: surface),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final scope = tester.widget<DashSurfaceScope>(
        find.byType(DashSurfaceScope),
      );
      expect(scope.mode, DashSurfaceMode.dialog);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(got, 'saved');
    });

    testWidgets('the close × dismisses', (tester) async {
      await pumpDashApp(
        tester,
        _opener((c) => showDashDialog<void>(c, builder: surface)),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Close').last);
      await tester.pumpAndSettle();
      expect(find.text('form body'), findsNothing);
    });

    testWidgets(
      'on a phone the same dialog is a full-screen page with stacked actions',
      (tester) async {
        await pumpDashApp(
          tester,
          _opener((c) => showDashDialog<void>(c, builder: surface)),
          size: DashSize.phone,
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<DashSurfaceScope>(find.byType(DashSurfaceScope)).mode,
          DashSurfaceMode.fullScreen,
        );
        final save = tester.getRect(find.text('Save'));
        final cancel = tester.getRect(find.text('Cancel'));
        expect(save.top, lessThan(cancel.top));
      },
    );

    testWidgets('a side panel slides in at the end side — the left in Arabic', (
      tester,
    ) async {
      await pumpDashApp(
        tester,
        _opener((c) => showDashSidePanel<void>(c, builder: surface)),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DashSurfaceScope>(find.byType(DashSurfaceScope)).mode,
        DashSurfaceMode.panel,
      );
      expect(
        tester.getRect(find.text('form body')).left,
        greaterThan(DashSize.desktop.size.width / 2),
      );

      await tester.pumpWidget(const SizedBox());
      await pumpDashApp(
        tester,
        _opener((c) => showDashSidePanel<void>(c, builder: surface)),
        lang: 'ar',
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('form body')).right,
        lessThan(DashSize.desktop.size.width / 2),
      );
    });

    testWidgets('a sheet is full screen on a phone', (tester) async {
      await pumpDashApp(
        tester,
        _opener((c) => showDashSheet<void>(c, builder: surface)),
        size: DashSize.phone,
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<DashSurfaceScope>(find.byType(DashSurfaceScope)).mode,
        DashSurfaceMode.fullScreen,
      );
    });
  });

  group('toasts', () {
    testWidgets('a toast shows at the top and leaves after four seconds', (
      tester,
    ) async {
      await pumpDashApp(
        tester,
        _opener((c) async => DashToast.success(c, 'Changes saved')),
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(find.text('Changes saved'), findsOneWidget);
      expect(tester.getRect(find.text('Changes saved')).top, lessThan(120));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump();
      expect(find.text('Changes saved'), findsNothing);
    });

    testWidgets('a loading toast stays until it is turned into a result', (
      tester,
    ) async {
      DashToastHandle? h;
      await pumpDashApp(
        tester,
        _opener((c) async => h = DashToast.loading(c, 'Exporting…')),
      );
      await tester.tap(find.text('Open'));
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Exporting…'), findsOneWidget);
      h!.update(DashToastKind.error, 'Export failed');
      await tester.pump();
      expect(find.text('Export failed'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Close'));
      await tester.pump();
      expect(find.text('Export failed'), findsNothing);
    });
  });

  group('page', () {
    testWidgets(
      'title, back, actions, tabs; the phone puts actions on their own line',
      (tester) async {
        var back = 0;
        var tab = 'a';
        Widget page() => StatefulBuilder(
          builder: (context, set) => Scaffold(
            body: DashPageScaffold(
              title: 'Orders',
              subtitle: 'Every sale, newest first.',
              onBack: () => back++,
              actions: [DashButton(label: 'New order', onPressed: () {})],
              tabs: DashPageTabs<String>(
                value: tab,
                onChanged: (v) => set(() => tab = v),
                tabs: const [
                  DashTab(value: 'a', label: 'All'),
                  DashTab(value: 'b', label: 'Today'),
                ],
              ),
              body: Text('tab $tab'),
            ),
          ),
        );
        await pumpDashApp(tester, page());
        await tester.tap(find.bySemanticsLabel('Back'));
        expect(back, 1);
        await tester.tap(find.text('Today'));
        await tester.pump();
        expect(find.text('tab b'), findsOneWidget);
        final title = tester.getRect(find.text('Orders'));
        expect(
          (tester.getRect(find.text('New order')).top - title.top).abs(),
          lessThan(24),
        );

        await tester.pumpWidget(const SizedBox());
        await pumpDashApp(tester, page(), size: DashSize.phone);
        expect(
          tester.getRect(find.text('New order')).top,
          greaterThan(tester.getRect(find.text('Orders')).bottom),
        );
      },
    );

    test('section tabs: the deepest matching path is the active one', () {
      const tabs = [
        DashSectionTab(path: '/settings', label: 'Appearance'),
        DashSectionTab(path: '/settings/brand', label: 'Brand'),
      ];
      expect(
        DashSectionTabs.activeFor(tabs, '/settings/brand'),
        '/settings/brand',
      );
      expect(
        DashSectionTabs.activeFor(tabs, '/settings/brand/logo'),
        '/settings/brand',
      );
      expect(DashSectionTabs.activeFor(tabs, '/settings'), '/settings');
      expect(DashSectionTabs.activeFor(tabs, '/settings/links'), '/settings');
    });
  });

  group('figures', () {
    testWidgets('a stat value shortens to fit and opens the exact figure', (
      tester,
    ) async {
      await pumpDashApp(
        tester,
        const Scaffold(
          body: Center(
            child: SizedBox(
              width: 120,
              child: DashStatValue(
                value: 452865000,
                format: DashStatFormat.money,
                label: 'Net sales',
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('EGP 4.5M'), findsOneWidget);
      await tester.tap(find.text('EGP 4.5M'));
      await tester.pumpAndSettle();
      expect(find.text('EGP 4,528,650.00'), findsOneWidget);
    });

    testWidgets('counts up on first draw, but not under reduced motion', (
      tester,
    ) async {
      Widget value() => Scaffold(
        body: DashAnimatedNumber(
          value: 1000,
          format: (n) => n.round().toString(),
        ),
      );
      await pumpDashApp(tester, value());
      await tester.pump(const Duration(milliseconds: 100));
      final mid = int.parse(tester.widget<Text>(find.byType(Text)).data!);
      expect(mid, lessThan(1000));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('1000'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpDashApp(tester, value(), reducedMotion: true);
      await tester.pump();
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('a status pill carries a glyph and its words', (tester) async {
      await pumpDashApp(
        tester,
        const Scaffold(
          body: DashStatusPill(label: 'Voided', tone: DashTone.danger),
        ),
      );
      expect(find.text('Voided'), findsOneWidget);
      expect(DashStatusPill.toneFor('VOIDED'), DashTone.danger);
      expect(DashStatusPill.toneFor('mystery'), DashTone.neutral);
    });
  });

  group('editable cards', () {
    testWidgets('tap a value, type, Enter commits the patch; Escape cancels', (
      tester,
    ) async {
      final patches = <Map<String, Object?>>[];
      await pumpDashApp(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: DashEditableCardGrid<String>(
              rows: const ['Latte'],
              rowKey: (r) => r,
              titleField: DashEditableField(
                key: 'name',
                label: 'Name',
                getValue: (r) => r,
              ),
              fields: [
                DashEditableField(
                  key: 'price',
                  label: 'Price',
                  type: DashEditableType.money,
                  getValue: (r) => 4500,
                ),
              ],
              onCommit: (row, patch) async => patches.add(patch),
            ),
          ),
        ),
      );
      await tester.tap(find.text('EGP 45.00'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '47.5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(patches, [
        {'price': 4750},
      ]);
      await tester.tap(find.text('Latte'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Flat White');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(patches.length, 1);
    });
  });
}
