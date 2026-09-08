# ScanResult

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**any_item** | **bool** | The whole menu is claimable, not just `rewards`.  When on, `rewards` stops being the list of what MAY be claimed — it is only what happens to be curated — and the till offers every line at `any_item_cost`. Sent rather than inferred, because a till cannot tell \"no catalogue\" apart from \"any item\" without being told. | 
**any_item_cost** | **i32** | What one line costs when `any_item` is on, in the branch's currency. | 
**member** | [**models::MemberView**](MemberView.md) |  | 
**recent** | [**Vec<models::LedgerEntry>**](LedgerEntry.md) | Recent history, so a teller can answer \"where did my points go?\". | 
**rewards** | [**Vec<models::RewardItem>**](RewardItem.md) | What this member could claim at this branch right now. Empty until the balance reaches the threshold, so the screen cannot tempt a teller into handing over a reward that has not been earned. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


