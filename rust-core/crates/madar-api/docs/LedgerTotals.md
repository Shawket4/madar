# LedgerTotals

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**below_target_gap** | **i64** | Σ(target·revenue − margin) over below-target rows — \"margin left on the table\" this period, in piastres. | 
**cost_known** | **i64** | Cost summed over rows where it is known. | 
**margin_known** | **i64** |  | 
**margin_pct** | Option<**f64**> |  | [optional]
**prev_margin_known** | **i64** |  | 
**prev_revenue** | **i64** |  | 
**revenue** | **i64** |  | 
**revenue_cost_unknown** | **i64** | Revenue sitting on rows whose cost is unknown (visibly reconciles). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


