/// The Staff drinks report's reads (REP-SPL-004…006, REP-SPL-019), keyed by
/// their params as the web's React Query keys are. Only a `resync` refreshes
/// them (no realtime event names `/staff-pool`).
library;

import 'package:dashboard_api/dashboard_api.dart'
    show OrderFull, StaffDrink, StaffDrinksSummary, StaffPoolToday;
import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `{branch_id, business_date}`: the LAST day of the period.
typedef PoolDayQuery = ({String branchId, String businessDate});

/// `{branch_id, from, to}`: the WHOLE period, as business days.
typedef DrinksQuery = ({String branchId, String from, String to});

/// `GET /staff-pool/today` (getStaffPoolToday).
final staffPoolTodayProvider = FutureProvider.autoDispose
    .family<StaffPoolToday, PoolDayQuery>((ref, q) {
      ref.watch(realtimeEpochProvider('/staff-pool/today'));
      return ref
          .watch(apiProvider)
          .staffPool
          .getStaffPoolToday(
            branchId: q.branchId,
            businessDate: q.businessDate,
          );
    });

/// `GET /staff-pool/drinks` (listStaffDrinks), newest first.
final staffDrinksProvider = FutureProvider.autoDispose
    .family<List<StaffDrink>, DrinksQuery>((ref, q) {
      ref.watch(realtimeEpochProvider('/staff-pool/drinks'));
      return ref
          .watch(apiProvider)
          .staffPool
          .listStaffDrinks(branchId: q.branchId, from: q.from, to: q.to);
    });

/// `GET /staff-pool/drinks/summary` (summarizeStaffDrinks): the same filter
/// as the list, so the strip and the rows describe the same drinks.
final staffDrinksSummaryProvider = FutureProvider.autoDispose
    .family<StaffDrinksSummary, DrinksQuery>((ref, q) {
      ref.watch(realtimeEpochProvider('/staff-pool/drinks/summary'));
      return ref
          .watch(apiProvider)
          .staffPool
          .summarizeStaffDrinks(branchId: q.branchId, from: q.from, to: q.to);
    });

/// `GET /orders/{order_id}` (getOrder): the sale a drink was rung on.
final staffDrinkOrderProvider = FutureProvider.autoDispose
    .family<OrderFull, String>((ref, id) {
      ref.watch(realtimeEpochProvider('/orders/$id'));
      return ref.watch(apiProvider).orders.getOrder(orderId: id);
    });
