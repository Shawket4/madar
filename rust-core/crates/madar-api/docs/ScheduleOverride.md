# ScheduleOverride

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | Option<**uuid::Uuid**> |  | [optional]
**employee_id** | **uuid::Uuid** |  | 
**end_time** | Option<**String**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**on_date** | **chrono::NaiveDate** |  | 
**org_id** | **uuid::Uuid** |  | 
**reason** | Option<**String**> |  | [optional]
**start_time** | Option<**String**> | This assignment's own from/to, when it has one (the block is unchanged). | [optional]
**warnings** | Option<[**Vec<models::LabourWarning>**](LabourWarning.md)> | Labour limits the person's week now goes past. Warnings, never blocks. | [optional]
**work_shift_id** | Option<**uuid::Uuid**> | `None` = an explicit day off. | [optional]
**work_shift_name** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


