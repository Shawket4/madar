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
**primary_ingredient_id** | Option<**uuid::Uuid**> |  | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


