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
**image_url** | Option<**String**> |  | [optional]
**is_active** | **bool** |  | 
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**org_id** | **uuid::Uuid** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**addon_slots** | [**Vec<models::AddonSlot>**](AddonSlot.md) |  | 
**allowed_addon_ids** | **Vec<uuid::Uuid>** | Explicit per-item addon allowlist. Empty = no restriction (use org catalog). | 
**optional_fields** | [**Vec<models::OptionalField>**](OptionalField.md) |  | 
**recipe_steps** | Option<[**Vec<models::RecipeStep>**](RecipeStep.md)> | How the item is made, in order. Each preset step carries its animation's address and fingerprint, so a device downloads only what its own menu uses and never the whole library. | [optional]
**recipes** | [**Vec<models::MenuItemRecipe>**](MenuItemRecipe.md) |  | 
**sizes** | [**Vec<models::ItemSize>**](ItemSize.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


