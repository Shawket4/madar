/// One customer's sheet (the web's `features/customers/customer-detail-sheet.tsx`,
/// SELL-CUS-026 … SELL-CUS-056).
///
/// A PUBLIC piece of the area: the Customers page opens it, and so does every
/// customer link on Orders, Floor and Bookings (read-only, through
/// `customerSheetControl` in shared/sheets.dart), and later the reports
/// area's tables page.
///
/// A loyalty member IS a customer under the same id, so this is also the
/// member sheet. Each section follows its own capability family:
/// `customers.view` reads the customer (identity, stats, orders, bookings);
/// `customers.addresses.view` the addresses; `loyalty.members.list` /
/// `loyalty.read` the card. Someone holding only the loyalty side sees the
/// card alone.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'addresses_section.dart';
import 'bookings_section.dart';
import 'customer_dialog.dart';
import 'customers_data.dart';
import 'member_section.dart';
import 'merge_dialog.dart';
import 'people_widgets.dart';
import 'person_surface.dart';

/// Opens [customerId]'s sheet from the end side (full screen on a phone) and
/// resolves when it closes.
///
/// - [readOnly]: opened from somewhere that only looks (an order, a floor, a
///   booking): no Edit / Merge / Erase / Adjust / Remove / Wallet actions
///   (SELL-ALL-016, SELL-CUS-055). A read-only sheet CLOSES ITSELF before
///   calling [onOpenOrder] (the web's `useCustomerSheet`); the Customers
///   page's own sheet stays open and the order stacks over it (SELL-CUS-053).
/// - [branchId]: the branch whose loyalty programme the balance is read
///   under; null = the organisation's.
/// - [onOpenOrder]: one of the customer's orders was chosen.
/// - [onSwitch]: after a merge the sheet follows the kept customer.
Future<void> showCustomerSheet(
  BuildContext context, {
  required String customerId,
  required ValueChanged<String> onOpenOrder,
  bool readOnly = false,
  String? branchId,
  ValueChanged<String>? onSwitch,
}) => showDashSidePanel<void>(
  context,
  width: DashMetrics.dialogWide,
  builder: (context) => CustomerSheet(
    customerId: customerId,
    readOnly: readOnly,
    branchId: branchId,
    onOpenOrder: onOpenOrder,
    onSwitch: onSwitch,
  ),
);

/// The sheet's content.
class CustomerSheet extends ConsumerStatefulWidget {
  const CustomerSheet({
    required this.customerId,
    required this.onOpenOrder,
    this.readOnly = false,
    this.branchId,
    this.onSwitch,
    super.key,
  });

  final String customerId;
  final bool readOnly;
  final String? branchId;
  final ValueChanged<String> onOpenOrder;
  final ValueChanged<String>? onSwitch;

  @override
  ConsumerState<CustomerSheet> createState() => _CustomerSheetState();
}

class _CustomerSheetState extends ConsumerState<CustomerSheet> {
  /// The customer shown: the one opened, then the kept one after a merge.
  late String _id = widget.customerId;
  bool _erasing = false;

  void _close() => Navigator.of(context).maybePop();

  void _openOrder(String orderId) {
    if (widget.readOnly) {
      // A link only looks: the customer sheet closes first.
      Navigator.of(context).pop();
    }
    widget.onOpenOrder(orderId);
  }

  Future<void> _edit(Customer c) => showCustomerDialog(context, customer: c);

  Future<void> _merge(Customer c) async {
    final kept = await showMergeDialog(context, duplicate: c);
    if (kept == null || !mounted) return;
    setState(() => _id = kept.customer.id);
    widget.onSwitch?.call(kept.customer.id);
  }

