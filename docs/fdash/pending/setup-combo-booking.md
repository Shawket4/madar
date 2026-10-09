# setup/combo_settings + booking_settings: AT PARITY, minors
1 (CMB-018): combo_settings_page.dart:94-99 _follow: drop the early return and re-seed whenever untouched: `_from = s; if (_form == null || !_dirty) _base = _form = ComboSettingsForm.from(s);`. Add a test: edit, undo the edit, a refresh lands, and the fresh value shows.
2 (CMB-017 test): assert byKey('cmb-loading') findsOneWidget before gate.release() (combo_settings_test.dart:119-129).
3 (BKG-010/011): booking_rules_dialog.dart:144 int.parse throws on 20+ digits. Add maxLength: 6 and use int.tryParse(v) ?? s![key].
4 (BKG-018 test): expect(width, 672); the dialog height ≤ 0.9 × the viewport height; a Scrollable sits inside BookingRulesDialog.
5 (BKG-016 test): an outside tap (tester.tapAt(Offset(8, 8))) closes it with no PUT.
6 (BKG-019 test): a persona without bookings.edit has no "Bookings" row in the settings rail.
7 nit (:515): iconSize IconSize.xs - 2 → IconSize.xs or a named constant.
