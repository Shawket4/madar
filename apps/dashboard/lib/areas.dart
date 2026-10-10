/// Every feature area the dashboard is built from, in nav order, and the
/// sheets and dialogs one area opens from another ([dashboardOpeners]).
library;

import 'package:dashboard_admin/dashboard_admin.dart';
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_catalog_offers/dashboard_catalog_offers.dart';
import 'package:dashboard_core/dashboard_core.dart' show AreaOpeners, DashArea;
import 'package:dashboard_inventory/dashboard_inventory.dart';
import 'package:dashboard_overview/dashboard_overview.dart';
import 'package:dashboard_reports/dashboard_reports.dart';
import 'package:dashboard_sell/dashboard_sell.dart';
import 'package:dashboard_setup/dashboard_setup.dart';
import 'package:dashboard_team/dashboard_team.dart';

const List<DashArea> dashboardAreas = [
  overviewArea,
  sellArea,
  catalogMenuArea,
  catalogOffersArea,
  reportsArea,
  inventoryArea,
  teamArea,
  setupArea,
  adminArea,
];

/// The real cross-area sheets and dialogs, for pages whose package cannot
/// depend on the area that owns them (reports, setup and admin opening sell's
/// customer and order sheets and team's Add employee dialog).
const AreaOpeners dashboardOpeners = AreaOpeners(
  customerSheet: customerSheetOpener,
  orderSheet: orderSheetOpener,
  addEmployee: addEmployeeOpener,
);
