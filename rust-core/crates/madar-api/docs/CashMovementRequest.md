# CashMovementRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount** | **i32** |  | 
**client_ref** | Option<**uuid::Uuid**> | Client-minted idempotency / reconciliation key. The POS sends a stable UUID per movement so a replayed offline movement dedupes instead of double-applying. Omit for live online movements. | [optional]
**corrects_id** | Option<**uuid::Uuid**> | For a `correction` only: the movement on this shift it reverses. The amount must be the exact opposite of that row's, and a row may be corrected once. Omit for a correction of something never recorded. | [optional]
**created_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the movement actually happened. Omit for live (online) movements — the server stamps `now()`. The POS sends this for movements made OFFLINE so they keep their real time after syncing. Future values are rejected. | [optional]
**kind** | Option<[**models::CashMovementKind**](CashMovementKind.md)> | What the movement is. Optional for the clients already in the field, which send only a signed amount: an omitted kind resolves by sign (negative → `pay_out`, positive → `pay_in`), exactly what the In/Out chips have always meant. A supplied kind must agree with the sign. | [optional]
**note** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


