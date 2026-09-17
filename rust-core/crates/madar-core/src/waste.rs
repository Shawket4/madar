//! Waste from the teller app (phase 6, capability `inventory.waste.record`).
//!
//! The person picks an INGREDIENT from the org catalog on the feed (any unit
//! of its family) or a MENU ITEM with a recipe (whole units, one size), a
//! reason and a note. The core works out the waste's value offline — the
//! recipe lines × the ingredient costs the feed carries — and decides the
//! `max_value` limit with `madar_authz::decide`: allowed, a manager approves
//! with their PIN on this device, or refused. The waste is queued as
//! `record_waste` and replayed through `/sync/replay`; the server explodes the
//! item with its own resolver, re-checks, and flags what the till let through.
//!
//! Nothing is shown locally afterwards (the waste log is the dashboard's), so
//! there is no mirror row, only the queued op.

use madar_authz::{decide, Cap, Request};
use serde::{Deserialize, Serialize};

use crate::approvals::{ActDecisionView, ApprovalView};
use crate::error::CoreError;
use crate::MadarCore;

pub(crate) const CAP: &str = "inventory.waste.record";
const OP: &str = "record_waste";

/// Reasons a person may pick, in display order (the backend's list minus the
/// system's own `order_cancelled`).
pub(crate) const REASONS: &[&str] = &["expired", "spoiled", "damaged", "overproduction", "theft", "other"];

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct WasteReasonView {
    pub key: String,
    pub label: String,
}

/// An ingredient the person may waste.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct WasteIngredientView {
    pub id: String,
    pub name: String,
    /// The ingredient's own unit.
    pub unit: String,
    /// Units the quantity may be typed in (its family).
    pub units: Vec<String>,
}

/// A menu item with a recipe, which a waste explodes into its ingredients.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct WasteItemView {
    pub id: String,
    pub name: String,
    /// Sizes that have a recipe, in menu order. Empty: the item has one size.
    pub sizes: Vec<String>,
}

/// What the person has picked so far.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct WasteInput {
    /// `ingredient` | `menu_item`
    pub subject_kind: String,
    pub subject_id: String,
    pub size_label: Option<String>,
    pub quantity: f64,
    /// `g` | `kg` | `ml` | `l` | `pcs`
    pub unit: String,
    pub reason: String,
    pub note: Option<String>,
}

/// One ingredient line the waste will take out of stock.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct WasteLineView {
    pub name: String,
    pub quantity: f64,
    pub unit: String,
}

/// The waste before it is recorded: its lines, value and the decision.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct WastePreviewView {
    pub lines: Vec<WasteLineView>,
    /// Piastres; `None` when no line has a cost on this device.
    pub value_minor: Option<i64>,
    /// Some line has no cost, so the value is a floor.
    pub value_partial: bool,
    pub decision: ActDecisionView,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct WasteRecordedView {
    pub id: String,
    pub subject_name: String,
    pub quantity: f64,
    pub unit: String,
    pub value_minor: Option<i64>,
}

// ── pure pieces ─────────────────────────────────────────────────────────────

/// (family, factor to the family's canonical unit). Mirrors MadarRust `units`.
fn unit_spec(unit: &str) -> Option<(&'static str, f64)> {
    match unit.trim().to_ascii_lowercase().as_str() {
        "g" => Some(("mass", 1.0)),
        "kg" => Some(("mass", 1000.0)),
        "ml" => Some(("volume", 1.0)),
        "l" => Some(("volume", 1000.0)),
        "pcs" => Some(("count", 1.0)),
        _ => None,
    }
}

/// `qty` in `from` expressed in `to`, rounded to 3 decimals; `None` across families.
pub(crate) fn convert(qty: f64, from: &str, to: &str) -> Option<f64> {
    let (ff, fk) = unit_spec(from)?;
    let (tf, tk) = unit_spec(to)?;
    (ff == tf).then(|| ((qty * fk / tk) * 1000.0).round() / 1000.0)
}

/// The units a quantity of an ingredient in `base` may be typed in.
pub(crate) fn units_of(base: &str) -> Vec<String> {
    match unit_spec(base).map(|(f, _)| f) {
        Some("mass") => vec!["g".into(), "kg".into()],
        Some("volume") => vec!["ml".into(), "l".into()],
        Some(_) => vec!["pcs".into()],
        None => vec![base.to_string()],
    }
}

