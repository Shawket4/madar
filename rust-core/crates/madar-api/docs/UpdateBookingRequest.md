# UpdateBookingRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**duration_minutes** | Option<**i32**> |  | [optional]
**force** | Option<**bool**> | Keep the booking when no table fits after a move (default true). | [optional]
**guest_name** | Option<**String**> |  | [optional]
**guest_phone** | Option<**String**> |  | [optional]
**notes** | Option<**String**> |  | [optional]
**party_size** | Option<**i32**> |  | [optional]
**section_id** | Option<**uuid::Uuid**> |  | [optional]
**starts_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**table_ids** | Option<**Vec<uuid::Uuid>**> | Present = reassign to exactly these tables (empty = unassign). | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


