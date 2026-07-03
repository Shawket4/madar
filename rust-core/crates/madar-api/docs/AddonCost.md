# AddonCost

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**addon_item_id** | **uuid::Uuid** |  | 
**addon_type** | **String** |  | 
**cost** | Option<**i64**> | Ingredient cost rollup in piastres over the ingredients that *are* priced. A partial rollup still returns the sum so far, with `cost_missing = true`; `null` only when nothing is priced. | [optional]
**cost_missing** | **bool** | `true` when at least one ingredient is unlinked or has no cost, so `cost` (if any) is partial rather than the full figure. | 
**margin_pct** | Option<**f64**> | `(price - cost) / price` — only when the cost is *complete* and price > 0. | [optional]
**name** | **String** |  | 
**price** | **i64** | Default price in piastres. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


