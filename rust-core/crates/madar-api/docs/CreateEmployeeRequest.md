# CreateEmployeeRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**app_access** | Option<**bool**> | May sign in to the staff app. Defaults to \"has a phone\". | [optional]
**base_salary_piastres** | Option<**i64**> | Piastres. Ignored without `hr.payroll.edit` for every branch. | [optional]
**branch_id** | Option<**uuid::Uuid**> |  | [optional]
**branch_ids** | Option<**Vec<uuid::Uuid>**> | Where they work (at least one). `branch_id` is the older one-branch form. | [optional]
**department_id** | Option<**uuid::Uuid**> |  | [optional]
**employee_code** | Option<**String**> |  | [optional]
**gender** | Option<**String**> | `m` · `f` | [optional]
**hire_date** | Option<**chrono::NaiveDate**> | Defaults to today. | [optional]
**job_title** | Option<**String**> |  | [optional]
**name** | Option<**String**> | Required unless `user_id` is given. | [optional]
**phone** | Option<**String**> | Their WhatsApp number: how they sign in to the staff app. | [optional]
**user_id** | Option<**uuid::Uuid**> | Make this existing Madar user an employee (kind `linked`). Their name and number are the defaults for the employee's. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


