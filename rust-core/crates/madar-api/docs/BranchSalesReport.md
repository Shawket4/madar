# BranchSalesReport

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**by_category** | [**Vec<models::CategorySales>**](CategorySales.md) |  | 
**cash_tips** | Option<**i64**> | The cash slice of `total_tips` (snapshotted `tip_is_cash`). | [optional]
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**gross_sales** | Option<**i64**> | Sales in range as rung up, before any refund. Was what `total_revenue` meant until 2026-09. | [optional]
**refunded_amount** | Option<**i64**> | Money refunded against the sales in range (partial refunds; a fully refunded order is out of every figure here by status). | [optional]
**revenue_by_method** | Option<**serde_json::Value**> | Money collected FOR GOODS, bucketed by the method actually tendered (`order_payments`) — money IN. Tips are not in here — see `total_tips` — and refunds are not netted out: they are money OUT with a tender of their own, on `GET /shifts/{id}/refunds` and the refunds dataset. | 
**subtotal** | **i64** |  | 
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**top_items** | [**Vec<models::ItemSales>**](ItemSales.md) |  | 
**total_delivery_fees** | Option<**i64**> | Delivery fees on the sales in range — inside `total_revenue`, outside the tax base, not food revenue. | [optional]
**total_discount** | **i64** |  | 
**total_line_items** | Option<**i64**> | Units sold (SUM of order_items.quantity) across non-voided orders in range. Counts units, not distinct lines (\"3× burger\" contributes 3), matching quantity_sold in the item/category breakdowns. | [optional]
**total_orders** | **i64** |  | 
**total_revenue** | **i64** | What the sales in range are worth after refunds: `gross_sales` less `refunded_amount`. A refund is attributed to the sale it was against, whenever it was issued — the same restatement a full refund makes by flipping the order's status out of the sold set. | 
**total_service_charge** | Option<**i64**> | Service charge on the dine-in bills in range — inside `total_revenue` as the shop's income, not a pass-through. | [optional]
**total_tax** | **i64** |  | 
**total_tips** | Option<**i64**> | Tips, standalone — never folded into a method bucket and never part of `total_revenue`. Same definition as `total_tips` on the shift report, so the two screens can be reconciled line for line. | [optional]
**voided_orders** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


