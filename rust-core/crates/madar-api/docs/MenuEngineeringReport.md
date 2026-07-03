# MenuEngineeringReport

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**cost_basis** | **String** | Cost basis the report was computed with: \"snapshot\" | \"current\". | 
**excluded_sales** | **i64** | Realized revenue (piastres) carried by the excluded SKUs — explains why `total_sales` differs between cost bases: each basis excludes a different set of un-costable rows. | 
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**rows** | [**Vec<models::MenuEngineeringRow>**](MenuEngineeringRow.md) |  | 
**rows_cost_missing** | **i64** | SKUs sold in the window but EXCLUDED from this report because their cost was unresolvable under the chosen basis. | 
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**total_cost** | **i64** |  | 
**total_profit** | **i64** |  | 
**total_sales** | **i64** | Totals over the returned rows. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


