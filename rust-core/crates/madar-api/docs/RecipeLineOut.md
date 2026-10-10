# RecipeLineOut

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | 
**ingredient_id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**line_cost_piastres** | Option<**i64**> | Cost of this line in piastres. `null` = UNKNOWN (ingredient unlinked/uncosted), never shown as 0. A priced line with `quantity = 0` (swap marker) costs 0. | [optional]
**quantity** | **String** | Base-unit, yield-normalized quantity, serialized as a string (numeric fidelity). | 
**size_label** | Option<**String**> | Option lines only: the size this amount is for (`null` = every size). | [optional]
**source** | Option<**String**> | Where the line came from: `own` (typed on this size; also legacy NULL rows), `base` (recipe base), `rule` (packaging rule) or `linked` (copied from the item this one follows). Only `own` lines are edited by `PUT /menu-item-sizes/{id}/recipe`. | [optional]
**unit** | **String** |  | 
**usable_quantity** | **String** | The usable amount in the base unit, before yield loss: `quantity` × the ingredient's yield, 3 dp (madar-units `usable_qty`; 100 g at 80 % yield stores 125, shows 100). What an editor shows and sends back; a line sent back unchanged keeps its stored `quantity`. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


