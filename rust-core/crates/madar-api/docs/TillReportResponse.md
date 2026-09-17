# TillReportResponse

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cash_adjustments** | **i64** |  | 
**cash_in_refunded_sales** | Option<**i64**> |  | [optional]
**cash_movements** | [**Vec<models::CashMovementSummaryRow>**](CashMovementSummaryRow.md) |  | 
**cash_movements_in** | **i64** |  | 
**cash_movements_net** | **i64** |  | 
**cash_movements_out** | **i64** |  | 
**cash_tips** | **i64** |  | 
**expected_cash** | **i64** |  | 
**net_payments** | **i64** |  | 
**non_cash_tips** | **i64** |  | 
**payment_summary** | [**Vec<models::PaymentSummaryRow>**](PaymentSummaryRow.md) |  | 
**printed_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**refunds_issued_amount** | Option<**i64**> |  | [optional]
**refunds_issued_cash** | Option<**i64**> |  | [optional]
**refunds_issued_count** | Option<**i64**> |  | [optional]
**refunds_issued_service_charge** | Option<**i64**> |  | [optional]
**refunds_issued_tax** | Option<**i64**> | The tax and service charge inside the refunds issued FROM this till's drawer (`refunds_issued_amount`'s split). | [optional]
**safe_drops** | **i64** |  | 
**service_charge_waived_amount** | Option<**i64**> |  | [optional]
**service_charge_waived_count** | Option<**i64**> | Table bills whose service charge was removed (`orders:waive_service`), and what those charges came to. Not part of any total. | [optional]
**spot_views** | Option<[**Vec<models::TillSpotView>**](TillSpotView.md)> | Who viewed (and printed) the cash spot report of this till, oldest first. Additive. | [optional]
**standard_float** | Option<**i64**> | `branches.standard_float`. | [optional]
**suggested_safe_drop** | Option<**i64**> |  | [optional]
**timezone** | Option<**String**> |  | [optional]
**total_payments** | **i64** |  | 
**total_service_charge** | Option<**i64**> | Service charge on this till's sales, less what their refunds took back. | [optional]
**total_tax** | Option<**i64**> | Tax on this till's sales, less the tax their refunds took back (a partial refund takes back its pro-rata share; a voided or fully refunded sale is out altogether). Additive. | [optional]
**total_tips** | **i64** |  | 
**voided_amount** | **i64** |  | 
**as_of_seq** | Option<**i64**> | The branch changefeed horizon read BEFORE the figures (OFFLINE_B_DESIGN §7): every change with `seq <= as_of_seq` is in this report. A device whose cursor has reached it, with nothing of the till still on its way, can take these figures as the authority. `0` when no horizon was available (then it is never newer than any cursor). Additive. | [optional]
**held_orders_left_open** | Option<**i32**> | \"N held orders left open\" at this close (see [`Till`]). Additive. | [optional]
**held_orders_left_open_total** | Option<**i32**> |  | [optional]
**old_bills_at_close** | Option<**i32**> |  | [optional]
**open_bills_at_close** | Option<**i32**> |  | [optional]
**order_number_range** | [**models::OrderNumberRange**](OrderNumberRange.md) |  | 
**reconciliation** | [**Vec<models::TillReconciliationLine>**](TillReconciliationLine.md) |  | 
**till** | [**models::Till**](Till.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


