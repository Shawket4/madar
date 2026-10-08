// The harness every dashboard widget test drives the real app through.
//
// flutter_test is every package's dev dependency and this library is only
// ever imported from tests, so it is not a runtime dependency of the core.
// ignore_for_file: depend_on_referenced_packages

/// [DashHarness]: the whole app — the router, the frame, the gates, every
/// area's pages — on the mock server and the mock gateways, with real fonts,
/// at a window size, in a language and a theme. It fails the test on a call
/// no mock answered, a mock handler that crashed, a word missing from the
/// tables (or English in Arabic), and (as every widget test does) a layout
/// overflow.
library;

import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/mock.dart';
import 'package:dashboard_core/shell.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:dashboard_kit/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final Map<String, Strings> _stringsCache = {};

/// The running app under test.
class DashHarness {
  DashHarness._({
    required this.tester,
    required this.server,
    required this.db,
    required this.session,
    required this.prefs,
    required this.container,
    required this.strings,
    required this.size,
    required this.locale,
    required this.dark,
    required this.shotArea,
  });

  final WidgetTester tester;
  final MockServer server;

  /// The seeded tables (null when the test brought its own server).
  final MockDb? db;
  final MockSessionGateway session;
  final MemoryPreferences prefs;
  final RecordingFileGateway files = RecordingFileGateway();
  final RecordingExportGateway exports = RecordingExportGateway();
  final MockRealtimeGateway realtime = MockRealtimeGateway();

  /// Every address opened outside the app (legal links).
  final List<Uri> openedLinks = [];
  final ProviderContainer container;
  final Strings strings;
  final DashSize size;
  final String locale;
  final bool dark;

  /// The `<area>` folder screenshots go to.
  final String shotArea;

  /// Set to let a test hit an unmatched route on purpose.
  bool allowUnmatched = false;

  /// Set to let a test show a word the tables do not have on purpose.
  bool allowMissingKeys = false;

  GoRouter get router => container.read(dashRouterProvider);

  /// The current location (path and query).
  Uri get location => router.routerDelegate.currentConfiguration.uri;

  /// `t()` in the harness's language.
  String t(
    String key, {
    Map<String, Object?>? args,
    num? count,
    String? defaultValue,
  }) => strings.translate(
    container.read(localeProvider),
    key,
    args: args,
    count: count,
    defaultValue: defaultValue,
  );

