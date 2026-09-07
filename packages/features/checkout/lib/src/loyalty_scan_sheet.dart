import 'package:feature_checkout/src/checkout_provider.dart';
import 'package:feature_checkout/src/loyalty_scan_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Identify the member whose balance is about to be spent, at tender time.
///
/// Redeeming changes what is owed, so it happens here, before payment — and it
/// requires a connection. A balance is shared state any till can spend, and a
/// reward gives away goods: two disconnected tills could each honour the last
/// one and neither could be undone, because the coffee is gone. The core
/// enforces that; this sheet just relays what it says.
///
/// (Earning is the opposite and works offline — see `LoyaltyAwardSheet`, the
/// button on the receipt and on a past order for 24 hours.)
class LoyaltyScanSheet extends ConsumerWidget {
  const LoyaltyScanSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(checkoutProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Scan the customer’s card',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          LoyaltyScanCapture(
            busy: state.loyaltyBusy,
            error: state.loyaltyError,
            onCaptured: ({token, phone}) async {
              final ok = await ref
                  .read(checkoutProvider.notifier)
                  .scanLoyalty(token: token, phone: phone);
              if (ok && context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}
