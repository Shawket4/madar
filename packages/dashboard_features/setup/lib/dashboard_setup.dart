/// The dashboard's setup area: its pages ([setupRoutes]), its mock backend
/// ([registerSetupMocks]) and its i18n supplement, as [setupArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerSetupMocks;
export 'src/routes.dart' show setupRoutes;

/// The setup area as the shell mounts it.
const DashArea setupArea = DashArea(
  key: 'setup',
  routes: setupRoutes,
  registerMocks: registerSetupMocks,
  i18nSupplements: [
    'packages/dashboard_setup/assets/i18n/en.json',
    'packages/dashboard_setup/assets/i18n/ar.json',
  ],
);
