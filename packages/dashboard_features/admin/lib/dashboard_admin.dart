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
    'packages/dashboard_admin/assets/i18n/en.json',
    'packages/dashboard_admin/assets/i18n/ar.json',
  ],
);
