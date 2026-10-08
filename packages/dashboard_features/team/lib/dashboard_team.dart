/// The dashboard's team area: its pages ([teamRoutes]), its mock backend
/// ([registerTeamMocks]) and its i18n supplement, as [teamArea].
library;

import 'package:dashboard_core/dashboard_core.dart';

import 'src/mock/register.dart';
import 'src/routes.dart';

export 'src/mock/register.dart' show registerTeamMocks;
export 'src/routes.dart' show teamRoutes;

/// The team area as the shell mounts it.
const DashArea teamArea = DashArea(
  key: 'team',
  routes: teamRoutes,
  registerMocks: registerTeamMocks,
  i18nSupplements: [
    'packages/dashboard_team/assets/i18n/en.json',
    'packages/dashboard_team/assets/i18n/ar.json',
  ],
);
