# CardView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**balance** | **i32** | The live balance, in `mode`'s currency. | 
**birthday_gift** | Option<[**models::BirthdayGiftView**](BirthdayGiftView.md)> | The member's birthday gift while it is open, or claimed and still in its window. Absent otherwise. | [optional]
**brand** | [**models::CardBrand**](CardBrand.md) | Whose card this is, and how it should look. | 
**can_redeem** | **bool** |  | 
**card** | Option<[**models::PublicCard**](PublicCard.md)> | The shop's card design (see [`JoinInfo::card`]); absent = classic. | [optional]
**card_size** | Option<**i32**> | The card size: how many stamps (or points) fill one card, the cheapest reward on offer (`model::card_size`), the same figure the till and the passes count towards. Equal to `next_reward_cost`, under its own name. | [optional]
**marketing_opt_out** | **bool** | They have asked this shop to stop sending them things. | 
**member_token** | **String** |  | 
**mode** | **String** |  | 
**name** | **String** |  | 
**next_reward_cost** | **i32** |  | 
**order_now_url** | Option<**String**> | \"Order now\": the ordering page, opened knowing who this is. Present only when public ordering is configured and the shop takes online orders — render the primary button when it is there, nothing when it is not. | [optional]
**passes** | [**models::PassLinks**](PassLinks.md) |  | 
**points_to_next_reward** | **i32** |  | 
**progress_to_next** | **i32** | Progress towards the next one, after the earned ones are set aside. | 
**rewards** | [**Vec<models::PublicReward>**](PublicReward.md) |  | 
**rewards_ready** | **i32** | Rewards the balance has already earned — a card does not stop at full. | 
**stamp_unit** | Option<**String**> | What one stamp stands for: `order`, `item` or `stamp` (a counter shop); absent for points. The join info's rule (`earn::StampUnit`). | [optional]
**tracks** | Option<[**Vec<models::MemberTrack>**](MemberTrack.md)> | Every stamp track of this member's card, when there is more than one. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


