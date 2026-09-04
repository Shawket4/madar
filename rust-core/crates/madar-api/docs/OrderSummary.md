# OrderSummary

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**completed** | **i64** |  | 
**delivery_fees** | Option<**i64**> | Total delivery charges (piastres) across completed orders in scope. Lets the dashboard surface delivery revenue separately from item sales. | [optional]
**delivery_orders** | Option<**i64**> | Count of completed delivery orders. | [optional]
**delivery_revenue** | Option<**i64**> | Gross revenue (total_amount) of completed delivery orders. | [optional]
**discounts** | **i64** |  | 
**in_mall_fees** | Option<**i64**> |  | [optional]
**in_mall_orders** | Option<**i64**> | In-mall channel: order count / gross revenue / delivery fees. | [optional]
**in_mall_revenue** | Option<**i64**> |  | [optional]
**line_items** | Option<**i64**> | Units sold (SUM of order_items.quantity) across completed orders in scope. Counts units, not distinct lines, matching the item-sales reports (\"3× burger\" contributes 3). | [optional]
**outside_fees** | Option<**i64**> |  | [optional]
**outside_orders** | Option<**i64**> | Outside channel: order count / gross revenue / delivery fees. | [optional]
**outside_revenue** | Option<**i64**> |  | [optional]
**revenue** | **i64** |  | 
**tips** | **i64** |  | 
**voided** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


