import 'dart:async';

import 'package:app_core/app_core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rust_bridge/rust_bridge.dart';

/// Open the customer card over whatever is on screen.
Future<void> showCustomerCard(BuildContext context, CustomerView customer) =>
    showMadarSheet<void>(
      context,
      size: SheetSize.hug,
      maxWidth: Responsive.sheetCompactMaxWidth,
      builder: (_) => CustomerCardSheet(customer: customer),
    );

/// Who a customer is, at a glance: the name, the phone (its last four digits
/// for someone without `customers.view` — the core decides), the member
/// badge with the balance the feed last carried, and their saved addresses.
///
/// Everything but the addresses is already on the till and shows at once.
/// The addresses are asked of the server when the card opens, only for
/// someone holding `customers.addresses.view`, and nothing waits on them:
/// offline, or on a server that cannot answer, the card says so in their
/// place and the rest of it stands.
class CustomerCardSheet extends ConsumerStatefulWidget {
  const CustomerCardSheet({required this.customer, super.key});

  final CustomerView customer;

  @override
  ConsumerState<CustomerCardSheet> createState() => _CustomerCardSheetState();
}

class _CustomerCardSheetState extends ConsumerState<CustomerCardSheet> {
  /// Null while loading (or when the actor may not see addresses at all).
  List<CustomerAddressView>? _addresses;
  String? _addressError;
  bool _mayViewAddresses = false;

  @override
  void initState() {
    super.initState();
    final bridge = ref.read(bridgeProvider);
    _mayViewAddresses = bridge.can(cap: Cap.customersAddressesView);
    // A customer added on this till a moment ago has no server row to ask.
    if (_mayViewAddresses && !widget.customer.pending) {
      unawaited(_loadAddresses(bridge));
    } else {
      _addresses = const [];
    }
  }

  Future<void> _loadAddresses(MadarBridge bridge) async {
    try {
      final rows = await bridge.customerAddresses(
        customerId: widget.customer.id,
      );
      if (mounted) setState(() => _addresses = rows);
    } on MadarError catch (e) {
      // No network is the ordinary case, and it has its own words: the card
      // is fine, this one list is not to be had right now.
      final message = switch (e) {
        MadarError_Offline() ||
        MadarError_Transient() => bridge.tr(key: 'customers.addresses_offline'),
        _ => bridge.humanMessage(e),
      };
      if (mounted) setState(() => _addressError = message);
    } on Object {
      if (mounted) {
        setState(
          () => _addressError = bridge.tr(key: 'customers.addresses_failed'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bridge = ref.bridge;
    final colors = context.madarColors;
    String t(String k) => bridge.tr(key: k);
    final c = widget.customer;
    final phone = c.phone ?? c.phoneHint;
    final muted = MadarType.bodySm.copyWith(color: colors.textMuted);

    return SingleChildScrollView(
      padding: const EdgeInsetsDirectional.all(Space.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Text(
            t('customers.card_title'),
            style: MadarType.bodySm.copyWith(color: colors.textMuted),
            textAlign: TextAlign.center,
          ),
          Semantics(
            header: true,
            child: Text(
              c.name,
              style: MadarType.h3.copyWith(
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: Space.sm,
            runSpacing: Space.xs,
            children: [
              Text(
                phone == null
                    ? t('customers.no_phone')
                    : MadarFormat.ltr(phone),
                style: MadarType.body.copyWith(color: colors.textSecondary),
              ),
              if (c.isMember)
                MadarTag(label: t('customers.member'), tone: MadarTone.accent),
              if (c.balanceLabel case final balance?)
                Text(
                  balance,
                  style: MadarType.body.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (c.pending) MadarTag(label: t('customers.pending')),
            ],
          ),
          if (_mayViewAddresses) ...[
            const MadarHairline(),
            MadarSectionHeader(text: t('customers.addresses')),
            if (_addressError case final error?)
              Text(error, style: muted)
            else if (_addresses case final rows?)
              if (rows.isEmpty)
                Text(t('customers.addresses_empty'), style: muted)
              else
                for (final a in rows)
                  _AddressRow(
                    address: a,
                    uses: t(
                      'customers.address_uses',
                    ).replaceAll('{count}', '${a.useCount}'),
                  )
            else
              const SkeletonScope(
                child: Column(
                  spacing: Space.sm,
                  children: [SkeletonRow(), SkeletonRow()],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.address, required this.uses});

  final CustomerAddressView address;
  final String uses;

  @override
  Widget build(BuildContext context) {
    final colors = context.madarColors;
    final a = address;
    final head = [?a.label, if (a.useCount > 1) uses].join(' · ');
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: Space.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (head.isNotEmpty)
            Text(
              head,
              style: MadarType.bodySm.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (a.line.isNotEmpty)
            Text(
              a.line,
              style: MadarType.body.copyWith(color: colors.textPrimary),
            ),
          if (a.notes case final notes?)
            Text(
              notes,
              style: MadarType.bodySm.copyWith(color: colors.textMuted),
            ),
        ],
      ),
    );
  }
}

/// The customer an order is LINKED to, as one tappable row: the name, the
/// member badge, and the card behind it. Resolved from the till's own list —
/// no network — so a customer this till does not hold yet renders nothing.
///
/// [orderedFor] is the snapshot contact ("Sara · 0100…") of an order placed
/// for someone else: the row then says "Ordered by {customer} for {contact}".
/// The snapshot stays what the driver calls and what the receipt prints; this
/// row only says whose order it is.
class LinkedCustomerRow extends ConsumerWidget {
  const LinkedCustomerRow({
    required this.customerId,
    this.orderedFor,
    super.key,
  });

  final String customerId;

  /// Non-null only when the order's contact is not the customer's own.
  final String? orderedFor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bridge = ref.bridge;
    final colors = context.madarColors;
    String t(String k) => bridge.tr(key: k);
    CustomerView? customer;
    try {
      customer = bridge.customerById(id: customerId);
    } on MadarError {
      customer = null;
    }
    if (customer == null) return const SizedBox.shrink();
    final c = customer;
    final marker = orderedFor == null
        ? null
        : t('customers.ordered_by_for')
              .replaceAll('{customer}', c.name)
              .replaceAll('{contact}', orderedFor!);
    return Semantics(
      button: true,
      label: marker ?? '${t('customers.linked')}: ${c.name}',
      hint: t('customers.view_card'),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(showCustomerCard(context, c)),
        child: MadarCard(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              spacing: Space.sm,
              children: [
                MadarIcon(
                  'person.fill',
                  tint: colors.accent,
                  size: IconSize.lg,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('customers.linked'),
                        style: MadarType.bodySm.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                      Text(
                        marker ?? c.name,
                        style: MadarType.body.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (c.isMember)
                  MadarTag(
                    label: t('customers.member'),
                    tone: MadarTone.accent,
                  ),
                const MadarGlyphIcon(MadarGlyph.chevronForward),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
