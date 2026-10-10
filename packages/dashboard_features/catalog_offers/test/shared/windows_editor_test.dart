// The shared windows editor (combo editor Availability, deal dialog), driven
// through the real shell on a test-only page: empty state, add, days, the
// day rule's error, remove, read-only; and the one-line window summary.
import 'package:dashboard_api/dashboard_api.dart' show SaleWindow;
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_catalog_offers/src/shared/menu_options.dart';
import 'package:dashboard_catalog_offers/src/shared/offers_format.dart';
import 'package:dashboard_catalog_offers/src/shared/sale_window_form.dart';
import 'package:dashboard_catalog_offers/src/shared/windows_editor.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// The editor on a page, holding its windows and checking them on every
/// change (as a form does after its first Save).
class _Host extends ConsumerStatefulWidget {
  const _Host({required this.enabled, required this.initial});

  final bool enabled;
  final List<WindowDraft> initial;

  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  late List<WindowDraft> windows = widget.initial;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final options = ref.watch(menuOptionsProvider);
    return DashPageScaffold(
      title: t('combos.sections.availability'),
      subtitle: t('combos.sections.availabilityDesc'),
      width: DashPageWidth.reading,
      body: WindowsEditor(
        value: windows,
        onChanged: (next) => setState(() => windows = next),
        branches: options.branches,
        errors: [for (final w in windows) validateWindow(w)],
        enabled: widget.enabled,
      ),
    );
  }
}

DashArea _area({bool enabled = true, List<WindowDraft> initial = const []}) =>
    DashArea(
      key: catalogOffersArea.key,
      routes: [
        DashRoute(
          path: '/test/windows',
          builder: (context, state) =>
              _Host(enabled: enabled, initial: initial),
        ),
      ],
      registerMocks: catalogOffersArea.registerMocks,
      i18nSupplements: catalogOffersArea.i18nSupplements,
    );

void main() {
  testWidgets('empty → add a window → clear days (error) → pick Mon → remove', (
    tester,
  ) async {
    final h = await DashHarness.pump(
      tester,
      areas: [_area()],
      path: '/test/windows',
    );
    expect(find.text(h.t('combos.windows.always')), findsOneWidget);
    await h.shot('shared/windows-empty');

    await h.tapText(h.t('combos.windows.add'));
    expect(find.text(h.t('combos.windows.always')), findsNothing);
    expect(
      find.text(h.t('combos.windows.windowN', args: {'n': 1})),
      findsOneWidget,
    );
    // Every day is on, so the shortcut reads "Clear".
    await h.tapText(h.t('combos.windows.clearDays'));
    expect(find.text(h.t('combos.errors.noDays')), findsOneWidget);
    expect(find.text(h.t('combos.windows.everyDay')), findsOneWidget);

    await h.tapLabel(h.t('combos.windows.day.mon'));
    expect(find.text(h.t('combos.errors.noDays')), findsNothing);
    await h.shot('shared/windows-one');

    await h.tapLabel(h.t('combos.windows.remove'));
    expect(find.text(h.t('combos.windows.always')), findsOneWidget);
  });

  testWidgets('read-only: no Add a window; the remove control is disabled', (
    tester,
  ) async {
    final h = await DashHarness.pump(
      tester,
      areas: [
        _area(
          enabled: false,
          initial: [
            WindowDraft.empty().copyWith(
              weekdays: 62,
              startsAt: '22:00',
              endsAt: '03:00',
            ),
          ],
        ),
      ],
      path: '/test/windows',
      locale: 'ar',
    );
    expect(find.text(h.t('combos.windows.add')), findsNothing);
    expect(find.text(h.t('combos.windows.crossesMidnight')), findsOneWidget);
    final remove = tester.widget<DashIconButton>(
      find.ancestor(
        of: find.bySemanticsLabel(h.t('combos.windows.remove')),
        matching: find.byType(DashIconButton),
      ),
    );
    expect(remove.onPressed, isNull);
    await h.shot('shared/windows-readonly');
  });

  testWidgets(
    'windowSummary reads a window in one line, as the deals list does',
    (tester) async {
      final h = await DashHarness.pump(
        tester,
        areas: [_area()],
        path: '/test/windows',
      );
      final t = h.container.read(tProvider);
      expect(windowSummary(t, const SaleWindow()), 'Every day · All branches');
      expect(
        windowSummary(
          t,
          const SaleWindow(
            weekdays: 62,
            startsAt: '12:00:00',
            endsAt: '16:00:00',
            validFrom: '2026-10-01',
            branchId: 'b-z',
          ),
          branchName: (id) => id == 'b-z' ? 'Zamalek' : null,
        ),
        'Mon, Tue, Wed, Thu, Fri · 12:00 to 16:00 · 2026-10-01 to … · Zamalek',
      );
      expect(
        windowSummary(
          t,
          const SaleWindow(branchId: 'gone'),
          branchName: (_) => null,
        ),
        'Every day · —',
      );
    },
  );
}
