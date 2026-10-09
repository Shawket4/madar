# Catalog offers / Deals (`/menu/deals`): differences from the web

One line per difference: what the web does, what Flutter does, why. Rows marked "question" port
the web's behaviour as it is and ask the owner whether it is intended.

| Row | Web | Flutter | Why |
|---|---|---|---|
| OFFR-DEA-046, 049 second deal | A new deal whose own POST succeeded but whose branch call then failed keeps the dialog open as "New deal"; pressing "Create deal" again POSTs a second, duplicate deal. | After a partial failure the dialog adopts the created deal: the next press PUTs it (and resends the branch calls), so there is never a second deal. Nothing is refreshed on the failure itself, as on the web. | A duplicate deal is a web bug (SPEC 6.3). Pinned by `deal_dialog_test` "OFFR-DEA-046 (divergence)…". |
| OFFR-DEA-023 dropped row | When the open deal leaves the list (deleted elsewhere, a `resync`), `dialogOpen` turns false without `onOpenChange`, so `?edit=<id>` stays in the address (`deals-page.tsx:46`). | The dialog closes and `?edit` is removed, as for any other close. | A stale `?edit` misleads a shared link and reopens nothing; same choice as the Discounts unit. Pinned by `deals_page_test` "OFFR-DEA-023 (divergence)…". |
| OFFR-DEA-002, OFFR-ALL-018 rights loading | Before `/authz/me` answers (first sign-in, nothing remembered) the page shows "No deals yet" with no New deal, then the real page. | The shell's route gate shows nothing until the rights are known (shell divergence SH-10). | Shell-wide rule; never shows an empty state that is not true. |
| OFFR-DEA-024 height | `max-h-[92vh]`, scrolling inside. | The kit dialog fits the window less its margin and scrolls inside; a phone gets the full-screen sheet. | Kit (`showDashDialog`). |
| OFFR-DEA-033 question: item order | The item picker sorts by `localeCompare(name, lang)`. | The area's shared pick list (`menu_options.dart`) sorts by code point, so a few Arabic names starting with alef-madda (آيس…) sort first. | Shared file, not this unit's; reported for the area. |
| OFFR-DEA-010 question: Arabic dates | A window's raw `YYYY-MM-DD` dates inside Arabic running text are reordered by the Unicode bidi rules (after Arabic letters the digits become Arabic numbers and the hyphens split them), so 2026-06-01 shows as 01-06-2026. | Same rendering (the same bidi algorithm). | Identical to the web; it reads as a day-month-year date. Owner question whether the summary should isolate or format its dates. |
