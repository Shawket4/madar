/// The mock backend for tests and mock mode: [MockServer] (an [ApiTransport]),
/// [MockDb] over the deterministic [MockSeed], [MockClock], the five
/// [Persona]s, and [registerCoreMocks] for what the app shell calls at start.
///
/// ```dart
/// final db = MockDb.seeded();
/// final server = MockServer(persona: Persona.owner, clock: db.clock);
/// registerCoreMocks(server, db);
/// server.on('POST', '/orders/{id}/void', (req) {
///   req.requireCap('orders.void');
///   ...
/// });
/// final api = DashboardApi(server);
/// ```
library;

export 'src/generated/mock_capabilities.dart';
export 'src/mock/handlers/core_handlers.dart';
export 'src/mock/mock_clock.dart';
export 'src/mock/mock_db.dart';
export 'src/mock/mock_ids.dart';
export 'src/mock/mock_server.dart';
export 'src/mock/personas.dart';
export 'src/mock/seed.dart';
export 'src/mock/seed_data.dart';
export 'src/mock/seed_ids.dart';
