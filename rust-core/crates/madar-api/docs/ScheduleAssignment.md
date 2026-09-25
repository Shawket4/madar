# ScheduleAssignment

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**branch_id** | Option<**uuid::Uuid**> | Where a business-wide block is worked (hunt H2-B8b); null = the block's own branch, else the person's first. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**day_of_week** | Option<**i32**> | Postgres `EXTRACT(DOW)` convention: 0 = Sunday … 6 = Saturday. `None` = every day of the week. | [optional]
**effective_from** | **chrono::NaiveDate** |  | 
**effective_to** | Option<**chrono::NaiveDate**> |  | [optional]
**employee_id** | **uuid::Uuid** |  | 
**id** | **uuid::Uuid** |  | 
**org_id** | **uuid::Uuid** |  | 
**work_shift_id** | **uuid::Uuid** |  | 
**work_shift_name** | Option<**String**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


