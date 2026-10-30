/// Fills dashboard_kit's words and formats from the live i18n.
library;

import 'package:dashboard_core/src/authz/gates.dart' show errorMessage;
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_core/src/scope/scope.dart'
    show activeTimezoneProvider;
import 'package:dashboard_core/src/session/session.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The kit's phrases over [t] (plurals through an `args['count']`).
DashKitStrings dashKitStringsFrom(Translator t) =>
    DashKitStrings.fromLookup((key, [args]) {
      final count = args?['count'];
      return t(key, args: args, count: count is num ? count : null);
    });

/// One [DashKitStrings] per translator, so the kit's inherited widget only
/// notifies on a real language change.
final dashKitStringsProvider = Provider<DashKitStrings>(
  (ref) => dashKitStringsFrom(ref.watch(tProvider)),
);

/// The kit's formats: the language, the org currency, and the scope's zone
/// and the app's clock, so a calendar's "today" is the branch's.
final dashKitFormatsProvider = Provider<DashKitFormats>(
  (ref) => DashKitFormats(
    languageCode: ref.watch(localeProvider),
    currency: ref.watch(
      currentSessionProvider.select((s) => s?.currencyCode ?? 'EGP'),
    ),
    timezone: ref.watch(activeTimezoneProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// Puts the kit's localizations above [child], from the live i18n. The shell
/// mounts it once, beside [DashI18nScope].
class DashKitScope extends ConsumerWidget {
  const DashKitScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashKitLocalizations(
      strings: ref.watch(dashKitStringsProvider),
      formats: ref.watch(dashKitFormatsProvider),
      describeError: (e) => errorMessage(e, t),
      child: child,
    );
  }
}
