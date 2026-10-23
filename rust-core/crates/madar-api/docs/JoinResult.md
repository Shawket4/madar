# JoinResult

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**already_member** | **bool** | True when this phone was already a member — the page says \"welcome back\" rather than pretending to have made a new card. | 
**balance** | **i32** | The live balance, in `mode`'s currency. Zero for a fresh member, and zero (not the real figure) while `verify_required`. | 
**brand** | [**models::CardBrand**](CardBrand.md) |  | 
**card_link_sent** | **bool** | While `verify_required`: the card link was also sent to the number on file, by WhatsApp — the one channel that proves possession without a code. False when no gateway is configured or there is no public base to build a link on; the page then offers only the OTP. | 
**card_size** | Option<**i32**> | The card size: how many stamps (or points) fill one card, the cheapest reward on offer (`model::card_size`), the same figure the till and the passes count towards. Equal to `next_reward_cost`, under its own name. | [optional]
**member_token** | Option<**String**> | Absent when `verify_required`: the page has nothing to show yet. | [optional]
**mode** | **String** |  | 
**name** | **String** | The name as the caller typed it. For a returning member the name ON FILE is not echoed until they have verified — it is a fact about the person who owns the phone, not about the person typing it. | 
**next_reward_cost** | **i32** |  | 
**passes** | Option<[**models::PassLinks**](PassLinks.md)> | Absent when `verify_required`. | [optional]
**stamp_unit** | Option<**String**> | What one stamp stands for: `order`, `item` or `stamp` (a counter shop); absent for points. The join info's rule (`earn::StampUnit`). | [optional]
**verify_required** | **bool** | This phone already has a card and the device has not proved it owns the phone. The page should run the ordinary OTP flow (`/public/otp/request` then `/public/otp/verify`) and POST here again with the `device_token` it is handed; the card comes back on that call. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


