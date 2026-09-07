# BranchSalesReport

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**by_category** | [**Vec<models::CategorySales>**](CategorySales.md) |  | 
**cash_tips** | Option<**i64**> | The cash slice of `total_tips` (snapshotted `tip_is_cash`). | [optional]
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**revenue_by_method** | Option<**serde_json::Value**> | Money collected FOR GOODS, bucketed by the method actually tendered (`order_payments`). Tips are not in here — see `total_tips`. | 
**subtotal** | **i64** |  | 
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**top_items** | [**Vec<models::ItemSales>**](ItemSales.md) |  | 
**total_discount** | **i64** |  | 
**total_line_items** | Option<**i64**> | Units sold (SUM of order_items.quantity) across non-voided orders in range. Counts units, not distinct lines (\"3× burger\" contributes 3), matching quantity_sold in the item/category breakdowns. | [optional]
**total_orders** | **i64** |  | 
**total_revenue** | **i64** |  | 
**total_tax** | **i64** |  | 
**total_tips** | Option<**i64**> | Tips, standalone — never folded into a method bucket and never part of `total_revenue`. Same definition as `total_tips` on the shift report, so the two screens can be reconciled line for line. | [optional]
**voided_orders** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


