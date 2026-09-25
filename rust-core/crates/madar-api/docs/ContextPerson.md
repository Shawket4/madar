# ContextPerson

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**advance_cap_piastres** | Option<**i64**> | Their salary-advance cap, decided by the server (AV-5, AT-3); shown under the same visibility as the salary. | [optional]
**advance_within_cap** | **bool** | What they owe in salary advances is within the cap; never hidden, so a manager sees \"within cap\" / \"over cap\" without the figure (D7). | 
**base_salary_piastres** | Option<**i64**> | Only for people whose pay the caller may see (null too when no salary is set: `salary_set`). | [optional]
**branch_ids** | **Vec<uuid::Uuid>** |  | 
**cant_work_days** | **Vec<i32>** |  | 
**device_model** | Option<**String**> |  | [optional]
**device_since** | Option<**chrono::DateTime<chrono::FixedOffset>**> |  | [optional]
**employee_id** | **uuid::Uuid** |  | 
**gender** | Option<**String**> |  | [optional]
**hire_date** | Option<**chrono::NaiveDate**> |  | [optional]
**name** | **String** |  | 
**pay_account** | Option<**String**> |  | [optional]
**pay_method** | **String** |  | 
**phone** | Option<**String**> |  | [optional]
**pref_time** | Option<**String**> |  | [optional]
**role** | **String** | `owner` · `manager` · `employee` (from the linked account; an employee with no account is `employee`). | 
**salary_set** | **bool** | A salary is on file (D9); false = \"not set\". Never hidden. | 
**user_id** | Option<**uuid::Uuid**> | Their Madar account, when they have one. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


