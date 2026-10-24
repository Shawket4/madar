# BirthdayGiftView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**any_item** | Option<**bool**> | The till's lookup only, while `open`: every line may be the gift (\"any item\" is a reward here). Absent elsewhere. | [optional]
**reward_item_ids** | Option<**Vec<uuid::Uuid>**> | The till's lookup only, while `open`: the reward items the gift may be taken as, whatever each costs (the whole catalogue, not only what the balance affords). The till runs `madar_loyalty::gift_eligible` over these and `any_item`, the server's own claim rule. Absent elsewhere. | [optional]
**status** | **String** | `open` (ready to claim) or `claimed`. | 
**valid_until** | **chrono::DateTime<chrono::FixedOffset>** | The gift is usable until this instant (end of its last day, shop time). | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


