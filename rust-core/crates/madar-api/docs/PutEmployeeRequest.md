# PutEmployeeRequest

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**app_access** | Option<**bool**> | Turning it off signs the phone out. | [optional]
**base_salary_piastres** | Option<**i64**> | Piastres. Ignored unless the caller has `hr.payroll.edit` for every branch — a branch manager editing a job title must not award a raise. | [optional]
**branch_ids** | Option<**Vec<uuid::Uuid>**> | The whole set of branches. | [optional]
**department_id** | Option<**uuid::Uuid**> |  | [optional]
**emergency_contact_name** | Option<**String**> |  | [optional]
**emergency_contact_phone** | Option<**String**> |  | [optional]
**employee_code** | Option<**String**> |  | [optional]
**employment_status** | Option<**String**> | `active` | `suspended` | `terminated`. Defaults to `active`. Anything but `active` signs the phone out (RO-10). | [optional]
**gender** | Option<**String**> | `m` · `f`; omitted keeps what is there. | [optional]
**hire_date** | Option<**chrono::NaiveDate**> |  | [optional]
**job_title** | Option<**String**> |  | [optional]
**name** | Option<**String**> |  | [optional]
**national_id** | Option<**String**> |  | [optional]
**notes** | Option<**String**> |  | [optional]
**on_payroll** | Option<**bool**> | Paid through Dawam. Like the salary, ignored unless the caller has `hr.payroll.edit` for every branch. | [optional]
**pay_account** | Option<**String**> |  | [optional]
**pay_method** | Option<**String**> | `cash` · `bank` · `wallet`; omitted keeps what is there. | [optional]
**phone** | Option<**String**> | A new number signs the old phone out (RO-10). Empty clears it. | [optional]
**photo_url** | Option<**String**> |  | [optional]
**termination_date** | Option<**chrono::NaiveDate**> |  | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


