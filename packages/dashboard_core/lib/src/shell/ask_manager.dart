/// "Ask a manager", as the web has it. There is no app-wide dialog on the
/// web (the manager's PIN step happens on the POS): a page offers an act the
/// person does not hold when the owner lets them ask (`authz.canAsk`), the
/// server queues it for approval, and the page says so. Pages call this
/// service so every area decides and words it the same way; the owner's
/// "Hidden / Ask a manager" policy itself is the Roles page's.
library;

import 'package:dashboard_core/src/authz/authz.dart';
import 'package:dashboard_core/src/authz/authz_providers.dart';
import 'package:dashboard_core/src/i18n/i18n_providers.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the person may do about an act that needs [Authz] capabilities.
class AskManager {
  const AskManager(this.authz);

  final Authz authz;

  /// The act is offered at all: held, or askable (`can || canAsk`).
  bool offers(String cap) => authz.can(cap) || authz.canAsk(cap);

  /// Only by asking: not held, but the owner lets this person ask.
  bool onlyByAsking(String cap) => authz.canAsk(cap);

  /// Whether the act waits for approval when done now: not held (asked), or
  /// [amount] (minor units) above the person's limit (`limits.max_amount`).
  /// The server's own answer, when it sends one, wins over this.
  bool waits(String cap, {num? amount}) {
    if (!authz.can(cap)) return true;
    final max = authz.limitsOf(cap)?.maxAmount;
    return amount != null && max != null && amount > max;
  }
}

final askManagerProvider = Provider<AskManager>(
  (ref) => AskManager(ref.watch(authzProvider)),
);

/// Tells the person their act waits for the owner (the web's info toast).
/// [message] is the page's own sentence when it has one; the default is the
/// web's pay-line wording.
void showAwaitingApproval(BuildContext context, {String? message}) {
  final t = context.translator;
  DashToast.info(
    context,
    message ??
        t(
          'dawam.payLinePending',
          defaultValue:
              'Over your limit: it waits for the owner before it counts.',
        ),
  );
}
