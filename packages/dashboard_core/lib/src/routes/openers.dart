/// Another area's sheet or dialog, opened from a page that cannot depend on
/// that area's package (reports, setup and admin cannot import sell or
/// team). The app, which composes every area, wires [areaOpenersProvider] to
/// the real implementations; unwired (a package's own tests) every opener is
/// null and the caller keeps its own fallback.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The customer sheet (sell's `CustomerDetailSheet`).
class CustomerSheetOpener {
  const CustomerSheetOpener({required this.open, required this.warm});

  /// Opens [customerId]'s sheet; resolves when it closes. [readOnly]: no
  /// edit, merge, erase or loyalty actions, and choosing an order closes it
  /// first. [branchId]: the programme a balance is read under (null = the
  /// org's).
  final Future<void> Function(
    BuildContext context,
    String customerId, {
    bool readOnly,
    String? branchId,
  })
  open;

  /// Warms the sheet's first reads (intent).
  final void Function(WidgetRef ref, String customerId, {String? branchId})
  warm;
}

/// The order sheet (sell's `OrderDetailSheet`), without Void.
class OrderSheetOpener {
  const OrderSheetOpener({required this.open, required this.warm});

  final Future<void> Function(BuildContext context, String orderId) open;
  final void Function(WidgetRef ref, String orderId) warm;
}

/// Team's Add employee dialog ("Make employee" with [userId] preset).
class AddEmployeeOpener {
  const AddEmployeeOpener({required this.open, required this.warm});

  final Future<void> Function(BuildContext context, {String? userId}) open;
  final void Function(WidgetRef ref) warm;
}

/// The cross-area openers the app wires; null = not wired.
class AreaOpeners {
  const AreaOpeners({this.customerSheet, this.orderSheet, this.addEmployee});

  final CustomerSheetOpener? customerSheet;
  final OrderSheetOpener? orderSheet;
  final AddEmployeeOpener? addEmployee;
}

/// Unwired by default; the app overrides it at boot.
final areaOpenersProvider = Provider<AreaOpeners>((_) => const AreaOpeners());
