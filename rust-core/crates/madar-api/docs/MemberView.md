# MemberView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**balance** | **i32** | The live balance, in `mode`'s currency. | 
**can_redeem** | **bool** | The balance affords at least one reward on offer here. | 
**enrolled_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**lifetime_points** | **i32** |  | 
**lifetime_visits** | **i32** |  | 
**locale** | **String** |  | 
**mode** | **String** | `\"points\"` or `\"visits\"` — what the branch that asked collects. | 
**name** | **String** |  | 
**next_reward_cost** | **i32** | The cheapest reward on offer here, in `mode`'s currency — what the progress line counts towards. Falls back to the scope's default cost when no rewards have been curated. | 
**org_id** | **uuid::Uuid** |  | 
**phone** | **String** |  | 
**points_balance** | **i32** |  | 
**points_to_next_reward** | **i32** | `next_reward_cost - balance`, floored at zero. | 
**visits_balance** | **i32** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


