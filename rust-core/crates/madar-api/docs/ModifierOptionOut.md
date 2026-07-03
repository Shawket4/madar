# ModifierOptionOut

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cost_incomplete** | **bool** |  | 
**cost_piastres** | Option<**i64**> | Option recipe cost in piastres (swap markers cost 0). `null` = unknown. | [optional]
**id** | **uuid::Uuid** |  | 
**included** | **bool** | `false` = the group offers this option but it is not enabled on this item (item's `included_option_ids` allowlist excludes it). | 
**is_active** | **bool** |  | 
**is_default** | **bool** |  | 
**name** | **String** |  | 
**price** | **i32** |  | 
**recipe** | [**Vec<models::RecipeLineOut>**](RecipeLineOut.md) |  | 
**replaces_ingredient_id** | Option<**uuid::Uuid**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


