# HoldTableRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**seated_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the party actually sat down, by the till's clock. An offline seat replays later than it happened; this keeps every device's table clock on the seating. Clamped server-side to the last 12 hours, never in the future, and never before the table's previous party left. Recorded only -- it moves no status. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


