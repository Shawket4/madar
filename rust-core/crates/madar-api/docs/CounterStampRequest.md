# CounterStampRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**customer_id** | **uuid::Uuid** | The member, as `/loyalty/lookup` resolved them. | 
**idempotency_key** | **String** | One per attempt, made by the page (a UUID). A retry with the same key stamps nothing new. | 
**items** | **u32** | Items bought on this visit, 1 to 50. | 
**track** | Option<**u32**> | The stamp track (1–4); absent = track 1. A track 2–4 stamps `items` stamps (or one with its \"per sale\" setting). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


