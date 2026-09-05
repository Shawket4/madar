# TransferView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**from_table_id** | Option<**uuid::Uuid**> |  | [optional]
**fulfilled_table_id** | Option<**uuid::Uuid**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**note** | Option<**String**> |  | [optional]
**occupant_id** | **uuid::Uuid** |  | 
**occupant_kind** | **String** | Always `open_ticket`. Kept on the wire so the rebuilt booking flow can queue into the same waitlist without a schema change. | 
**occupant_label** | Option<**String**> | Display label for the queue: the held order's name / the ticket's ref. | [optional]
**requested_by** | Option<**uuid::Uuid**> |  | [optional]
**resolved_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**status** | **String** | `waiting` | `fulfilled` | `cancelled`. | 
**target_section_id** | Option<**uuid::Uuid**> |  | [optional]
**target_table_id** | Option<**uuid::Uuid**> |  | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


