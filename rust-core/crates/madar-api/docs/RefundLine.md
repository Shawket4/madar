# RefundLine

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount** | **i32** |  | 
**id** | **uuid::Uuid** |  | 
**item_name** | **String** | `order_items.item_name`, so a receipt reprint names the dish without a second lookup. | 
**order_item_id** | **uuid::Uuid** |  | 
**quantity** | **i32** |  | 
**restock** | **bool** | Whether the goods came back. Recorded per line; nothing in this module writes it `true` yet (see the module docs on restock). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


