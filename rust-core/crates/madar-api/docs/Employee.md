# Employee

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**app_access** | **bool** | May sign in to the staff app with a WhatsApp code. | 
**base_salary_piastres** | Option<**i64**> | `None` when the caller may not read this person's pay — see the module docs. | [optional]
**branch_ids** | **Vec<uuid::Uuid>** | Where they work; managers see the people of their branches (RO-6). | 
**cant_work_days** | **Vec<i32>** | Days they can't work: 0 = Sunday … 6 = Saturday. | 
**created_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**department_id** | Option<**uuid::Uuid**> |  | [optional]
**department_name** | Option<**String**> |  | [optional]
**device_last_seen** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**device_model** | Option<**String**> | The live phone signed in to the staff app, if any. | [optional]
**device_since** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**email** | Option<**String**> |  | [optional]
**emergency_contact_name** | Option<**String**> |  | [optional]
**emergency_contact_phone** | Option<**String**> |  | [optional]
**employee_code** | Option<**String**> |  | [optional]
**employment_status** | **String** | `active` · `suspended` · `terminated` | 
**gender** | Option<**String**> | `m` · `f` · null — only ever a soft default for late shifts (SC-13). | [optional]
**hire_date** | Option<**chrono::NaiveDate**> |  | [optional]
**id** | **uuid::Uuid** |  | 
**job_title** | Option<**String**> |  | [optional]
**kind** | **String** | `linked` · `app` (signs in to the staff app, no Madar account) · `manual` (records only, no app). | 
**name** | **String** |  | 
**national_id** | Option<**String**> |  | [optional]
**notes** | Option<**String**> |  | [optional]
**org_id** | **uuid::Uuid** |  | 
**pay_account** | Option<**String**> |  | [optional]
**pay_method** | **String** | `cash` · `bank` · `wallet` | 
**phone** | Option<**String**> |  | [optional]
**photo_url** | Option<**String**> |  | [optional]
**pref_time** | Option<**String**> | `morning` · `evening` · null | [optional]
**role** | Option<**String**> | The linked user's POS role; null for an unlinked employee. | [optional]
**termination_date** | Option<**chrono::NaiveDate**> |  | [optional]
**updated_at** | **chrono::DateTime<chrono::FixedOffset>** |  | 
**user_id** | Option<**uuid::Uuid**> | The linked Madar user, when this employee is one (a cashier, a manager, the owner). Null for someone who is only on payroll. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