/// `Σ qty × cost`, rounded once; partial when a line has no cost.
/// Same figure as MadarRust `inventory::waste::value_of`.
pub(crate) fn value_of(lines: &[(f64, Option<f64>)]) -> (Option<i64>, bool) {
    let known: Vec<f64> = lines.iter().filter_map(|(q, c)| c.map(|c| q * c)).collect();
    let partial = known.len() < lines.len();
    if known.is_empty() {
        (None, partial)
    } else {
        (Some(known.iter().sum::<f64>().round() as i64), partial)
    }
}

/// The recipe lines a waste of `item` at `size` takes, merged by ingredient
/// (`(ingredient id, name, unit, qty per unit)`). No size: the first size
/// (menu order) that has a recipe, as the server resolves it.
pub(crate) fn recipe_for(
    item: &crate::menu::MenuItemView,
    size: Option<&str>,
) -> Vec<(String, String, String, f64)> {
    let sized = |label: &str| item.recipes.iter().any(|r| r.size_label.as_deref() == Some(label));
    let target: Option<String> = match size {
        Some(s) => Some(s.to_string()),
        None => item
            .sizes
            .iter()
            .filter(|s| s.is_active)
            .chain(item.sizes.iter().filter(|s| !s.is_active))
            .map(|s| s.label.clone())
            .find(|l| sized(l))
            .or_else(|| item.recipes.iter().find_map(|r| r.size_label.clone())),
    };
    let mut out: Vec<(String, String, String, f64)> = Vec::new();
    for r in item.recipes.iter().filter(|r| match (&r.size_label, &target) {
        (None, _) => true,
        (Some(rs), Some(t)) => rs == t,
        (Some(_), None) => false,
    }) {
        let Some(id) = r.org_ingredient_id.clone() else { continue };
        match out.iter_mut().find(|l| l.0 == id) {
            Some(l) => l.3 += r.quantity,
            None => out.push((id, r.ingredient_name.clone(), r.unit.clone(), r.quantity)),
        }
    }
    out
}

fn sizes_with_recipe(item: &crate::menu::MenuItemView) -> Vec<String> {
    item.sizes
        .iter()
        .map(|s| s.label.clone())
        .filter(|l| item.recipes.iter().any(|r| r.size_label.as_deref() == Some(l.as_str())))
        .collect()
}

fn invalid(field: &str, detail: String) -> CoreError {
    CoreError::Validation { field: field.into(), detail }
}

/// Resolved pieces of a waste, for preview, approval and recording.
struct Planned {
    subject_name: String,
    lines: Vec<WasteLineView>,
    value_minor: Option<i64>,
    value_partial: bool,
}

impl MadarCore {
    fn waste_ingredient_rows(&self, branch: &str) -> Vec<serde_json::Value> {
        crate::sync_pull::rows_of_type(&self.store, branch, "ingredient")
            .into_iter()
            .filter(|r| r.get("is_active").and_then(|v| v.as_bool()).unwrap_or(true))
            .collect()
    }

    /// Whether the waste screen is offered at all: the person holds the
    /// capability, or may ask a manager for it. Hidden otherwise.
    pub fn can_record_waste(&self) -> bool {
        self.decide_act(CAP.into(), None, None, None).outcome != "deny"
    }

    /// The reasons, labelled in the current language.
    pub fn waste_reasons(&self) -> Vec<WasteReasonView> {
        let locale = self.current_locale();
        REASONS
            .iter()
            .map(|k| WasteReasonView {
                key: (*k).to_string(),
                label: crate::i18n::tr(&locale, &format!("waste.reason_{k}")),
            })
            .collect()
    }

    /// Catalog ingredients matching `query` (name contains), by name.
    pub fn waste_ingredients(&self, query: String) -> Result<Vec<WasteIngredientView>, CoreError> {
        let branch = self.session_branch_id()?;
        let q = query.trim().to_lowercase();
        let mut out: Vec<WasteIngredientView> = self
            .waste_ingredient_rows(&branch)
            .iter()
            .filter_map(|r| {
                let s = |k: &str| r.get(k).and_then(|v| v.as_str()).map(str::to_string);
                let name = s("name")?;
                let id = s("id")?;
                let unit = s("unit").unwrap_or_else(|| "pcs".into());
                (q.is_empty() || name.to_lowercase().contains(&q)).then(|| WasteIngredientView {
                    id,
                    units: units_of(&unit),
                    name,
                    unit,
                })
            })
            .collect();
        out.sort_by_key(|a| a.name.to_lowercase());
        Ok(out)
    }

