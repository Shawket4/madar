# admin/orgs: verifier findings (1 major, minors)
1 MAJOR (ORG-019/020): at 1024×768 the Edit and Delete icons are off-screen (the column floors sum to 816 + padding, against ~718 free). Set minWidth near the web's content widths in orgs_page.dart (Name 180, Currency 96, Tax 104, Custom branding 130, Status 104). Add a tablet test that the Delete icon is hitTestable at 1024×768, and re-shoot.
2 minor (ORG-003): the page reads GET /orgs via its own orgsListProvider while the shell picker uses core orgsProvider (dashboard_core scope.dart:173); the web shares one cache entry. Use core's orgsProvider on the page (or have orgsListProvider forward to it) so there's one entry, and keep the route prefetch warming that same provider. Mutations invalidate it once.
3 minor: fix the stale header comment in orgs_page.dart (lines 5-6: it says "No route guard"; the route is platformOnly).
4 minor (divergences; reply with rows): label row 004 "shell contract / question"; log row 040 English (Flutter strips the "Conflict: " prefix the web shows); log row 058 (the web never re-fills the open dialog; Flutter re-fills until edited, per the owner rule).
5 minor tests: use h.refusalWords instead of hand-copied sentences (provision_wizard_test 040/039, orgs_page_test 015, org_dialog_test 055).
6 minor tests: the wizard's Create refreshes /orgs when the wizard closed mid-request; warming on the Edit pencil and Export (publicBrandProvider); the 015 Retry test asserts exactly one more call to that read.
(7, the Arabic LTR placeholder, is a kit fix already in kit batch 1.)
