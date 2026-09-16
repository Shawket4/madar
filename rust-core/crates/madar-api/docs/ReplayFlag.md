# ReplayFlag

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**author_id** | **uuid::Uuid** |  | 
**author_name** | Option<**String**> |  | [optional]
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**capability** | **String** | The `resource:action` cell the author did not hold. | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** | When it reached us. The gap is the offline window. | 
**id** | **i64** |  | 
**occurred_at** | **chrono::DateTime<chrono::FixedOffset>** | When the act happened on the device. | 
**op** | **String** | The replayed op, e.g. `CashMovement`. | 
**reason** | **String** | `stale_snapshot` — they held it when they acted and the device had not heard the revocation yet. `unauthorized_offline` — nothing explains it. `pin_wrong_branch` — their correct PIN was typed at a branch they may not sign in at (`op` = `PinSignIn`, `details.attempts` counts the tries). | 
**reviewed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**reviewed_by** | Option<**uuid::Uuid**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


