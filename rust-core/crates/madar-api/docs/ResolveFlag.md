# ResolveFlag

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**action** | **String** | `ignore` · `excuse_paid` · `excuse_unpaid` · `deduct` · `revoke` (a new phone) · `confirm`. A cover's flag takes only `confirm` or `reject`, which decide the cover itself (400 `FLAG_COVER_CONFIRM_OR_REJECT`). | 
**amount_piastres** | Option<**i64**> | For `deduct`: the amount the manager typed (CL-7). | [optional]
**reason** | Option<**String**> | For `deduct`: why, on the pay line the employee sees (AD-9). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


