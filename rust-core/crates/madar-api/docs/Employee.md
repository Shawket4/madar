# Employee

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**base_salary_piastres** | Option<**i64**> | `None` when the caller lacks `payroll:read` — see the module docs. | [optional]
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**department_id** | Option<**uuid::Uuid**> |  | [optional]
**department_name** | Option<**String**> |  | [optional]
**email** | Option<**String**> |  | [optional]
**emergency_contact_name** | Option<**String**> |  | [optional]
**emergency_contact_phone** | Option<**String**> |  | [optional]
**employee_code** | Option<**String**> |  | [optional]
**employment_status** | **String** |  | 
**hire_date** | Option<**chrono::NaiveDate**> |  | [optional]
**is_active** | **bool** |  | 
**job_title** | Option<**String**> |  | [optional]
**name** | **String** | From `users` — the employee's name IS their user name; there is no second copy to drift. | 
**national_id** | Option<**String**> |  | [optional]
**notes** | Option<**String**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**phone** | Option<**String**> |  | [optional]
**photo_url** | Option<**String**> |  | [optional]
**role** | **String** | The POS role. Orthogonal to employment: a cleaner is a `teller`-role user with the POS permissions revoked. | 
**termination_date** | Option<**chrono::NaiveDate**> |  | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**user_id** | **uuid::Uuid** |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


