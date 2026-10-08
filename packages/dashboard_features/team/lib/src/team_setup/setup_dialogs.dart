/// The dialogs Set-up mounts over its steps (TEAM-SET-036…038): Add employee
/// and Import from a spreadsheet (step 2, the Employees unit's dialogs) and
/// the Work shift dialog for a new block (step 3, the Work shifts unit's).
/// After a create the checklist refetches (`/staff` is invalidated by the
/// dialog), so "n of 4" and the tick update live.
library;

import 'package:dashboard_api/dashboard_api.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Step 2 "Add employee".
Future<void> openSetupAddEmployee(BuildContext context, WidgetRef ref) async {}

/// Step 2 "Import from a spreadsheet".
Future<void> openSetupImportPeople(BuildContext context, WidgetRef ref) async {}

/// Step 3 "New shift": a new block; "Every branch" only with the right at
/// every branch, else the block starts at the first branch.
Future<void> openSetupNewShift(
  BuildContext context,
  WidgetRef ref, {
  required List<Branch> branches,
  required bool wholeBusiness,
}) async {}
