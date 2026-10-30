# FinalizeInput

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**payment_method** | **String** | The actual method the customer paid (overrides the hint). Must be an org method. | 
**sold_by** | Option<**uuid::Uuid**> | Who was picked as serving at checkout, on a branch that asks (`branches.pick_teller_at_checkout`). Same rule as `sold_by` on an order: attribution only; someone who cannot ring sales at the branch is recorded as nobody, never refused. Additive. | [optional]
**till_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


