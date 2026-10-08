/// The dashboard's admin area: its pages ([adminRoutes]), its mock backend
/// ([registerAdminMocks]) and its i18n supplement, as [adminArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerAdminMocks;
export 'src/routes.dart' show adminRoutes;

/// The admin area as the shell mounts it.
const DashArea adminArea = DashArea(
  key: 'admin',
  routes: adminRoutes,
  registerMocks: registerAdminMocks,
  i18nSupplements: [
    // Shared by the area's units (lib/src/shared).
    'packages/dashboard_admin/assets/i18n/en.json',
    'packages/dashboard_admin/assets/i18n/ar.json',
    // One pair per unit, so builders never share a file.
    'packages/dashboard_admin/assets/i18n/orgs.en.json',
    'packages/dashboard_admin/assets/i18n/orgs.ar.json',
    'packages/dashboard_admin/assets/i18n/users.en.json',
    'packages/dashboard_admin/assets/i18n/users.ar.json',
    'packages/dashboard_admin/assets/i18n/branches.en.json',
    'packages/dashboard_admin/assets/i18n/branches.ar.json',
    'packages/dashboard_admin/assets/i18n/onboarding.en.json',
    'packages/dashboard_admin/assets/i18n/onboarding.ar.json',
    'packages/dashboard_admin/assets/i18n/devices.en.json',
    'packages/dashboard_admin/assets/i18n/devices.ar.json',
    'packages/dashboard_admin/assets/i18n/roles.en.json',
    'packages/dashboard_admin/assets/i18n/roles.ar.json',
    'packages/dashboard_admin/assets/i18n/review.en.json',
    'packages/dashboard_admin/assets/i18n/review.ar.json',
  ],
);
