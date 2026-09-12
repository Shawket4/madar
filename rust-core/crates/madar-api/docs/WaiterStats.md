# WaiterStats

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**avg_items_per_order** | **f64** | line_items / orders; 0 when the waiter has no non-voided orders. | 
**avg_order_value** | **i64** | Average bill as rung up — a refund does not shrink what was ordered. | 
**line_items** | **i64** | Units sold (SUM of order_items.quantity) on this waiter's non-voided orders — the upsell signal behind avg_items_per_order. | 
**orders** | **i64** |  | 
**revenue** | **i64** | Net of refunds against this waiter's sales. | 
**voided** | **i64** |  | 
**waiter_id** | **uuid::Uuid** |  | 
**waiter_name** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


