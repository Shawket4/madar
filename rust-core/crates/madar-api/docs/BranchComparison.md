# BranchComparison

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**avg_order_value** | **i64** |  | 
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**cash_tips** | Option<**i64**> | The cash slice of `total_tips`. | [optional]
**gross_sales** | Option<**i64**> |  | [optional]
**refunded_amount** | Option<**i64**> |  | [optional]
**revenue_by_method** | Option<**serde_json::Value**> | Goods only, by method actually tendered — money in. Tips are in `total_tips`; refunds are not netted from the buckets. | 
**total_orders** | **i64** |  | 
**total_revenue** | **i64** | Net of refunds: `gross_sales − refunded_amount`. | 
**total_tips** | Option<**i64**> | Tips, standalone — same definition as on the branch sales + shift reports. | [optional]
**void_rate_pct** | **f64** |  | 
**voided_orders** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


