// E2E roster m1: "Omar Khaled said they can't work Fris." A preference
// names the whole day.
import 'package:flutter_test/flutter_test.dart';
import 'package:staff_core/staff_core.dart';
import 'package:staff_core/testing.dart';

void main() {
  tearDown(() => currentLang = 'en');

  test("a day someone can't work is named in full", () {
    words = coreWord;
    expect(
      cantWorkWords('Omar Khaled', DateTime.friday),
      "Omar Khaled said they can't work on Fridays.",
    );
    currentLang = 'ar';
    words = (k) => coreWord(k, arabic: true);
    expect(cantWorkWords('عمر', DateTime.friday), contains('الجمعة'));
  });
}
