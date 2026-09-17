# TimeseriesPoint

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addons** | **i64** | SUM(order_item_addons.quantity) across non-voided orders in this period. | 
**discount** | **i64** |  | 
**line_items** | **i64** | SUM(order_items.quantity) across non-voided orders in this period. | 
**orders** | **i64** |  | 
**period** | **String** |  | 
**refunded** | Option<**i64**> |  | [optional]
**revenue** | **i64** | Net of refunds against the period's sales; `refunded` is what came off. | 
**revenue_by_method** | Option<**serde_json::Value**> |  | 
**tax** | **i64** |  | 
**voided** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