  /// Pumps the app at [path].
  ///
  /// - [areas]: the areas whose pages and mocks to load (their mocks are
  ///   registered after the core's, so an area can replace a core route).
  /// - [persona]: who is signed in; null starts signed out.
  /// - [server] (with [db]): a server the test set up itself, mocks and all.
  /// - [clock]: the mock clock (defaults to the seed's).
  /// - [prefs]: preferences to start from (language and theme come from
  ///   [locale] and [dark]).
  /// - [shotArea]: the screenshot folder (the single area's key, else
  ///   `shell`).
  static Future<DashHarness> pump(
    WidgetTester tester, {
    List<DashArea> areas = const [],
    String path = '/',
    Persona? persona = Persona.owner,
    DashSize size = DashSize.desktop,
    String locale = 'en',
    bool dark = false,
    MockServer? server,
    MockDb? db,
    MockClock? clock,
    Map<String, String>? prefs,
    bool reducedMotion = true,
    String? shotArea,
  }) async {
    await tester.runAsync(loadDashFonts);
    final cacheKey = areas.map((a) => a.key).join(',');
    final strings = _stringsCache[cacheKey] ??= (await tester.runAsync(
      () => loadDashStrings(areas: areas),
    ))!;
    strings.log.clear();

    MockDb? seeded = db;
    var srv = server;
    if (srv == null) {
      seeded ??= MockDb.seeded();
      srv = MockServer(
        persona: persona ?? Persona.owner,
        clock: clock ?? seeded.clock,
      );
      registerCoreMocks(srv, seeded);
      for (final a in areas) {
        a.registerMocks?.call(srv, seeded);
      }
    }
    final mockClock = clock ?? seeded?.clock ?? srv.clock;
    final session = MockSessionGateway(srv, signedInAs: persona);
    final memory = MemoryPreferences({
      languagePrefKey: locale,
      themePrefKey: dark ? ThemePref.dark.name : ThemePref.light.name,
      ...?prefs,
    });

    late final DashHarness h;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        dashAreasProvider.overrideWithValue(areas),
        dashInitialLocationProvider.overrideWithValue(path),
        stringsProvider.overrideWithValue(strings),
        initialLocaleProvider.overrideWithValue(locale),
        preferencesProvider.overrideWithValue(memory),
        sessionGatewayProvider.overrideWithValue(session),
        transportProvider.overrideWith(
          (ref) => SessionGuardTransport(
            session.transport,
            onUnauthorized: () =>
                ref.read(sessionProvider.notifier).handleUnauthorized(),
            signedIn: () => ref.read(currentSessionProvider) != null,
          ),
        ),
        clockProvider.overrideWithValue(() => mockClock.now),
        fileGatewayProvider.overrideWith((ref) => h.files),
        exportGatewayProvider.overrideWith((ref) => h.exports),
        realtimeGatewayProvider.overrideWith((ref) => h.realtime),
        linkOpenerProvider.overrideWith(
          (ref) =>
              (uri) async => h.openedLinks.add(uri),
        ),
      ],
    );
    h = DashHarness._(
      tester: tester,
      server: srv,
      db: seeded,
      session: session,
      prefs: memory,
      container: container,
      strings: strings,
      size: size,
      locale: locale,
      dark: dark,
      shotArea: shotArea ?? (areas.length == 1 ? areas.single.key : 'shell'),
    );

    // Checks run first (tear-downs run last-registered first), then the
    // container goes.
    addTearDown(container.dispose);
    addTearDown(h._verify);

    size.apply(tester);
    ensureTimeZones();
    // The kept session is restored before the first frame, as the app's
    // boot does.
    await tester.runAsync(() => container.read(sessionProvider.future));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: DashApp(
          localizationsDelegates: dashTestLocalizationsDelegates,
          reducedMotion: reducedMotion,
        ),
      ),
    );
    await h.settle();
    return h;
  }

  void _verify() {
    final problems = <String>[];
    if (!allowUnmatched && server.unmatched.isNotEmpty) {
      problems.add(
        'calls no mock answered:\n  ${server.unmatched.map((c) => '${c.method} ${c.path}').join('\n  ')}',
      );
    }
    if (server.handlerErrors.isNotEmpty) {
      problems.add(
        'mock handlers crashed:\n  ${server.handlerErrors.join('\n  ')}',
      );
    }
    if (!allowMissingKeys) {
      final log = strings.log;
      if (log.missing.isNotEmpty) {
        problems.add(
          'words missing from the tables: ${log.missing.join(', ')}',
        );
      }
      if (log.englishFallbacks.isNotEmpty) {
        problems.add(
          'English shown in another language: ${log.englishFallbacks.join(', ')}',
        );
      }
    }
    if (problems.isNotEmpty) {
      fail('DashHarness: ${problems.join('\n')}');
    }
  }

  /// Lets the mock's answers land and the frames settle (bounded: a
  /// repeating animation never stops it).
  Future<void> settle({
    int rounds = 8,
    Duration step = const Duration(milliseconds: 50),
  }) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        for (var j = 0; j < 5; j++) {
          await Future<void>.delayed(Duration.zero);
        }
      });
      await tester.pump(step);
    }
  }

  /// Navigates to [location] and settles.
  Future<void> go(String location) async {
    router.go(location);
    await settle();
  }

  /// Taps [finder] (the first match) and settles.
  Future<void> tap(Finder finder) async {
    await tester.ensureVisible(finder.first);
    await tester.pump();
    await tester.tap(finder.first);
    await settle();
  }

  /// Taps the [index]th widget showing [text].
  Future<void> tapText(String text, {int index = 0}) =>
      tap(find.text(text).at(index));

  /// Taps the widget with [key].
  Future<void> tapKey(Key key) => tap(find.byKey(key));

  /// Taps the control a screen reader calls [label].
  Future<void> tapLabel(String label) => tap(find.bySemanticsLabel(label));

  /// Types [text] into the field [finder] finds (an `EditableText` inside it).
  Future<void> enterText(Finder finder, String text) async {
    final field = find.descendant(
      of: finder,
      matching: find.byType(EditableText),
      matchRoot: true,
    );
    await tester.enterText(field.first, text);
    await settle(rounds: 3);
  }

  /// Scrolls [scrollable] (the first one by default) until [finder] shows.
  Future<void> scrollUntilVisible(
    Finder finder, {
    double delta = 300,
    Finder? scrollable,
  }) async {
    await tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: scrollable ?? find.byType(Scrollable).first,
    );
    await settle(rounds: 2);
  }

  /// Expects a toast saying [text]; then lets it expire (so no timer is
  /// left running) unless [keep].
  Future<void> expectToast(String text, {bool keep = false}) async {
    expect(find.text(text), findsWidgets, reason: 'toast "$text"');
    if (!keep) await flushTimers();
  }

  /// Runs every pending timer out (toasts, debounces).
  Future<void> flushTimers() async {
    await tester.pump(DashToast.duration + const Duration(seconds: 1));
    await settle(rounds: 2);
  }

  /// Writes `<FDASH_SHOTS>/<area>/<page>/<name>--<size>-<lang>-<theme>.png`
  /// when FDASH_SHOTS is set. [name] may carry its page (`orders/void`);
  /// without one, the page is the current path.
  Future<void> shot(String name) async {
    final dir = dashShotsDir;
    if (dir == null) return;
    final parts = name.split('/');
    final file = parts.removeLast();
    final page = parts.isNotEmpty
        ? parts.join('/')
        : (location.path == '/'
              ? 'home'
              : location.path.substring(1).replaceAll('/', '-'));
    await _precacheImages();
    debugDisableShadows = false;
    _repaintAll();
    await tester.pump();
    try {
      await captureShot(
        tester,
        '$dir/$shotArea/$page/$file--${size.name}-$locale-${dark ? 'dark' : 'light'}.png',
      );
    } finally {
      debugDisableShadows = true;
      _repaintAll();
      await tester.pump();
    }
  }

  Future<void> _precacheImages() async {
    final elements = find.byType(Image).evaluate().toList();
    if (elements.isEmpty) return;
    await tester.runAsync(() async {
      for (final e in elements) {
        final image = (e.widget as Image).image;
        try {
          await precacheImage(
            image,
            e,
            onError: (_, _) {},
          ).timeout(const Duration(seconds: 5));
        } on Object {
          // A network image in a test never loads; its fallback shows.
        }
      }
    });
    await tester.pump();
  }

  void _repaintAll() {
    void visit(RenderObject o) {
      o.markNeedsPaint();
      o.visitChildren(visit);
    }

    for (final v in tester.binding.renderViews) {
      visit(v);
    }
  }
}
