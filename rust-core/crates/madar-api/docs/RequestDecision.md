# RequestDecision

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**is_paid** | Option<**bool**> | Paid or unpaid. REQUIRED when approving leave (RQ-2). For `excuse` and `early_departure`, omitted falls back to the rule (`excused_time_paid_default`, branch then business, RQ-7). | [optional]
**note** | Option<**String**> | Required when cancelling someone else's request, or any approved one (AT-7). | [optional]
**status** | **String** | `approved` | `rejected` | `cancelled`. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


