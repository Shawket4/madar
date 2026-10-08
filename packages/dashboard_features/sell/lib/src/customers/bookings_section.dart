/// The tables a customer has booked (the web's
/// `features/customers/bookings-section.tsx`, SELL-CUS-050 … 052, 058):
/// newest first, read through the merge chain, ten at a time. For someone
/// who may read bookings the date opens that booking on the Bookings page —
/// its branch (the shell's scope switches to it), its day, its id.
library;

import 'package:dashboard_api/dashboard_api.dart' hide Column;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/booking_status.dart';
import 'customers_data.dart';
import 'people_widgets.dart';

class BookingsSection extends ConsumerStatefulWidget {
  const BookingsSection({required this.customerId, super.key});

  final String customerId;

  @override
  ConsumerState<BookingsSection> createState() => _BookingsSectionState();
}

class _BookingsSectionState extends ConsumerState<BookingsSection> {
  int _limit = customerBookingsPage;
  List<BookingView>? _previous;

  CustomerBookingsQuery get _key => (id: widget.customerId, limit: _limit);

  /// Leaves the page for the booking: every sheet closes, the scope moves to
  /// the booking's branch (the period stays), and `/bookings` opens that
  /// day and booking (`navigate({to: "/bookings", search: {...prev,
  /// branchId, date, booking}})`).
  void _open(BookingView b) {
    final zone = ref.read(formatProvider).timezone;
    final day = inZone(b.startsAt, zone);
    final date =
        '${day.year.toString().padLeft(4, '0')}-'
        '${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final router = GoRouter.of(context);
    // Every sheet and dialog is a pageless route over the router's pages.
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.settings is Page);
    router.go(
      Uri(
        path: '/bookings',
        queryParameters: {
          'branchId': b.branchId,
          'date': date,
          'booking': b.id,
        },
      ).toString(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tProvider);
    final fmt = ref.watch(formatProvider);
    final access = ref.watch(peopleAccessProvider);
    final c = context.madarColors;
    final q = ref.watch(customerBookingsProvider(_key));
    if (q.value != null) _previous = q.value;
    final rows = q.value ?? _previous;
    final branches = ref.watch(branchesProvider).value;
    String branchName(String id) {
      for (final b in branches ?? const <Branch>[]) {
        if (b.id == id) return b.name;
      }
      return '—';
    }

    final Widget body;
    if (rows == null && q.isLoading) {
      body = const DashSkeleton(height: Space.xxl * 2 + Space.lg);
    } else if (q.hasError && !q.isLoading) {
      body = InlineFailure(
        message: peopleErrorMessage(q.error, t),
        onRetry: () => ref.invalidate(customerBookingsProvider(_key)),
      );
    } else if (rows == null || rows.isEmpty) {
      body = DashedNote(t('customers.bookings.empty'));
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: Space.md,
        children: [
          SizedBox(
            width: double.infinity,
            child: RuledBox(
              children: [
                for (final b in rows)
                  Padding(
                    key: ValueKey('customer-booking-${b.id}'),
                    padding: const EdgeInsets.all(Space.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Space.md,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: DashMetrics.hair,
                          ),
                          child: DashIcon(
                            'calendar-clock',
                            size: IconSize.sm,
                            color: c.textSecondary,
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (access.canOpenBookings)
                                LinkText(
                                  label: fmt.fmtDateTime(b.startsAt),
                                  strong: true,
                                  onTap: () => _open(b),
                                )
                              else
                                Text(
                                  fmt.fmtDateTime(b.startsAt),
                                  style: DashType.bodyMedium.copyWith(
                                    color: c.textPrimary,
                                  ),
                                ),
                              Text.rich(
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: t(
                                        'customers.bookings.party',
                                        args: {
                                          'n': fmt.fmtNumber(b.partySize),
                                        },
                                      ),
                                    ),
                                    const TextSpan(text: ' · '),
                                    TextSpan(text: branchName(b.branchId)),
                                  ],
                                ),
                                style: DashType.body.copyWith(
                                  color: c.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        BookingStatusPill(status: b.status),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (rows.length >= _limit)
            DashButton(
              label: t('customers.bookings.more'),
              variant: DashButtonVariant.outline,
              size: DashButtonSize.compact,
              loading: q.isLoading,
              onPressed: () =>
                  setState(() => _limit += customerBookingsPage),
            ),
        ],
      );
    }
    return PeopleSection(title: t('customers.bookings.title'), child: body);
  }
}
