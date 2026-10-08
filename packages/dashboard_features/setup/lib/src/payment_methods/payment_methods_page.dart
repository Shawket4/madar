/// `/settings/payment-methods` Payment methods (`features/payment-methods/payment-methods-page.tsx`, SET-PAY rows).
///
/// Rendered inside the settings shell (`routes.dart`), so its
/// [DashPageScaffold] draws as a pane: a section heading, no page gutter.
/// Placeholder body until the unit's page lands.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PaymentMethodsPage extends ConsumerWidget {
  const PaymentMethodsPage({this.edit, super.key});

  /// `?edit=<id>|new` (SET-SHL-012, SET-PAY-012): the editor to open.
  final String? edit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('settings.paymentMethods'),
      subtitle: t('settings.paymentMethodsHint'),
      width: DashPageWidth.reading,
      body: DashEmptyState(
        icon: 'layers',
        title: t('shell.pendingTitle'),
        description: t('shell.pendingBody'),
      ),
    );
  }
}
