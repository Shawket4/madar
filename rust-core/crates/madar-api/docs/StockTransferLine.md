# StockTransferLine

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**id** | **uuid::Uuid** |  | 
**ingredient_name** | **String** |  | 
**note** | Option<**String**> |  | [optional]
**org_ingredient_id** | **uuid::Uuid** |  | 
**qty_received** | Option<**f64**> | `None` until received. | [optional]
**qty_sent** | **f64** | Asked for while `requested`, planned while `draft`, sent from dispatch on. | 
**unit** | **String** |  | 
**unit_cost** | Option<**f64**> | Frozen at dispatch from the source's cost; `None` before dispatch or unknown. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


