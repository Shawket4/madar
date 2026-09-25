# MenuItemFull

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**base_price** | **i32** |  | 
**category_id** | Option<**uuid::Uuid**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**default_milk_addon_id** | Option<**String**> |  | [optional]
**deleted_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**description** | Option<**String**> |  | [optional]
**description_translations** | **serde_json::Value** |  | 
**id** | **uuid::Uuid** |  | 
**image** | Option<[**models::AssetGroupRef**](AssetGroupRef.md)> | Asset refs (Track B4, §11.10); null when no asset or not attached by this endpoint. | [optional]
**image_url** | Option<**String**> |  | [optional]
**is_active** | **bool** |  | 
**kind** | Option<**String**> | `item` | `combo` (combos module). A combo's price is its `one_size` row like any item; its slots are on `GET /combos/{id}`. Additive. | [optional]
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**org_id** | **uuid::Uuid** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**addon_slots** | [**Vec<models::AddonSlot>**](AddonSlot.md) |  | 
**all_sizes** | Option<[**Vec<models::ItemSize>**](ItemSize.md)> | Every size row, INCLUDING the synthetic `one_size` one. Additive: this is where price actually lives, and it is what the dashboard's size editor and new POS builds read. An item always has at least one entry. | [optional]
**allowed_addon_ids** | **Vec<uuid::Uuid>** | Explicit per-item addon allowlist. Empty = no restriction (use org catalog). | 
**combo** | Option<[**models::ComboFeed**](ComboFeed.md)> | A kind=combo row: its slots, windows and channel toggles for the requested branch; `null` for an item. Combo rows are served only to a client that can sell them (a browser, POS ≥ 0.9.0, the KDS). | [optional]
**meal** | Option<[**models::MealLink**](MealLink.md)> | A kind=item row: its \"make it a meal\" upsell (C14), or `null`. | [optional]
**optional_fields** | [**Vec<models::OptionalField>**](OptionalField.md) |  | 
**pricing** | Option<**serde_json::Value**> | How a sale line of this item is priced at the requested branch: madar-catalog's `ItemView` (sizes with their branch prices, the branch's item price, the recipe's swap bases and their candidates, the optional fields). The till prices with it exactly as the order path does. Present on `?full=true` lists; additive, older tills ignore it. | [optional]
**recipe_steps** | Option<[**Vec<models::RecipeStep>**](RecipeStep.md)> | How the item is made, in order. Each preset step carries its animation's address and fingerprint, so a device downloads only what its own menu uses and never the whole library. | [optional]
**recipes** | [**Vec<models::MenuItemRecipe>**](MenuItemRecipe.md) |  | 
**sizes** | [**Vec<models::ItemSize>**](ItemSize.md) | LEGACY SHAPE — unchanged for clients at or below v0.7.11: the synthetic `one_size` row that now carries a single-price item's price is hidden here, so an old till still sees a size-less item exactly as it did. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


