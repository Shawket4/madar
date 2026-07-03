# RecipeLineOut

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | 
**ingredient_id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**line_cost_piastres** | Option<**i64**> | Cost of this line in piastres. `null` = UNKNOWN (ingredient unlinked/uncosted), never shown as 0. A priced line with `quantity = 0` (swap marker) costs 0. | [optional]
**quantity** | **String** | Base-unit, yield-normalized quantity, serialized as a string (numeric fidelity). | 
**unit** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