    /// Menu items with a recipe matching `query`, by name.
    pub fn waste_items(&self, query: String) -> Result<Vec<WasteItemView>, CoreError> {
        let q = query.trim().to_lowercase();
        let catalog = self.catalog()?;
        let mut out: Vec<WasteItemView> = catalog
            .items
            .iter()
            .filter(|i| i.recipes.iter().any(|r| r.org_ingredient_id.is_some()))
            .filter(|i| q.is_empty() || i.name.to_lowercase().contains(&q))
            .map(|i| WasteItemView {
                id: i.id.clone(),
                name: i.name.clone(),
                sizes: sizes_with_recipe(i),
            })
            .collect();
        out.sort_by_key(|a| a.name.to_lowercase());
        Ok(out)
    }

    fn plan_waste(&self, input: &WasteInput) -> Result<Planned, CoreError> {
        let locale = self.current_locale();
        let tr = |k: &str| crate::i18n::tr(&locale, k);
        if !(input.quantity.is_finite() && input.quantity > 0.0) {
            return Err(invalid("quantity", tr("waste.qty_required")));
        }
        let branch = self.session_branch_id()?;
        let rows = self.waste_ingredient_rows(&branch);
        let cost_of = |id: &str| {
            rows.iter()
                .find(|r| r.get("id").and_then(|v| v.as_str()) == Some(id))
                .and_then(|r| r.get("cost_per_unit"))
                .and_then(|v| v.as_f64())
        };
        match input.subject_kind.as_str() {
            "ingredient" => {
                let row = rows
                    .iter()
                    .find(|r| r.get("id").and_then(|v| v.as_str()) == Some(input.subject_id.as_str()))
                    .ok_or_else(|| invalid("subject", tr("waste.pick_something")))?;
                let name = row.get("name").and_then(|v| v.as_str()).unwrap_or_default().to_string();
                let base = row.get("unit").and_then(|v| v.as_str()).unwrap_or("pcs").to_string();
                let qty = convert(input.quantity, &input.unit, &base)
                    .ok_or_else(|| invalid("unit", tr("waste.unit_mismatch")))?;
                let (value_minor, value_partial) = value_of(&[(qty, cost_of(&input.subject_id))]);
                Ok(Planned {
                    lines: vec![WasteLineView { name: name.clone(), quantity: qty, unit: base }],
                    subject_name: name,
                    value_minor,
                    value_partial,
                })
            }
            "menu_item" => {
                if input.quantity.fract() != 0.0 {
                    return Err(invalid("quantity", tr("waste.whole_units")));
                }
                let catalog = self.catalog()?;
                let item = catalog
                    .items
                    .iter()
                    .find(|i| i.id == input.subject_id)
                    .ok_or_else(|| invalid("subject", tr("waste.pick_something")))?;
                let recipe = recipe_for(item, input.size_label.as_deref());
                if recipe.is_empty() {
                    return Err(invalid("subject", tr("waste.no_recipe")));
                }
                let priced: Vec<(f64, Option<f64>)> = recipe
                    .iter()
                    .map(|(id, _, _, q)| (q * input.quantity, cost_of(id)))
                    .collect();
                let (value_minor, value_partial) = value_of(&priced);
                Ok(Planned {
                    subject_name: item.name.clone(),
                    lines: recipe
                        .into_iter()
                        .map(|(_, name, unit, q)| WasteLineView { name, quantity: q * input.quantity, unit })
                        .collect(),
                    value_minor,
                    value_partial,
                })
            }
            _ => Err(invalid("subject", tr("waste.pick_something"))),
        }
    }

    fn waste_request(value_minor: Option<i64>) -> Request {
        let mut r = Request::of(Cap::InventoryWasteRecord);
        r.value = Some(value_minor.unwrap_or(0));
        r
    }

    /// The waste's lines and value, and whether the person may record it.
    pub fn preview_waste(&self, input: WasteInput) -> Result<WastePreviewView, CoreError> {
        let p = self.plan_waste(&input)?;
        let decision = self.decide_waste(p.value_minor);
        Ok(WastePreviewView {
            lines: p.lines,
            value_minor: p.value_minor,
            value_partial: p.value_partial,
            decision,
        })
    }

