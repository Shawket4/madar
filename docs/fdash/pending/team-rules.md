# team/rules: verifier findings (1 major, 4 minor)
1 MAJOR (ALL-010/022): rules_page.dart:372 `if (s == null || q.hasError)` swaps the form for skeletons during Riverpod's automatic retry (hasError is true while retrying). Use `if (s == null || (q.hasError && !q.retrying))`. Add a ProviderContainer(retry: webRetry) test: a 500 then a 200 keeps the form on screen.
2 minor (ALL-009): rules_page.dart:328-333: when the form is edited and a newer answer lands, also set `_loaded = RulesValues.from(s);` so the confirmation and branchBody measure against current values.
3 minor (RUL-012/043, ALL-013): give me divergence rows (reply) for the Arabic arrow (← in Arabic; the web always prints →) and for describeChange wording the choice values (the web shows raw wire values). Mark the TEAM-ALL-013 test "(divergence)".
4 minor (RUL-011): the fixed-amount rung field shows "50", not "50.00". Add minDecimals: 2 (rules_cards.dart _RungRow), and make the test (rules_page_test.dart:208) expect '50.00'.
5 minor (ALL-025, RUL-034): add a rules test that drives night_range_field.dart's equal-times refusal and "End at … instead" suggestion. Merging it with shifts' ShiftTimeRange is an area-check item; don't do it now.
Run test/rules and test/shared.
