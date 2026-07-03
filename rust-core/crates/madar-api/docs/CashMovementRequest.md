# CashMovementRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**amount** | **i32** |  | 
**client_ref** | Option<**uuid::Uuid**> | Client-minted idempotency / reconciliation key. The POS sends a stable UUID per movement so a replayed offline movement dedupes instead of double-applying. Omit for live online movements. | [optional]
**created_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the movement actually happened. Omit for live (online) movements — the server stamps `now()`. The POS sends this for movements made OFFLINE so they keep their real time after syncing. Future values are rejected. | [optional]
**note** | **String** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


