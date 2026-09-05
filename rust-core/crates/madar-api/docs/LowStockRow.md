# LowStockRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**ingredient_name** | **String** |  | 
**on_hand** | **f64** |  | 
**org_ingredient_id** | **uuid::Uuid** |  | 
**par_max** | Option<**f64**> | Order-up-to level; `null` when only a reorder point is set. | [optional]
**par_min** | **f64** | Reorder point the item is at or below. | 
**suggested_qty** | **f64** | Quantity to bring stock back to par_max (or par_min when no max is set). | 
**supplier_id** | Option<**uuid::Uuid**> | Default supplier for this ingredient (for one-click \"create PO\"); may be null. | [optional]
**supplier_name** | Option<**String**> |  | [optional]
**unit** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


