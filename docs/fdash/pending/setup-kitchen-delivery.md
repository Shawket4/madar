# setup/kitchen + setup/delivery: both AT PARITY; minor fixes
## kitchen
1 (KST-008/SHL-021): log in setup-kitchen.md (reply with the row): the web makes a column searchable only if the first row's value is a string, so "epson" finds nothing when the first station has no printer; Flutter always searches the printer model.
## delivery
2 (DLV-015/021): watch deliveryDiscountsProvider(orgId) at the top of _DeliverySettingsFormState.build (not only inside _discountField under ch.enabled), so GET /discounts runs alongside settings as on the web (settings-page.tsx:41). Test: an all-off branch asks GET /discounts once on mount.
3 (DZN-017/018/019): zone_dialog.dart _save returns on !mounted before both toasts. Pass the page context as `host` (as station_dialog.dart does) and toast on mounted ? context : host.
4 (SHL-018): Enter in zone km/fee and the delivery fee/distance/prep fields doesn't submit (kit DashNumberField has no onSubmitted). Log a kit divergence row (reply) and list the kit candidate; wire it if the kit gains onSubmitted.
5 (DZN-008): the Status pill should be the default size (drop small: true; web zones-page.tsx:139-145).
