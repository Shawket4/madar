//! The item sheet's "Last: Large · Oat milk" chip: an item's most recent
//! configuration sold ON THIS DEVICE, read from the local order rows. A synced
//! sale answers from the feed's `items`; a sale still queued from the lines it
//! was rung with (`ledger::local::LOCAL_ITEMS`), so the sale just rung counts
//! at once, online or not. Reads never touch the network.

use rusqlite::params;
use serde_json::Value;

use crate::cart::{self, AddonSelection};
use crate::i18n;
use crate::ledger::local::LOCAL_ITEMS;

/// An item as this device last sold it, ready to apply on its sheet.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LastItemConfig {
    pub size_label: Option<String>,
    pub addons: Vec<AddonSelection>,
    pub optional_field_ids: Vec<String>,
    /// In the cart line's words: the size, each add-on (`×n` past one), each
    /// optional field, joined by " · ".
    pub words: String,
    /// The chip, in the till's language: "Last: Large · Oat milk".
    pub text: String,
}

/// How many of this device's sales carrying the item the chip looks through
/// for a plain line of it (a combo part or a staff drink is skipped).
const LOOKBACK: i64 = 50;

/// One sold line's configuration: size, add-ons, optional field ids.
type Sold = (Option<String>, Vec<AddonSelection>, Vec<String>);

/// The last plain line of `item_id` in an order row. A combo's part, a staff
/// drink and a loyalty reward are not the item as a customer ordered it.
fn sold_in(raw: &Value, item_id: &str) -> Option<Sold> {
    let fed = raw.get("items").and_then(Value::as_array).filter(|a| !a.is_empty());
    let lines = fed.or_else(|| raw.get(LOCAL_ITEMS).and_then(Value::as_array))?;
    lines.iter().rev().find_map(|l| {
        if l.get("menu_item_id").and_then(Value::as_str) != Some(item_id) {
            return None;
        }
        let set = |k: &str| l.get(k).is_some_and(|v| !v.is_null());
        let reward = l.get("is_reward").and_then(Value::as_bool) == Some(true);
        if reward || ["combo", "combo_line_id", "staff_drink", "staff_drink_id"].into_iter().any(set) {
            return None;
        }
        let size = l
            .get("size_label")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .map(str::to_string);
        let addons = l
            .get("addons")
            .and_then(Value::as_array)
            .map(|a| {
                a.iter()
                    .filter_map(|a| {
                        Some(AddonSelection {
                            addon_item_id: a.get("addon_item_id")?.as_str()?.to_string(),
                            qty: a.get("quantity").and_then(Value::as_i64).unwrap_or(1).max(1),
                        })
                    })
                    .collect()
            })
            .unwrap_or_default();
        // The command names them `optional_field_ids`; the feed's lines carry
        // `optionals` rows.
        let optionals = match l.get("optional_field_ids").and_then(Value::as_array) {
            Some(ids) => ids.iter().filter_map(|v| v.as_str().map(str::to_string)).collect(),
            None => l
                .get("optionals")
                .and_then(Value::as_array)
                .map(|o| {
                    o.iter()
                        .filter_map(|o| o.get("optional_field_id")?.as_str().map(str::to_string))
                        .collect()
                })
                .unwrap_or_default(),
        };
        Some((size, addons, optionals))
    })
}

impl crate::MadarCore {
    /// This item's most recent configuration sold on THIS device (its device
    /// code, or a row it wrote), newest sale first, voided sales aside — kept
    /// to what the menu still sells, in the cart line's words. `None` when
    /// this device never sold it, or the configuration has nothing to show.
    pub fn last_item_config(&self, item_id: String) -> Option<LastItemConfig> {
        // This device: its code on a synced sale, or a row it wrote itself and
        // the feed has not confirmed yet (a sale rung before the device had a
        // number carries no code).
        let device = self
            .store
            .kv_get(crate::checkout::KEY_DEVICE_CODE)
            .ok()
            .flatten()
            .unwrap_or_default();
        let catalog = self.catalog().ok()?;
        let item = catalog.items.iter().find(|i| i.id == item_id)?;
        let rows: Vec<String> = self
            .store
            .with_conn(|c| {
                let mut st = c.prepare(
                    "SELECT raw FROM ledger_orders
                      WHERE (device_code=?1 AND ?1 <> '' OR origin='local') AND status NOT IN ('voided','cancelled')
                        AND instr(raw, ?2) > 0
                      ORDER BY julianday(created_at) DESC, local_updated_at DESC
                      LIMIT ?3",
                )?;
                let rows = st
                    .query_map(params![device, item_id, LOOKBACK], |r| r.get::<_, String>(0))?
                    .collect::<Result<Vec<_>, _>>()?;
                Ok(rows)
            })
            .ok()?;
        let (size, addons, optionals) = rows
            .iter()
            .find_map(|raw| sold_in(&serde_json::from_str(raw).ok()?, &item_id))?;

        // What the menu still sells; the rest of the sale is dropped.
        let size = size.filter(|s| {
            !cart::is_one_size(s) && item.sizes.iter().any(|z| z.is_active && &z.label == s)
        });
        let addon_name = |id: &str| {
            catalog
                .addons
                .iter()
                .find(|a| a.id == id && a.is_active)
                .map(|a| a.name.clone())
        };
        let addons: Vec<AddonSelection> =
            addons.into_iter().filter(|a| addon_name(&a.addon_item_id).is_some()).collect();
        let field_name = |id: &str| {
            item.optional_fields
                .iter()
                .find(|f| f.id == id && f.is_active)
                .map(|f| f.name.clone())
        };
        let optionals: Vec<String> =
            optionals.into_iter().filter(|id| field_name(id).is_some()).collect();

        // The cart line's words (sell_cart.dart): size · add-on (×n) · field.
        let mut words: Vec<String> = size.iter().cloned().collect();
        for a in &addons {
            let name = addon_name(&a.addon_item_id).unwrap_or_default();
            words.push(if a.qty > 1 { format!("{name} ×{}", a.qty) } else { name });
        }
        words.extend(optionals.iter().filter_map(|id| field_name(id)));
        if words.is_empty() {
            return None;
        }
        let words = words.join(" · ");
        let text = i18n::tr(&catalog.locale, "order.last_config").replace("{config}", &words);
        Some(LastItemConfig {
            size_label: size,
            addons,
            optional_field_ids: optionals,
            words,
            text,
        })
    }
}
