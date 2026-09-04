# MarginLedgerReport

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**cost_basis** | **String** |  | 
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**rows** | [**Vec<models::MarginLedgerRow>**](MarginLedgerRow.md) |  | 
**rows_cost_unknown** | **i64** | Rows whose cost is unknown under the chosen basis (they ARE in `rows`). | 
**target_pct** | **f64** |  | 
**target_source** | **String** | `branch` | `org` | `default`. | 
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**totals** | [**models::LedgerTotals**](LedgerTotals.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


