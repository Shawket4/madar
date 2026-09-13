# PointsLiability

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**currency** | **String** | `\"points\"` or `\"visits\"` — the currency the valuation is in. | 
**members_with_balance** | **i64** | Live members with a positive balance. | 
**outstanding_points** | **i64** |  | 
**outstanding_visits** | **i64** |  | 
**value_per_unit_minor** | Option<**f64**> | Minor units one unit of the live currency has bought, on average, over every redemption this org has recorded (value given ÷ balance spent). `None` until the first redemption with a recorded value. | [optional]
**valued_minor** | Option<**i64**> | The outstanding balance in the live currency × `value_per_unit_minor`, rounded. An estimate — a balance is worth what it will be spent on. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


