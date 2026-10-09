// Working with no network, through the real shell and the home page: what
// was read is saved and shown again offline (after a relaunch too) under the
// banner; back online the banner goes and the page reads again; signing out
// wipes it all.
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_overview/dashboard_overview.dart';
import 'package:flutter_test/flutter_test.dart';

const _welcome = 'Welcome back, Nour El-Sayed';
const _sales = '/reports/branches/{branchId}/sales';

final Finder _banner = find.textContaining("You're offline. Showing data");

({MockServer server, MockDb db}) _seeded() {
  final db = MockDb.seeded();
  final server = MockServer(persona: Persona.owner, clock: db.clock);
  registerCoreMocks(server, db);
  registerOverviewMocks(server, db);
  return (server: server, db: db);
}

void main() {
  late ({MockServer server, MockDb db}) s;
  late MemoryBlobs blobs;
  late OfflineStore store;

  setUp(() async {
    s = _seeded();
    blobs = MemoryBlobs();
    store = await OfflineStore.open(blobs);
  });

  Future<DashHarness> launch(WidgetTester tester, {String locale = 'en'}) =>
      DashHarness.pump(
        tester,
        areas: const [overviewArea],
        server: s.server,
        db: s.db,
        locale: locale,
        offlineStore: store,
      );

  testWidgets('offline after online: saved answers under the banner; back '
      'online it goes and the page reads again', (tester) async {
    final h = await launch(tester);
    expect(find.text(_welcome), findsOneWidget);
    expect(_banner, findsNothing);
    expect(store.owner, SeedIds.owner);
    expect(store.keysWithPrefix('').length, greaterThan(5));

    s.server.offline = true;
    final cache = h.container.read(queryCacheProvider);
    final refresh = cache.refetchActive();
    await h.settle();
    await refresh;
    expect(_banner, findsOneWidget);
    expect(find.text(_welcome), findsOneWidget);
    expect(find.text('Retry'), findsNothing);

    // The network is back; the next answer from the server clears the
    // banner and reads again what was built on saved data.
    s.server.offline = false;
    final before = s.server.callsTo(_sales).length;
    h.container.invalidate(branchesProvider);
    await h.settle();
    expect(_banner, findsNothing);
    expect(s.server.callsTo(_sales).length, greaterThan(before));
  });

  for (final locale in ['en', 'ar']) {
    testWidgets('cold start offline ($locale): the kept session, the shell '
        'and the page from disk, with the banner', (tester) async {
      final first = await launch(tester, locale: locale);
      // The saves still queued land before the relaunch.
      await first.settle();
      s.server.offline = true;
      // Relaunched: the store opens again from what is on "disk".
      store = (await tester.runAsync(() => OfflineStore.open(blobs)))!;
      expect(store.owner, SeedIds.owner);
      final h = await launch(tester, locale: locale);
      expect(h.location.path, '/');
      expect(
        find.textContaining(
          locale == 'en'
              ? "You're offline. Showing data saved at"
              : 'أنت غير متصل بالإنترنت. تُعرض بيانات محفوظة في',
        ),
        findsOneWidget,
      );
      if (locale == 'en') expect(find.text(_welcome), findsOneWidget);
      expect(find.text(locale == 'en' ? 'Retry' : 'إعادة المحاولة'), findsNothing);
    });
  }

  testWidgets('a first sign-in needs the network', (tester) async {
    s.server.offline = true;
    final h = await DashHarness.pump(
      tester,
      areas: const [overviewArea],
      server: s.server,
      db: s.db,
      persona: null,
      offlineStore: store,
    );
    expect(h.location.path, '/login');
    expect(store.keysWithPrefix(''), isEmpty);
  });

  testWidgets('signing out wipes every saved answer', (tester) async {
    final h = await launch(tester);
    expect(store.keysWithPrefix(''), isNotEmpty);
    await h.container.read(sessionProvider.notifier).signOut();
    await h.settle();
    expect(store.keysWithPrefix(''), isEmpty);
    expect(store.owner, isNull);
  });
}
