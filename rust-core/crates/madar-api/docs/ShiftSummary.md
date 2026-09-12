# ShiftSummary

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**cash_discrepancy** | Option<**i64**> |  | [optional]
**cash_tips** | Option<**i64**> | The cash slice of `total_tips`. | [optional]
**closed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**closing_cash_declared** | Option<**i64**> |  | [optional]
**closing_cash_system** | Option<**i64**> |  | [optional]
**gross_sales** | Option<**i64**> | This shift's sales as rung up, before any refund. Was what `total_revenue` meant until 2026-09. | [optional]
**opened_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**opening_cash** | **i64** |  | 
**refunded_amount** | Option<**i64**> | Money refunded AGAINST this shift's sales, whenever and from whichever drawer it was issued. `gross_sales − refunded_amount = total_revenue`. A fully refunded sale is out of all three (its status is `refunded`). | [optional]
**refunds_issued_amount** | Option<**i64**> |  | [optional]
**refunds_issued_cash** | Option<**i64**> |  | [optional]
**refunds_issued_count** | Option<**i64**> | Refunds ISSUED IN THIS SHIFT — keyed on `order_refunds.shift_id`, the drawer the money left, which need not be the shift that made the sale. This is the Z-report's money-out line: `refunds_issued_cash` is what the drawer is short by relative to its cash sales. | [optional]
**revenue_by_method** | Option<**serde_json::Value**> | Goods only, by method actually tendered — money IN. Tips are in `total_tips`; refunds are not netted from these buckets (they are money OUT, with their own tender — see `refunds_issued_*`). | 
**shift_id** | **uuid::Uuid** |  | 
**status** | **String** |  | 
**teller_id** | **uuid::Uuid** |  | 
**teller_name** | **String** |  | 
**total_delivery_fees** | Option<**i64**> | Delivery fees on this shift's sales. Inside `total_revenue` (the customer paid them) but outside the tax base and not food revenue. | [optional]
**total_discount** | **i64** |  | 
**total_orders** | **i64** |  | 
**total_revenue** | **i64** | What this shift's sales are worth after refunds: `gross_sales` less `refunded_amount`. Same definition as `total_revenue` on the branch sales report, so the two reconcile. | 
**total_service_charge** | Option<**i64**> | Service charge added to this shift's dine-in bills. Inside `total_revenue` as the shop's income; see `analytics::schema` for why. | [optional]
**total_tax** | **i64** |  | 
**total_tips** | Option<**i64**> | Tips, standalone — matches `total_tips` on `GET /shifts/{id}/report`. | [optional]
**voided_orders** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


