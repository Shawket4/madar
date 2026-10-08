/// `/customers` (the web's `features/customers/customers-page.tsx`, SELL-CUS
/// rows): everybody the shop knows — the people list, the customer sheet,
/// add / edit / merge / erase and the loyalty card.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../orders/order_sheet.dart';
import 'customer_dialog.dart';
import 'customer_sheet.dart';
import 'customers_data.dart';
import 'customers_list.dart';

class CustomersPage extends ConsumerStatefulWidget {
  const CustomersPage({super.key});

  /// The route's builder (routes.dart points here). The open customer is
  /// page state, not in the URL.
  static Widget route(BuildContext context, GoRouterState state) =>
      const CustomersPage();

  @override
  ConsumerState<CustomersPage> createState() => _CustomersPageState();
}

class _CustomersPageState extends ConsumerState<CustomersPage> {
  /// The person whose sheet is open (the selected row).
  String? _openId;

  /// Opens [id]'s sheet; closing it (×, Escape, outside) clears the open
  /// customer and the row selection (SELL-CUS-056).
  Future<void> _open(String id) async {
    if (_openId != null) return;
    setState(() => _openId = id);
    await showCustomerSheet(
      context,
      customerId: id,
      // The order stacks over the customer, which stays open; this order
      // sheet has no Void (SELL-CUS-053).
      onOpenOrder: _openOrder,
      onSwitch: (kept) {
        if (mounted) setState(() => _openId = kept);
      },
    );
    if (mounted) setState(() => _openId = null);
  }

  void _openOrder(String orderId) {
    showOrderSheet(context, orderId: orderId, onSwitchOrder: _openOrder);
  }

  Future<void> _add() async {
    final saved = await showCustomerDialog(context);
    if (saved != null && mounted) await _open(saved.customer.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final access = ref.watch(peopleAccessProvider);
    // The page's own gate (SELL-CUS-002): its own words once permissions are
    // known and lack customers.view; before they load, the header alone
    // (SELL-CUS-057). The route has no capability, so the shell's generic
    // gate does not answer first.
    if (access.ready && !access.canViewCustomers) {
      return Restricted(
        title: t('nav.customers'),
        who: t('customers.noAccess'),
      );
    }
    return DashPageScaffold(
      title: t('customers.title'),
      subtitle: t('customers.subtitle'),
      actions: [
        if (access.canCreate)
          DashButton(label: t('customers.add'), icon: 'plus', onPressed: _add),
      ],
      body: !access.ready
          ? const SizedBox.shrink()
          : CustomersList(openId: _openId, onOpen: _open),
    );
  }
}
