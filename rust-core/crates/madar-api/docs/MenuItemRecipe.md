# MenuItemRecipe

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**category** | **String** |  | 
**ingredient_name** | **String** |  | 
**ingredient_unit** | **String** |  | 
**org_ingredient_id** | Option<**uuid::Uuid**> |  | [optional]
**quantity_used** | **f64** |  | 
**size_label** | **String** |  | 
**usable_quantity** | **f64** | The usable amount before yield loss: `quantity_used` × the linked ingredient's yield, 3 dp (madar-units `usable_qty`). What the catalog item dialog shows. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


