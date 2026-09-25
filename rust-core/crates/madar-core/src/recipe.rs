//! Local recipe preview — the effective ingredient list for a configured item.
//!
//! Ports the Flutter teller app's `computeRecipeLocally` (recipe_api.dart) into
//! the core so the customization sheet can show, live and offline, how the
//! selected size / addons / optionals change the drink's ingredients:
//!   1. base recipe rows for the chosen size (size-agnostic rows always apply),
//!   2. SWAPS — an option of a swap family (milk, beans, any explicit `swaps`
//!      group) replaces the base line of its category in place (inheriting the
//!      base quantity), unless it is the recipe's own choice — the shared
//!      pricing rule's decision (madar-catalog), so the preview shows the cup
//!      the line is charged for,
//!   3. additive addons — every other addon adds its ingredients × selected qty,
//!   4. optional fields that carry an ingredient deduction add their line.
//!
//! Pure (item + catalog + selection in, view rows out) so it's unit-testable
//! without a store or network, and cheap enough to recompute on every toggle.
//! Lines are NOT merged by ingredient — the sheet groups them by source tag.

use crate::cart::AddonSelection;
use crate::catalog_pricing::PricingMirror;
use crate::menu::{AddonItemView, MenuItemView, RecipeLineView};

/// One effective ingredient line, tagged by origin so the sheet can chip it.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct ComputedRecipeLineView {
    pub ingredient_name: String,
    pub unit: String,
    pub quantity: f64,
    /// Display tag: `"base"`, `"addon"`, the swap addon's name, or the optional
    /// field's name — the sheet renders this (uppercased) as a chip.
    pub source_label: String,
    /// True for base drink-recipe lines (the sheet tones these as the accent).
    pub is_base: bool,
}

// Internal working row — carries the matching key (category) the swap step
// needs but the host view omits.
#[derive(Clone)]
struct Row {
    name: String,
    unit: String,
    quantity: f64,
    category: String,
    is_base: bool,
    /// `None` for base rows; `Some(label)` once an addon/optional sets the tag.
    source_label: Option<String>,
}

