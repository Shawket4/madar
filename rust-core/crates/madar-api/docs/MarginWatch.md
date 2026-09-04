# MarginWatch

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**bottom** | [**Vec<models::MarginLedgerRow>**](MarginLedgerRow.md) | Worst contributors (asc, only rows with known margin), max 3. | 
**branch_id** | **uuid::Uuid** |  | 
**from** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**open_signals** | **i64** |  | 
**rows_cost_unknown** | **i64** |  | 
**target_pct** | **f64** |  | 
**to** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**top** | [**Vec<models::MarginLedgerRow>**](MarginLedgerRow.md) | Top contributors by known margin (desc), max 3. | 
**totals** | [**models::LedgerTotals**](LedgerTotals.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


