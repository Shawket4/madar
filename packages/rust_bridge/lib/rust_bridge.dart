/// Madar POS — FFI bridge to madar-core via flutter_rust_bridge.
///
/// Consumers get: the `MadarCore` lifecycle wrapper, the generated
/// `MadarBridge` handle (every core method), the DTO types, and the sealed
/// unions (AppRoute, MadarError, VaultCommand, RealtimeMessage, AlertCommand).
/// The generated internals (`src/generated/frb_generated*.dart`) stay private.
library;

export 'src/core.dart';
export 'src/failure.dart';
export 'src/generated/api/bridge.dart';
export 'src/generated/api/cart.dart';
export 'src/generated/api/catalog.dart';
export 'src/generated/api/delivery.dart';
export 'src/generated/api/device.dart';
export 'src/generated/api/error.dart';
export 'src/generated/api/floor.dart';
export 'src/generated/api/kds.dart';
export 'src/generated/api/orders.dart';
export 'src/generated/api/printing.dart';
export 'src/generated/api/realtime.dart';
export 'src/generated/api/routes.dart';
export 'src/generated/api/shift.dart';
export 'src/generated/api/sync.dart';
export 'src/generated/api/tickets.dart';
export 'src/generated/api/types.dart';
export 'src/generated/api/vault.dart';
