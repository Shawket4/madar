# admin/devices: verifier findings (1 major, 2 minor)
1 MAJOR (DEV-004/009/015/017/025): at tablet width (1024; content ~720 px) the column floors add up to more than the width, so the table scrolls and hides Last seen, the Edit pencil and "Withdraw"; Name/App/pill are cut.
- devices_table.dart: drop Code's flex: 2 and set minWidth ~72 (the Wrap lets the pill drop under). Type/Status ~88–96, Name ~96, App ~110, Last seen ~160–180 (or let the stamp wrap). The total must fit 720.
- activation_codes.dart: same floors, and a rowActionsWidth just wide enough for "Withdraw".
- client_versions.dart: Device and Last legacy hit floors 200 → ~140.
- Add a DashSize.tablet test: the pencil, "Withdraw" and the Last seen header are hitTestable() without scrolling. Re-shoot at tablet and check.
2 minor (DEV-012 test): assert the refusal with h.refusalWords(MockResponse.conflict('Another device at this branch uses that code', code: 'DEVICE_CODE_TAKEN')) (or the file's wordsFor), not a hand-copied sentence behind exists().
3 minor (DEV-008/016 tests): while the gate is held, assert find.byType(DashSkeleton) findsWidgets.
