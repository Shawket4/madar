# BundleSuggestion

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**association** | [**models::BundleAssociation**](BundleAssociation.md) |  | 
**bundle_cm** | Option<**i64**> |  | [optional]
**bundle_cost** | Option<**i64**> | All cost-derived fields are `None` when any component lacks cost data. | [optional]
**bundle_discount_pct** | **f64** |  | 
**bundle_items** | [**Vec<models::ItemKey>**](ItemKey.md) |  | 
**bundle_list_price** | **i64** |  | 
**bundle_margin_pct** | Option<**f64**> |  | [optional]
**bundle_suggested_price** | **i64** |  | 
**explanation** | **String** |  | 
**focus_item** | [**models::ItemKey**](ItemKey.md) |  | 
**forecast** | [**models::BundleForecast**](BundleForecast.md) |  | 
**guard_clips** | [**Vec<models::GuardClip>**](GuardClip.md) |  | 
**missing_costs** | **bool** | True ⟺ at least one component is cost-missing. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


