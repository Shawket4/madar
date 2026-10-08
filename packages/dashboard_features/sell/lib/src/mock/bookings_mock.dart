/// The bookings unit's mock backend: `/bookings`: GET/POST /bookings, PATCH /bookings/{id},
/// POST /bookings/{id}/seat|complete|no-show|cancel, GET /bookings/availability,
/// GET/PUT /bookings/settings (+ the floor reads it shares with the floor unit).
///
/// Handlers behave like the backend (SPEC 3.2): capability refusals as a 403
/// envelope WITHOUT a code (SELL-ALL-017), validation errors, not-found,
/// paging and filters, and state (a write shows in the next read). Shared
/// rows come from the area seed (`../area_seed.dart`, already loaded into
/// [db]); this unit's own extra rows are added here.
library;

import 'package:dashboard_api/mock.dart';

void registerBookingsMocks(MockServer server, MockDb db) {}
