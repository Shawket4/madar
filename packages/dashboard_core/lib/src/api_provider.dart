/// The generated client over the active transport.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:dashboard_core/src/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `final api = ref.watch(apiProvider);` then `api.orders.listOrders(...)`.
final apiProvider = Provider<DashboardApi>(
  (ref) => DashboardApi(ref.watch(transportProvider)),
);
