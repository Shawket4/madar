# LowStockRow

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**current_stock** | **f64** |  | 
**deficit** | **f64** | reorder_threshold − current_stock: how much to order to reach par. | 
**ingredient_name** | **String** |  | 
**org_ingredient_id** | **uuid::Uuid** |  | 
**reorder_threshold** | **f64** |  | 
**supplier_id** | Option<**uuid::Uuid**> | Default supplier for this ingredient (for one-click \"create PO\"); may be null. | [optional]
**supplier_name** | Option<**String**> |  | [optional]
**unit** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


