# SkuCost

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**category_id** | Option<**uuid::Uuid**> |  | [optional]
**cost** | Option<**i64**> | Recipe cost rollup in piastres over the ingredients that *are* priced. `null` only when there is no recipe, or no recipe ingredient has a known cost at all. A partial rollup (some ingredients unpriced) still returns the sum so far, with `cost_missing = true` flagging it as incomplete. | [optional]
**cost_missing** | **bool** | `true` when at least one recipe ingredient is unlinked or has no cost, so `cost` (if any) is a partial figure rather than the full COGS. | 
**food_cost_pct** | Option<**f64**> | `cost / price` — only when the cost is *complete* and price > 0. | [optional]
**item_name** | **String** |  | 
**margin_pct** | Option<**f64**> | `(price - cost) / price` — only when the cost is *complete* and price > 0. Suppressed (`null`) for partial rollups so an incomplete cost is never graded as a food-cost percentage. | [optional]
**menu_item_id** | **uuid::Uuid** |  | 
**price** | **i64** | Current price in piastres for this SKU. | 
**size_label** | **String** | `\"one_size\"` when the item has no sizes. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


