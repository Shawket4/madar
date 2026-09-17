# SizeOut

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**base_id** | Option<**uuid::Uuid**> | Recipe base this size expands (`PUT /menu-item-sizes/{id}/base`), or `null`. | [optional]
**cost_incomplete** | **bool** | `true` when at least one recipe line is unlinked/uncosted (so `cost_piastres`, if present, is a partial figure rather than the full COGS). | 
**cost_piastres** | Option<**i64**> | Recipe cost rollup in piastres over the priced ingredients. `null` when there is no recipe or nothing is priced; a partial rollup returns the sum-so-far with `cost_incomplete = true`. | [optional]
**id** | **uuid::Uuid** |  | 
**is_active** | **bool** |  | 
**label** | **String** |  | 
**price** | **i32** |  | 
**recipe** | [**Vec<models::RecipeLineOut>**](RecipeLineOut.md) |  | 
**sort** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


