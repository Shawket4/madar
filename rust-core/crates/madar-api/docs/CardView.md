# CardView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**balance** | **i32** | The live balance, in `mode`'s currency. | 
**brand** | [**models::CardBrand**](CardBrand.md) | Whose card this is, and how it should look. | 
**can_redeem** | **bool** |  | 
**marketing_opt_out** | **bool** | They have asked this shop to stop sending them things. | 
**member_token** | **String** |  | 
**mode** | **String** |  | 
**name** | **String** |  | 
**next_reward_cost** | **i32** |  | 
**passes** | [**models::PassLinks**](PassLinks.md) |  | 
**points_to_next_reward** | **i32** |  | 
**progress_to_next** | **i32** | Progress towards the next one, after the earned ones are set aside. | 
**rewards** | [**Vec<models::PublicReward>**](PublicReward.md) |  | 
**rewards_ready** | **i32** | Rewards the balance has already earned — a card does not stop at full. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