  Future<void> _erase(Customer c) async {
    final t = ref.read(tProvider);
    final ok = await showDashConfirm(
      context,
      title: t('customers.eraseTitle', args: {'name': c.name}),
      description: t('customers.eraseBody'),
      confirmLabel: t('customers.erase'),
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _erasing = true);
    try {
      await ref.read(apiProvider).customers.eraseCustomer(id: c.id);
      if (!mounted) return;
      DashToast.success(context, t('customers.erased'));
      invalidatePeople(ref);
      _close();
    } on Object catch (e) {
      if (mounted) DashToast.error(context, peopleErrorMessage(e, t));
    } finally {
      if (mounted) setState(() => _erasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final access = ref.watch(peopleAccessProvider);
    final canEdit = access.canEdit && !widget.readOnly;
    final canMerge = access.canMerge && !widget.readOnly;
    // PDPL erase is its own capability: the owner's by default.
    final canErase = access.canErase && !widget.readOnly;

    final detail = access.canViewCustomers
        ? ref.watch(customerDetailProvider(_id))
        : null;
    final customer = detail?.value?.customer;
    // After a merge the id that was opened resolves to the one kept; the
    // card, if there is one, lives under the kept id.
    final personId = customer?.id ?? _id;
    // The card: asked for once the customer says there is one — or straight
    // away by someone who can only see the loyalty side.
    final wantsCard =
        access.canViewMember &&
        (access.canViewCustomers ? customer?.isMember == true : true);
    final card = wantsCard
        ? ref.watch(
            loyaltyMemberProvider((id: personId, branchId: widget.branchId)),
          )
        : null;
    final primary = detail ?? card;
    final name = customer?.name ?? card?.value?.member.name;
    final phone = customer?.phone ?? card?.value?.member.phone;
    final isMember = customer != null
        ? customer.isMember == true
        : card?.value != null;

    final Widget body;
    if (primary == null || (primary.isLoading && !primary.hasValue)) {
      body = const DashSkeleton(height: Space.xxl * 8);
    } else if (!primary.hasValue) {
      body = DashEmptyState(
        title: access.canViewCustomers
            ? t('customers.loadFailed')
            : t('loyalty.memberLoadFailed'),
        description: primary.hasError
            ? peopleErrorMessage(primary.error, t)
            : null,
        action: DashButton(
          label: t('common.retry'),
          variant: DashButtonVariant.outline,
          onPressed: () => access.canViewCustomers
              ? ref.invalidate(customerDetailProvider(_id))
              : ref.invalidate(
                  loyaltyMemberProvider((
                    id: personId,
                    branchId: widget.branchId,
                  )),
                ),
        ),
      );
    } else {
      final d = detail?.value;
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.xl,
        children: [
          if (d != null && customer != null) ...[
            if (d.resolvedFrom != null)
              StatusNote(children: [NoteText(t('customers.resolvedFrom'))]),
            _CustomerStats(customer: customer),
            if (canEdit || canMerge || canErase)
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  if (canEdit)
                    DashButton(
                      label: t('common.edit'),
                      icon: 'pencil',
                      variant: DashButtonVariant.outline,
                      size: DashButtonSize.compact,
                      onPressed: () => _edit(customer),
                    ),
                  if (canMerge)
                    DashButton(
                      label: t('customers.mergeInto'),
                      icon: 'git-merge',
                      variant: DashButtonVariant.outline,
                      size: DashButtonSize.compact,
                      onPressed: () => _merge(customer),
                    ),
                  if (canErase)
                    _DestructiveOutline(
                      label: t('customers.erase'),
                      loading: _erasing,
                      onPressed: () => _erase(customer),
                    ),
                ],
              ),
            _Identity(detail: d),
          ],
          if (wantsCard && card != null)
            PeopleSection(
              title: t('customers.loyalty'),
              child: switch (card) {
                AsyncValue(:final value?) => MemberSection(
                  detail: value,
                  branchId: widget.branchId,
                  readOnly: widget.readOnly,
                  onOpenOrder: _openOrder,
                  // They left and are still a customer: the sheet stays for
                  // someone who can see the customer, and closes for someone
                  // who could only ever see the card.
                  onForgotten: () {
                    if (!access.canViewCustomers) _close();
                  },
                ),
                AsyncValue(isLoading: true) => const DashSkeleton(
                  height: Space.xxl * 5,
                ),
                AsyncValue(:final error) => DashEmptyState(
                  title: t('loyalty.memberLoadFailed'),
                  description: error == null
                      ? null
                      : peopleErrorMessage(error, t),
                  action: DashButton(
                    label: t('common.retry'),
                    variant: DashButtonVariant.outline,
                    onPressed: () => ref.invalidate(
                      loyaltyMemberProvider((
                        id: personId,
                        branchId: widget.branchId,
                      )),
                    ),
                  ),
                ),
              },
            ),
          if (d != null && customer != null) ...[
            if (access.canViewAddresses)
              AddressesSection(customerId: customer.id),
            BookingsSection(customerId: customer.id),
            _RecentOrders(orders: d.recentOrders, onOpenOrder: _openOrder),
          ],
        ],
      );
    }

