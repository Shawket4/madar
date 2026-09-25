# AddonItem

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addon_type** | **String** |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**default_price** | **i32** |  | 
**id** | **uuid::Uuid** |  | 
**ingredients** | Option<[**Vec<models::AddonItemIngredient>**](AddonItemIngredient.md)> |  | [optional]
**is_active** | **bool** |  | 
**name** | **String** |  | 
**name_translations** | **serde_json::Value** |  | 
**org_id** | **uuid::Uuid** |  | 
**pricing** | Option<**serde_json::Value**> | How a sale line charges this option: madar-catalog's `OptionView` (branch-effective price, its group's effect and swap category, the ingredient it replaces, its lines per size). The till prices lines with it exactly as the order path does. Additive; older tills ignore it. | [optional]
**primary_ingredient_id** | Option<**uuid::Uuid**> |  | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


