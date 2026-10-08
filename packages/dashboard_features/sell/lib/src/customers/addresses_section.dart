/// Where a customer has had orders sent (the web's
/// `features/customers/addresses-section.tsx`, SELL-CUS-049) — behind
/// `customers.addresses.view`; the sheet draws it only for someone holding
/// it, so nothing is asked for otherwise. Read-only: an address is saved by
/// ordering to it.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'customers_data.dart';
import 'people_widgets.dart';
import 'person_surface.dart';

class AddressesSection extends ConsumerWidget {
  const AddressesSection({required this.customerId, super.key});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final q = ref.watch(customerAddressesProvider(customerId));
    final Widget body;
    if (q.isLoading && !q.hasValue) {
      body = const DashSkeleton(height: Space.xxl * 2 + Space.lg);
    } else if (q.hasError && !q.isLoading) {
      body = InlineFailure(
        message: peopleErrorMessage(q.error, t),
        onRetry: () => ref.invalidate(customerAddressesProvider(customerId)),
      );
    } else {
      final rows = q.value ?? const <CustomerAddress>[];
      body = rows.isEmpty
          ? DashedNote(t('customers.addresses.empty'))
          : RuledBox(children: [for (final a in rows) _AddressRow(a)]);
    }
    return PeopleSection(title: t('customers.addresses.title'), child: body);
  }
}

class _AddressRow extends ConsumerWidget {
  const _AddressRow(this.a);

  final CustomerAddress a;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final c = context.madarColors;
    final label = a.label?.trim() ?? '';
    final channel = addressChannel(t, a.channel);
    final line = formatAddressLine(a, t);
    final notes = a.deliveryNotes ?? '';
    final title = label.isNotEmpty ? label : channel;
    return Padding(
      key: ValueKey('customer-address-${a.id}'),
      padding: const EdgeInsets.all(Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: DashMetrics.hair),
            child: DashIcon(
              'map-pin',
              size: IconSize.sm,
              color: c.textSecondary,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              spacing: DashMetrics.hair,
              children: [
                Wrap(
                  spacing: Space.sm,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    Text(
                      title,
                      textDirection: autoDirection(title),
                      style: DashType.bodyMedium.copyWith(color: c.textPrimary),
                    ),
                    if (label.isNotEmpty)
                      Text(
                        channel,
                        style: DashType.small.copyWith(color: c.textSecondary),
                      ),
                  ],
                ),
                if (line.isNotEmpty)
                  Text(
                    line,
                    textDirection: autoDirection(line),
                    style: DashType.body.copyWith(color: c.textSecondary),
                  ),
                if (notes.isNotEmpty)
                  Text(
                    notes,
                    textDirection: autoDirection(notes),
                    style: DashType.small.copyWith(color: c.textSecondary),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t(
                  'customers.addresses.used',
                  args: {'n': fmt.fmtNumber(a.useCount)},
                ),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
              Text(
                t(
                  'customers.addresses.lastUsed',
                  args: {'date': fmt.fmtDate(a.lastUsedAt)},
                ),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
