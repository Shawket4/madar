# ScanResult

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**member** | [**models::MemberView**](MemberView.md) |  | 
**recent** | [**Vec<models::LedgerEntry>**](LedgerEntry.md) | Recent history, so a teller can answer \"where did my points go?\". | 
**rewards** | [**Vec<models::RewardItem>**](RewardItem.md) | What this member could claim at this branch right now. Empty until the balance reaches the threshold, so the screen cannot tempt a teller into handing over a reward that has not been earned. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


