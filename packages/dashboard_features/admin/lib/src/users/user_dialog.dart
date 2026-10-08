/// The user editor (ADM-USR-020..032, 053, 054; web `features/users/user-dialog.tsx`).
///
/// CROSS-UNIT CONTRACT: the onboarding wizard's team step (ADM-ONB-020)
/// opens this same dialog in create mode, so keep [showUserDialog]'s
/// signature stable. The users builder owns this file and fills it in.
library;

import 'package:dashboard_api/dashboard_api.dart' show UserPublic;
import 'package:flutter/widgets.dart';

/// Opens the user dialog: [user] null = "New User" (create), else "Edit
/// User". Resolves true when a user was created or saved, false when the
/// dialog closed without one.
Future<bool> showUserDialog(BuildContext context, {UserPublic? user}) async {
  // Scaffold: the users unit replaces this with the real dialog.
  return false;
}
