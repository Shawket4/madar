# setup/brand_appearance + whatsapp: AT PARITY, minors
1 (SET-BRD-009): the web fixed its image-uploader error (getErrorMessage), so delete the SET-BRD-009 divergence row (reply) and drop "(divergence)" from the test name (test/brand_appearance/brand_test.dart:242).
2 (SET-SHL-006): DashOption.group now exists in the kit. Pass the settings group labels in the phone picker (settings_shell.dart:89-107), and update the kit-divergence row.
3 (intent): give /settings/brand a prefetch warming orgBrandProvider(s.orgId!) when an org is in scope, and /settings/whatsapp one warming whatsappStatusProvider (platform admins only), in setup lib/src/routes.dart (your two entries only). Log them as intent beyond the web, and add a hover-Brand case to the SET-SHL-013 test.
4 (SET-SHL-014): add booking.*, branch.settings_changed and resync to the live-update test (on a Bookings pane and on a pane that reads /branches).
5 (SET-APP-003): _GlyphSegments height → DashMetrics.control - 2 * DashMetrics.ring; wrap it in Semantics(container: true, label: t('settings.themeHint')).
6 (SET-BRD-021): apps/dashboard/lib/real/files.dart:103: drop gif from the image picker's types (the web offers png/jpeg/webp).
