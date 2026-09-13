# LoyaltyAnalytics

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**earned_points** | **i64** | Balance earned, net of clawbacks written in the range. | 
**from** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**liability** | [**models::PointsLiability**](PointsLiability.md) |  | 
**redeemed_points** | **i64** | Balance spent, net of reversals written in the range. | 
**redeemed_units** | **i64** | Units handed over as rewards. | 
**redeemed_value_minor** | **i64** | Minor units of goods given away as rewards, on sales not voided. | 
**redemptions** | **i64** | Redemption rows in the range (one per covered order line). | 
**refused_redemptions** | **i64** | Replayed sales whose rewards the points could not pay for. | 
**to** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**top_rewards** | [**Vec<models::TopReward>**](TopReward.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


