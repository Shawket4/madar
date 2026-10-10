/// Mock implementations of dashboard_core's gateways for tests and mock mode:
/// [MockSessionGateway] over the MockServer's auth endpoints and personas
/// (with [ScopedTransport] adding the scope headers), [MemoryPreferences],
/// [RecordingFileGateway], [RecordingExportGateway] and a controllable
/// [MockRealtimeGateway] (or `TransportRealtimeGateway` over the server).
library;

export 'src/mock/mock_gateways.dart';
