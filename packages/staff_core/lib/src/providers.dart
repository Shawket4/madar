import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:staff_core/src/data.dart';
import 'package:staff_core/src/format.dart';

/// The core behind the store — the staff bridge on a device, a fake in tests.
/// The app overrides it at boot.
final dawamBackendProvider = Provider<DawamBackend>(
  (_) => throw UnimplementedError('override dawamBackendProvider at boot'),
);

/// Dawam's picture — the staff-app counterpart of `app_core`'s `coreProvider`.
final dawamProvider = ChangeNotifierProvider<DawamStore>((ref) {
  final store = DawamStore(ref.watch(dawamBackendProvider));
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

  VoidCallback? _action;

  void show(
    String text, {
    ChipTone tone = ChipTone.accent,
    String? actionLabel,
    VoidCallback? onAction,
    String? icon,
  }) {
    _action = onAction;
    state = ToastData(
      id: DateTime.now().microsecondsSinceEpoch,
      text: text,
      tone: tone,
      actionLabel: onAction == null ? null : actionLabel,
      icon:
          icon ??
          (tone == ChipTone.danger ? 'exclamationmark.triangle' : 'checkmark'),
    );
    _timer?.cancel();
    // A toast with an action stays long enough to reach for it.
    _timer = Timer(
      Duration(milliseconds: onAction == null ? 2600 : 6000),
      dismiss,
    );
  }

  /// The toast's action was tapped: run it once, then close.
  void act() {
    final a = _action;
    dismiss();
    a?.call();
  }

  void dismiss() {
    _timer?.cancel();
    _action = null;
    state = null;
  }
}

final toastProvider = NotifierProvider<ToastNotifier, ToastData?>(
  ToastNotifier.new,
);
