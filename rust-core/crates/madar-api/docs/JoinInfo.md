# JoinInfo

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**birthday_enabled** | **bool** | Ask for a date of birth. False means the form does not show the field — a shop that does not run birthday rewards is not given one to hold. | 
**birthday_gift** | Option<**String**> | What the birthday gives here: `item` (one free item) or `amount` (`birthday_reward_amount` on the card). Absent when birthdays are off or give nothing. | [optional]
**birthday_reward_amount** | Option<**i32**> | What the birthday is worth here, so the page can say what it is FOR rather than asking for a date of birth and explaining nothing. | [optional]
**branch_id** | Option<**uuid::Uuid**> | Absent for an org-wide code — the customer has not told us where they are, and nothing in the programme needs to know. | [optional]
**branch_name** | Option<**String**> |  | [optional]
**brand** | [**models::CardBrand**](CardBrand.md) | Whose programme this is, and how the page should look. | 
**card** | Option<[**models::PublicCard**](PublicCard.md)> | The shop's card design, when it published one (or runs several stamp tracks): the page draws it with the `card` wasm package. Absent = the classic card, and the page loads nothing extra. | [optional]
**card_size** | Option<**i32**> | The card size: how many stamps (or points) fill one card, the cheapest reward on offer (`model::card_size`), the same figure the till and the passes count towards. Equal to `next_reward_cost`, under its own name. | [optional]
**earn_piastres_per_point** | **i32** | EGP that earns one point — the page's \"a point for every N EGP\" line. Piastres on the wire, as everywhere; the page divides by 100. Only meaningful when `mode` is `\"points\"`. | 
**enabled** | **bool** | False when the program is off here — the page says so instead of taking a signup that would go nowhere. | 
**member_count** | Option<**i64**> | \"N+ people already have this card\": the programme's live members, floored to a step (100, 150, 200, 250, 300, 400, 500, 750, 1000, ...; `loyalty::social`). Absent at 100 members or fewer, and never exact. | [optional]
**mode** | **String** | `\"points\"` (earned on spend) or `\"visits\"` (a stamp per order) — which sentence the page writes. | 
**next_reward_cost** | **i32** | The cheapest reward on offer, in `mode`'s currency. | 
**require_otp** | **bool** | The page collects an OTP only when the branch asks for one. | 
**rewards** | [**Vec<models::PublicReward>**](PublicReward.md) | The rewards on offer, each with what it costs. | 
**stamp_unit** | Option<**String**> | What one stamp stands for: `order` (one per sale), `item` (one per item bought) or `stamp` (a Rewards by Madar counter shop: the teller stamps the card). Absent for a points programme. The same rule the passes and messages use (`earn::StampUnit`). | [optional]
**terms** | Option<**String**> |  | [optional]
**terms_ar** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


