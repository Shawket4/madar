# PutEmployeeRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**base_salary_piastres** | Option<**i64**> | Piastres. Ignored unless the caller has `payroll:update` — a branch manager editing a job title must not be able to award a raise. | [optional]
**department_id** | Option<**uuid::Uuid**> |  | [optional]
**emergency_contact_name** | Option<**String**> |  | [optional]
**emergency_contact_phone** | Option<**String**> |  | [optional]
**employee_code** | Option<**String**> |  | [optional]
**employment_status** | Option<**String**> | `active` | `suspended` | `terminated`. Defaults to `active`. | [optional]
**hire_date** | Option<**chrono::NaiveDate**> |  | [optional]
**job_title** | Option<**String**> |  | [optional]
**national_id** | Option<**String**> |  | [optional]
**notes** | Option<**String**> |  | [optional]
**photo_url** | Option<**String**> |  | [optional]
**termination_date** | Option<**chrono::NaiveDate**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


