/// Users ▸ Make employee (ADM-USR-014): the row action opens the TEAM
/// area's Add employee dialog preset to link the person (web
/// `AddEmployeeDialog userId=…`, `features/dawam/add-employees.tsx`).
///
/// The admin package cannot depend on dashboard_team, so the app, which
/// composes both, hands the dialog in: at start-up it sets
/// `makeEmployeeLauncher = (context, userId) =>
/// showAddEmployeeDialog(context, userId: userId);`. Until it does, the row
/// action does not show (never a button that does nothing).
library;

import 'package:flutter/widgets.dart';

/// Opens the Add employee dialog for the Madar user [userId]; resolves when
/// it closes.
typedef MakeEmployeeLauncher =
    Future<void> Function(BuildContext context, String userId);

/// Set by the app shell (see the library comment); null hides the action.
MakeEmployeeLauncher? makeEmployeeLauncher;
