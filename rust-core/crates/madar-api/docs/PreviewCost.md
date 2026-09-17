# PreviewCost

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**cost_missing** | **bool** | At least one deducted line has no cost: `total` is partial. | 
**margin_pct** | Option<**f64**> | `(price − cost) / price` (fraction, like `/costing`); null when the cost is partial or the price is 0. | [optional]
**total** | **i64** | Piastres over the deducted lines with a known cost. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


