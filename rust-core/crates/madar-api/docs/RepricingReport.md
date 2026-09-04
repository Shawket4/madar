# RepricingReport

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**skus_considered** | **i64** | Active priced SKUs considered in total. | 
**skus_cost_unknown** | **i64** | Active priced SKUs whose cost is not fully known — NOT suggested (no guessed cost); surfaced so coverage is transparent. | 
**suggestions** | [**Vec<models::RepricingSuggestion>**](RepricingSuggestion.md) | Underpriced SKUs with a target-restoring suggestion, biggest uplift first. | 
**target_pct** | **f64** |  | 
**target_source** | **String** | `branch` | `org` | `default`. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


