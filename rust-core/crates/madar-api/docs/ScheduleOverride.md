# ScheduleOverride

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**created_by** | Option<**uuid::Uuid**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**on_date** | **chrono::NaiveDate** |  | 
**org_id** | **uuid::Uuid** |  | 
**reason** | Option<**String**> |  | [optional]
**user_id** | **uuid::Uuid** |  | 
**work_shift_id** | Option<**uuid::Uuid**> | `None` = an explicit day off. | [optional]
**work_shift_name** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


