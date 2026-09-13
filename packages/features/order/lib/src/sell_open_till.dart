// The no-till banner's way on: "Open till" from Sell, without leaving Sell.
//
// A teller who rings up a sale before opening the drawer used to be told
// "Open a till to settle" and left to find the Till tab. This pushes the same
// opening form the Till embeds, and comes back to the cart — untouched — the
// moment the core says the till is open.
import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:feature_order/src/order_providers.dart';
import 'package:feature_order/src/words.dart';
import 'package:feature_till/feature_till.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Push the opening form over Sell; the cart re-reads the till on return.
Future<void> openTillFromSell(BuildContext context, WidgetRef ref) async {
  final notifier = ref.read(orderProvider.notifier);
  await MadarPages.push<void>(context, (_) => const _OpenTillPage());
  await notifier.reconcileTill();
}

class _OpenTillPage extends ConsumerWidget {
  const _OpenTillPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    // The core moves the route off OpenTill once the drawer is open: that is
    // the answer, and the page's job is done.
    ref.listen(shellProvider.select((s) => s.route), (prev, next) {
      if (next is! AppRoute_OpenTill && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    return MadarPageScaffold(
      width: MadarContentWidth.form,
      title: orderWord(bridge, 'sell.open_shift'),
      bodyInset: false,
      body: const OpenTillScreen(embedded: true),
    );
  }
}
