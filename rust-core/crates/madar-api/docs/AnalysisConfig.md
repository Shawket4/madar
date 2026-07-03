# AnalysisConfig

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**analysis_window_days** | Option<**f64**> |  | [optional][default to 30.0]
**bundle_discount_pct_range** | Option<**Vec<serde_json::Value>**> |  | [optional][default to [0.1, 0.25]]
**bundle_max_size** | Option<**u32**> |  | [optional][default to 3]
**bundle_top_k_partners** | Option<**u32**> |  | [optional][default to 5]
**bundle_top_n_per_focus** | Option<**u32**> |  | [optional][default to 3]
**halo_repeat_rate** | Option<**f64**> |  | [optional][default to 0.15]
**max_price_change_pct_per_cycle** | Option<**f64**> |  | [optional][default to 0.15]
**min_cooccurrences_for_bundle** | Option<**f64**> |  | [optional][default to 8.0]
**min_gross_margin_pct** | Option<**f64**> |  | [optional][default to 0.55]
**min_lift_for_bundle** | Option<**f64**> |  | [optional][default to 1.2]
**min_units_for_classification** | Option<**f64**> |  | [optional][default to 20.0]
**price_rounding_rule** | Option<[**models::PriceRoundingRule**](PriceRoundingRule.md)> |  | [optional]
**promotion_lift_prior** | Option<**f64**> |  | [optional][default to 1.25]
**recency_half_life_days** | Option<**f64**> |  | [optional][default to 14.0]
**revenue_mode_max_raise_pct** | Option<**f64**> | Conservative max-raise cap for revenue-only items (no margin floor to guard against). | [optional][default to 0.05]
**target_food_cost_pct** | Option<**f64**> |  | [optional][default to 0.3]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


