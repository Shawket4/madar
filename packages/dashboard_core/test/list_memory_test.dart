// DashListMemory's rules, without a screen: org and branch scoping, the
// memo's readers, a stale choice, a detail page's way back, and the URL
// filters' redirect.
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/shell.dart' show rememberedQueryRedirect;
import 'package:flutter_test/flutter_test.dart';

enum _Tab { items, addons }

void main() {
  var scope = (org: 'org-a' as String?, branch: 'b1' as String?);
  DashListMemory memory() => DashListMemory(() => scope);

  setUp(() => scope = (org: 'org-a', branch: 'b1'));

  group('DashListMemory', () {
    test('remembers per list; another org forgets everything', () {
      final m = memory()..remember('menu.items', {'category': 'c1'});
      expect(m.recall('menu.items').string('category'), 'c1');
      expect(m.recall('orders').isEmpty, isTrue);
      scope = (org: 'org-b', branch: null);
      expect(m.recall('menu.items').isEmpty, isTrue);
      scope = (org: 'org-a', branch: 'b1');
      expect(m.recall('menu.items').isEmpty, isTrue, reason: 'not kept');
    });

    test('signing out (no org) forgets everything', () {
      final m = memory()..remember('x', {'a': 'b'});
      scope = (org: null, branch: null);
      expect(m.recall('x').isEmpty, isTrue);
    });

    test('sameBranch says whether the branch is the one picked in', () {
      final m = memory()..remember('tills', {'teller': 't1'});
      expect(m.recall('tills').sameBranch, isTrue);
      scope = (org: 'org-a', branch: 'b2');
      expect(m.recall('tills').sameBranch, isFalse);
      expect(m.recall('tills').string('teller'), 't1');
    });

    test('a page bucket per path, fresh for another org', () {
      final m = memory();
      final a = m.bucketFor('/orders');
      expect(m.bucketFor('/orders'), same(a));
      expect(m.bucketFor('/tills'), isNot(same(a)));
      scope = (org: 'org-b', branch: null);
      expect(m.bucketFor('/orders'), isNot(same(a)));
    });

    test('a detail goes back where it was opened from; never a loop', () {
      final m = memory()
        ..openedFrom('/menu/items/1', Uri.parse('/menu/items?x=1'));
      expect(m.backTarget('/menu/items/1', '/menu/items'), '/menu/items?x=1');
      // Item 1 → its linked item 2 → back from 2 goes where 1 would.
      m.openedFrom('/menu/items/2', Uri.parse('/menu/items/1'));
      expect(m.backTarget('/menu/items/2', '/menu/items'), '/menu/items?x=1');
      m.openedFrom('/menu/items/1', Uri.parse('/menu/items/2'));
      expect(m.backTarget('/menu/items/1', '/menu/items'), '/menu/items?x=1');
      expect(m.backTarget('/menu/combos/9', '/menu/combos'), '/menu/combos');
    });
  });

  group('DashMemo', () {
    test('typed readers fall back on anything unexpected', () {
      const memo = DashMemo({
        'tab': 'addons',
        'bad': 'nope',
        'page': 3,
        'empty': '',
        'set': ['a', 'b', 3],
      });
      expect(memo.enumOr('tab', _Tab.values, _Tab.items), _Tab.addons);
      expect(memo.enumOr('bad', _Tab.values, _Tab.items), _Tab.items);
      expect(memo.enumOrNull('missing', _Tab.values), isNull);
      expect(memo.getOr('page', 0), 3);
      expect(memo.getOr('tab', 0), 0, reason: 'a string is not an int');
      expect(memo.string('empty'), isNull);
      expect(memo.setOf<String>('set'), {'a', 'b'});
      expect(DashMemo.empty.isEmpty, isTrue);
    });

    test('dashStale: only a set value its loaded options lack', () {
      expect(dashStale<String>(null, ['a']), isFalse);
      expect(dashStale('a', null), isFalse, reason: 'options not loaded');
      expect(dashStale('a', ['a', 'b']), isFalse);
      expect(dashStale('z', ['a', 'b']), isTrue);
    });
  });

  group('rememberedQueryRedirect', () {
    const route = DashRoute(
      path: '/tills',
      rememberQuery: ['status', 'teller'],
      branchQuery: ['teller'],
    );
    String? go(DashListMemory m, String to, {String? from}) =>
        rememberedQueryRedirect(
          memory: m,
          route: route,
          uri: Uri.parse(to),
          from: from == null ? null : Uri.parse(from),
        );

    test('restores on entry, keeps the other params, only its keys', () {
      final m = memory();
      expect(go(m, '/tills?status=open&teller=t1&report=r9'), isNull);
      final back = Uri.parse(go(m, '/tills?report=r1', from: '/orders')!);
      expect(back.queryParameters, {
        'report': 'r1',
        'status': 'open',
        'teller': 't1',
      });
    });

    test('on the page, a cleared filter is remembered as cleared', () {
      final m = memory();
      go(m, '/tills?status=open', from: '/orders');
      expect(go(m, '/tills', from: '/tills?status=open'), isNull);
      expect(go(m, '/tills', from: '/orders'), isNull);
    });

    test('another branch: branch-bound keys not restored, and stripped '
        'from the page', () {
      final m = memory();
      go(m, '/tills?status=open&teller=t1', from: '/orders');
      scope = (org: 'org-a', branch: 'b2');
      expect(
        go(m, '/tills?status=open&teller=t1', from: '/tills'),
        '/tills?status=open',
      );
      expect(go(m, '/tills?status=open', from: '/tills'), isNull);
      go(m, '/tills?status=open&teller=t1', from: '/orders');
      scope = (org: 'org-a', branch: 'b3');
      expect(go(m, '/tills', from: '/orders'), '/tills?status=open');
    });

    test('a route without remembered keys is left alone', () {
      expect(
        rememberedQueryRedirect(
          memory: memory(),
          route: const DashRoute(path: '/x'),
          uri: Uri.parse('/x?a=1'),
        ),
        isNull,
      );
    });
  });
}
