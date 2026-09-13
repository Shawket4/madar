# HoldTableRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**party_size** | Option<**i32**> | How many people sat down (covers), as the host counted them. Recorded on the hold and inherited by the bill's first round when it carries no guest count of its own. Anything not positive is not recorded. | [optional]
**seated_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the party actually sat down, by the till's clock. An offline seat replays later than it happened; this keeps every device's table clock on the seating. Clamped server-side to the last 12 hours, never in the future, and never before the table's previous party left. Recorded only -- it moves no status. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


