# CreateFloorTransferRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**id** | **uuid::Uuid** | Client-minted id (offline-first identity; retries dedup on it). | 
**note** | Option<**String**> |  | [optional]
**occupant_id** | **uuid::Uuid** |  | 
**occupant_kind** | **String** | `held_order` | `open_ticket`. | 
**target_section_id** | Option<**uuid::Uuid**> | The wish: any table in this section… | [optional]
**target_table_id** | Option<**uuid::Uuid**> | …or exactly this table. At least one of the two is required. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


