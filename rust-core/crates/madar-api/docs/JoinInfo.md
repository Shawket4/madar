# JoinInfo

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**branch_name** | **String** |  | 
**earn_piastres_per_point** | **i32** | EGP that earns one point — the page's \"a point for every N EGP\" line. Piastres on the wire, as everywhere; the page divides by 100. Only meaningful when `mode` is `\"points\"`. | 
**enabled** | **bool** | False when the program is off here — the page says so instead of taking a signup that would go nowhere. | 
**mode** | **String** | `\"points\"` (earned on spend) or `\"visits\"` (a stamp per order) — which sentence the page writes. | 
**next_reward_cost** | **i32** | The cheapest reward on offer, in `mode`'s currency. | 
**org_name** | **String** |  | 
**program_name** | **String** |  | 
**program_name_ar** | Option<**String**> |  | [optional]
**require_otp** | **bool** | The page collects an OTP only when the branch asks for one. | 
**rewards** | [**Vec<models::PublicReward>**](PublicReward.md) | The rewards on offer, each with what it costs. | 
**terms** | Option<**String**> |  | [optional]
**terms_ar** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


