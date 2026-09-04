# AnalyticsResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**avg_order_total** | **i64** | `total_revenue / total_orders`, truncated to whole piastres. 0 when the window is empty. | 
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**from** | **chrono::NaiveDate** |  | 
**from_utc** | **chrono::DateTime<chrono::FixedOffset>** | The exact half-open instant window `[from_utc, to_utc)` the figures cover, echoed so there is never a question about what was included. | 
**limit** | Option<**i64**> | Echo of the paging actually applied, and how many rows came back. | [optional]
**offset** | **i64** |  | 
**orders** | [**Vec<models::AnalyticsOrder>**](AnalyticsOrder.md) |  | 
**returned** | **i64** |  | 
**subtotal** | **i64** |  | 
**timezone** | **String** | IANA zone the business days were resolved in. | 
**to** | **chrono::NaiveDate** |  | 
**to_utc** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**total_discount** | **i64** |  | 
**total_orders** | **i64** | Orders in the window. Voided and refunded orders are excluded here and everywhere below, as are orders tendered with a payment method the merchant has hidden from partners — none are returned at all. | 
**total_revenue** | **i64** | Sum of the per-order `total_amount`. | 
**total_service_charge** | **i64** |  | 
**total_tax** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


