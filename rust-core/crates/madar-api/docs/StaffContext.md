# StaffContext

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**adjustment_limit_piastres** | Option<**i64**> | My ceiling on a bonus/deduction before it waits for the owner; null = none. | [optional]
**advance_limit_percent** | Option<**i64**> |  | [optional]
**branches** | [**Vec<models::ContextBranch>**](ContextBranch.md) |  | 
**caps** | **Vec<String>** | The HR capabilities I hold (`hr.*` keys) — through my Madar account; empty for an employee with none. The app gates tabs on these (PM-4). | 
**employee_id** | **uuid::Uuid** | Who is signed in: the employee. | 
**modules** | **Vec<String>** | The org's modules (`pos`, `dawam`); POS on means till punches (CL-13). | 
**name** | **String** |  | 
**org_id** | **uuid::Uuid** |  | 
**org_name** | **String** |  | 
**people** | [**Vec<models::ContextPerson>**](ContextPerson.md) |  | 
**role** | **String** | `owner` · `manager` · `employee` | 
**settings** | [**models::ContextSettings**](ContextSettings.md) |  | 
**user_id** | Option<**uuid::Uuid**> | Their Madar account, when they have one; manager acts go through it. | [optional]
**work_shifts** | [**Vec<models::WorkShiftBrief>**](WorkShiftBrief.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


