// E2E roster (Omar, iPhone, 24 Sep): with the phone's connection cut, asking
// for a swap / claiming an open shift / saving preferences showed the TILL's
// words — "You're offline and this teller hasn't been set up for offline
// sign-in yet." The staff app has no offline sign-in: a lost connection
// reads "This needs a connection. Try again when you're online." (S-133,
// S-139), in the phone's language.
import 'package:flutter_test/flutter_test.dart';
import 'package:madar_staff/boot.dart' show dawamErrorText;
import 'package:rust_bridge_staff/rust_bridge_staff.dart';

void main() {
  String word(String key) => '<$key>';
  String human(MadarError e) => '<human>';

  test('offline reads as "needs a connection", not the till\'s sign-in', () {
    expect(
      dawamErrorText(
        const MadarError.offline(detail: 'connection refused'),
        word: word,
        human: human,
      ),
      '<staff.needs_connection>',
    );
  });

  test('a 403 keeps the server\'s sentence, without its kind', () {
    expect(
      dawamErrorText(
        const MadarError.forbidden(
          resource: 'holidays',
          action:
              "Forbidden: This needs Publish the week's roster for every branch (hr.schedule.publish).",
        ),
        word: word,
        human: human,
      ),
      "This needs Publish the week's roster for every branch (hr.schedule.publish).",
    );
  });

  test('a 403 keeps the server\'s sentence; the rest as before', () {
    expect(
      dawamErrorText(
        const MadarError.forbidden(
          resource: 'adjustments',
          action: 'Above your limit.',
        ),
        word: word,
        human: human,
      ),
      'Above your limit.',
    );
    expect(
      dawamErrorText(
        const MadarError.transient(detail: 'x'),
        word: word,
        human: human,
      ),
      '<human>',
    );
  });
}
