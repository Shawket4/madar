# PosMetricsReport

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**average_ticket** | **i64** | `net_sales / order_count`, rounded half up; 0 with no sales. | 
**branch_id** | **uuid::Uuid** |  | 
**from** | **chrono::NaiveDate** |  | 
**gross_sales** | **i64** |  | 
**hourly** | [**Vec<models::PosMetricsHour>**](PosMetricsHour.md) | Always 24 rows, hour 0 first. | 
**net_sales** | **i64** | Sold sales net of refunds against them (`branch_sales.total_revenue`). | 
**order_count** | **i64** | Sold sales (`branch_sales.total_orders`). | 
**refunded_amount** | **i64** |  | 
**refunded_orders_count** | **i64** | Sales refunded in full (out of every sold figure above). | 
**refunds_issued_amount** | **i64** |  | 
**refunds_issued_count** | **i64** | Refunds ISSUED inside the window at this branch, whichever sale they refund. | 
**tenders** | [**Vec<models::PosMetricsTender>**](PosMetricsTender.md) | By amount, largest first. | 
**timezone** | **String** | The IANA zone the days were cut in. | 
**to** | **chrono::NaiveDate** |  | 
**top_items** | [**Vec<models::PosMetricsItem>**](PosMetricsItem.md) | Top [`TOP_ITEMS`] by quantity (then revenue, then name). | 
**voided_amount** | **i64** |  | 
**voided_count** | **i64** |  | 
**window_from** | **chrono::DateTime<chrono::FixedOffset>** | `[window_from, window_to)`: local midnight of `from` to local midnight after `to`. | 
**window_to** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


