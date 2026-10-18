// The dashboard's frame-timing harness: the real app on the mock backend,
// driven through its heavy flows, each one inside `watchPerformance`, so the
// driver writes build and raster times (p90/p99/worst, frames over the 16 ms
// budget) per flow to `build/integration_response_data.json`.
//
// Run it in profile mode on a desktop target (see `test_driver/perf.dart`):
//
//   flutter drive --profile -d linux \
//     --driver=test_driver/perf.dart \
//     --target=integration_test/perf_test.dart \
//     --dart-define=MADAR_MOCK=1 \
//     --dart-define=MADAR_DASHBOARD_DYLIB=<path to libmadar_frb_dashboard>
//
// Linux has no committed platform folder: `flutter create --platforms=linux .`
// makes one locally (do not commit it). On macOS / Windows the bundled
// library loads by itself and the dylib define can be left out.
// ignore_for_file: depend_on_referenced_packages
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:madar_dashboard/boot/mock.dart';
import 'package:rust_bridge_dashboard/rust_bridge_dashboard.dart';

const String _dylib = String.fromEnvironment('MADAR_DASHBOARD_DYLIB');

/// `--dart-define=PERF_TRACE=1`: record each flow's timeline instead (the
/// frame phases, Dart and GC), to find what a slow frame spent its time on;
/// `PERF_TRACE=widgets` adds every widget build, layout and paint as its own
/// event (heavy: the timeline buffer keeps only the last few frames, so
/// pair it with a short [_only] flow).
const String _traceMode = String.fromEnvironment('PERF_TRACE');
const bool _trace = _traceMode != '';
const bool _traceWidgets = _traceMode == 'widgets';

/// `--dart-define=PERF_ONLY=charts,orders_scroll`: measure only these flows
/// (app start still runs, unmeasured; the other flows are skipped).
const String _only = String.fromEnvironment('PERF_ONLY');

/// `--dart-define=PERF_COUNT=1`, in a DEBUG build (`flutter drive` without
/// `--profile`): instead of timings, count each flow's widget builds by
/// type (`debugOnRebuildDirtyWidget`) and provider updates by provider, to
/// see what rebuilds and what a provider change cascades into.
const bool _count = String.fromEnvironment('PERF_COUNT') == '1';

/// Provider updates by provider (the hot shared ones by name).
final class _ProviderCounts extends ProviderObserver {
  final Map<String, int> updates = {};

  static String nameOf(ProviderBase<Object?> p) {
    if (identical(p, tProvider)) return 'tProvider';
    if (identical(p, formatProvider)) return 'formatProvider';
    if (identical(p, currentScopeProvider)) return 'currentScopeProvider';
    if (identical(p, scopeProvider)) return 'scopeProvider';
    if (identical(p, authzProvider)) return 'authzProvider';
    if (identical(p, localeProvider)) return 'localeProvider';
    if (identical(p, apiProvider)) return 'apiProvider';
    if (identical(p.from, realtimeEpochProvider)) {
      return 'realtimeEpochProvider(${p.argument})';
    }
    final arg = p.argument == null ? '' : '(${p.argument})';
    return '${p.name ?? p.runtimeType}$arg';
  }

  @override
  void didUpdateProvider(
    ProviderObserverContext context,
    Object? previousValue,
    Object? newValue,
  ) {
    final k = nameOf(context.provider);
    updates[k] = (updates[k] ?? 0) + 1;
  }
}

Map<String, int> _top(Map<String, int> m, int n) {
  final e = m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return {for (final x in e.take(n)) x.key: x.value};
}

