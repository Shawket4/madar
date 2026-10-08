/// The offers catalogue area's pages (`/menu/combos`, `/menu/combos/:comboId`,
/// `/menu/deals`, `/discounts`), module `pos`. Nav visibility is the
/// generated nav's (Combos and Deals: `menu.items.read`; Discounts:
/// `discounts.read`); [DashRoute.caps] here is the PAGE gate, as each web
/// page runs it:
///
/// - `/menu/combos` and `/menu/combos/:comboId` gate themselves
///   (`OffersPageGate`): the list's Restricted body is account-specific
///   (`combos.noAccess`) and the editor's title is "New combo" on `new`,
///   which the shell's gate cannot word;
/// - `/menu/deals`: `menu.items.read`, the default Restricted ("Deals");
/// - `/discounts`: no page gate at all (OFFR-DSC-003; the server refuses).
///
/// The editor is its own route, not a child of the list (the web un-nests it,
/// `combos_.$comboId`), so opening a combo never builds the list under it.
library;

import 'package:dashboard_core/dashboard_core.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'combo_editor/combo_editor_page.dart';
import 'combos/combos_page.dart';
import 'deals/deals_page.dart';
import 'discounts/discounts_page.dart';

const List<DashRoute> catalogOffersRoutes = [
  DashRoute(
    path: '/menu/combos',
    builder: _combos,
    titleKey: 'combos.title',
    titleFallback: 'Combos',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/menu/combos/:comboId',
    builder: _comboEditor,
    titleKey: 'combos.title',
    titleFallback: 'Combos',
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/menu/deals',
    builder: _deals,
    titleKey: 'deals.title',
    titleFallback: 'Deals',
    caps: [Cap.menuItemsRead],
    module: OrgModule.pos,
  ),
  DashRoute(
    path: '/discounts',
    builder: _discounts,
    titleKey: 'discounts.title',
    titleFallback: 'Discounts',
    module: OrgModule.pos,
  ),
];

Widget _combos(BuildContext context, GoRouterState state) => const CombosPage();

Widget _comboEditor(BuildContext context, GoRouterState state) =>
    ComboEditorPage(comboId: state.pathParameters['comboId'] ?? 'new');

Widget _deals(BuildContext context, GoRouterState state) =>
    DealsPage(edit: state.uri.queryParameters['edit']);

Widget _discounts(BuildContext context, GoRouterState state) =>
    DiscountsPage(edit: state.uri.queryParameters['edit']);
