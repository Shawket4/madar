# BookingView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**cancel_reason** | Option<**String**> |  | [optional]
**cancelled_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**cancelled_by** | Option<**String**> |  | [optional]
**completed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | Option<**uuid::Uuid**> |  | [optional]
**ends_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**guest_name** | **String** |  | 
**guest_phone** | **String** |  | 
**held_from** | **chrono::DateTime<chrono::FixedOffset>** | The floor shows the claimed tables as held from here (branch `hold_minutes` before the start). Clients compare with their clock. | 
**id** | **uuid::Uuid** |  | 
**locale** | **String** |  | 
**needs_table** | **bool** | Active but holding no table: the host must assign one. | 
**no_show_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**notes** | Option<**String**> |  | [optional]
**open_ticket_id** | Option<**uuid::Uuid**> | The ticket this party is (or was) eating on. DERIVED from `open_tickets.booking_id` — the live one if there is one, else the latest — never stored on the booking. | [optional]
**party_size** | **i32** |  | 
**phone_verified** | **bool** |  | 
**reminder_sent_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**seated_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**section_id** | Option<**uuid::Uuid**> |  | [optional]
**source** | **String** | `public` | `host`. | 
**starts_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**status** | **String** | `confirmed` | `seated` | `completed` | `no_show` | `cancelled`. | 
**table_ids** | **Vec<uuid::Uuid>** |  | 
**table_labels** | **Vec<String>** |  | 
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


