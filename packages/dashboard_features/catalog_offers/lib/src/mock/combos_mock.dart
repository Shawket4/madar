/// The combos list's mock backend (`/menu/combos`): `GET /combos`
/// (`q`, `category_id`, `is_active`, `page`, `per_page`) and
/// `GET /assets/jobs/{id}`. The categories and the menu-item delete are the
/// area's shared handlers (`shared_mocks.dart`); summaries come from
/// `offers_rules.dart` (`comboRows`, `comboSummaryJson`).
library;

import 'package:dashboard_api/mock.dart';

void registerCombosMocks(MockServer server, MockDb db) {}