    fn decide_waste(&self, value_minor: Option<i64>) -> ActDecisionView {
        let locale = self.current_locale();
        let grants = self
            .session
            .read()
            .unwrap_or_else(|e| e.into_inner())
            .as_ref()
            .and_then(|s| s.authz.clone());
        match grants {
            Some(g) => crate::approvals::decision_view(
                &decide(&crate::approvals::effective_from(&g), &Self::waste_request(value_minor)),
                &locale,
            ),
            None => self.decide_act(CAP.into(), None, None, None),
        }
    }

    /// A manager approves this waste with their PIN on this device.
    pub fn approve_waste(&self, approver_pin: String, input: WasteInput) -> Result<ApprovalView, CoreError> {
        let p = self.plan_waste(&input)?;
        self.approve_request(approver_pin, CAP.into(), Self::waste_request(p.value_minor))
    }

    /// Record the waste. Works offline: it is queued and replayed. Needs the
    /// capability within its limit, or a manager's approval for it.
    pub fn record_waste(
        &self,
        input: WasteInput,
        approval: Option<ApprovalView>,
    ) -> Result<WasteRecordedView, CoreError> {
        let locale = self.current_locale();
        if !REASONS.contains(&input.reason.as_str()) {
            return Err(invalid("reason", crate::i18n::tr(&locale, "waste.reason_required")));
        }
        let p = self.plan_waste(&input)?;
        let decision = self.decide_waste(p.value_minor);
        let approval = match decision.outcome.as_str() {
            "allow" => None,
            "needs_approval" => match approval {
                Some(a) if a.capability == CAP && a.value_minor.unwrap_or(0) >= p.value_minor.unwrap_or(0) => {
                    Some(a)
                }
                _ => {
                    return Err(CoreError::Forbidden { resource: "approval".into(), action: decision.reason })
                }
            },
            _ => return Err(CoreError::Forbidden { resource: "waste".into(), action: decision.reason }),
        };
        let branch = self.session_branch_id()?;
        let id = uuid::Uuid::new_v4().to_string();
        let now = self.corrected_now().to_rfc3339();
        let till_id = self.current_till().ok().flatten().filter(|t| t.is_open).map(|t| t.id);
        let note = input.note.as_deref().map(str::trim).filter(|n| !n.is_empty()).map(str::to_string);
        let request = serde_json::json!({
            "id": id,
            "branch_id": branch,
            "subject_kind": input.subject_kind,
            "subject_id": input.subject_id,
            "size_label": if input.subject_kind == "menu_item" { input.size_label.clone() } else { None },
            "quantity": input.quantity,
            "unit": input.unit,
            "reason": input.reason,
            "note": note,
            "occurred_at": now,
            "device_id": self.lan_device_id(),
            "till_id": till_id,
        });
        let payload = serde_json::json!({
            "request": request,
            "approval": approval.as_ref().map(crate::approvals::approval_wire),
        });
        let (user_id, clock_offset_ms) = self.outbox_meta();
        self.store.enqueue(&crate::store::NewOutboxOp {
            id: format!("waste:{id}"),
            op_type: OP.into(),
            idempotency_key: format!("waste:{id}"),
            payload: payload.to_string(),
            event_at: now,
            user_id,
            clock_offset_ms,
            entity_type: Some("waste".into()),
            entity_id: Some(id.clone()),
            ..Default::default()
        })?;
        self.send_in_background(Vec::new());
        Ok(WasteRecordedView {
            id,
            subject_name: p.subject_name,
            quantity: input.quantity,
            unit: input.unit,
            value_minor: p.value_minor,
        })
    }
}

