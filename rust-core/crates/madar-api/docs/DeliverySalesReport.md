# DeliverySalesReport

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**avg_order_value** | **i64** |  | 
**cancelled_orders** | **i64** |  | 
**channels** | [**Vec<models::DeliveryChannelSales>**](DeliveryChannelSales.md) |  | 
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**total_delivery_fees** | **i64** |  | 
**total_goods_revenue** | Option<**i64**> | `total_revenue − total_delivery_fees`. | [optional]
**total_orders** | **i64** |  | 
**total_revenue** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


