// Switching language has to reach the screens ALREADY on stage, not just the
// one in front of you.
//
// `bridge.tr(key:)` is an imperative call: a screen pulls its strings once at
// build time and then sits there. Nothing about a language change invalidated
// those screens, so a teller switching to Arabic from Settings got an Arabic
// settings sheet over a stack of English ones — which reads as missing
// translations and was reported as exactly that.
import 'package:app_core/app_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// A bridge whose `tr` answers in whatever language it was last set to, so a
/// test can see the switch land without a Rust core behind it.
class _FakeBridge implements MadarBridge {
  String _locale = 'en';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName;
    if (name == #tr) {
      final key = invocation.namedArguments[#key] as String? ?? '';
      return _locale == 'ar' ? 'AR:$key' : 'EN:$key';
    }
    if (name == #setLocale) {
      _locale = invocation.namedArguments[#locale] as String? ?? 'en';
      return null;
    }
    if (name == #locale) return _locale;
    if (name == #isRtl) return _locale == 'ar';
    return null;
  }
}

/// The core, faked far enough to hand back a bridge. The test overrides
/// THIS and not `bridgeProvider`, on purpose: `overrideWithValue` pins a
/// provider to a constant, which would quietly delete the very rebuild this
/// test exists to prove.
class _FakeCore implements MadarCore {
  _FakeCore(this._bridge);

  final MadarBridge _bridge;

  @override
  MadarBridge get bridge => _bridge;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A screen of the shape every screen in this app has: read the bridge, pull
/// a string, render it.
class _Screen extends ConsumerWidget {
  const _Screen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    return Text(
      bridge.tr(key: 'order.title'),
      textDirection: TextDirection.ltr,
    );
  }
}

void main() {
  testWidgets('a language switch re-renders a screen that never watched it', (
    tester,
  ) async {
    final fake = _FakeBridge();
    final container = ProviderContainer(
      overrides: [coreProvider.overrideWithValue(_FakeCore(fake))],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const _Screen()),
    );
    expect(find.text('EN:order.title'), findsOneWidget);

    // The switch happens somewhere else entirely — a settings sheet over the
    // top — and this screen never watched the locale.
    container.read(localeProvider.notifier).set('ar');
    await tester.pump();

    expect(
      find.text('AR:order.title'),
      findsOneWidget,
      reason: 'the screen behind the language picker must switch too',
    );
  });

  test('the generation moves on every set, including a re-pick', () {
    final container = ProviderContainer(
      overrides: [coreProvider.overrideWithValue(_FakeCore(_FakeBridge()))],
    );
    addTearDown(container.dispose);

    final before = container.read(localeGenerationProvider);
    container.read(localeProvider.notifier).set('ar');
    final after = container.read(localeGenerationProvider);
    expect(after, greaterThan(before));

    // Re-picking the language already in force still counts: the core may
    // have re-keyed its catalogue underneath even when the tag has not moved.
    container.read(localeProvider.notifier).set('ar');
    expect(container.read(localeGenerationProvider), greaterThan(after));
  });
}
