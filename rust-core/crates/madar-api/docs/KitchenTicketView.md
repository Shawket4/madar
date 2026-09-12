# KitchenTicketView

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**close_reason** | Option<**String**> | `bumped`, `settled`, `voided` or `retired` — see [`CloseReason`]. | [optional]
**closed_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When the ticket left the kitchen's attention for good; `null` while it is live. A till queue that shows history renders closed tickets greyed; the KDS feed never returns them. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**id** | **uuid::Uuid** |  | 
**items** | [**Vec<models::KitchenTicketItemView>**](KitchenTicketItemView.md) |  | 
**kitchen_ref** | Option<**String**> |  | [optional]
**round_number** | **i32** |  | 
**source_id** | **uuid::Uuid** |  | 
**source_type** | **String** |  | 
**status** | **String** | The state of the cooking: `firing`, `ready`, `voided`. | 
**table_label** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


