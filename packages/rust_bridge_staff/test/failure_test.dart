// The staff app's words for a refusal. E2E requests (run 10): with the network
// cut, sending a leave said "You're offline and this teller hasn't been set up
// for offline sign-in yet." — the POS till's sign-in words, not the staff
// app's. A staff action that needs the server says it needs a connection.
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

class _Words implements MadarBridge {
  @override
  String tr({required String key}) => switch (key) {
    'staff.needs_connection' =>
      "This needs a connection. Try again when you're online.",
    'err.offline_no_setup' =>
      "You're offline and this teller hasn't been set up for offline sign-in yet.",
    _ => key,
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test("offline reads as the staff app's 'needs a connection'", () {
    final words = _Words();
    expect(
      words.humanMessage(
        const MadarError.offline(detail: 'error sending request'),
      ),
      "This needs a connection. Try again when you're online.",
    );
  });
}
