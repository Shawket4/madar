// The staff app's words for a core error (E2E clocking C1, requests run 10):
// Dawam has no offline sign-in to set up, so "offline" must never read as the
// POS teller's "this teller hasn't been set up for offline sign-in yet" — it
// showed on the privacy notice when "I agree" was tapped offline, and when a
// leave was sent with the network cut.
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge_staff/rust_bridge_staff.dart';
import 'package:rust_bridge_staff/src/failure.dart';
import 'package:rust_bridge_staff/src/generated/api/error.dart';

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
  String words(String key) => '<$key>';

  test('offline reads "this needs a connection"', () {
    for (final detail in ['error sending request', '']) {
      expect(
        staffErrorText(MadarError.offline(detail: detail), words),
        '<staff.needs_connection>',
      );
    }
  });

  test("the bridge's humanMessage says it too", () {
    expect(
      _Words().humanMessage(
        const MadarError.offline(detail: 'error sending request'),
      ),
      "This needs a connection. Try again when you're online.",
    );
  });

  test('the server and the core keep their own words', () {
    expect(
      staffErrorText(
        const MadarError.server(status: 409, code: 'X', detail: 'Refused.'),
        words,
      ),
      'Refused.',
    );
    expect(
      staffErrorText(const MadarError.transient(detail: ''), words),
      '<err.network>',
    );
    expect(
      staffErrorText(const MadarError.internal(detail: ' '), words),
      '<err.generic>',
    );
  });
}
