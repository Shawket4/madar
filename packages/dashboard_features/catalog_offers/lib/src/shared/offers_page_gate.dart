/// A page-level `<Restricted>` for the pages whose refusal the shell's route
/// gate cannot word: the combos list (an account-specific body,
/// `combos.noAccess`) and the combo editor (titled "New combo" on `new`).
/// Their routes carry no capabilities; the page wraps its body in this.
///
/// As the shell's gate (divergence SH-10), but the page's own skeleton (not a
/// blank) while the person's rights load, and nothing asked (OFFR-ALL-018);
/// an error with Retry if they fail to load, then the page for whoever holds
/// any of [caps], else [Restricted].
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class OffersPageGate extends ConsumerWidget {
  const OffersPageGate({
    required this.title,
    required this.caps,
    required this.loading,
    required this.child,
    this.who,
    super.key,
  });

  /// The Restricted page's title.
  final String title;

  /// Any of these opens the page.
  final List<String> caps;

  /// The Restricted body, when not the default.
  final String? who;

  /// The page's skeleton while the rights load.
  final Widget loading;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = ref.watch(authzProvider);
    if (!a.ready) {
      return a.error == null ? loading : const AuthzLoadError();
    }
    return a.canAny(caps) ? child : Restricted(title: title, who: who);
  }
}
