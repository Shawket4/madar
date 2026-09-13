// The no-shift banner's way on: "Open shift" from Sell, without leaving Sell.
//
// A teller who rings up a sale before opening the drawer used to be told
// "Open a shift to settle" and left to find the Till tab. This pushes the same
// opening form the Till embeds, and comes back to the cart — untouched — the
// moment the core says the shift is open.
import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/words.dart';
import 'package:feature_shift/feature_shift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Push the opening form over Sell; the cart re-reads the shift on return.
Future<void> openShiftFromSell(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(orderProvider.notifier);
  await MadarPages.push<void>(context, (_) => const _OpenShiftPage());
  await notifier.reconcileShift();
}

class _OpenShiftPage extends ConsumerWidget {
  const _OpenShiftPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    // The core moves the route off OpenShift once the drawer is open: that is
    // the answer, and the page's job is done.
    ref.listen(shellProvider.select((s) => s.route), (prev, next) {
      if (next is! AppRoute_OpenShift && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    return MadarPageScaffold(
      width: MadarContentWidth.form,
      title: orderWord(bridge, 'sell.open_shift'),
      bodyInset: false,
      body: const OpenShiftScreen(embedded: true),
    );
  }
}
