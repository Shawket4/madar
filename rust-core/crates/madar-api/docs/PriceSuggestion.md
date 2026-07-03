# PriceSuggestion

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**action** | [**models::Action**](Action.md) |  | 
**anchors** | [**models::PriceAnchors**](PriceAnchors.md) |  | 
**classification** | [**models::Classification**](Classification.md) |  | 
**cm_per_unit** | Option<**f64**> |  | [optional]
**confidence** | [**models::Confidence**](Confidence.md) |  | 
**cost_missing** | **bool** | True when cost data is unavailable for this item. Mirrors `classification` mode, exposed flat for UI badge rendering. | 
**cost_reduction_whatif_margin** | Option<**f64**> | Only computed for CM-tracked Plowhorses. | [optional]
**current_price** | **i64** |  | 
**effective_price** | **f64** |  | 
**explanation** | **String** |  | 
**food_cost_pct** | Option<**f64**> |  | [optional]
**guard_clips** | [**Vec<models::GuardClip>**](GuardClip.md) |  | 
**item_name** | **String** |  | 
**key** | [**models::ItemKey**](ItemKey.md) |  | 
**margin_pct** | Option<**f64**> |  | [optional]
**peer_comparison** | Option<[**models::PeerComparison**](PeerComparison.md)> |  | [optional]
**popularity_share** | **f64** |  | 
**price_changed_in_window** | **bool** |  | 
**suggested_delta_abs** | Option<**i64**> |  | [optional]
**suggested_delta_pct** | Option<**f64**> |  | [optional]
**suggested_price** | Option<**i64**> |  | [optional]
**units_sold_raw** | **f64** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


