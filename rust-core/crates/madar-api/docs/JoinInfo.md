# JoinInfo

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**birthday_enabled** | **bool** | Ask for a date of birth. False means the form does not show the field — a shop that does not run birthday rewards is not given one to hold. | 
**birthday_reward_amount** | Option<**i32**> | What the birthday is worth here, so the page can say what it is FOR rather than asking for a date of birth and explaining nothing. | [optional]
**branch_id** | Option<**uuid::Uuid**> | Absent for an org-wide code — the customer has not told us where they are, and nothing in the programme needs to know. | [optional]
**branch_name** | Option<**String**> |  | [optional]
**brand** | [**models::CardBrand**](CardBrand.md) | Whose programme this is, and how the page should look. | 
**earn_piastres_per_point** | **i32** | EGP that earns one point — the page's \"a point for every N EGP\" line. Piastres on the wire, as everywhere; the page divides by 100. Only meaningful when `mode` is `\"points\"`. | 
**enabled** | **bool** | False when the program is off here — the page says so instead of taking a signup that would go nowhere. | 
**mode** | **String** | `\"points\"` (earned on spend) or `\"visits\"` (a stamp per order) — which sentence the page writes. | 
**next_reward_cost** | **i32** | The cheapest reward on offer, in `mode`'s currency. | 
**require_otp** | **bool** | The page collects an OTP only when the branch asks for one. | 
**rewards** | [**Vec<models::PublicReward>**](PublicReward.md) | The rewards on offer, each with what it costs. | 
**terms** | Option<**String**> |  | [optional]
**terms_ar** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


