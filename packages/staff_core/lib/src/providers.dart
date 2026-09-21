import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:staff_core/src/data.dart';
import 'package:staff_core/src/format.dart';

/// Dawam's core — the staff-app counterpart of `app_core`'s `coreProvider`.
/// Today the in-memory store; the staff bridge's calls land behind it.
final dawamProvider = ChangeNotifierProvider<DawamStore>((ref) {
  final store = DawamStore();
  ref.onDispose(store.stop);
  return store;
});

/// Host hooks the APP overrides at boot (the core's `setLocale`, the prefs
/// store). No-ops so tests run bare — the `app_core` pattern.
final localePersisterProvider = Provider<void Function(String)>((_) => (_) {});
final themeChoicePersisterProvider = Provider<void Function(ThemeChoice)>(
  (_) => (_) {},
);

/// The UI language. Writes through to the core (via the host hook), which
/// then answers `tr` in it.
class LocaleNotifier extends Notifier<String> {
  LocaleNotifier({this.initial = 'ar'});

  /// The persisted value the app boots with. Arabic first (APP-4).
  final String initial;

  @override
  String build() => currentLang = initial;

  void set(String locale) {
    currentLang = locale;
    ref.read(localePersisterProvider)(locale);
    state = locale;
  }
}

final localeProvider = NotifierProvider<LocaleNotifier, String>(
  LocaleNotifier.new,
);

/// Light · dark · system — the POS's choice, persisted the same way.
class ThemeChoiceNotifier extends Notifier<ThemeChoice> {
  ThemeChoiceNotifier({this.initial = ThemeChoice.light});

  final ThemeChoice initial;

  @override
  ThemeChoice build() => initial;

  void set(ThemeChoice choice) {
    state = choice;
    ref.read(themeChoicePersisterProvider)(choice);
  }
}

final themeChoiceProvider = NotifierProvider<ThemeChoiceNotifier, ThemeChoice>(
  ThemeChoiceNotifier.new,
);

/// The one transient toast, drawn by the app over everything (the POS's
/// chrome toast): 2.6 s, the natives' lifetime.
class ToastNotifier extends Notifier<ToastData?> {
  Timer? _timer;

  @override
  ToastData? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  void show(String text, {ChipTone tone = ChipTone.accent}) {
    state = ToastData(
      id: DateTime.now().microsecondsSinceEpoch,
      text: text,
      tone: tone,
      icon: tone == ChipTone.danger ? 'exclamationmark.triangle' : 'checkmark',
    );
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 2600), dismiss);
  }

  void dismiss() {
    _timer?.cancel();
    state = null;
  }
}

final toastProvider = NotifierProvider<ToastNotifier, ToastData?>(
  ToastNotifier.new,
);