/// The `/sync/replay` envelope for a queued waste, `occurred_at` re-based by
/// the fresh clock skew.
pub(crate) fn replay_envelope(
    payload: &str,
    teller_id: &str,
    delta_ms: i64,
) -> Result<serde_json::Value, String> {
    let mut p: serde_json::Value = serde_json::from_str(payload).map_err(|e| e.to_string())?;
    let mut request = p.get_mut("request").map(serde_json::Value::take).ok_or("no request")?;
    if delta_ms != 0 {
        if let Some(at) = request
            .get("occurred_at")
            .and_then(|v| v.as_str())
            .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
        {
            request["occurred_at"] =
                serde_json::json!((at + chrono::Duration::milliseconds(delta_ms)).to_rfc3339());
        }
    }
    let mut env = serde_json::json!({ "op": OP, "teller_id": teller_id, "request": request });
    if let Some(a) = p.get("approval").filter(|a| !a.is_null()) {
        env["approval"] = a.clone();
    }
    Ok(env)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::menu::{ItemSizeView, MenuItemView, RecipeLineView};

    fn line(name: &str, id: &str, size: Option<&str>, q: f64) -> RecipeLineView {
        RecipeLineView {
            ingredient_name: name.into(),
            quantity: q,
            unit: "g".into(),
            size_label: size.map(Into::into),
            category: "general".into(),
            org_ingredient_id: Some(id.into()),
        }
    }

    fn size(label: &str, active: bool) -> ItemSizeView {
        ItemSizeView { id: label.into(), label: label.into(), price_minor: 0, is_active: active }
    }

    fn item(sizes: Vec<ItemSizeView>, recipes: Vec<RecipeLineView>) -> MenuItemView {
        MenuItemView {
            id: "i".into(),
            name: "Latte".into(),
            description: None,
            category_id: None,
            base_price_minor: 0,
            image_url: None,
            local_image_path: None,
            is_active: true,
            default_milk_addon_id: None,
            allowed_addon_ids: vec![],
            sizes,
            addon_slots: vec![],
            optional_fields: vec![],
            recipes,
            recipe_steps: vec![],
        }
    }

    #[test]
    fn units_convert_within_a_family_only() {
        assert_eq!(convert(0.5, "kg", "g"), Some(500.0));
        assert_eq!(convert(250.0, "ml", "l"), Some(0.25));
        assert_eq!(convert(1.0, "g", "ml"), None);
        assert_eq!(units_of("ml"), vec!["ml", "l"]);
        assert_eq!(units_of("pcs"), vec!["pcs"]);
    }

    #[test]
    fn the_value_is_rounded_once_and_partial_without_a_cost() {
        // 18 g × 2 + 200 ml × 0.1, three times = 168 (a sub-piastre cost still counts).
        assert_eq!(value_of(&[(54.0, Some(2.0)), (600.0, Some(0.1))]), (Some(168), false));
        assert_eq!(value_of(&[(10.0, Some(0.333)), (5.0, None)]), (Some(3), true));
        assert_eq!(value_of(&[(5.0, None)]), (None, true));
    }

    #[test]
    fn an_items_recipe_is_its_sizes_lines_merged_by_ingredient() {
        let it = item(
            vec![size("Small", true), size("Large", true)],
            vec![
                line("Beans", "b", Some("Small"), 14.0),
                line("Beans", "b", Some("Large"), 18.0),
                line("Milk", "m", Some("Large"), 200.0),
                line("Beans top-up", "b", Some("Large"), 2.0),
            ],
        );
        let large = recipe_for(&it, Some("Large"));
        assert_eq!(large.len(), 2);
        assert_eq!(large[0].3, 20.0, "two lines of one ingredient merge");
        // No size: the first size (menu order) with a recipe.
        assert_eq!(recipe_for(&it, None), vec![("b".into(), "Beans".into(), "g".into(), 14.0)]);
        assert_eq!(sizes_with_recipe(&it), vec!["Small", "Large"]);
    }

    #[test]
    fn the_envelope_carries_the_request_and_approval_and_rebases_the_time() {
        let payload = serde_json::json!({
            "request": { "id": "w", "occurred_at": "2026-09-17T08:00:00+00:00" },
            "approval": { "id": "a", "capability": CAP, "approver_id": "m", "value_minor": 900 }
        })
        .to_string();
        let env = replay_envelope(&payload, "t", 60_000).unwrap();
        assert_eq!(env["op"], "record_waste");
        assert_eq!(env["teller_id"], "t");
        assert_eq!(env["request"]["occurred_at"], "2026-09-17T08:01:00+00:00");
        assert_eq!(env["approval"]["value_minor"], 900);
        let bare = serde_json::json!({ "request": { "id": "w" }, "approval": null }).to_string();
        assert!(replay_envelope(&bare, "t", 0).unwrap().get("approval").is_none());
    }
}
