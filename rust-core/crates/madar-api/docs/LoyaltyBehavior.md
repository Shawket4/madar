# LoyaltyBehavior

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**active_member_rate** | **f64** | `active_members / total_members`. `0.0` when there are no members. | 
**active_members** | **i64** | Distinct (not deleted) members with any loyalty transaction in the range — deleted members are left out of every count so no rate over `total_members` can exceed 1. | 
**from** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**members_ever_redeemed** | **i64** | Distinct (not deleted) members who have ever redeemed a reward. Org-wide, lifetime. | 
**new_member_share** | **f64** | `new_members_active / active_members`. | 
**new_members_active** | **i64** | Active members who enrolled during the range. | 
**one_time_members** | **i64** | Members with exactly 1 earning visit in the range. | 
**redemption_rate** | **f64** | `members_ever_redeemed / total_members`. | 
**redemption_ratio** | **f64** | `redeemed_points_period / earned_points_period` — the share of what was earned in the range that got spent in it. Points earned before the range and redeemed inside it are not the numerator's earn, so this can exceed 1.0 on a range with heavy redemption of an older balance. | 
**repeat_members** | **i64** | Members with 2+ earning visits in the range. | 
**repeat_visit_rate** | **f64** | `repeat_members / (repeat_members + one_time_members)`. `0.0` when nobody earned in the range. | 
**returning_members_active** | **i64** | Active members who enrolled before the range started. | 
**to** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**total_members** | **i64** | Enrolled, not deleted, as of now. Org-wide. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


