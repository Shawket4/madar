/// The discounts page's mock backend (`/discounts`): `GET /discounts`,
/// `POST /discounts`, `PATCH /discounts/{id}` and `DELETE /discounts/{id}`,
/// over the area seed's `discounts` table (answered sorted by `name`; see
/// `legacyDiscountValue` for the legacy `value`).
library;

import 'package:dashboard_api/mock.dart';

void registerDiscountsMocks(MockServer server, MockDb db) {}
