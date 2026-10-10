# Team / Set-up: differences from the web

`/staff/setup` (the four steps, the branch pins, the dialogs it opens, the set-up nav leaf).
Web: `MadarDashboard` `main` @ v1.4.18. One row per difference; tests pinning a fix are named
`'<ROW> …'` in `packages/dashboard_features/team/test/team_setup/`.

| Row | Web | Flutter | Why |
|---|---|---|---|
| TEAM-SET-016 / 017 | "Use my location" asks the browser (`navigator.geolocation`, high accuracy, 15 s, no cached fix). | Asks a `SetupLocator` (`setup_location.dart`) with the same options. No location plugin ships with the dashboard, so the default locator answers "can't read its location" (`dawam.pinNoGeo`) and the owner pastes a link; the app installs a real reader with `setupLocatorProvider.notifier.use(...)`. | Question: needs a location dependency (e.g. `geolocator`) in `apps/dashboard`; the words still say "browser" (the web's). |
| TEAM-SET-023 | The pin editor copies the branch once (`useState(saved)`); a refresh that brings a newer pin leaves the old one in the editor, and Save would put it back. | The editor re-seeds from a refreshed branch until the person touches it (paste, locate, radius); after a save it follows the server again. | A form that copied old data once would save it over newer data (brief: re-seed rule). |
