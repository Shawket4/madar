// The recipe builder's tests drive it through the real shell, inside the
// two dialogs that host it on the web (`addon-recipe-dialog.tsx`: standalone,
// one size, "New ingredient", its own Save; `menu-item-dialog.tsx`: deferred,
// the item's sizes, no "New ingredient"). Those dialogs are the items unit's;
// these hosts reproduce just how they wire the builder, over the mock
// backend, on a blank page of the area.
import 'dart:async';

import 'package:dashboard_api/dashboard_api.dart'
    show AddonIngredient, ApiException;
import 'package:dashboard_api/mock.dart';
import 'package:dashboard_catalog_menu/dashboard_catalog_menu.dart';
import 'package:dashboard_catalog_menu/src/area_seed.dart';
import 'package:dashboard_catalog_menu/src/shared/menu_providers.dart';
import 'package:dashboard_catalog_menu/src/shared/menu_text.dart';
import 'package:dashboard_core/dashboard_core.dart';
import 'package:dashboard_core/testing.dart';
import 'package:dashboard_kit/dashboard_kit.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The blank page the dialogs open over.
const String recipeHostPath = '/menu/recipe-builder-host';

class RecipeHostPage extends ConsumerWidget {
  const RecipeHostPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    return DashPageScaffold(
      title: t('recipes.title'),
      subtitle: t('recipes.subtitle'),
      body: const SizedBox.shrink(),
    );
  }
}

Widget _hostPage(BuildContext context, GoRouterState state) =>
    const RecipeHostPage();

/// The area plus the blank host page (same key, so the same words and
/// screenshot folder).
final DashArea recipeHostArea = DashArea(
  key: catalogMenuArea.key,
  routes: [
    ...catalogMenuRoutes,
    DashRoute(
      path: recipeHostPath,
      builder: _hostPage,
      titleKey: 'recipes.title',
      module: OrgModule.pos,
    ),
  ],
  registerMocks: catalogMenuArea.registerMocks,
  i18nSupplements: catalogMenuArea.i18nSupplements,
);

Future<DashHarness> pumpRecipeHost(
  WidgetTester tester, {
  Persona persona = Persona.owner,
  DashSize size = DashSize.desktop,
  String locale = 'en',
  bool dark = false,
}) => DashHarness.pump(
  tester,
  areas: [recipeHostArea],
  path: recipeHostPath,
  persona: persona,
  size: size,
  locale: locale,
  dark: dark,
);

/// Opens [builder]'s surface as the hosts do (`sm:max-w-2xl`; full screen on
/// a phone) and settles.
Future<void> openHostDialog(DashHarness h, WidgetBuilder builder) async {
  unawaited(
    showDashDialog<void>(
      h.tester.element(find.byType(RecipeHostPage)),
      width: DashMetrics.dialogWide,
      builder: builder,
    ),
  );
  await h.settle();
}

String get sabahOrg => SeedIds.sabahOrg;

/// The seeded Extras group's options (add-ons).
String extrasOption(String key) => MenuSeedIds.option('extras', key);

/// `GET /recipes/addons/{id}` as the add-on recipe dialog reads it.
final addonLinesProvider = FutureProvider.autoDispose
    .family<List<AddonIngredient>, String>(
      (ref, id) =>
          ref.watch(apiProvider).recipes.listAddonIngredients(addonItemId: id),
    );

/// What the standalone host's Save received.
class SaveLog {
  final List<(List<CleanRow>, List<RemovedRow>)> calls = [];

  /// When set, the next save waits for it.
  Completer<void>? hold;

  /// When set, the next save fails with it (the host toasts and rethrows).
  ApiException? failWith;
}

/// The add-on recipe dialog's wiring: the add-on's lines and the catalog
/// load, then one `one_size` column, margin against the default price,
/// "New ingredient" on, its own Save.
class AddonRecipeHost extends ConsumerWidget {
  const AddonRecipeHost({
    required this.addonId,
    required this.addonName,
    required this.defaultPrice,
    required this.log,
    this.closeOnSave = true,
    super.key,
  });

  /// The web's dialog closes after a save; off, the builder stays to show
  /// its new baseline.
  final bool closeOnSave;
  final String addonId;
  final String addonName;
  final int? defaultPrice;
  final SaveLog log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final catalog =
        ref.watch(ingredientCatalogProvider(sabahOrg)).value ?? const [];
    final lines = ref.watch(addonLinesProvider(addonId));
    return DashSurface(
      title: t('menu.addonRecipe.title'),
      description: '$addonName — ${t('menu.addonRecipe.desc')}',
      body: lines.isLoading
          ? const Center(child: MadarSpinner())
          : RecipeBuilder(
              orgId: sabahOrg,
              sizes: const [oneSize],
              initialRows: [
                for (final r in lines.value ?? const <AddonIngredient>[])
                  RecipeRowInit(
                    sizeLabel: oneSize,
                    orgIngredientId: r.orgIngredientId,
                    ingredientName: r.ingredientName,
                    ingredientUnit: r.unit,
                    quantityUsed: r.quantityUsed,
                  ),
              ],
              catalog: catalog,
              priceForSize: (_) => defaultPrice,
              onSave: (rows, removed) async {
                log.calls.add((rows, removed));
                final hold = log.hold;
                if (hold != null) await hold.future;
                final fail = log.failWith;
                if (fail != null) {
                  if (context.mounted) {
                    DashToast.error(context, fail.message);
                  }
                  throw fail;
                }
                if (context.mounted) {
                  DashToast.success(context, t('recipes.builder.saved'));
                  if (closeOnSave) Navigator.of(context).pop();
                }
              },
            ),
    );
  }
}

