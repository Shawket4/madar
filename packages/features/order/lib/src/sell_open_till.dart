// The no-till banner's way on: "Open till" from Sell, without leaving Sell.
//
// A teller who rings up a sale before opening the drawer used to be told
// "Open a till to settle" and left to find the Till tab. This pushes the same
// opening form the Till embeds, and comes back to the cart — untouched — the
// moment the core says the till is open.
//
// Never over an open till (owner report 2026-09-25): `openTillPage` refuses
// the push when the shell — the one owner of the till — says one is open, and
// the page takes itself away the moment one opens. The cart reads the same
// owner, so it shows the till with no reload here.
import 'package:feature_till/feature_till.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Push the opening form over Sell when no till is open.
Future<void> openTillFromSell(BuildContext context, WidgetRef ref) =>
    openTillPage(context, ref);
