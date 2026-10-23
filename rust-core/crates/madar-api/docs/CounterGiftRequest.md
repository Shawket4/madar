# CounterGiftRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**customer_id** | **uuid::Uuid** | The member, as `/loyalty/lookup` resolved them. | 
**idempotency_key** | **String** | One per attempt, made by the page (a UUID). A retry with the same key claims nothing new. | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


