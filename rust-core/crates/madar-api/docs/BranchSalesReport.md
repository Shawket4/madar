# BranchSalesReport

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**by_category** | [**Vec<models::CategorySales>**](CategorySales.md) |  | 
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**revenue_by_method** | Option<**serde_json::Value**> |  | 
**subtotal** | **i64** |  | 
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**top_items** | [**Vec<models::ItemSales>**](ItemSales.md) |  | 
**total_discount** | **i64** |  | 
**total_orders** | **i64** |  | 
**total_revenue** | **i64** |  | 
**total_tax** | **i64** |  | 
**voided_orders** | **i64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


