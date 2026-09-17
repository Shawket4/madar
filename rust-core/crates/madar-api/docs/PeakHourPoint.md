# PeakHourPoint

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addons** | **i64** | SUM(order_item_addons.quantity) across non-voided orders in this hour bucket. | 
**avg_orders_per_day** | **f64** | Orders averaged over the number of calendar days (may be fractional). | 
**avg_revenue_per_day** | **i64** | Revenue in piastres averaged over the number of calendar days in the queried range. | 
**discount** | **i64** |  | 
**hour** | **i32** |  | 
**line_items** | **i64** | SUM(order_items.quantity) across non-voided orders in this hour bucket. | 
**orders** | **i64** |  | 
**orders_pct** | **f64** | This hour's orders as a percentage of the period total (0–100, 1 dp). | 
**revenue** | **i64** |  | 
**revenue_pct** | **f64** | This hour's revenue as a percentage of the period total (0–100, 1 dp). | 
**tax** | **i64** |  | 
**voided** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


