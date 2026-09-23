# ContextPerson

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**base_salary_piastres** | Option<**i64**> | Only for people whose pay the caller may see. | [optional]
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
**user_id** | Option<**uuid::Uuid**> | Their Madar account, when they have one. | [optional]

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


