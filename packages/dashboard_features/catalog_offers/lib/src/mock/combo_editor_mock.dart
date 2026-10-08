/// The combo editor's mock backend (`/menu/combos/:comboId`):
/// `GET /combos/{id}`, `POST /combos`, `PUT /combos/{id}`,
/// `POST /combos/economics` and `POST /uploads/menu-items/{id}`. The pick
/// lists and the delete are the area's shared handlers (`shared_mocks.dart`);
/// a combo's JSON and its economics come from `offers_rules.dart`
/// (`comboJson`, `analyseCombo`).
library;

import 'package:dashboard_api/mock.dart';

void registerComboEditorMocks(MockServer server, MockDb db) {}
