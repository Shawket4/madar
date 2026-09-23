// APP-6 on the till: the token goes to the server once per (token, language),
// a push with the app open draws the shell's banner, and sign-out hands the
// token back. Firebase itself is not reachable in a test host, so this drives
// PosPush's own logic directly — what it sends, when, and how it words a
// notification the server wrote.

import 'package:flutter_test/flutter_test.dart';
import 'package:madar/app/push.dart';
import 'package:rust_bridge/rust_bridge.dart';

class _Bridge implements MadarBridge {
  final List<String> calls = [];
  bool offline = false;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final a = invocation.namedArguments;
    switch (invocation.memberName) {
      case #setPushToken:
        if (offline) {
          return Future<void>.error(
            const MadarError.offline(detail: 'no network'),
          );
        }
        calls.add('set:${a[#token]}|${a[#locale]}|${a[#platform]}');
        return Future<void>.value();
      case #clearPushToken:
        calls.add('clear:${a[#token]}');
        return Future<void>.value();
      default:
        return null;
    }
  }
}

/// PosPush with a token already in hand (Firebase is what normally sets it).
PosPush _push(_Bridge bridge, {List<String>? posted, String locale = 'ar'}) {
  return PosPush(
    bridge: bridge,
    locale: locale,
    post: ({required title, required body, required tag}) async =>
        posted?.add('$title|$body|$tag'),
    openQueue: () {},
  )..debugSetToken('fcm-1');
}

void main() {
  test('the token goes up once per token and language', () async {
    final bridge = _Bridge();
    final push = _push(bridge);

    await push.register();
    await push.register(); // nothing new to say
    expect(bridge.calls, ['set:fcm-1|ar|android']);

    push.language('en');
    await Future<void>.delayed(Duration.zero);
    expect(bridge.calls.last, 'set:fcm-1|en|android');
  });

  test('a failed register is retried, not remembered as done', () async {
    final bridge = _Bridge()..offline = true;
    final push = _push(bridge);

    await push.register();
    expect(bridge.calls, isEmpty);

    bridge.offline = false;
    await push.register();
    expect(bridge.calls, ['set:fcm-1|ar|android']);
  });

  test('signing out hands the token back', () async {
    final bridge = _Bridge();
    final push = _push(bridge);
    await push.register();

    await push.forget();
    expect(bridge.calls.last, 'clear:fcm-1');

    // …and the next sign-in registers again rather than skipping.
    await push.register();
    expect(bridge.calls.last, 'set:fcm-1|ar|android');
  });

  test('a push with the app open is drawn with the server words', () async {
    final posted = <String>[];
    final push = _push(_Bridge(), posted: posted);

    await push.debugShow(
      title: 'Online order #12',
      body: '3 items - 240 EGP',
      data: {'order_id': 'o-9'},
    );
    expect(posted, ['Online order #12|3 items - 240 EGP|o-9']);

    // Nothing to say: nothing drawn.
    await push.debugShow(title: '', body: '', data: const {});
    expect(posted, hasLength(1));
  });
}
