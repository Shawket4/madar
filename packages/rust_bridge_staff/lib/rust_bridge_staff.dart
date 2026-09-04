/// Madar employee staff app — FFI bridge to madar-core via flutter_rust_bridge.
///
/// A SEPARATE bindings binary from the POS `rust_bridge` and the management
/// `rust_bridge_dashboard`. Consumers get: the `MadarCore` lifecycle wrapper, the
/// generated `MadarBridge` handle (employee self-service only), the DTO types,
/// and the `MadarError` sealed union. The generated internals
/// (`src/generated/frb_generated*.dart`) stay private.
library;

export 'src/core.dart';
export 'src/failure.dart';
export 'src/generated/api/bridge.dart';
export 'src/generated/api/error.dart';
export 'src/generated/api/staff.dart';
export 'src/generated/api/types.dart';
