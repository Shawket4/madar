# AddonIngredient

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addon_item_id** | **uuid::Uuid** |  | 
**id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**org_ingredient_id** | Option<**uuid::Uuid**> |  | [optional]
**quantity_used** | **f64** |  | 
**unit** | **String** |  | 
**usable_quantity** | **f64** | The usable amount before yield loss: `quantity_used` × the linked ingredient's yield, 3 dp (madar-units `usable_qty`). What an editor shows and sends back; a line sent back unchanged keeps its stored quantity. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


