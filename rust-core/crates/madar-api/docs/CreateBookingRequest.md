# CreateBookingRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**duration_minutes** | Option<**i32**> | Defaults to the branch's `default_duration_minutes`. | [optional]
**force** | Option<**bool**> | Create even when no table fits (the booking shows as \"needs a table\"). | [optional]
**guest_name** | **String** |  | 
**guest_phone** | **String** |  | 
**locale** | Option<**String**> | `en` | `ar` for the guest's messages. | [optional]
**notes** | Option<**String**> |  | [optional]
**party_size** | **i32** |  | 
**section_id** | Option<**uuid::Uuid**> | Seating preference for the auto-assigner. | [optional]
**send_confirmation** | Option<**bool**> | Send the WhatsApp confirmation (default true). | [optional]
**starts_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**table_ids** | Option<**Vec<uuid::Uuid>**> | Explicit tables (skips auto-assignment). Empty = deliberately none. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


