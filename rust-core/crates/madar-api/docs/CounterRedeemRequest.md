# CounterRedeemRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**customer_id** | **uuid::Uuid** |  | 
**idempotency_key** | **String** | One per attempt, made by the page (a UUID). | 
**track** | Option<**u32**> | The stamp track (1–4) to complete; absent = track 1. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


