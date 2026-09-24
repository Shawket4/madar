// The staff app's words for a core error (E2E clocking C1): Dawam has no
// offline sign-in to set up, so "offline" must never read as the POS
// teller's "this teller hasn't been set up for offline sign-in yet" — it
// showed on the privacy notice when "I agree" was tapped offline.
import 'package:flutter_test/flutter_test.dart';
import 'package:rust_bridge_staff/src/failure.dart';
import 'package:rust_bridge_staff/src/generated/api/error.dart';

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