    return PersonSurface(
      title: name ?? t('customers.customer'),
      titleTrailing: isMember ? const MemberPill() : null,
      description: phone == null || phone.isEmpty
          ? null
          : PhoneText(
              phone,
              style: DashType.mono.copyWith(
                fontSize: 14,
                color: context.madarColors.textSecondary,
              ),
            ),
      body: body,
    );
  }
}

/// "Erase customer": an outline button in the destructive colour, with the
/// eraser glyph and a spinner while it runs.
class _DestructiveOutline extends StatelessWidget {
  const _DestructiveOutline({
    required this.label,
    required this.loading,
    required this.onPressed,
  });

  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.madarColors;
    return DashPressable(
      onTap: loading ? null : onPressed,
      enabled: !loading,
      semanticLabel: label,
      excludeChildSemantics: true,
      builder: (context, s) => Container(
        constraints: const BoxConstraints(minHeight: DashMetrics.target),
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        foregroundDecoration: dashFocusRing(
          context,
          s,
          BorderRadius.circular(Radii.control),
        ),
        decoration: BoxDecoration(
          color: s.highlighted ? c.hover : c.card,
          borderRadius: BorderRadius.circular(Radii.control),
          border: Border.all(color: c.input),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: Space.sm,
          children: [
            if (loading)
              SizedBox.square(
                dimension: IconSize.sm,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.errorText,
                ),
              )
            else
              DashIcon('eraser', size: IconSize.sm, color: c.errorText),
            Text(
              label,
              style: DashType.bodyMedium.copyWith(
                fontSize: DashType.meta.fontSize,
                color: c.errorText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerStats extends ConsumerWidget {
  const _CustomerStats({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = customer;
    return StatGrid(
      children: [
        StatBox(
          label: t('customers.orders'),
          value: fmt.fmtNumber(c.ordersCount),
        ),
        StatBox(
          label: t('customers.totalSpent'),
          value: fmt.fmtMoney(c.totalSpent),
        ),
        StatBox(
          label: t('customers.lastVisit'),
          value: c.lastOrderAt == null ? '—' : fmt.fmtDate(c.lastOrderAt),
        ),
        StatBox(label: t('customers.since'), value: fmt.fmtDate(c.createdAt)),
      ],
    );
  }
}

/// Who they are (`Identity`). Read-only: Edit changes name, phone and notes;
/// only the customer changes their consent.
class _Identity extends ConsumerWidget {
  const _Identity({required this.detail});

  final CustomerDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final lang = ref.watch(localeProvider);
    final c = context.madarColors;
    final cu = detail.customer;
    final birthday = formatBirthday(cu.birthMonth, cu.birthDay, lang);
    final muted = DashType.body.copyWith(color: c.textSecondary);
    final strong = DashType.body.copyWith(color: c.textPrimary);
    Widget unknown() => Text(t('customers.notGiven'), style: muted);
    Widget value(String s) => Text(s, textAlign: TextAlign.end, style: strong);
    Widget row(String label, Widget v) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.lg,
        children: [
          Text(label, style: muted),
          Expanded(
            child: Align(alignment: AlignmentDirectional.centerEnd, child: v),
          ),
        ],
      ),
    );
    final phone = cu.phone;
    return PeopleSection(
      title: t('customers.details'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          RuledBox(
            children: [
              row(
                t('customers.phone'),
                phone == null || phone.isEmpty ? unknown() : PhoneText(phone),
              ),
              row(t('customers.language'), switch (cu.locale) {
                'ar' => value(t('customers.languageAr')),
                'en' => value(t('customers.languageEn')),
                _ => unknown(),
              }),
              row(
                t('customers.birthday'),
                birthday == null ? unknown() : value(birthday),
              ),
              row(
                t('customers.source.label'),
                isCustomerSource(cu.source)
                    ? value(t('customers.source.${cu.source}'))
                    : unknown(),
              ),
              row(
                t('customers.marketing'),
                value(
                  cu.marketingOptOut == true
                      ? t('customers.marketingOff')
                      : t('customers.marketingOn'),
                ),
              ),
            ],
          ),
          Text(
            t('customers.marketingNote'),
            style: DashType.small.copyWith(color: c.textSecondary),
          ),
          if (cu.notes case final n? when n.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(color: c.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: DashMetrics.hair,
                children: [
                  Text(
                    t('customers.notes'),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                  Text(n, textDirection: autoDirection(n), style: strong),
                ],
              ),
            ),
          if (detail.mergedFrom.isNotEmpty)
            Text(
              t('customers.mergedFrom', args: {'n': detail.mergedFrom.length}),
              style: DashType.small.copyWith(color: c.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// The customer's recent orders (`RecentOrders`): a table on a wide screen,
/// stacked rows on a phone; with none, only "No orders yet".
class _RecentOrders extends ConsumerWidget {
  const _RecentOrders({required this.orders, required this.onOpenOrder});

  final List<CustomerOrder> orders;
  final ValueChanged<String> onOpenOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    if (orders.isEmpty) {
      return DashEmptyState(icon: 'receipt', title: t('customers.noOrders'));
    }
    String ref8(CustomerOrder o) =>
        o.orderRef ?? (o.id.length > 8 ? o.id.substring(0, 8) : o.id);
    String status(CustomerOrder o) =>
        t('orderStatus.${o.status}', defaultValue: o.status);
    final body = DashType.body.copyWith(color: c.textPrimary);
    final money = DashType.mono.copyWith(fontSize: 14, color: c.textPrimary);
    final Widget table;
    if (DashBreakpoints.isPhone(context)) {
      table = RuledBox(
        children: [
          for (final o in orders)
            Padding(
              key: ValueKey('customer-order-${o.id}'),
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: LinkText(
                          label: ref8(o),
                          mono: true,
                          onTap: () => onOpenOrder(o.id),
                        ),
                      ),
                      Text(
                        dashFigure(fmt.fmtMoney(o.totalAmount)),
                        style: money,
                      ),
                    ],
                  ),
                  Text(
                    '${o.branchName ?? '—'} · ${status(o)}',
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.sm),
                    child: Text(
                      fmt.fmtDateTime(o.createdAt),
                      style: DashType.small.copyWith(color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    } else {
      Widget head(String s, {bool end = false}) => Text(
        s.toUpperCase(),
        textAlign: end ? TextAlign.end : TextAlign.start,
        style: DashType.tableHeader.copyWith(color: c.textSecondary),
      );
      Widget cell(Widget child, {bool end = false, bool header = false}) =>
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: Space.md,
              vertical: header ? Space.sm + DashMetrics.hair : 0,
            ),
            child: Align(
              alignment: end
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: child,
            ),
          );
      final rule = BoxDecoration(
        border: Border(top: BorderSide(color: c.hairline)),
      );
      // The web's `overflow-x-auto` table: columns sized to their content,
      // Branch and Status taking what is left.
      table = Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: c.hairline),
        ),
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: box.maxWidth),
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: const {
                  0: IntrinsicColumnWidth(),
                  1: IntrinsicColumnWidth(flex: 1),
                  2: IntrinsicColumnWidth(flex: 1),
                  3: IntrinsicColumnWidth(),
                  4: IntrinsicColumnWidth(),
                },
                children: [
                  TableRow(
                    children: [
                      cell(head(t('customers.order')), header: true),
                      cell(head(t('customers.branch')), header: true),
                      cell(head(t('common.status')), header: true),
                      cell(
                        head(t('common.total'), end: true),
                        header: true,
                        end: true,
                      ),
                      cell(
                        head(t('common.date'), end: true),
                        header: true,
                        end: true,
                      ),
                    ],
                  ),
                  for (final o in orders)
                    TableRow(
                      key: ValueKey('customer-order-${o.id}'),
                      decoration: rule,
                      children: [
                        cell(
                          LinkText(
                            label: ref8(o),
                            mono: true,
                            onTap: () => onOpenOrder(o.id),
                          ),
                        ),
                        cell(Text(o.branchName ?? '—', style: body)),
                        cell(Text(status(o), style: body)),
                        cell(
                          Text(
                            dashFigure(fmt.fmtMoney(o.totalAmount)),
                            style: money,
                          ),
                          end: true,
                        ),
                        cell(
                          Text(fmt.fmtDateTime(o.createdAt), style: body),
                          end: true,
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return PeopleSection(title: t('customers.recentOrders'), child: table);
  }
}
