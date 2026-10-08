/// `/bookings` (the web's `features/bookings/bookings-page.tsx`, SELL-BKG
/// rows): the day list and timeline, the booking dialog, the settings dialog.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/branch_required.dart';

class BookingsPage extends ConsumerWidget {
  const BookingsPage({this.date, this.bookingId, super.key});

  /// The route's builder (routes.dart points here; the search params are
  /// this unit's to read).
  static Widget route(BuildContext context, GoRouterState state) {
    final q = state.uri.queryParameters;
    final date = q['date'];
    return BookingsPage(
      date: date != null && _ymd.hasMatch(date) ? date : null,
      bookingId: q['booking'],
    );
  }

  static final RegExp _ymd = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// `?date=YYYY-MM-DD` (validated): that day (SELL-BKG-030).
  final String? date;

  /// `?booking=`: that booking's dialog once the day loads (SELL-BKG-031).
  final String? bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final branchId = ref.watch(sellBranchIdProvider);
    return DashPageScaffold(
      title: t('bookings.title'),
      subtitle: branchId == null ? null : t('bookings.description'),
      body: branchId == null
          ? const BranchRequiredState(
              messageKey: 'bookings.pickBranch',
              icon: 'calendar-clock',
            )
          : DashEmptyState(
              icon: 'layers',
              title: t('shell.pendingTitle'),
              description: t('shell.pendingBody'),
            ),
    );
  }
}
