/// The Madar backend API for the Flutter dashboard: the transport seam, every
/// schema as a model, one API class per tag and the [DashboardApi] facade.
///
/// ```dart
/// final api = DashboardApi(transport);
/// final page = await api.orders.listOrders(branchId: id, page: 1);
/// ```
library;

export 'src/generated/apis.dart';
export 'src/generated/facade.dart';
export 'src/generated/models.dart';
export 'src/generated/operations.dart';
export 'src/transport.dart';