/// Compute the effective recipe for `item` given the chosen `size_label`,
/// `addons` (id + qty) and `optional_ids`. Which option swaps what, into
/// which ingredient, is the shared pricing rule's decision (madar-catalog, the
/// server's): the preview shows the cup the line is charged for.
/// `addon_catalog` supplies the additive options' ingredient quantities.
pub(crate) fn compute_recipe(
    item: &MenuItemView,
    addon_catalog: &[AddonItemView],
    pricing: &PricingMirror,
    size_label: Option<&str>,
    addons: &[AddonSelection],
    optional_ids: &[String],
) -> Vec<ComputedRecipeLineView> {
    let view = pricing.view_for(item, addon_catalog);

    // 1. Base rows for the recipe size: the chosen size, else the item's
    //    default recipe size (the server's). A row with no size_label applies
    //    to every size.
    let recipe_size = madar_catalog::recipe_size(&view.item, size_label);
    let base_rows: Vec<&RecipeLineView> = item
        .recipes
        .iter()
        .filter(|r| r.size_label.as_deref().is_none_or(|rs| rs == recipe_size))
        .collect();

    let mut rows: Vec<Row> = base_rows
        .iter()
        .map(|r| Row {
            name: r.ingredient_name.clone(),
            unit: r.unit.clone(),
            quantity: r.quantity,
            category: r.category.clone(),
            is_base: true,
            source_label: None,
        })
        .collect();

    // 2 + 3. The options as the rule charges them (one per swap family, the
    //        last pick): a swap replaces the base line of its category (unless
    //        it is the recipe's own choice); an add-on adds its ingredients.
    let selection = madar_catalog::Selection {
        size_label: size_label.map(str::to_string),
        options: addons
            .iter()
            .filter(|a| view.option(&a.addon_item_id).is_some())
            .map(|a| madar_catalog::Pick {
                id: a.addon_item_id.clone(),
                quantity: a.qty,
            })
            .collect(),
        optionals: Vec::new(),
    };
    let priced = madar_catalog::price_options(&view, &selection).unwrap_or_default();
    for p in &priced.options {
        let Some(addon) = addon_catalog.iter().find(|a| a.id == p.id) else {
            continue;
        };
        if let Some(target) = &p.target {
            // The recipe's own choice, or nothing to swap in: the cup is as
            // the recipe makes it.
            if let Some(repl) = p.replacement.as_ref().filter(|_| !p.is_base) {
                // Replace every base line of this category in place; a swapped
                // line inherits the base quantity (swaps never scale) and is
                // re-tagged with the addon's name (no longer the plain base).
                for r in rows
                    .iter_mut()
                    .filter(|r| r.is_base && r.category == target.slug)
                {
                    r.name = repl.name.clone();
                    r.unit = repl.unit.clone();
                    r.source_label = Some(addon.name.clone());
                    r.is_base = false;
                }
            }
            continue; // swap families never add a separate line
        }

        // Additive addon: append each ingredient, scaled by the selected qty.
        for ing in &addon.ingredients {
            rows.push(Row {
                name: ing.ingredient_name.clone(),
                unit: ing.unit.clone(),
                quantity: ing.quantity * p.quantity as f64,
                category: "general".into(),
                is_base: false,
                source_label: Some("addon".into()),
            });
        }
    }

    // 4. Optional fields that carry an ingredient deduction.
    for oid in optional_ids {
        let Some(f) = item.optional_fields.iter().find(|f| &f.id == oid) else {
            continue;
        };
        if let (Some(name), Some(unit), Some(qty)) = (
            f.ingredient_name.as_ref(),
            f.ingredient_unit.as_ref(),
            f.quantity_used,
        ) {
            rows.push(Row {
                name: name.clone(),
                unit: unit.clone(),
                quantity: qty,
                category: "general".into(),
                is_base: false,
                source_label: Some(f.name.clone()),
            });
        }
    }

    rows.into_iter()
        .map(|r| ComputedRecipeLineView {
            ingredient_name: r.name,
            unit: r.unit,
            quantity: r.quantity,
            source_label: r.source_label.unwrap_or_else(|| "base".into()),
            is_base: r.is_base,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::menu::{AddonIngredientView, ItemSizeView, OptionalFieldView};

    fn addon(id: &str, name: &str, atype: &str, ings: Vec<AddonIngredientView>) -> AddonItemView {
        AddonItemView {
            id: id.into(),
            name: name.into(),
            addon_type: atype.into(),
            default_price_minor: 0,
            is_active: true,
            ingredients: ings,
        }
    }

    fn ing(name: &str, unit: &str, qty: f64, org: Option<&str>) -> AddonIngredientView {
        AddonIngredientView {
            ingredient_name: name.into(),
            unit: unit.into(),
            quantity: qty,
            org_ingredient_id: org.map(String::from),
        }
    }

    fn recipe(
        name: &str,
        unit: &str,
        qty: f64,
        size: Option<&str>,
        cat: &str,
        org: Option<&str>,
    ) -> RecipeLineView {
        RecipeLineView {
            ingredient_name: name.into(),
            quantity: qty,
            unit: unit.into(),
            size_label: size.map(String::from),
            category: cat.into(),
            org_ingredient_id: org.map(String::from),
        }
    }

    fn item(recipes: Vec<RecipeLineView>, optionals: Vec<OptionalFieldView>) -> MenuItemView {
        MenuItemView {
            id: "item1".into(),
            name: "Latte".into(),
            description: None,
            category_id: None,
            base_price_minor: 5000,
            image_url: None,
            local_image_path: None,
            is_active: true,
            default_milk_addon_id: Some("milk_default".into()),
            allowed_addon_ids: vec![],
            sizes: vec![ItemSizeView {
                id: "s1".into(),
                label: "M".into(),
                price_minor: 5000,
                is_active: true,
            }],
            addon_slots: vec![],
            optional_fields: optionals,
            recipes,
            recipe_steps: vec![],
            kind: "item".into(),
        }
    }

    fn sel(id: &str, qty: i64) -> AddonSelection {
        AddonSelection {
            addon_item_id: id.into(),
            qty,
        }
    }

    #[test]
    fn base_recipe_filters_by_size_and_keeps_agnostic_rows() {
        let it = item(
            vec![
                recipe(
                    "Beans",
                    "g",
                    18.0,
                    Some("M"),
                    "coffee_bean",
                    Some("o-beans"),
                ),
                recipe(
                    "Beans",
                    "g",
                    24.0,
                    Some("L"),
                    "coffee_bean",
                    Some("o-beans"),
                ),
                recipe("Water", "ml", 30.0, None, "general", Some("o-water")),
            ],
            vec![],
        );
        let out = compute_recipe(
            &it,
            &[],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[],
            &[],
        );
        // M coffee row + size-agnostic water; the L row is excluded.
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].ingredient_name, "Beans");
        assert_eq!(out[0].quantity, 18.0);
        assert!(out[0].is_base);
        assert_eq!(out[1].ingredient_name, "Water");
    }

    #[test]
    fn milk_swap_replaces_base_line_inheriting_quantity() {
        let it = item(
            vec![recipe(
                "Whole milk",
                "ml",
                200.0,
                Some("M"),
                "milk",
                Some("o-whole"),
            )],
            vec![],
        );
        let oat = addon(
            "a-oat",
            "Oat Milk",
            "milk_type",
            vec![ing("Oat milk", "ml", 999.0, Some("o-oat"))],
        );
        let out = compute_recipe(
            &it,
            &[oat],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[sel("a-oat", 1)],
            &[],
        );
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].ingredient_name, "Oat milk");
        assert_eq!(
            out[0].quantity, 200.0,
            "swap inherits the base quantity, not the addon's"
        );
        assert_eq!(out[0].source_label, "Oat Milk");
        assert!(!out[0].is_base);
    }

    #[test]
    fn reselecting_default_milk_is_not_a_swap() {
        let it = item(
            vec![recipe(
                "Whole milk",
                "ml",
                200.0,
                Some("M"),
                "milk",
                Some("o-whole"),
            )],
            vec![],
        );
        // Same org-ingredient id as the base line → not a swap.
        let same = addon(
            "a-whole",
            "Whole Milk",
            "milk_type",
            vec![ing("Whole milk", "ml", 200.0, Some("o-whole"))],
        );
        let out = compute_recipe(
            &it,
            &[same],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[sel("a-whole", 1)],
            &[],
        );
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].ingredient_name, "Whole milk");
        assert!(out[0].is_base, "default re-selection stays a base line");
        assert_eq!(out[0].source_label, "base");
    }

    #[test]
    fn additive_addon_scales_by_quantity() {
        let it = item(
            vec![recipe(
                "Beans",
                "g",
                18.0,
                Some("M"),
                "coffee_bean",
                Some("o-beans"),
            )],
            vec![],
        );
        let syrup = addon(
            "a-syrup",
            "Caramel",
            "extra",
            vec![ing("Caramel syrup", "ml", 10.0, Some("o-car"))],
        );
        let out = compute_recipe(
            &it,
            &[syrup],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[sel("a-syrup", 2)],
            &[],
        );
        assert_eq!(out.len(), 2);
        assert_eq!(out[1].ingredient_name, "Caramel syrup");
        assert_eq!(out[1].quantity, 20.0, "10ml × 2");
        assert_eq!(out[1].source_label, "addon");
        assert!(!out[1].is_base);
    }

    #[test]
    fn optional_with_ingredient_adds_line_cosmetic_does_not() {
        let with_ing = OptionalFieldView {
            id: "opt-shot".into(),
            name: "Extra shot".into(),
            price_minor: 1500,
            is_active: true,
            ingredient_name: Some("Espresso".into()),
            ingredient_unit: Some("shot".into()),
            quantity_used: Some(1.0),
            org_ingredient_id: Some("o-esp".into()),
        };
        let cosmetic = OptionalFieldView {
            id: "opt-deco".into(),
            name: "Latte art".into(),
            price_minor: 0,
            is_active: true,
            ingredient_name: None,
            ingredient_unit: None,
            quantity_used: None,
            org_ingredient_id: None,
        };
        let it = item(
            vec![recipe("Beans", "g", 18.0, Some("M"), "coffee_bean", None)],
            vec![with_ing, cosmetic],
        );
        let out = compute_recipe(
            &it,
            &[],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[],
            &["opt-shot".into(), "opt-deco".into()],
        );
        assert_eq!(out.len(), 2, "cosmetic optional contributes no line");
        assert_eq!(out[1].ingredient_name, "Espresso");
        assert_eq!(out[1].quantity, 1.0);
        assert_eq!(out[1].source_label, "Extra shot");
    }

    #[test]
    fn swap_with_no_addon_ingredients_leaves_base_untouched() {
        let it = item(
            vec![recipe(
                "Whole milk",
                "ml",
                200.0,
                Some("M"),
                "milk",
                Some("o-whole"),
            )],
            vec![],
        );
        let empty = addon("a-x", "Mystery Milk", "milk_type", vec![]);
        let out = compute_recipe(
            &it,
            &[empty],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[sel("a-x", 1)],
            &[],
        );
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].ingredient_name, "Whole milk");
        assert!(out[0].is_base);
    }

    #[test]
    fn lines_are_not_merged_by_ingredient() {
        let it = item(
            vec![recipe(
                "Beans",
                "g",
                18.0,
                Some("M"),
                "coffee_bean",
                Some("o-beans"),
            )],
            vec![],
        );
        // Two additive shots of the same ingredient stay as two rows.
        let shot = addon(
            "a-shot",
            "Shot",
            "extra",
            vec![ing("Espresso", "ml", 30.0, Some("o-esp"))],
        );
        let out = compute_recipe(
            &it,
            &[shot.clone(), shot],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[sel("a-shot", 1), sel("a-shot", 1)],
            &[],
        );
        assert_eq!(out.len(), 3, "base + two separate addon rows, not merged");
    }

    // ── empty / trivial cases ───────────────────────────────────────────────

    #[test]
    fn empty_recipe_and_no_selection_yields_nothing() {
        let it = item(vec![], vec![]);
        let out = compute_recipe(
            &it,
            &[],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[],
            &[],
        );
        assert!(out.is_empty());
    }

    #[test]
    fn size_agnostic_only_recipe_ignores_size_selection() {
        // All rows are size-agnostic → they apply regardless of the chosen size.
        let it = item(
            vec![
                recipe("Water", "ml", 30.0, None, "general", Some("o-water")),
                recipe("Sugar", "g", 5.0, None, "general", Some("o-sugar")),
            ],
            vec![],
        );
        let m = compute_recipe(
            &it,
            &[],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[],
            &[],
        );
        let none = compute_recipe(
            &it,
            &[],
            &crate::catalog_pricing::PricingMirror::default(),
            None,
            &[],
            &[],
        );
        assert_eq!(m.len(), 2);
        assert_eq!(none.len(), 2); // no size chosen, still both agnostic rows
    }

    // ── target-size inference when no size is passed ────────────────────────

    #[test]
    fn no_size_selected_uses_first_concrete_size_present() {
        // size_label=None on the call: target_size is inferred from the first
        // recipe row that carries a size_label (here "M"). The "L" row is dropped.
        let it = item(
            vec![
                recipe(
                    "Beans",
                    "g",
                    18.0,
                    Some("M"),
                    "coffee_bean",
                    Some("o-beans"),
                ),
                recipe(
                    "Beans",
                    "g",
                    24.0,
                    Some("L"),
                    "coffee_bean",
                    Some("o-beans"),
                ),
                recipe("Water", "ml", 30.0, None, "general", Some("o-water")),
            ],
            vec![],
        );
        let out = compute_recipe(
            &it,
            &[],
            &crate::catalog_pricing::PricingMirror::default(),
            None,
            &[],
            &[],
        );
        assert_eq!(out.len(), 2); // M coffee + agnostic water
        assert_eq!(out[0].quantity, 18.0); // the M row, not L
    }

    #[test]
    fn unknown_selected_size_keeps_only_agnostic_rows() {
        // A size that matches no concrete row → size-specific rows all excluded,
        // only size-agnostic rows survive.
        let it = item(
            vec![
                recipe(
                    "Beans",
                    "g",
                    18.0,
                    Some("M"),
                    "coffee_bean",
                    Some("o-beans"),
                ),
                recipe("Water", "ml", 30.0, None, "general", Some("o-water")),
            ],
            vec![],
        );
        let out = compute_recipe(
            &it,
            &[],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("XL"),
            &[],
            &[],
        );
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].ingredient_name, "Water");
    }

    // ── coffee swaps ────────────────────────────────────────────────────────

    #[test]
    fn coffee_swap_replaces_coffee_bean_base_line() {
        let it = item(
            vec![recipe(
                "House Beans",
                "g",
                18.0,
                Some("M"),
                "coffee_bean",
                Some("o-house"),
            )],
            vec![],
        );
        let decaf = addon(
            "a-decaf",
            "Decaf",
            "coffee_type",
            vec![ing("Decaf beans", "g", 99.0, Some("o-decaf"))],
        );
        let out = compute_recipe(
            &it,
            &[decaf],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[sel("a-decaf", 1)],
            &[],
        );
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].ingredient_name, "Decaf beans");
        assert_eq!(out[0].quantity, 18.0, "swap inherits base qty");
        assert_eq!(out[0].source_label, "Decaf");
        assert!(!out[0].is_base);
    }

    #[test]
    fn milk_addon_with_no_matching_base_category_does_not_add_or_swap() {
        // The item has only a coffee_bean base line; a milk swap finds no `milk`
        // base row → has_base is false → nothing changes, milk adds no line.
        let it = item(
            vec![recipe(
                "Beans",
                "g",
                18.0,
                Some("M"),
                "coffee_bean",
                Some("o-beans"),
            )],
            vec![],
        );
        let oat = addon(
            "a-oat",
            "Oat",
            "milk_type",
            vec![ing("Oat milk", "ml", 200.0, Some("o-oat"))],
        );
        let out = compute_recipe(
            &it,
            &[oat],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[sel("a-oat", 1)],
            &[],
        );
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].ingredient_name, "Beans");
        assert!(out[0].is_base);
    }

    #[test]
    fn milk_swap_replaces_all_matching_base_lines() {
        // Two base milk lines of the same category → both get swapped in place.
        let it = item(
            vec![
                recipe("Whole milk", "ml", 150.0, None, "milk", Some("o-whole")),
                recipe("Whole milk", "ml", 50.0, None, "milk", Some("o-whole")),
            ],
            vec![],
        );
        let oat = addon(
            "a-oat",
            "Oat",
            "milk_type",
            vec![ing("Oat milk", "ml", 0.0, Some("o-oat"))],
        );
        let out = compute_recipe(
            &it,
            &[oat],
            &crate::catalog_pricing::PricingMirror::default(),
            None,
            &[sel("a-oat", 1)],
            &[],
        );
        assert_eq!(out.len(), 2);
        assert!(out.iter().all(|r| r.ingredient_name == "Oat milk"));
        assert_eq!(out[0].quantity, 150.0); // each keeps its own base qty
        assert_eq!(out[1].quantity, 50.0);
        assert!(out.iter().all(|r| !r.is_base && r.source_label == "Oat"));
    }

    #[test]
    fn swap_default_detection_requires_both_ids_present() {
        // Base line has NO org_ingredient_id; even if the addon ingredient has one,
        // is_default is false (the `_` arm), so this is treated as a real swap.
        let it = item(
            vec![recipe("Whole milk", "ml", 200.0, Some("M"), "milk", None)],
            vec![],
        );
        let oat = addon(
            "a-oat",
            "Oat",
            "milk_type",
            vec![ing("Oat milk", "ml", 0.0, Some("o-oat"))],
        );
        let out = compute_recipe(
            &it,
            &[oat],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[sel("a-oat", 1)],
            &[],
        );
        assert_eq!(out[0].ingredient_name, "Oat milk"); // swapped
        assert!(!out[0].is_base);
    }

    // ── unknown / missing references are skipped ────────────────────────────

    #[test]
    fn unknown_addon_id_is_skipped() {
        let it = item(
            vec![recipe(
                "Beans",
                "g",
                18.0,
                Some("M"),
                "coffee_bean",
                Some("o-beans"),
            )],
            vec![],
        );
        // Catalog is empty → the selection's addon can't be found → skipped.
        let out = compute_recipe(
            &it,
            &[],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[sel("ghost", 1)],
            &[],
        );
        assert_eq!(out.len(), 1);
        assert_eq!(out[0].ingredient_name, "Beans");
    }

    #[test]
    fn unknown_optional_id_is_skipped() {
        let it = item(
            vec![recipe("Beans", "g", 18.0, Some("M"), "coffee_bean", None)],
            vec![],
        );
        let out = compute_recipe(
            &it,
            &[],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[],
            &["no-such-optional".into()],
        );
        assert_eq!(out.len(), 1);
    }

    #[test]
    fn optional_missing_any_ingredient_field_contributes_no_line() {
        // ingredient_name + unit present but quantity_used None → no line (the
        // `if let (Some, Some, Some)` guard fails).
        let partial = OptionalFieldView {
            id: "opt-x".into(),
            name: "Partial".into(),
            price_minor: 0,
            is_active: true,
            ingredient_name: Some("Foam".into()),
            ingredient_unit: Some("ml".into()),
            quantity_used: None,
            org_ingredient_id: None,
        };
        let it = item(
            vec![recipe("Beans", "g", 18.0, Some("M"), "coffee_bean", None)],
            vec![partial],
        );
        let out = compute_recipe(
            &it,
            &[],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[],
            &["opt-x".into()],
        );
        assert_eq!(out.len(), 1, "no quantity → no deduction line");
    }

    // ── addon qty clamping & multi-ingredient additives ─────────────────────

    #[test]
    fn additive_addon_qty_clamps_to_one_when_zero_or_negative() {
        let it = item(vec![], vec![]);
        let syrup = addon(
            "a-syrup",
            "Caramel",
            "extra",
            vec![ing("Syrup", "ml", 10.0, Some("o-car"))],
        );
        // qty 0 → clamped to 1 (10ml × 1).
        let zero = compute_recipe(
            &it,
            &[syrup.clone()],
            &crate::catalog_pricing::PricingMirror::default(),
            None,
            &[sel("a-syrup", 0)],
            &[],
        );
        assert_eq!(zero[0].quantity, 10.0);
        // negative qty → also clamps to 1.
        let neg = compute_recipe(
            &it,
            &[syrup],
            &crate::catalog_pricing::PricingMirror::default(),
            None,
            &[sel("a-syrup", -5)],
            &[],
        );
        assert_eq!(neg[0].quantity, 10.0);
    }

    #[test]
    fn additive_addon_emits_a_line_per_embedded_ingredient() {
        let it = item(vec![], vec![]);
        let combo = addon(
            "a-combo",
            "Combo Shot",
            "extra",
            vec![
                ing("Espresso", "ml", 30.0, Some("o-esp")),
                ing("Sugar", "g", 5.0, Some("o-sug")),
            ],
        );
        let out = compute_recipe(
            &it,
            &[combo],
            &crate::catalog_pricing::PricingMirror::default(),
            None,
            &[sel("a-combo", 2)],
            &[],
        );
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].quantity, 60.0); // 30 × 2
        assert_eq!(out[1].quantity, 10.0); // 5 × 2
        assert!(out.iter().all(|r| r.source_label == "addon" && !r.is_base));
    }

    // ── ordering: base, then addons, then optionals ─────────────────────────

    #[test]
    fn output_order_is_base_then_addons_then_optionals() {
        let opt = OptionalFieldView {
            id: "opt-shot".into(),
            name: "Extra shot".into(),
            price_minor: 1500,
            is_active: true,
            ingredient_name: Some("Espresso".into()),
            ingredient_unit: Some("shot".into()),
            quantity_used: Some(1.0),
            org_ingredient_id: Some("o-esp".into()),
        };
        let it = item(
            vec![recipe(
                "Beans",
                "g",
                18.0,
                Some("M"),
                "coffee_bean",
                Some("o-beans"),
            )],
            vec![opt],
        );
        let syrup = addon(
            "a-syrup",
            "Caramel",
            "extra",
            vec![ing("Syrup", "ml", 10.0, Some("o-car"))],
        );
        let out = compute_recipe(
            &it,
            &[syrup],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[sel("a-syrup", 1)],
            &["opt-shot".into()],
        );
        assert_eq!(out.len(), 3);
        assert_eq!(out[0].source_label, "base"); // base first
        assert_eq!(out[1].source_label, "addon"); // addon second
        assert_eq!(out[2].source_label, "Extra shot"); // optional last
    }

    #[test]
    fn swap_then_additive_addon_coexist_in_selection_order() {
        // A milk swap followed by an additive syrup: base milk is replaced in
        // place (stays at index 0), the syrup appends after.
        let it = item(
            vec![recipe(
                "Whole milk",
                "ml",
                200.0,
                Some("M"),
                "milk",
                Some("o-whole"),
            )],
            vec![],
        );
        let oat = addon(
            "a-oat",
            "Oat",
            "milk_type",
            vec![ing("Oat milk", "ml", 0.0, Some("o-oat"))],
        );
        let syrup = addon(
            "a-syrup",
            "Caramel",
            "extra",
            vec![ing("Syrup", "ml", 10.0, Some("o-car"))],
        );
        let out = compute_recipe(
            &it,
            &[oat, syrup],
            &crate::catalog_pricing::PricingMirror::default(),
            Some("M"),
            &[sel("a-oat", 1), sel("a-syrup", 1)],
            &[],
        );
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].ingredient_name, "Oat milk"); // swapped base line, in place
        assert_eq!(out[0].source_label, "Oat");
        assert_eq!(out[1].ingredient_name, "Syrup"); // additive appended
    }
}
