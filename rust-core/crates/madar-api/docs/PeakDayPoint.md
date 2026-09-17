# PeakDayPoint

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addons** | **i64** | SUM(order_item_addons.quantity) across non-voided orders on this weekday. | 
**avg_orders_per_day** | **f64** | Orders averaged over how many times this weekday occurred (may be fractional). | 
**avg_revenue_per_day** | **i64** | Revenue in piastres averaged over how many times this weekday occurred in the queried range. | 
**day_of_week** | **i32** | Day of week per `EXTRACT(dow ...)`: 0 = Sunday .. 6 = Saturday. | 
**discount** | **i64** |  | 
**line_items** | **i64** | SUM(order_items.quantity) across non-voided orders on this weekday. | 
**orders** | **i64** |  | 
**orders_pct** | **f64** | This weekday's orders as a percentage of the period total (0–100, 1 dp). | 
**revenue** | **i64** |  | 
**revenue_pct** | **f64** | This weekday's revenue as a percentage of the period total (0–100, 1 dp). | 
**tax** | **i64** |  | 
**voided** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


