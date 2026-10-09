/// The Work shift dialog Set-up mounts over step 3 (TEAM-SET-038), for a new
/// block. Steps 2's dialogs are the Employees unit's (`showAddEmployeeDialog`,
/// `showImportPeopleDialog`), called straight from the page.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Step 3 "New shift": a new block; "Every branch" only with the right at
/// every branch, else the block starts at the first branch.
Future<void> openSetupNewShift(
  BuildContext context,
  WidgetRef ref, {
  required List<Branch> branches,
  required bool wholeBusiness,
}) async {}
