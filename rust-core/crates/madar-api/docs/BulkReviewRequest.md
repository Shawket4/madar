# BulkReviewRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**approval** | Option<[**models::ReplayApproval**](ReplayApproval.md)> | Optional one-time manager approval (the ordinary `ReplayApproval` shape, as `live_approval` carries on an order, a refund or a waste). Additive: without it the call behaves exactly as before. | [optional]
**flag_ids** | **Vec<i64>** | Every open flag to resolve at once — a till, a day, or a hand-picked selection. Order does not matter; each id is its own transaction. | 
**note** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


