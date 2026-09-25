# StaffContext

## Properties

Name | Type | Description | Notes
------------ | ------------- | ------------- | -------------
**adjustment_limit_piastres** | Option<**i64**> | My ceiling on a bonus before it waits for the owner; null = none. | [optional]
**advance_limit_percent** | Option<**i64**> | My ceiling on an advance, as whole percent of the person's salary owed after it (the grant stores basis points); null = none. | [optional]
**branches** | [**Vec<models::ContextBranch>**](ContextBranch.md) |  | 
**caps** | **Vec<String>** | The HR capabilities I hold (`hr.*` keys) — through my Madar account; empty for an employee with none. The app gates tabs on these (PM-4). | 
**caps_everywhere** | **Vec<String>** | The capabilities I hold at EVERY branch: the list `GET /authz/me` puts in `everywhere`, for the business-wide acts (the rules, payroll, public holidays: `hr.rules.edit`, D3). Empty without a Madar account. | 
**deduction_limit_piastres** | Option<**i64**> | My ceiling on a deduction (AD-5: separate from the bonus limit). | [optional]
**employee_id** | **uuid::Uuid** | Who is signed in: the employee. | 
**first_open_date** | **chrono::NaiveDate** | The first day (from my today) not inside an approved or paid month: where a new bonus or deduction lands by default (\"lands in October's pay\", minor default M27). | 
**modules** | **Vec<String>** | The org's modules (`pos`, `dawam`); POS on means till punches (CL-13). | 
**name** | **String** |  | 
**org_id** | **uuid::Uuid** |  | 
**org_name** | **String** |  | 
**people** | [**Vec<models::ContextPerson>**](ContextPerson.md) |  | 
**privacy_accepted_at** | Option<**chrono::DateTime<chrono::FixedOffset>**> | When THIS phone accepted the location notice; null = show it before any location is taken (AT-5). A new phone, or a restored session on one that never accepted, starts null. | [optional]
**role** | **String** | `owner` · `manager` · `employee` | 
**settings** | [**models::ContextSettings**](ContextSettings.md) |  | 
**user_id** | Option<**uuid::Uuid**> | Their Madar account, when they have one; manager acts go through it. | [optional]
**work_shifts** | [**Vec<models::WorkShiftBrief>**](WorkShiftBrief.md) |  | 

[[Back to Model list]](../README.md#documentation-for-models) [[Back to API list]](../README.md#documentation-for-api-endpoints) [[Back to README]](../README.md)


