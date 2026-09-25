# ReviewAdvance

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount_piastres** | Option<**i64**> | Approve a different amount than asked. | [optional]
**approve** | **bool** |  | 
**installments** | Option<**i32**> |  | [optional]
**note** | Option<**String**> | Why (kept as the decision note). Required to reject: `note` or `reason`, `reason` wins (400 `REASON_REQUIRED`, D8). | [optional]
**reason** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


