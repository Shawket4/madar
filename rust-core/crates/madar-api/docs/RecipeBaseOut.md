# RecipeBaseOut

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**item_count** | **i64** | Distinct menu items those sizes belong to. | 
**lines** | [**Vec<models::RecipeBaseLineOut>**](RecipeBaseLineOut.md) |  | 
**name** | **String** |  | 
**name_ar** | Option<**String**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**size_count** | **i64** | Item sizes currently pointing at this base. | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


