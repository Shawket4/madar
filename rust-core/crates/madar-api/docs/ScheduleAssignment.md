# ScheduleAssignment

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**day_of_week** | Option<**i32**> | Postgres `EXTRACT(DOW)` convention: 0 = Sunday … 6 = Saturday. `None` = every day of the week. | [optional]
**effective_from** | **chrono::NaiveDate** |  | 
**effective_to** | Option<**chrono::NaiveDate**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**org_id** | **uuid::Uuid** |  | 
**user_id** | **uuid::Uuid** |  | 
**work_shift_id** | **uuid::Uuid** |  | 
**work_shift_name** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


