# VarianceReport

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**net_variance_value** | **i64** | overage − shrinkage (net effect on inventory value). | 
**rows** | [**Vec<models::VarianceRow>**](VarianceRow.md) |  | 
**stocktake_id** | **uuid::Uuid** |  | 
**total_overage_value** | **i64** | Piastres of overage (positive variances). | 
**total_shrinkage_value** | **i64** | Piastres lost to shrinkage (negative variances), as a positive number. | 
**unknown_cost_count** | **i64** | Count of counted rows whose cost was unknown (excluded from totals). | 
**variance_threshold_pct** | **f64** | Org tolerance used to compute `is_flagged`. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


