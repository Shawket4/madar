/// Riverpod wiring for the UI text: the tables, the language, `t()`.
library;

import 'dart:ui' show PlatformDispatcher;

import 'package:dashboard_core/src/gateways/preferences.dart';
import 'package:dashboard_core/src/i18n/loader.dart';
import 'package:dashboard_core/src/i18n/strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The loaded tables. The app (and the test harness) overrides this with the
/// result of `loadStrings()`.
final stringsProvider = Provider<Strings>(
  (ref) => throw StateError(
    'stringsProvider must be overridden with loadStrings() at boot',
  ),
);

/// The preference key the web stores the language under (`madar.lang`).
const String languagePrefKey = 'madar.lang';

/// The language to start in when none was chosen yet: the device's first
/// language the dashboard supports, regions stripped (the web's
/// `navigatorLanguageOnly` detector), else English.
final initialLocaleProvider = Provider<String>((ref) {
  for (final l in PlatformDispatcher.instance.locales) {
    final code = l.languageCode.toLowerCase();
    if (supportedLanguages.contains(code)) return code;
  }
  return 'en';
});

/// Told about every language change, so real mode can word the core's
/// refusals in the same language. The app overrides it; the default does
/// nothing.
final localeSinkProvider = Provider<void Function(String lang)>(
  (ref) => (_) {},
);

/// The active language: exactly `en` or `ar`.
class LocaleNotifier extends Notifier<String> {
  @override
  String build() {
    final stored = ref.watch(preferencesProvider).getString(languagePrefKey);
    final String initial = ref.watch(initialLocaleProvider);
    return _asLanguage(stored) ?? initial;
  }

  static String? _asLanguage(String? l) {
    if (l == null) return null;
    final base = l.split(RegExp('[-_]')).first.toLowerCase();
    return supportedLanguages.contains(base) ? base : null;
  }

  /// Switches the language and remembers it on this device.
  Future<void> set(String lang) async {
    final next = _asLanguage(lang) ?? 'en';
    state = next;
    ref.read(localeSinkProvider)(next);
    await ref.read(preferencesProvider).setString(languagePrefKey, next);
  }

  /// English <-> Arabic.
  Future<void> toggle() => set(state == 'ar' ? 'en' : 'ar');
}

final localeProvider = NotifierProvider<LocaleNotifier, String>(
  LocaleNotifier.new,
);

/// Whether the active language reads right to left.
final isRtlProvider = Provider<bool>(
  (ref) => ref.watch(localeProvider) == 'ar',
);

/// `t()` bound to the active language.
class Translator {
  const Translator(this.strings, this.lang);

  final Strings strings;
  final String lang;

  bool get isRtl => lang == 'ar';

  TextDirection get textDirection =>
      isRtl ? TextDirection.rtl : TextDirection.ltr;

  String call(
    String key, {
    Map<String, Object?>? args,
    num? count,
    String? defaultValue,
    Map<String, String>? defaultValues,
  }) => strings.translate(
    lang,
    key,
    args: args,
    count: count,
    defaultValue: defaultValue,
    defaultValues: defaultValues,
  );

  /// An array value (`returnObjects: true`).
  List<String> list(String key) => strings.list(lang, key);

  /// Whether [key] has text without a default.
  bool exists(String key, {num? count}) =>
      strings.exists(lang, key, count: count);

  @override
  bool operator ==(Object other) =>
      other is Translator &&
      identical(other.strings, strings) &&
      other.lang == lang;

  @override
  int get hashCode => Object.hash(identityHashCode(strings), lang);
}

final tProvider = Provider<Translator>(
  (ref) => Translator(ref.watch(stringsProvider), ref.watch(localeProvider)),
);

/// Puts the active [Translator] in the widget tree so `context.t()` follows
/// language changes. The shell mounts it once, under the `ProviderScope`.
class DashI18nScope extends ConsumerWidget {
  const DashI18nScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      DashI18n(translator: ref.watch(tProvider), child: child);
}

/// The inherited [Translator] (see [DashI18nScope]).
class DashI18n extends InheritedWidget {
  const DashI18n({required this.translator, required super.child, super.key});

  final Translator translator;

  static Translator? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DashI18n>()?.translator;

  @override
  bool updateShouldNotify(DashI18n oldWidget) =>
      oldWidget.translator != translator;
}

/// `context.t('orders.voidTitle')`.
extension DashTContext on BuildContext {
  /// The active translator: the nearest [DashI18n], else read from the
  /// provider scope (which does not rebuild on a language change, so mount
  /// [DashI18nScope]).
  Translator get translator =>
      DashI18n.maybeOf(this) ??
      ProviderScope.containerOf(this, listen: false).read(tProvider);

  String t(
    String key, {
    Map<String, Object?>? args,
    num? count,
    String? defaultValue,
    Map<String, String>? defaultValues,
  }) => translator(
    key,
    args: args,
    count: count,
    defaultValue: defaultValue,
    defaultValues: defaultValues,
  );
}

/// `ref.t('orders.voidTitle')` inside a build (it watches the language).
extension DashTRef on WidgetRef {
  String t(
    String key, {
    Map<String, Object?>? args,
    num? count,
    String? defaultValue,
    Map<String, String>? defaultValues,
  }) => watch(tProvider)(
    key,
    args: args,
    count: count,
    defaultValue: defaultValue,
    defaultValues: defaultValues,
  );
}
