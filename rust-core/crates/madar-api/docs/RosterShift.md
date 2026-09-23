# RosterShift

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | **uuid::Uuid** |  | 
**changed** | **bool** | Changed after its week was published (SC-4). | 
**crosses_midnight** | **bool** | Ends the next day. | 
**date** | **chrono::NaiveDate** |  | 
**employee_id** | **uuid::Uuid** |  | 
**employee_name** | **String** |  | 
**end_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**end_time** | **String** |  | 
**from_override** | **bool** | The date holds its own set, not the standing pattern. | 
**on_leave** | **bool** | On approved leave or a mission that day. | 
**shift_name** | **String** |  | 
**start_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**start_time** | **String** | Effective wall-clock times at the branch (the assignment's own, else the block's for that weekday, else its default). | 
**times_edited** | **bool** | This assignment has its own from/to (show it as edited). | 
**work_shift_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