/// Real time passes (the binding is live): motion plays as a person sees it.
Future<void> _idle(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('dashboard frame timings', (tester) async {
    if (_dylib.isNotEmpty) await MadarCore.initForTest(dylibPath: _dylib);
    late ProviderContainer container;
    final providers = _ProviderCounts();

    final only = _only.isEmpty ? null : _only.split(',').toSet();
    Future<void> flow(String name, Future<void> Function() body) async {
      // App start always runs (the rest need the app); other flows not
      // asked for are skipped (each one opens its own page first).
      if (only != null && !only.contains(name)) {
        return name == 'app_start' ? body() : null;
      }
      if (_count) {
        debugPrint('PERF flow $name');
        final builds = <String, int>{};
        providers.updates.clear();
        debugOnRebuildDirtyWidget = (e, builtOnce) {
          final k = '${e.widget.runtimeType}';
          builds[k] = (builds[k] ?? 0) + 1;
        };
        try {
          await body();
        } finally {
          debugOnRebuildDirtyWidget = null;
        }
        (binding.reportData ??= {})[name] = {
          'builds_total': builds.values.fold<int>(0, (a, b) => a + b),
          'pages': {
            for (final e in builds.entries)
              if (e.key.endsWith('Page') || e.key == 'DashShell')
                e.key: e.value,
          },
          'top_widgets': _top(builds, 30),
          'provider_updates': _top(providers.updates, 30),
        };
        return;
      }
      if (!_trace) return binding.watchPerformance(body, reportKey: name);
      debugProfileBuildsEnabled = _traceWidgets;
      debugProfileLayoutsEnabled = _traceWidgets;
      debugProfilePaintsEnabled = _traceWidgets;
      try {
        await binding.traceAction(
          body,
          streams: const ['Dart', 'Embedder', 'GC'],
          reportKey: name,
        );
      } finally {
        debugProfileBuildsEnabled = false;
        debugProfileLayoutsEnabled = false;
        debugProfilePaintsEnabled = false;
      }
    }

    String t(String key) => container.read(tProvider)(key);

    Future<void> go(String path, {int settle = 1500}) async {
      container.read(dashRouterProvider).go(path);
      await _idle(settle);
    }

    Future<void> tapText(String text, {int settle = 900}) async {
      final f = find.text(text);
      if (f.evaluate().isEmpty) return;
      await tester.tap(f.first, warnIfMissed: false);
      await _idle(settle);
    }

    Future<void> escape({int settle = 700}) async {
      // The physical key given: the desktop key maps cannot look one up.
      await simulateKeyDownEvent(
        LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await simulateKeyUpEvent(
        LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      await _idle(settle);
    }

    /// Drags the page's main scroll view down and back, the way a mouse
    /// wheel or a trackpad would.
    Future<void> scrollPage({int passes = 3}) async {
      // Only a scroll view the pointer actually reaches at its centre.
      final scrollables = find
          .byWidgetPredicate(
            (w) =>
                w is Scrollable &&
                axisDirectionToAxis(w.axisDirection) == Axis.vertical,
          )
          .hitTestable();
      if (scrollables.evaluate().isEmpty) return;
      // The largest vertical scroll view is the page's.
      Finder best = scrollables.first;
      var area = 0.0;
      for (var i = 0; i < scrollables.evaluate().length; i++) {
        final f = scrollables.at(i);
        final s = tester.getSize(f);
        if (s.width * s.height > area) {
          area = s.width * s.height;
          best = f;
        }
      }
      final center = tester.getCenter(best);
      for (var p = 0; p < passes; p++) {
        for (var i = 0; i < 6; i++) {
          await tester.timedDragFrom(
            center,
            const Offset(0, -260),
            const Duration(milliseconds: 220),
          );
          await _idle(60);
        }
        await tester.fling(best, const Offset(0, 1600), 3000);
        await _idle(700);
      }
    }

    await flow('app_start', () async {
      container = await bootMock(observers: [providers]);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const DashApp(
            localizationsDelegates: [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        ),
      );
      await _idle(4000);
    });

    // Nothing touched for three seconds: an app at rest draws no frames.
    await flow('idle', () async {
      await _idle(3000);
    });

    await flow('sidebar_navigation', () async {
      for (final p in const [
        '/orders',
        '/menu/items',
        '/reports/operations',
        '/inventory/ingredients',
        '/staff/team',
        '/customers',
        '/reports/financial',
        '/settings',
        '/',
      ]) {
        await go(p, settle: 1200);
      }
    });

    await flow('dashboard_home', () async {
      await go('/orders', settle: 800);
      await go('/', settle: 3000);
      await scrollPage(passes: 2);
    });

    await flow('operations_tabs', () async {
      await go('/reports/operations', settle: 2000);
      for (final tab in operationsTabKeys) {
        await tapText(t('reports.operations.tabs.$tab'), settle: 1300);
      }
      await tapText(t('reports.operations.tabs.tables'), settle: 1000);
    });

    await flow('orders_scroll', () async {
      await go('/orders', settle: 2000);
      await scrollPage();
    });

    await flow('menu_items_grid', () async {
      await go('/menu/items', settle: 2000);
      await scrollPage();
    });

    await flow('dialogs_and_sheets', () async {
      await go('/orders', settle: 1500);
      for (var i = 0; i < 3; i++) {
        final rows = find.descendant(
          of: find.byWidgetPredicate((w) => w is DashDataTable),
          matching: find.byType(DashPressable),
        );
        if (rows.evaluate().isNotEmpty) {
          await tester.tap(rows.at(i), warnIfMissed: false);
          await _idle(1100);
          await escape(settle: 800);
        }
      }
      // A centred dialog from the page header's primary action.
      final nav = container.read(dashRouterProvider);
      final ctx = nav.routerDelegate.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        for (var i = 0; i < 3; i++) {
          showDashConfirm(ctx, title: 'Perf', description: 'Open and close');
          await _idle(700);
          await escape();
        }
      }
    });

    await flow('date_range_picker', () async {
      await go('/reports/financial', settle: 2000);
      for (var i = 0; i < 3; i++) {
        final picker = find.byType(DashDateRangePicker);
        if (picker.evaluate().isEmpty) break;
        await tester.tap(picker.first, warnIfMissed: false);
        await _idle(900);
        await escape(settle: 700);
      }
    });

    // Realtime bursts, as the branch stream delivers them: ten till events
    // on the home (they invalidate `/tills` and `/reports`, which the home's
    // reads watch), then three resyncs on Orders (everything is stale).
    await flow('realtime_home', () async {
      await go('/', settle: 2500);
      final bus = container.read(realtimeBusProvider);
      for (var i = 0; i < 10; i++) {
        bus.dispatch(RealtimeFrame(event: 'till.updated', id: 'perf-$i'));
        await _idle(500);
      }
      await _idle(1000);
    });

    await flow('realtime_orders', () async {
      await go('/orders', settle: 2000);
      final bus = container.read(realtimeBusProvider);
      for (var i = 0; i < 3; i++) {
        bus.dispatch(RealtimeFrame(event: 'resync', id: 'perf-r$i'));
        await _idle(1200);
      }
    });

    // Typing in the Orders search, a key at a time.
    await flow('typing', () async {
      await go('/orders', settle: 1500);
      final field = find.byType(EditableText);
      if (field.evaluate().isEmpty) return;
      const word = 'latte cup';
      for (var i = 1; i <= word.length; i++) {
        await tester.enterText(field.first, word.substring(0, i));
        await _idle(150);
      }
      await _idle(800);
    });

    await flow('charts', () async {
      await go('/reports/financial', settle: 2500);
      await scrollPage(passes: 2);
      await go('/basira', settle: 2500);
      await scrollPage(passes: 1);
    });
  });
}

/// The Operations report's tab ids, in the order the strip shows them.
const List<String> operationsTabKeys = [
  'overview',
  'items',
  'tellers',
  'waiters',
  'branches',
];
