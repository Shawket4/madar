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
**opened_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**opening_cash** | **i64** |  | 
**revenue_by_method** | Option<**serde_json::Value**> | Goods only, by method actually tendered. Tips are in `total_tips`. | 
**shift_id** | **uuid::Uuid** |  | 
**status** | **String** |  | 
**teller_id** | **uuid::Uuid** |  | 
**teller_name** | **String** |  | 
**total_discount** | **i64** |  | 
**total_orders** | **i64** |  | 
**total_revenue** | **i64** |  | 
**total_tax** | **i64** |  | 
**total_tips** | Option<**i64**> | Tips, standalone — matches `total_tips` on `GET /shifts/{id}/report`. | [optional]
**voided_orders** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


