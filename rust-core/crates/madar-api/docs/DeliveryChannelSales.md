# DeliveryChannelSales

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**avg_order_value** | **i64** |  | 
**cancelled_orders** | **i64** |  | 
**channel** | **String** | Delivery channel: `in_mall`, `outside`, `umbrella` or `pickup`. | 
**delivery_fees** | **i64** | Sum of `delivery_fee` (piastres) over delivered orders. Outside the tax base and not food revenue; a pickup carries none. | 
**goods_revenue** | Option<**i64**> | `revenue − delivery_fees`: the bill for the goods (tax included), the figure comparable with dine-in and takeaway revenue. | [optional]
**orders** | **i64** |  | 
**revenue** | **i64** | Sum of `total` (piastres) over delivered orders on this channel — the whole bill, delivery fee included. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


