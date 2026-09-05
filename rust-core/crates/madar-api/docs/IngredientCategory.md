# IngredientCategory

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**ingredient_count** | **i64** | Live (non-deleted) ingredients in this category. | 
**name** | **String** |  | 
**org_id** | **uuid::Uuid** |  | 
**slug** | **String** | Stable machine key (`general`, `milk`, `coffee_bean`, …). `milk` and `coffee_bean` carry swap semantics in the menu; the slug never changes. | 
**sort_order** | **i32** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