/// What the deferred host has been handed.
class RowsLog {
  final List<List<CleanRow>> updates = [];
  List<CleanRow> get last => updates.last;
}

/// The item dialog's recipe section: the item's sizes, the rows streamed to
/// the dialog, no "New ingredient", no footer; the size's price, else the
/// lowest.
class ItemRecipeHost extends ConsumerWidget {
  const ItemRecipeHost({
    required this.sizes,
    required this.prices,
    required this.initialRows,
    required this.log,
    super.key,
  });

  final List<String> sizes;

  /// Piastres by size label.
  final Map<String, int> prices;
  final ValueListenable<List<RecipeRowInit>> initialRows;
  final RowsLog log;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tProvider);
    final c = context.madarColors;
    final catalog =
        ref.watch(ingredientCatalogProvider(sabahOrg)).value ?? const [];
    int? priceForSize(String size) {
      final exact = prices[size];
      if (exact != null) return exact;
      return prices.values.isEmpty
          ? null
          : prices.values.reduce((a, b) => a < b ? a : b);
    }

    return DashSurface(
      title: t('menu.editItem'),
      description: t('menu.itemDesc'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Space.md,
        children: [
          Wrap(
            spacing: Space.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                t('menu.recipe'),
                style: DashType.bodyStrong.copyWith(color: c.textPrimary),
              ),
              Text(
                t('menu.recipeHint'),
                style: DashType.small.copyWith(color: c.textSecondary),
              ),
            ],
          ),
          ValueListenableBuilder(
            valueListenable: initialRows,
            builder: (context, rows, _) => RecipeBuilder(
              orgId: sabahOrg,
              sizes: sizes,
              initialRows: rows,
              catalog: catalog,
              priceForSize: priceForSize,
              deferred: true,
              onRowsChange: log.updates.add,
              allowCreateIngredient: false,
            ),
          ),
        ],
      ),
      actions: [
        DashButton(
          label: t('common.cancel'),
          variant: DashButtonVariant.outline,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// A Caffè Latte's recipe as the item dialog seeds it (base espresso + its
/// own milk), Regular and Large.
List<RecipeRowInit> latteRows() => [
  RecipeRowInit(
    sizeLabel: 'Regular',
    orgIngredientId: MenuSeedIds.ingredient('house_blend'),
    ingredientName: 'House espresso blend',
    ingredientUnit: 'g',
    quantityUsed: 18,
  ),
  RecipeRowInit(
    sizeLabel: 'Regular',
    orgIngredientId: MenuSeedIds.ingredient('full_milk'),
    ingredientName: 'Full cream milk',
    ingredientUnit: 'ml',
    quantityUsed: 180,
  ),
  RecipeRowInit(
    sizeLabel: 'Large',
    orgIngredientId: MenuSeedIds.ingredient('house_blend'),
    ingredientName: 'House espresso blend',
    ingredientUnit: 'g',
    quantityUsed: 27,
  ),
  RecipeRowInit(
    sizeLabel: 'Large',
    orgIngredientId: MenuSeedIds.ingredient('full_milk'),
    ingredientName: 'Full cream milk',
    ingredientUnit: 'ml',
    quantityUsed: 240,
  ),
];

/// The latte's prices (piastres).
const Map<String, int> lattePrices = {'Regular': 11500, 'Large': 13500};

/// Opens the add-on recipe host for the Extras group's "Extra shot"
/// (18 g of the house blend, sold at EGP 30).
Future<SaveLog> openExtraShot(
  DashHarness h, {
  SaveLog? log,
  bool closeOnSave = true,
}) async {
  final l = log ?? SaveLog();
  await openHostDialog(
    h,
    (_) => AddonRecipeHost(
      addonId: extrasOption('shot'),
      addonName: 'Extra shot',
      defaultPrice: 3000,
      log: l,
      closeOnSave: closeOnSave,
    ),
  );
  return l;
}

/// Opens the item host with the latte (or [rows]) and returns its log.
Future<(RowsLog, ValueNotifier<List<RecipeRowInit>>)> openLatte(
  DashHarness h, {
  List<String> sizes = const ['Regular', 'Large'],
  Map<String, int> prices = lattePrices,
  List<RecipeRowInit>? rows,
}) async {
  final log = RowsLog();
  final initial = ValueNotifier<List<RecipeRowInit>>(rows ?? latteRows());
  addTearDown(initial.dispose);
  await openHostDialog(
    h,
    (_) => ItemRecipeHost(
      sizes: sizes,
      prices: prices,
      initialRows: initial,
      log: log,
    ),
  );
  return (log, initial);
}

/// The quantity box of [ingredient] in [size] (its accessible name).
Finder qtyBox(DashHarness h, String ingredient, String size) =>
    find.bySemanticsLabel(
      h.t(
        'modeling.grid.cellAria',
        args: {'ingredient': ingredient, 'size': size},
      ),
    );

/// The ingredient picker showing [label] (a picked ingredient, or the
/// placeholder).
Finder ingredientPicker(DashHarness h, String label) =>
    find.bySemanticsLabel('${h.t('recipes.ingredient')}: $label');

/// The section of [size] (its card).
Finder sizeSection(int index) => find.byKey(ValueKey('recipe-size-$index'));
