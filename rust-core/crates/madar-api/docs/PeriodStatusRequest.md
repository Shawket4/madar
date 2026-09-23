# PeriodStatusRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**reason** | Option<**String**> | Why (AD-9). Required to reopen. | [optional]
**status** | **String** | `draft` (reopen an approved month, before anyone is paid) or `closed` (archive a paid month). Approving is `POST …/generate`; Paid is reached by marking everyone paid (PAY-7), never by hand. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


