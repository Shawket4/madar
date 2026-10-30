/// Who sold an order (teller pick, MadarRust `orders.sold_by`): on a branch
/// that asks who's serving at checkout, the till records the picked person
/// as `sold_by`, and `teller_id` stays whoever was signed in (the drawer and
/// the money permissions are theirs). One rule for every screen that names
/// an order's teller: the order sheets, the orders list and the export.
library;

import 'package:dashboard_api/dashboard_api.dart'
    show Order, OrderExport, OrderFull;

/// [teller] is who sold; [signedIn] is whoever was signed in, set only when
/// someone else was picked (the "Signed in" line), else null.
typedef OrderSeller = ({String teller, String? signedIn});

/// The picked person ([soldByName]), else the signed-in one ([tellerName]);
/// the signed-in person again as [OrderSeller.signedIn] when [soldBy] is set
/// and is not [tellerId]. Nobody picked reads exactly as before.
OrderSeller orderSeller({
  required String tellerId,
  required String tellerName,
  String? soldBy,
  String? soldByName,
}) => (
  teller: soldByName ?? tellerName,
  signedIn: soldBy != null && soldBy != tellerId ? tellerName : null,
);

extension OrderSellerOfOrder on Order {
  /// Who sold this order ([orderSeller]).
  OrderSeller get seller => orderSeller(
    tellerId: tellerId,
    tellerName: tellerName,
    soldBy: soldBy,
    soldByName: soldByName,
  );
}

extension OrderSellerOfOrderFull on OrderFull {
  /// Who sold this order ([orderSeller]).
  OrderSeller get seller => orderSeller(
    tellerId: tellerId,
    tellerName: tellerName,
    soldBy: soldBy,
    soldByName: soldByName,
  );
}

extension OrderSellerOfOrderExport on OrderExport {
  /// Who sold this order ([orderSeller]).
  OrderSeller get seller => orderSeller(
    tellerId: tellerId,
    tellerName: tellerName,
    soldBy: soldBy,
    soldByName: soldByName,
  );
}
